# 外网生成向量、U 网离线 VCS/Verdi 测试指南

## 1. 两个环境的职责

| 阶段 | 运行地点和工具 | 工作 |
|---|---|---|
| A：生成和打包 | 外网：Python 3 和本仓库源码 | 运行 Python 参考模型，生成输入与预期结果，打包 RTL、testbench、向量和校验文件；不需要 VCS/Verdi |
| B：RTL 仿真 | U 网：Linux、GNU Make、VCS、Verdi PLI 及许可证、C/C++ 编译工具 | 只使用转入的向量编译和仿真，自检并输出 FSDB；**不需要 Python、pip 或网络** |

使用公司批准的介质和流程导入 U 网；本指南不会自动跨网传输。命令以 Linux `sh`/`bash` 为例。包内测试密钥和数据为测试用，不要替换成真实密钥或用户数据。以下 `/design/tb/` 是 U 网本机工作目录示例；本次执行环境无法访问该目录。

```text
外网                                      U 网 /design/tb/
Python 参考模型                           mdm_sec_u/vectors/*.txt
  ├─> 20 个定向整包用例（输入+期望） ───┐      │
  └─> 515 个 AES 块（输入+期望） ─────┤      ├─> VCS +VECTORS → testbench 对比 DUT
                                       │      └─> sim.log + 原生 FSDB → Verdi
RTL + 两个 testbench + Makefile.u ─────┘
```

默认测试范围是 **20 个定向包 + 前 8 个 AES 块**，可切换成全部 515 个 AES 块。这是便于波形观察的定向测试，**不等同于以前的 5546 包完整回归**。

## 2. 外网：生成向量和传输包

外网需要本仓库的完整源码和 Python 3（建议 3.8 及以上）；不需要 VCS。以下命令在包含 `Makefile`、`rtl/`、`tests/`、`sec_core/`、`tools/` 的**仓库根目录**执行：

```sh
python3 --version
# 可选：如果外网 Python 环境允许安装依赖，启用 AES 独立交叉检查
python3 -m pip install pycryptodome

# 不需要 Make、VCS 或 Verdi；同时生成向量并生成转网文件
python3 tools/prepare_u_bundle.py --output deliverables/u_transfer
```

`pycryptodome` 可选：安装后生成时独立检查 AES 块、AES-CTR 和 AES-CMAC；未安装仍会检查脚本中的固定答案并生成向量，但会提示跳过这部分独立检查。只有脚本成功退出、并输出两条生成文件路径后，才能继续传输。

```text
deliverables/u_transfer/mdm_sec_u.tar.gz          # 待转入 U 网的完整包
deliverables/u_transfer/mdm_sec_u.tar.gz.sha256   # 上述压缩包的 SHA-256
```

脚本只覆盖上述两个同名输出，不会删除整个输出目录；再次打包请先备份旧包。`deliverables/` 为生成目录，不提交 Git。可在外网检查包：

```sh
(cd deliverables/u_transfer && sha256sum -c mdm_sec_u.tar.gz.sha256)
tar -tzf deliverables/u_transfer/mdm_sec_u.tar.gz
```

其中 `vectors/wave_vectors.txt` 为整包 testbench 的输入和参考期望值；`vectors/wave_vectors.cases.txt` 是人看的 20 个用例清单；`vectors/aes_vectors.txt` 每行是 `key block_in expected_block_out`，共 515 行。`vectors/generation_info.txt` 记录外网生成日志、独立检查是否运行以及生成器源码的 SHA-256。包不包含 Python 源码。Python 向量生成器使用固定测试数据和固定随机种子。

将 **两个文件** `mdm_sec_u.tar.gz`、`mdm_sec_u.tar.gz.sha256` 一并按批准流程转入 U 网 `/design/tb/`。散列用于检测传输损坏或误配，并不能替代受信任渠道或数字签名。

## 3. U 网：校验和解压

确认 `/design/tb/` 可写、空间足够，并且当前没有同名的 `mdm_sec_u` 目录。以下命令**不会覆盖已有目录**；任一步失败须停止，核对导入文件或换一个空目录：

```sh
cd /design/tb
sha256sum -c mdm_sec_u.tar.gz.sha256 && \
  test ! -e mdm_sec_u && \
  tar -xzf mdm_sec_u.tar.gz && \
  cd mdm_sec_u && \
  make -f Makefile.u verify-bundle
```

最后一步的 `SHA256SUMS` 会逐项检查转入的 RTL、testbench、向量、Makefile 和说明。每次运行仿真或 Verdi 时 `Makefile.u` 也会自动检查；文件缺失或被修改时应重新从外网生成并转入整个包，不要自行删除或修改校验清单。

