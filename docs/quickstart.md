# MDM_SEC 代码使用方法

## 1. 先运行示例

从仓库根目录执行：

```sh
make example       # 运行一个自检的 AES 模式 4 示例
make test -j 2     # 可选：完整 RTL 回归
make yosys-check   # 可选：RTL 结构检查，需 Yosys
```

`make example` 需要 GNU Make、C++ 编译器以及支持 `--binary --timing` 的 Verilator 5。完整回归还需要 Python 3；PyCryptodome 是可选依赖。工具可执行文件不在 `PATH` 时，可用 `VERILATOR=/path/to/verilator`、`YOSYS=/path/to/yosys` 指定。

示例源码是 [`examples/tb_mdm_sec_quickstart.sv`](../examples/tb_mdm_sec_quickstart.sv)。它是**仿真用测试平台**，待综合的 RTL 仍为 `rtl/*.v`，采用 Verilog-2005。示例使用模式 4、AES-CTR 加密和 AES-CMAC 完整性：

| 字段 | 示例值 |
|---|---|
| A | `11 22 33 44 55`（5 字节） |
| B | `66 77 88`（3 字节） |
| 加密密钥 | `000102030405060708090a0b0c0d0e0f` |
| 完整性密钥 | `0f0e0d0c0b0a09080706050403020100` |
| COUNT / BEARER / DIRECTION | `32'h398a59b4` / `5'h15` / `1'b1` |

成功时输出包含：

```text
Response: MAC=f387a200, cipher_bytes=3
Cipher:   data=73830000000000000000000000000000, keep=e000, last=1
PASS mode 4 AES-CTR/AES-CMAC quickstart
```

这些密钥和参数仅用于演示，不能用于实际通信。

## 2. 加入工程并例化

顶层是 [`rtl/mdm_sec.v`](../rtl/mdm_sec.v)。将 [`rtl/files.f`](../rtl/files.f) 中的 `.v` 文件加入工程，设置 Verilog include 路径为 `rtl/`，使编译器找到两个 `.vh` 文件。不同厂商工具对 filelist 的支持不同；也可手动添加其中列出的文件。例如，在仓库根目录可用以下命令做 Verilog-2005 lint：

```sh
verilator --language 1364-2005 --lint-only --top-module mdm_sec -f rtl/files.f
```

如果安装的是 `verilator-cli`，将上面的 `verilator` 替换为 `verilator-cli`。综合时不要将示例 testbench 作为设计顶层。

下面是命名端口例化模板；同名信号需要在上层按相应位宽声明，并由上层驱动输入、接收输出。完整可运行的连线及驱动见上述示例文件。

```verilog
mdm_sec #(.MAX_BYTES(2048)) u_mdm_sec (
    .clk(clk), .rst_n(rst_n),
    .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
    .cmd_mode(cmd_mode), .cmd_cipher_alg(cmd_cipher_alg), .cmd_int_alg(cmd_int_alg),
    .cmd_cipher_key(cmd_cipher_key), .cmd_int_key(cmd_int_key),
    .cmd_count(cmd_count), .cmd_bearer(cmd_bearer), .cmd_direction(cmd_direction),
    .cmd_a_bytes(cmd_a_bytes), .cmd_b_bytes(cmd_b_bytes),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
    .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
    .rsp_mac(rsp_mac), .rsp_mac_valid(rsp_mac_valid),
    .rsp_cipher_bytes(rsp_cipher_bytes), .rsp_error(rsp_error),
    .cipher_valid(cipher_valid), .cipher_ready(cipher_ready),
    .cipher_data(cipher_data), .cipher_keep(cipher_keep), .cipher_last(cipher_last),
    .rsp_rx_mac(rsp_rx_mac), .rsp_rx_mac_valid(rsp_rx_mac_valid),
    .rsp_mac_match(rsp_mac_match)
);
```

| 信号 | 方向（相对 `mdm_sec`） | 位宽 / 作用 |
|---|---|---|
| `clk`, `rst_n` | 输入 | 时钟、异步低有效复位；复位期间 `cmd_ready=0` |
| `cmd_valid`, `cmd_ready` | 输入、输出 | 命令握手 |
| `cmd_mode` | 输入 | 3 位，选择模式 0–5 |
| `cmd_cipher_alg`, `cmd_int_alg` | 输入 | 各 2 位，分别选择算法 |
| `cmd_cipher_key`, `cmd_int_key` | 输入 | 各 128 位，两个通道独立密钥 |
| `cmd_count`, `cmd_bearer`, `cmd_direction` | 输入 | 分别为 32、5、1 位的 3GPP 参数 |
| `cmd_a_bytes`, `cmd_b_bytes` | 输入 | 各 16 位，A/B 的**字节数** |
| `in_valid`, `in_ready`, `in_data` | 输入、输出、输入 | 包数据握手，数据宽 128 位 |
| `rsp_valid`, `rsp_ready` | 输出、输入 | 响应握手 |
| `rsp_mac`, `rsp_mac_valid` | 输出 | 32 位计算 MAC 及有效标志 |
| `rsp_cipher_bytes`, `rsp_error` | 输出 | 16 位后续数据长度、命令错误标志 |
| `cipher_valid`, `cipher_ready`, `cipher_data` | 输出、输入、输出 | 128 位结果流握手 |
| `cipher_keep`, `cipher_last` | 输出 | 16 位有效字节掩码、末 beat 标志 |
| `rsp_rx_mac`, `rsp_rx_mac_valid`, `rsp_mac_match` | 输出 | 模式 5 的接收验证码（32 位）、有效及比较结果 |

