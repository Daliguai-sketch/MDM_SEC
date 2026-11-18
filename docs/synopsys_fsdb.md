# 使用 VCS 和 Verdi 生成 FSDB

此流程直接使用 **VCS 仿真和 Verdi PLI 生成原生 FSDB**，不是把 VCD 改名为 FSDB。包级和 AES 仍运行与 [waveforms.md](waveforms.md) 相同的自检用例；可综合 RTL 无需增加波形代码。

## 环境准备

在 Linux 上配置本地的 VCS、Verdi、有效许可证、Python 3、GNU Make 和 VCS 所需的 C/C++ 编译工具。许可证按本机/公司的既有方式配置即可，不需要提交许可证或密钥。确认工具可用：

```sh
command -v vcs
command -v verdi
printf 'VCS_HOME=%s\nVERDI_HOME=%s\n' "$VCS_HOME" "$VERDI_HOME"
```

如果工具安装目录存在但 `PATH` 未包含其 `bin`，可按本机实际环境设置 `VCS_HOME`、`VERDI_HOME` 并将其 `bin` 加入 `PATH`。Makefile 也会在已设置 `VCS_HOME`/`VERDI_HOME` 时尝试对应的 `bin/vcs`、`bin/verdi`。请使用本机已经配置好的版本，不要照搬其他机器的安装路径。

编译时需要匹配本地 Verdi 版本的 `novas.tab` 和 `pli.a`。默认从 `VERDI_HOME` 或 `NOVAS_HOME` 的以下目录自动查找：

- `share/PLI/VCS/LINUX64/`
- `share/PLI/VCS/linux64/`

不同安装布局可以显式指定 PLI 目录，或分别指定两个文件，示例如下（将路径替换为本机实际路径）：

```sh
make fsdb VERDI_PLI_DIR=/实际路径/share/PLI/VCS/LINUX64
# 或：
make fsdb VERDI_TAB=/实际路径/novas.tab VERDI_PLI=/实际路径/pli.a
```

`VCS=/绝对路径/vcs`、`VERDI=/绝对路径/verdi` 可覆盖可执行文件位置。路径应避免空格。默认 VCS 选项为 `-full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb -lca +memcbk`，并链接上述 Verdi PLI；例如可用 `VCS_EXTRA_FLAGS='+vcs+lic+wait'` 添加本地选项。更换工具、PLI 或编译选项后，使用 `make -B fsdb ...` 强制重新编译；不同 `WAVE_MAX_BYTES` 和 AES 配置会自动使用不同编译目录。

## 生成与打开

在仓库根目录执行：

```sh
make fsdb                             # 低面积 AES：包级 + AES 块级
make fsdb WAVE_AES_LOW_AREA=0         # 高速 AES：包级 + AES 块级

make verdi-packet                     # 打开低面积包级 FSDB 与对应 simv.daidir
make verdi-aes                        # 打开低面积 AES 块级 FSDB
make verdi-packet WAVE_AES_LOW_AREA=0 # 打开高速包级 FSDB
```

也可以分别执行 `make fsdb-packet` 和 `make fsdb-aes`。GUI 需要可用的图形显示环境；仅生成 FSDB 不需要启动 GUI。`make verdi-*` 只打开已有结果，不重新运行仿真；打开时的 `WAVE_AES_LOW_AREA`、`WAVE_MAX_BYTES` 和 `FSDB_DIR` 应与生成时一致。也可手工打开，例如：

```sh
verdi -simflow -dbdir build/rtl/vcs_packet_512_1/simv.daidir \
      -ssf build/rtl/waveforms/mdm_sec_low_area.fsdb &
```

默认生成的文件：

| 文件 | 内容 |
|---|---|
| `build/rtl/waveforms/mdm_sec_low_area.fsdb` | 低面积配置的 20 个包级用例 |
| `build/rtl/waveforms/aes128_low_area.fsdb` | 低面积 AES 块级测试，默认 8 块 |
| `build/rtl/waveforms/mdm_sec_fast.fsdb` | `WAVE_AES_LOW_AREA=0` 的包级测试 |
| `build/rtl/waveforms/aes128_fast.fsdb` | `WAVE_AES_LOW_AREA=0` 的 AES 块级测试 |
| `build/rtl/vcs_packet_512_1/vcs_compile.log`、`sim.log` | 默认包级编译和仿真日志 |
| `build/rtl/vcs_aes_1/vcs_compile.log`、`sim.log` | 默认 AES 编译和仿真日志 |
| `build/rtl/wave_vectors.cases.txt` | 包用例编号、算法、预期 MAC 和名称 |