包的主要内容：

```text
/design/tb/mdm_sec_u/
├── Makefile.u                        # U 网专用入口，强制使用预生成向量
├── Makefile                          # 公共 VCS/Verdi 规则，由入口文件包含
├── SHA256SUMS
├── README_U.md                       # 本文
├── rtl/                              # Verilog RTL 和 .vh
├── tests/rtl/
│   ├── tb_mdm_sec.sv                 # 整包仿真最顶层
│   └── tb_aes_random.sv              # AES 块级仿真最顶层
└── vectors/
    ├── wave_vectors.txt              # tb_mdm_sec 真正读取的文件
    ├── wave_vectors.cases.txt        # 用例说明，不是仿真输入
    ├── aes_vectors.txt               # tb_aes_random 真正读取的文件
    └── generation_info.txt           # 外网生成记录
```

## 4. U 网：配置工具并运行

在 U 网按本机已有安装方式配置 `VCS_HOME`、`VERDI_HOME`（或 `NOVAS_HOME`）、`PATH` 和有效许可证，不要将许可证或真实密钥写入仓库。需要与 VCS 匹配的 Verdi PLI `novas.tab`、`pli.a`，默认从 `VERDI_HOME`/`NOVAS_HOME` 的 `share/PLI/VCS/LINUX64` 或 `linux64` 查找；特殊安装布局可在命令后设置 `VERDI_PLI_DIR=/本机实际目录`，或分别指定 `VERDI_TAB`、`VERDI_PLI`。路径避免空格。Verdi GUI 需要图形显示环境，生成 FSDB 本身不需要启动 GUI。

```sh
cd /design/tb/mdm_sec_u
command -v vcs
command -v verdi
printf 'VCS_HOME=%s\nVERDI_HOME=%s\n' "$VCS_HOME" "$VERDI_HOME"

# 默认低面积 AES，20 个包和 8 个 AES 块；无 Python 调用
make -f Makefile.u fsdb BUILD_DIR=/design/tb/build/rtl
```

可只执行 `fsdb-packet` 或 `fsdb-aes`。如果 VCS 不在 `PATH`，可指定 `VCS=/本机实际路径/vcs`；Verdi 类似可指定 `VERDI=/本机实际路径/verdi`。为避免重复使用旧版本 RTL 编译出的 `simv`，**U 网入口每次仿真均重新编译**，打开 Verdi 时不重编译。即使使用 `-B` 或文件时间戳变化，该入口也不会生成向量或调用 Python。

预期输出：

```text
/design/tb/build/rtl/
├── vcs_packet_512_1/
│   ├── vcs_compile.log               # tb_mdm_sec 编译日志
│   ├── sim.log                       # 整包自检日志
│   └── simv.daidir/                  # 对应 VCS/Verdi 数据库
├── vcs_aes_1/
│   ├── vcs_compile.log
│   ├── sim.log                       # AES 自检日志
│   └── simv.daidir/
└── waveforms/
    ├── mdm_sec_low_area.fsdb         # 整包原生 FSDB
    └── aes128_low_area.fsdb          # AES 原生 FSDB
```

不要把 `BUILD_DIR` 设置成包含源码或向量的 `/design/tb` 或 `/design/tb/mdm_sec_u`；一般 Makefile 的 `clean` 会删除整个 `BUILD_DIR`。U 网入口不开放 `clean` 和 Python 回归目标。

### 验收和打开波形

```sh
grep -E 'DIRECTED configuration|PASS directed waveform cases|PASS 20 packet vectors' \
  /design/tb/build/rtl/vcs_packet_512_1/sim.log
grep -F 'PASS 8 AES blocks, 50-cycle latency/II' \
  /design/tb/build/rtl/vcs_aes_1/sim.log
ls -lh /design/tb/build/rtl/waveforms/*.fsdb

make -f Makefile.u verdi-packet BUILD_DIR=/design/tb/build/rtl
make -f Makefile.u verdi-aes BUILD_DIR=/design/tb/build/rtl
```

成功条件是 Make 返回 0、对应日志有上述自检 `PASS`、FSDB 非空并能在本地 Verdi 打开。Make 检查日志和文件非空，但**不解析 FSDB 内部事件**。日志中如果出现 `$fatal`、编译错误、超时或缺失 `PASS`，不能算通过；编译或校验失败时旧日志/波形可能仍在，不能拿旧文件当本次结果。查看 `vcs_compile.log` 和 `sim.log` 定位问题。

### 可选：全部 AES 向量和高速配置

