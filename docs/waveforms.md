# 定向测试与波形查看

生成波形不修改可综合 RTL；波形由仿真 testbench 生成。定向包测试使用固定输入和参考模型结果自动核对响应、MAC、所有输出字节、握手及依赖保护；任何错误或覆盖不足都会令仿真失败。另有独立的 AES 块波形，便于观察低面积实现的轮次、列处理及连续启动。

## 运行与生成 VCD

在仓库根目录准备 Python 3、GNU Make、C++ 编译器和 Verilator 5（支持 `--binary --timing --trace`）。可选安装 PyCryptodome，以独立交叉检查 AES-CTR、AES-CMAC 和 AES 块；没有它也可生成向量和运行自检。GTKWave 用于查看波形，不是运行仿真的必要条件。

```sh
make test-directed                 # 只运行 20 个包用例，默认低面积 AES，不写 VCD
make test-directed WAVE_AES_LOW_AREA=0  # 同一组用例切换高速 AES
make wave                          # 运行自检并产生两个低面积版 VCD
make wave WAVE_AES_LOW_AREA=0      # 产生两个高速版 VCD，不覆盖低面积版
```

例如，PyPI 版 Verilator 不在 `PATH` 中时，可以指定 `make wave VERILATOR="$HOME/.local/bin/verilator-cli"`。首次运行需要编译；成功时可看到 20 个包用例及 AES 块 `PASS`，随后还会看到 `PASS packet VCD` 和 `PASS aes VCD`。`make test` 也包含 `test-directed`，但不会自动生成 VCD。

默认输出：

| 文件 | 内容 |
|---|---|
| `build/rtl/waveforms/mdm_sec_low_area.vcd` | 低面积 AES 配置的六模式包接口与内部依赖 |
| `build/rtl/waveforms/aes128_low_area.vcd` | 独立低面积 AES 核的轮次和连续块 |
| `build/rtl/waveforms/mdm_sec_fast.vcd` | `WAVE_AES_LOW_AREA=0` 时的包波形 |
| `build/rtl/waveforms/aes128_fast.vcd` | `WAVE_AES_LOW_AREA=0` 时的独立高速 AES 核 |
| `build/rtl/wave_vectors.cases.txt` | 每个包用例的编号、算法、长度、预期 MAC 和名称 |

两个 VCD 目标会自动检查文件中的时钟/复位变化、主要握手和内部信号、用例编号、模式 5 成功/失败响应及 AES 固定答案；它是波形完整性冒烟检查，不能替代 testbench 的逐项比较。文件名中的 `low_area` 和 `fast` 对应 RTL 的 `AES_LOW_AREA=1` 和 `0`。每次运行会覆盖所选配置的同名 VCD；所有生成文件均在 `build/`，`make clean` 会删除，重要结果请先另存。

其他选项：

```sh
make wave-packet                          # 只生成包级 VCD
make wave-aes WAVE_AES_BLOCKS=2           # 只生成 AES VCD；默认 8 块
make wave-packet WAVE_MAX_BYTES=2048      # 使用顶层默认容量重新编译
make wave WAVE_DIR=build/my-waves          # 更改 VCD 输出目录
```

`WAVE_AES_BLOCKS` 可设为 2～515（向量文件当前有 515 块）；前 200 块逐块检查最早连续启动。波形包 bench 默认为 `WAVE_MAX_BYTES=512`，足以容纳全部定向用例，但不是 RTL 的默认 2048 字节参数；可设为 512～65535。改变容量会重编译，较大容量的编译和仿真可能更慢。更改容量不会改变 VCD 文件名，如要保留两种容量，请分别设置 `WAVE_DIR`。为限制文件大小，包波形追踪深度为 4，包含输入缓冲读写端口但不展开所有存储单元；AES 独立波形包含更深的低面积核心层次。

## 查看方法

```sh
gtkwave build/rtl/waveforms/mdm_sec_low_area.vcd
gtkwave build/rtl/waveforms/aes128_low_area.vcd
```

在 GTKWave 左侧选择 `tb_mdm_sec` 或 `tb_aes_random` 层次，将所需信号加入波形窗口，使用 Zoom Full / Zoom In 和游标查看。仿真时钟周期为 10 ns，VCD 时间精度为 1 ps。日志 `CASE <编号> ... at <时间>` 可以帮助定位；也可以先加入 `wave_case_id` 和 `wave_phase`，在对应编号附近放大：

- `tb_mdm_sec.wave_case_id`：0～19 对应下表；`-1`（十六进制 `ffffffff`）是用例前后的复位、非法命令等检查。
- `tb_mdm_sec.wave_phase`：0 前后检查、1 命令、2 输入、3 等待运算、4 响应、5 输出、6 用例完成。空输入/输出或零时长阶段可能不会在波形中单独可见。
- `cmd_valid/cmd_ready`、`in_valid/in_ready`、`rsp_valid/rsp_ready`、`cipher_valid/cipher_ready` 为接口握手；输入和输出均故意插入停顿，响应也保持数拍，用于检查背压期间数据稳定。
- testbench 在命令握手后故意改变 `cmd_mode` 和密钥等输入，证明命令已锁存；之后看 `tb_mdm_sec.dut.mode_q`，不要把此时的 `cmd_mode=7` 误认为正在执行非法模式。

