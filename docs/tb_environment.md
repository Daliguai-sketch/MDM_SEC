# 验证环境说明（本地目录 `/design/tb/`）

本文说明现有仓库的验证顶层、Python 生成与仿真读取的向量、波形和已完成的验证结果。下文的 `make fsdb` 是 **Python 和 VCS 同机**的开发流程。若 Python 在外网、RTL 仿真在 U 网，请改用 [外网生成、U 网离线测试指南](u_network_test.md)，不要在 U 网运行本文的普通 `make fsdb`。

下文假设本机的 `/design/tb/` 可写，并通过 `BUILD_DIR=/design/tb/build/rtl` 将**生成文件**放到该目录；运行命令时，当前目录仍需是包含 `Makefile`、`rtl/`、`tests/` 的仓库根目录。

`/design/tb/` 是用户本机路径，本次运行环境无法访问该目录：下述绝对路径是本地执行命令后的预期位置，并非声称这些文件已在用户机器生成。如果完整仓库本身位于 `/design/tb/`，可以直接在那里运行；否则 testbench 源码仍在仓库的 `tests/rtl/`，不会自动复制到 `/design/tb/`。

## 顶层和验证结构

| 用途 | 仿真顶层模块 | 顶层源码（相对仓库根目录） | 被测模块 |
|---|---|---|---|
| 六模式整包 / FSDB | `tb_mdm_sec` | `tests/rtl/tb_mdm_sec.sv` | `rtl/mdm_sec.v` 中的 `mdm_sec`，实例名 `dut` |
| AES 单块 / FSDB | `tb_aes_random` | `tests/rtl/tb_aes_random.sv` | `rtl/mdm_aes128.v` 中的 `mdm_aes128`，实例名 `dut` |

因此，综合使用的设计顶层是 **`mdm_sec`**，整包仿真的最外层是 **`tb_mdm_sec`**，不是 `mdm_sec`。整包主要层次为：

```text
tb_mdm_sec                      仿真 testbench（产生激励、检查结果）
└── dut : mdm_sec               可综合 DUT
    ├── u_input_buffer          共享输入/结果缓存
    ├── u_cipher                加密通道（含 u_aes、u_snow、u_zuc）
    └── u_integrity             完整性通道（含 u_aes、u_snow、u_zuc）
```

`tb_aes_random` 是另一个独立仿真，不是 `tb_mdm_sec` 的子模块。默认波形包仿真使用 `TEST_MAX_BYTES=512`、`TEST_AES_LOW_AREA=1`，以减小仿真规模；RTL 自身的默认 `MAX_BYTES` 为 2048。`WAVE_AES_LOW_AREA=0` 选择高速 AES。

## 执行及目录

先按本地环境配置 VCS、Verdi、许可证和 `VERDI_HOME`（或 `NOVAS_HOME`）。进入**仓库根目录**，运行：

```sh
# 向量、VCS 编译产物、日志和 FSDB 均落到 /design/tb/build/rtl 下
make fsdb BUILD_DIR=/design/tb/build/rtl

# 用同一参数打开波形和对应 VCS 数据库
make verdi-packet BUILD_DIR=/design/tb/build/rtl
make verdi-aes BUILD_DIR=/design/tb/build/rtl
```

执行 `make fsdb` 时，Make 会按需自动运行 Python 生成向量，然后分别编译并运行两个 VCS testbench。也可只运行 `make fsdb-packet BUILD_DIR=/design/tb/build/rtl` 或 `make fsdb-aes BUILD_DIR=/design/tb/build/rtl`。预期生成：

```text
/design/tb/
└── build/rtl/                         # BUILD_DIR，均为生成文件
    ├── wave_vectors.txt               # 整包 TB 真正读取的向量
    ├── wave_vectors.cases.txt         # 人可读的用例清单，不是 TB 输入
    ├── aes_vectors.txt                # AES 单块 TB 真正读取的向量
    ├── vcs_packet_512_1/
    │   ├── simv                       # tb_mdm_sec VCS 仿真程序
    │   ├── simv.daidir/               # VCS/Verdi 设计数据库
    │   ├── vcs_compile.log            # 编译日志
    │   └── sim.log                    # 整包仿真/自检日志
    ├── vcs_aes_1/
    │   ├── simv                       # tb_aes_random VCS 仿真程序
    │   ├── simv.daidir/
    │   ├── vcs_compile.log
    │   └── sim.log                    # AES 仿真/自检日志
    └── waveforms/
        ├── mdm_sec_low_area.fsdb      # 整包波形
        └── aes128_low_area.fsdb       # AES 单块波形
```

`BUILD_DIR` 默认是仓库根目录下的 `build/rtl`；只有明确设置成上述绝对路径，或者仓库根目录恰好是 `/design/tb/` 时，默认输出才对应上图。`FSDB_DIR=其他目录` 可单独改变波形输出位置。修改 AES/容量参数会改变 VCS 编译目录；不同容量使用同名波形文件，如需同时保留请分别设置 `FSDB_DIR`。