`MAX_BYTES` 限制输入 `A+B` 的总字节数，默认 2048，合法范围为 1–65535。128 位密钥按高字节在前填写，通信两端需使用匹配的密钥和协议参数。`cmd_direction` 是协议中的 DIRECTION 位，不是加密/解密选择信号。EEA 算法的 XOR 变换用于加密和解密。

## 3. 选择模式与算法

`||` 表示字节串拼接，`enc` 表示加解密 XOR 变换，`int` 表示计算 32 位 MAC。

| `cmd_mode` | 计算的 MAC | 后续 `cipher_data` 流 |
|---:|---|---|
| 0 | 不计算 | `enc(B)` |
| 1 | `int(A || B)` | 原样 `B` |
| 2 | `int(A || B)` | `enc(B || MAC)` |
| 3 | `int(A || enc(B))` | `enc(B)` |
| 4 | `int(A || B)` | `enc(B)` |
| 5 | 对 `A || 明文` 计算 MAC | 解密 B，去掉末尾 4 字节验证码后的明文 |

模式 5 中 B 是完整的加密输入，包含加密的 4 字节验证码；`cmd_b_bytes >= 4`。它对应模式 2 的接收布局，**不是模式 3 认证布局的直接逆过程**。

| 算法 ID | `cmd_cipher_alg` | `cmd_int_alg` |
|---:|---|---|
| 0 | EEA0，原样输出 | EIA0，MAC 恒为 0，无安全认证 |
| 1 | SNOW 3G / EEA1 | SNOW 3G / EIA1 |
| 2 | AES-128 CTR / EEA2 | AES-128 CMAC / EIA2，取高 32 位 |
| 3 | ZUC / EEA3 | ZUC / EIA3 |

模式 2–5 的两条通道在装载完整包之后同拍启动，允许实际处理重叠；模式 2、3、5 存在数据依赖，会在需要 MAC、密文或明文时等待，不保证每拍同时推进。

## 4. 一个包的握手顺序

所有握手在 `clk` 上升沿的 `valid && ready` 时发生。发送方在 `valid=1 && ready=0` 时须保持 `valid` 和对应负载稳定。

1. **复位**：将 `rst_n` 拉低后释放。模块一次只能处理一个包。
2. **命令**：设置模式、算法、密钥、COUNT、BEARER、DIRECTION 和 A/B 字节数，拉高 `cmd_valid`，直到与 `cmd_ready` 握手。握手后命令字段才可以改变；若没有下一条命令则拉低 `cmd_valid`。
3. **输入 A，再输入 B**：分别经 `in_valid/in_ready/in_data` 发送；每段从新的 128 位 beat 开始，每 beat 最多 16 字节，高字节在前，末 beat 不足的低字节忽略。零长段不发送 beat。没有输入 `keep`，有效长度来自命令。
4. **接收响应**：等待 `rsp_valid`，拉高 `rsp_ready` 完成握手并保存所需字段。先检查 `rsp_error`；合法命令的 MAC 有效性看 `rsp_mac_valid`，输出长度看 `rsp_cipher_bytes`。模式 5 还需检查 `rsp_rx_mac_valid` 和 `rsp_mac_match`。
5. **接收输出**：响应握手后才出现 `cipher_valid`。若 `rsp_cipher_bytes` 非零，使用 `cipher_ready` 接收每个 beat，依据 `cipher_keep` 取高位有效字节，直到 `cipher_last` 的握手；若为零则没有输出 beat。必须接收完整输出，模块才会重新接受下一包。

示例中 A、B 各自占一个 beat，依次送入：

```verilog
128'h11223344550000000000000000000000  // A：高 5 字节
128'h66778800000000000000000000000000  // B：高 3 字节
```

输出为 `738300...`，`cipher_keep=16'he000`，表示高 3 字节有效；`cipher_last=1`。`cipher_keep[15]` 对应 `cipher_data[127:120]`。

非法模式、`A+B` 超过 `MAX_BYTES` 或 65535、模式 2 的 `B>65531`、模式 5 的 `B<4` 均被拒绝：模块不接收包数据，直接返回 `rsp_error=1` 和零输出长度。上层应在发送前检查命令，或在等待输入就绪时同时处理错误响应，避免一直等 `in_ready`。

## 5. 使用注意

- 模式 5 验证不匹配时 `rsp_error` 仍为 0，模块仍会输出解密数据；必须检查 `rsp_mac_match` 并丢弃未认证明文，同时排空输出或复位中止。EIA0 不提供安全认证。
- 模式 2 输出长度为 `B+4`，模式 5 为 `B-4`；模式 1 也会输出原样 B。其他模式输出长度为 B。
- 接口仅支持整字节消息。顶层输入/输出为 128 位，内部算法通道为 32 位；处理延迟包含装载、初始化、运算和握手。
- 内部缓存使用异步读；若目标 SRAM 只支持同步读，需适配并增加流水级。复位不擦除缓存内容，生产系统需另行考虑密钥/数据清除与安全防护。

更完整的协议、时序和限制见 [`rtl_interface.md`](rtl_interface.md)，回归记录见 [`verification.md`](verification.md)。