### 20 个包用例

编号和详细参数也记录在生成的 `wave_vectors.cases.txt` 中；长度单位为字节。EEA/EIA 的编号 0、1、2、3 分别为 NULL、SNOW 3G、AES、ZUC。

| ID | 模式 | 主要场景 |
|---:|---:|---|
| 0 | 0 | EEA1 已知答案，加密 32 字节 |
| 1 | 0 | EEA2 已知答案，加密 32 字节 |
| 2 | 0 | EEA3 已知答案，加密 100 字节 |
| 3 | 1 | EIA1 已知 MAC：`731f1165` |
| 4 | 1 | EIA2 已知 MAC：`b93787e6` |
| 5 | 1 | EIA3 已知 MAC：`b1811961` |
| 6 | 2 | AES-CMAC 后追加 MAC，再 AES-CTR 加密 |
| 7 | 2 | 原文覆盖保护、同沿读旧值及追加 MAC 等待 |
| 8 | 3 | 长包 AES 加密结果供 EIA3 消费，完整性通道等待密文 |
| 9 | 4 | 原地写入与完整性原文读取的冲突保护 |
| 10 | 4 | quickstart 固定答案，MAC `f387a200`，密文 `738300` |
| 11 | 5 | 解密并认证成功，计算和接收 MAC 均为 `12a10d82` |
| 12 | 5 | 篡改接收 MAC，计算为 `12a10d82`，接收为 `12a10d83` |
| 13 | 5 | 仅四字节 MAC，解密后明文为空 |
| 14 | 4 | A/B 均为空，NULL 加密和 NULL 完整性 |
| 15 | 2 | B 为空，仍追加并加密 MAC |
| 16 | 3 | ZUC 加密与 SNOW 3G 完整性混合 |
| 17 | 4 | SNOW 3G 加密与 ZUC 完整性混合 |
| 18 | 5 | 长包解密，完整性通道等待明文，认证成功 |
| 19 | 5 | 篡改密文载荷，解密后认证失败 |

### 包级重点信号

在 `tb_mdm_sec.dut` 下可加入：

- `enc_start` / `int_start`：模式 2～5 的两条通道同拍启动；`enc_in_valid/enc_in_ready`、`int_in_valid/int_in_ready` 和 `result_wr_en` 可用于看实际并发与等待。
- `enc_mem_ready`、`enc_mac_ready`、`int_dep_ready`、`enc_pos`、`int_pos`：用例 7/9 中加密写入等待完整性读取原文，用例 7 还要等生成 MAC；用例 8/18 中完整性输入等待已经提交的密文/明文。日志给出 `waits(old/MAC/result)`、`same-edge` 和 `overlap` 计数；用例 7/8/9/18 的关键等待由断言强制覆盖。
- `u_input_buffer.wr_en/wr_addr/wr_bytes/wr_data`、`rd0_addr/rd0_data`、`rd1_addr/rd1_data`：观察共享缓冲的读写地址和数据。用例 7/9 检查同一沿读取原文并写回时，完整性一侧读到的是写前旧值。
- `rsp_mac`、`rsp_rx_mac`、`rsp_rx_mac_valid`、`rsp_mac_match`、`rsp_error`：在 `rsp_valid=1` 时对比用例 11 和 12；二者 `rsp_error` 都为 0，但 `rsp_mac_match` 分别为 1 和 0。用例 19 同样产生失败结果。
- `cipher_data`、`cipher_keep`、`cipher_last`：观察输出数据和有效字节；有效字节从高位向低位排列，见 [RTL 接口](rtl_interface.md)。

### AES 重点信号

独立 AES bench 的根节点为 `tb_aes_random`。加入 `clk/rst_n/start/ready/busy/done`、`key/block_in/block_out` 和 `scoreboard_active`。开头有四次中途复位测试；`scoreboard_active=1` 后才是逐块自检。首块是 FIPS-197 固定答案：密钥 `000102030405060708090a0b0c0d0e0f`，输入 `00112233445566778899aabbccddeeff`，输出 `69c4e0d86a7b0430d8cdb78070b4c55a`。

低面积版展开 `dut.g_low_area.u_core`，可看 `state/round/column`、`key_reg/round_state`、`sbox_in/sbox_out`，以及 `u_subbytes`、`u_key_expand`、`u_mix_column`、`u_shift_rows`、`u_add_round_key`；每块 50 拍。高速版展开 `dut.g_fast.u_core`，看 `state/pair/round_state`；每块 5 拍。两者均允许最后一拍接收下一块，`busy=1` 不代表一定 `ready=0`，以 `start && ready` 为接收条件。

## 安全提示

VCD 和 AES 逐块日志包含密钥、明文、密文和中间状态；本测试数据仅供演示。不要将真实密钥或用户数据写入波形，也不要公开真实系统的敏感波形。模式 5 验证失败时本 RTL 仍会输出解密数据，系统必须检查 `rsp_rx_mac_valid` 和 `rsp_mac_match`，并丢弃未认证数据；EIA0 不提供完整性保护。