高速配置的编译目录分别为 `vcs_packet_512_0`、`vcs_aes_0`。FSDB 默认放在 `WAVE_DIR`，也可以单独指定 `FSDB_DIR=build/my-fsdb`。每次仿真会覆盖所选配置的同名 FSDB；更改 `WAVE_MAX_BYTES` 不会改变文件名，需要保留不同容量的结果时应分别指定 `FSDB_DIR`，避免用错与波形不匹配的 `simv.daidir`。`build/` 是生成目录，`make clean` 会删除它，重要波形请先另存。

自检成功应看到 `PASS directed waveform cases`、`PASS 20 packet vectors` 和 `PASS 8 AES blocks`。Make 会确认包级打印的 `MAX_BYTES/AES_LOW_AREA`、AES 的 50/5 拍配置、通过标记以及 FSDB 文件非空，任何一步失败时返回非零；非空检查**不解析 FSDB 内部事件**。可在 Verdi 打开实际波形，也可选用本机 `fsdb2vcd` 导出后检查关键事件：

```sh
fsdb2vcd build/rtl/waveforms/mdm_sec_low_area.fsdb -o build/rtl/from_fsdb_packet.vcd
python3 tests/check_vcd.py packet build/rtl/from_fsdb_packet.vcd
fsdb2vcd build/rtl/waveforms/aes128_low_area.fsdb -o build/rtl/from_fsdb_aes.vcd
python3 tests/check_vcd.py aes build/rtl/from_fsdb_aes.vcd
```

检查脚本依赖 testbench 的层次和信号名；如果本机版本转换出的名称不同，请先在 Verdi 中核对。`make test-vcs-flow` 仅用模拟程序验证命令拼接、参数和失败处理，不能代替真实 VCS/Verdi 仿真。

## 参数与观察信号

```sh
make fsdb-packet WAVE_MAX_BYTES=2048  # 默认包 bench 为 512，RTL 默认容量为 2048
make fsdb-aes WAVE_AES_BLOCKS=2       # 默认 8；允许 2～515 块
make fsdb-packet FSDB_MDA=1           # 额外记录共享 input buffer 的存储数组
```

`WAVE_MAX_BYTES` 可设为 512～65535。默认记录 testbench 及 DUT 下各层普通信号，不记录存储数组的所有元素；`FSDB_MDA=1` 额外对 `tb_mdm_sec.dut.u_input_buffer` 下的存储数组执行 `$fsdbDumpMDA`，不影响独立 AES 波形。容量大或开启数组跟踪时文件可能显著增大。使用 `FSDB_MDA=1` 会覆盖同名包级 FSDB，如需同时保存，请指定不同的 `FSDB_DIR`。

在 Verdi 中先添加 `tb_mdm_sec.wave_case_id`、`wave_phase`，再观察 `cmd_valid/cmd_ready`、`in_valid/in_ready`、`rsp_valid/rsp_ready` 和 `cipher_valid/cipher_ready`；更多依赖、缓存读写、模式 5 认证及 AES 轮次信号见 [waveforms.md](waveforms.md)。用例 11 是 MAC 成功，用例 12 是 MAC 篡改失败。`wave_case_id=-1` 表示用例前后复位/错误检查。

## 排错

- `Install/configure VCS`：检查 `VCS_HOME`/`PATH` 或指定 `VCS=`；检查本机许可证是否可用。
- `Verdi PLI not found` 或 `$fsdbDumpfile` 未定义：检查 `VERDI_HOME`/`NOVAS_HOME`、PLI 路径及 VCS/Verdi 版本是否匹配，必要时显式设置 `VERDI_PLI_DIR`；更改后 `make -B fsdb`。
- `Packet/AES FSDB missing or empty`：查看相应 `vcs_compile.log`、`sim.log` 和 PLI 信息，确认磁盘目录可写及 Verdi dump 库可加载。
- 看不到缓存数组：使用 `FSDB_MDA=1`，确认 VCS 编译包含 `+memcbk`，并在 Verdi 的 `dut.u_input_buffer.g_bank` 层次中查看；大容量数组会增加波形体积。
- 无法打开源码层次：确认没有从 `VCS_FLAGS` 中移除 `-debug_access+all -kdb -lca`，并用生成该 FSDB 的对应 `simv.daidir` 打开。

FSDB 和仿真日志可包含密钥、明文与中间状态；提供的向量仅为测试数据，禁止公开真实密钥或用户数据。模式 5 认证失败时 RTL 仍输出明文，系统必须自行丢弃未认证数据。