```sh
# 全部 515 个 AES 块，用独立 BUILD_DIR 保留上面的 8 块波形和日志
make -f Makefile.u fsdb-aes BUILD_DIR=/design/tb/build/rtl_aes_all WAVE_AES_BLOCKS=515
# 预期：PASS 515 AES blocks, 50-cycle latency/II
make -f Makefile.u verdi-aes BUILD_DIR=/design/tb/build/rtl_aes_all

# 高速 AES 配置，仍使用同一份转网向量；编译目录和波形名不同
make -f Makefile.u fsdb BUILD_DIR=/design/tb/build/rtl WAVE_AES_LOW_AREA=0
make -f Makefile.u verdi-packet BUILD_DIR=/design/tb/build/rtl WAVE_AES_LOW_AREA=0
```

高速配置的波形为 `mdm_sec_fast.fsdb`、`aes128_fast.fsdb`，AES 延迟/启动间隔为 5 拍；低面积配置为 50 拍，这不是整包延迟。`FSDB_MDA=1` 可额外记录包缓存数组，会增大 FSDB 并覆盖同名包波形；如需保留旧结果，另设 `BUILD_DIR` 或 `FSDB_DIR`，打开 Verdi 时使用相同参数。

## 5. 仿真实际读取和比对内容

整包最顶层是 `tb_mdm_sec`，其 `dut` 是设计顶层 `mdm_sec`；AES 最顶层是独立的 `tb_aes_random`，其 `dut` 是 `mdm_aes128`。Make 使用绝对路径启动各自的 `simv`，等价于传入：

```text
+VECTORS=/design/tb/mdm_sec_u/vectors/wave_vectors.txt
+VECTORS=/design/tb/mdm_sec_u/vectors/aes_vectors.txt
```

两个 testbench 通过 `$fopen`/`$fscanf` 读取文件；前者驱动命令和数据，检查 MAC、状态、输出数据、握手及依赖，后者逐块比较 AES 输出并检查时序。期望结果已在外网写入向量，U 网无需计算 Python 参考值；默认不额外生成完整 DUT 输出向量文件。失败时 `$fatal` 并写日志。

Verdi 中先观察 `tb_mdm_sec.wave_case_id`、`wave_phase`、`cmd_valid/cmd_ready`、`in_valid/in_ready`、`rsp_valid/rsp_ready`、`cipher_valid/cipher_ready`，然后对照 `vectors/wave_vectors.cases.txt`。其中用例 11 为模式 5 认证成功，用例 12 为 MAC 被篡改，预期 `rsp_mac_match=0`；这是**预期负例而非仿真失败**。模式 5 认证失败时 RTL 仍输出明文，系统必须丢弃未认证数据。

## 6. 本次检查结果

- 外网侧已生成 **20 个包用例和 515 个 AES 块**；PyCryptodome 对 AES 块、AES-CTR 和 AES-CMAC 的独立检查通过。
- 转网包解压后不含 Python 源码；用 Verilator 分别编译低面积和高速 RTL，两种配置均通过 20 个包和全部 515 个 AES 块。已编译的仿真程序在 `PATH` 不含 Python 的环境中运行也通过。
- 离线入口的 7 项自动检查通过，包括纯 shell 模拟 VCS 且 `PATH` 中没有 Python、`make -B`、时间戳变化、禁止复用旧 `simv`、缺失/损坏文件和误用目标。**这些是流程模拟，不是真实 VCS 或 FSDB 检查。**
- 本次环境没有 VCS/Verdi，不能访问 U 网 `/design/tb/`。实际的 VCS 编译、Verdi PLI、波形生成和打开仍须在 U 网确认。

## 7. 常见问题与限制

- `sha256sum -c` 失败：停止运行；确认包与 `.sha256` 同次生成、传输完整，并按批准流程重传。`SHA256SUMS` 失败也应重新转入完整包。
- `Packet/AES vectors missing`：确认解压后的 `vectors/` 完整；U 网不会自动补生成。
- `Install/configure VCS` 或许可证失败：检查本机 VCS、编译器和许可；`Verdi PLI not found` 检查 PLI 目录、版本和读权限。
- 避免在 U 网直接运行 `make fsdb` 或 `make test`：普通 `Makefile` 的默认开发流程可能自动调用 Python。**只使用 `make -f Makefile.u ...`**，该入口只允许上述仿真、Verdi 和校验目标。
- `wave_vectors.cases.txt` 不是激励文件；修改 RTL、TB 或向量后需在外网用匹配版本重新生成整个包，不要跳过哈希检查。
- 历史 Verilator/Icarus 自检通过，并不代表已在 U 网实际运行 VCS。当前环境没有 VCS/Verdi，也无法访问 `/design/tb/`，真实 VCS 编译、PLI 和 FSDB 仍需在 U 网执行确认。