**清理注意：** `make clean` 会递归删除整个 `BUILD_DIR`。不要把 `BUILD_DIR` 直接设置成含有源码或其他重要文件的 `/design/tb`；上例使用其下的专用生成子目录 `/design/tb/build/rtl`。

## Python 向量和 testbench 读取方式

流程为：

```text
tests/gen_wave_vectors.py + tests/reference_model.py
  -> /design/tb/build/rtl/wave_vectors.txt（输入 + Python 参考期望值）
  -> simv +VECTORS=/design/tb/build/rtl/wave_vectors.txt
  -> tb_mdm_sec 用 $value$plusargs / $fopen / $fscanf 读取
  -> 驱动 mdm_sec，比较 MAC、状态、长度和每个输出 beat，检查握手/依赖
  -> sim.log + FSDB
```

Python 包级生成器一次生成 **20 个确定性用例**。`wave_vectors.txt` 中每个用例先有一行描述符，再依次放 A 输入、B 输入和预期输出；每个数据行是高字节在前、末尾补零的 128 位十六进制 beat。描述符字段依次为：

```text
id mode cipher_alg int_alg cipher_key int_key count bearer direction
   A字节数 B字节数 期望MAC MAC有效 期望输出字节数 接收MAC 接收MAC有效 MAC匹配
```

字段实际写在同一行。`wave_vectors.cases.txt` 是编号和结果摘要，方便对照波形，不是 TB 读取的向量。testbench 不另写完整 DUT 输出向量文件：它直接将 DUT 输出与向量中的期望值逐拍比较；不一致时 `$fatal` 并在日志中报告错误，成功则打印各 case 和汇总 `PASS`。

AES 块级向量由 `tests/gen_aes_vectors.py` 生成 `aes_vectors.txt`，每行依次为 `key block_in expected_block_out`，共 515 组；`make fsdb` 默认只用前 8 组以控制波形大小。首行为 FIPS-197：

```text
000102030405060708090a0b0c0d0e0f 00112233445566778899aabbccddeeff 69c4e0d86a7b0430d8cdb78070b4c55a
```

可先单独生成及检查（在仓库根目录）：

```sh
python3 tests/gen_wave_vectors.py /design/tb/build/rtl/wave_vectors.txt
python3 tests/gen_aes_vectors.py /design/tb/build/rtl/aes_vectors.txt
cat /design/tb/build/rtl/wave_vectors.cases.txt
head -5 /design/tb/build/rtl/wave_vectors.txt
head -3 /design/tb/build/rtl/aes_vectors.txt
```

PyCryptodome 是可选依赖；存在时进一步独立检查 AES，缺少时仍生成固定答案和参考模型向量。`make test` 的大规模回归另生成 `packet_vectors.txt`、`tiny_vectors.txt` 和 `boundary_vectors.txt`；它依赖 Verilator，并非 `make fsdb` 自动运行的范围。

## 已有结果与本机需确认的结果

- 已在 Verilator 上完成完整回归：大规模包用例 **5546 个**（低面积 2641+240+12，高速 2641+12），以及默认 20 个低面积定向包；高速配置的 20 个定向包也单独通过。
- AES 完整回归两种配置各 **515 块**通过；原语延迟/最早启动间隔为低面积 **50 拍**、高速 **5 拍**，并非整包延迟。
- 四态 Icarus 仿真分别通过两种配置的 20 个定向包和各 8 个 AES 块；其中用例 11 的 `MAC=12a10d82`、`RX=12a10d82`、`match=1`，用例 12 的 `RX=12a10d83`、`match=0`。
- 当前执行环境没有 VCS/Verdi，**没有在这里实测真实 VCS 编译或生成真实 FSDB**。前述结果不能代替您本机 Synopsys 工具的验证。

本机 `make fsdb` 正常完成后，整包 `sim.log` 应出现 `DIRECTED configuration MAX_BYTES=512 AES_LOW_AREA=1`、`PASS directed waveform cases` 和 `PASS 20 packet vectors`；AES `sim.log` 应出现 `PASS 8 AES blocks, 50-cycle latency/II`。Make 检查自检日志和 FSDB 非空，但不解析 FSDB 中每个事件；请用 Verdi 实际查看，或参考 [synopsys_fsdb.md](synopsys_fsdb.md) 的 `fsdb2vcd` 检查方法。

波形中先查看 `tb_mdm_sec.wave_case_id`、`wave_phase`、命令/数据/响应握手，以及 `dut.enc_start`、`dut.int_start`、`rsp_mac`、`rsp_rx_mac`、`rsp_mac_match`。用例编号和进一步的信号说明见 [waveforms.md](waveforms.md)。波形可能包含测试密钥和数据，不要公开真实密钥；模式 5 验证失败时仍输出解密数据，系统必须丢弃未认证数据。
