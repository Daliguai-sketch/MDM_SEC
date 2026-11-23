# U 网无 Makefile 仿真：filelist + run.sh

## 1. 流程与范围

向量在外网用 Python 参考模型生成，连同 RTL、testbench 和脚本按批准流程转入 U 网；**U 网的项目流程只运行 `run.sh`，无需项目 Makefile、Python、pip 或网络**。U 网需要 Linux、Bash、VCS、Verdi PLI、许可证、VCS 所需 C/C++ 工具，以及 `tar`、`mktemp` 等基本工具。`run.sh` 不调用 `make`；VCS 自身编译流程可能需要 GNU make/gmake，具体以现场 VCS 安装要求为准。

默认一条命令执行：

1. `tb_mdm_sec` 读取并自检 **2641 个包级回归向量**，不打开波形，避免完整回归 FSDB 过大；
2. 使用同一个 `simv` 自检 **20 个定向包**，生成原生 `waves.fsdb`；
3. 单独编译 `tb_aes_random`，回归前 **8 个 AES 块**并生成 AES FSDB；可选全部 515 个。

也可只跑包级或跳过 2641 包。2641 包是默认 `MAX_BYTES=2048` 的一组配置，**不是涵盖三种 AES 和全部容量的完整回归**；默认 AES 为低面积配置。所有测试数据和密钥仅用于验证，不得在可公开波形中放真实密钥。

## 2. 外网生成并打包

在包含本仓库 `rtl/`、`tests/`、`sec_core/`、`tools/` 的外网机器上执行：

```sh
# 可选：安装后对 AES 块、CTR 和 CMAC 增加独立交叉检查
python3 -m pip install pycryptodome

# 此步骤在外网执行；不需要 VCS/Verdi，也不使用 Make
python3 tools/prepare_u_bundle.py --output deliverables/u_transfer
```

生成 `deliverables/u_transfer/mdm_sec_u.tar.gz`，将这一个文件转网即可；相同输入和生成环境下可重现。**只有生成命令成功退出并输出包路径后再转网**；失败时目录可能仍有上一次的旧包，不能当作新结果。PyCryptodome 不可用时仍生成固定答案及参考向量，但日志会明确提示跳过独立 AES 检查。脚本只覆盖该同名输出，`deliverables/` 不提交 Git。

## 3. 转网包目录及 filelist

```text
mdm_sec_u/
├── README_U.md
└── design/
    ├── vc/
    │   ├── mdm_sec_rtl.vc            # RTL 文件列表和 +incdir
    │   ├── mdm_sec.v                 # 所有 .v 均在 vc/
    │   ├── mdm_aes128*.v ...
    │   ├── mdm_aes_balanced_blocks.v # 5 拍优化核的分层组合模块
    │   └── mdm_sboxes.vh ...         # 必需的 include 文件
    └── tb/
        ├── run.sh                    # 一条命令执行默认回归和 FSDB
        ├── filelist.f                # 整包编译列表
        ├── tb_mdm_sec.sv             # 整包仿真顶层
        ├── filelist_aes.f            # 可选 AES 测试列表
        ├── tb_aes_random.sv          # 可选 AES 仿真顶层
        └── vectors/
            ├── packet_vectors.txt    # 2641 包，输入及参考期望
            ├── wave_vectors.txt      # 20 个定向包，输入及参考期望
            ├── wave_vectors.cases.txt# 20 个用例的可读说明
            ├── aes_vectors.txt       # 515 个 AES 块
            └── generation_info.txt   # 外网生成日志和生成器名称
```

`tb/filelist.f` 对应用户给出的两级文件列表：

```text
-f ../vc/mdm_sec_rtl.vc
tb_mdm_sec.sv
```

与截图中的绝对路径形式等价，但这里采用 `vc/` 和 `tb/` 之间的相对路径，可把整个 `design/` 放到不同机器而不改写用户名路径。`mdm_sec_rtl.vc` 中列出 `../vc/*.v` 和 `+incdir+../vc`；`.vh` 随 RTL 一同复制。运行脚本会在独立输出目录建立同样的 `vc/tb` 相对布局，使用上述 `filelist.f` 编译。

外网产生的向量不包含 Python 源码；不能在 U 网自动补生成。请将 RTL、testbench 和向量作为一个完整的包转入，不要混用不同版本。脚本只检查所需文件是否存在、可读且非空，不检查传输后内容是否改变。

`AES_LOW_AREA=2` 的 balanced 核已拆分模块，转入时必须同时更新 `mdm_aes128_balanced.v`、新增的 `mdm_aes128_balanced_timing.v`、`mdm_aes_balanced_blocks.v` 和文件列表；也需要包内的 `mdm_aes_blocks.v`、`mdm_aes_sbox.v`、`mdm_aes_mix_balanced.vh` 及 include 路径。若综合使用独立 filelist，也必须加入新 `.v`。综合顶层参数默认是 1；选择 2 后，cipher 选原 balanced，integrity 默认选时序候选；顶层 `AES_INTEGRITY_TIMING_OPT=0` 可回退。仿真脚本的环境变量不会自动传给 `rc_flow`。该核下的 `u_key_expand1/2`、`u_round1/2` 可查看层次面积；综合自动 flatten 可能移除层次，需由现场流程按工具版本保留并报告，父级含子级时不要重复累加面积。新完整性实例路径为 `g_balanced_timing.u_core`，必须重新核对现场 SDC 和实例匹配。

### 3.1 综合参数及 375 MHz 对比

比较两次 RTL elaboration：均将 `mdm_sec.AES_LOW_AREA` 设为 2，`AES_INTEGRITY_TIMING_OPT` 分别设为 0（原版）和 1（时序候选），其他工艺、约束、PVT、保层和综合选项保持一致。若现场流程不提供参数覆盖入口，可在**独立的综合源码副本**修改 `mdm_sec.v` 的默认值，再确认没有其他参数覆盖：

```verilog
parameter integer MAX_BYTES = 2048,
parameter integer AES_LOW_AREA = 2,
parameter integer AES_INTEGRITY_TIMING_OPT = 1  // 对比原版时改为 0
```

然后按现场既有命令 `rc_flow -top mdm_sec -syn rtl3` 重新展开、综合和报告。此处不了解现场 `rc_flow` 包装器，不假定它支持额外传参；`env AES_LOW_AREA=2 ... ./run.sh` 只配置仿真。检查 elaboration 实例、SDC、`dont_touch` 和路径组是否匹配新层次；不要将每拍更新的 `round_state` 反馈设为 5 拍 multicycle 或 false path。分别检查两个通道的 setup/hold、全设计 WNS/TNS、关键路径和面积，再进行所需工艺角及布局布线后 STA。当前候选仅在未映射通用逻辑上观察到拓扑级数下降，**没有目标工艺延时或 375 MHz 收敛保证**。

## 4. U 网解压并运行

以下 `/design/tb/` **仅为转网工作目录示例**；请按本机实际路径替换，不假定它是仓库根目录。把压缩包转入一个可写目录，并确认没有同名 `mdm_sec_u` 目录。先配好 VCS、Verdi 和许可证，再执行以下命令；任一步失败都会停止后续命令：

```sh
# /design/tb 按本机实际转网目录替换
cd /design/tb && \
  test ! -e mdm_sec_u && test ! -L mdm_sec_u && \
  tar -xzf mdm_sec_u.tar.gz && \
  cd mdm_sec_u/design/tb && \
  ./run.sh
```

已解压且环境配置好以后，只需进入 `mdm_sec_u/design/tb` 并运行 `./run.sh`；脚本每次会检查所需输入文件是否可读且非空。

如果将包内 `design/vc/`、`design/tb/` 完整安装到现有工程，而该工程路径与截图相同，也可以进入 `/proj/asic/xin.zhang/r3p0/nl_sec_dev/nl_sec/de/design/tb` 运行 `./run.sh`。**已有工程先核对冲突并自行备份，不要直接覆盖同名源码或用户文件**；RTL、testbench、向量及清单必须来自同一个包。相对 filelist 不要求这个特定绝对路径。

在 U 网通过既有方式设置 VCS 和 Verdi，并将工具路径设为环境变量供脚本继承。以下检查适用于 Bash 和 csh/tcsh：

```sh
which vcs
which verdi
env | grep -E '^(VCS_HOME|VERDI_HOME|NOVAS_HOME)='
```

若站点尚未设置，Bash 中使用 `export VCS_HOME=/实际路径`，csh/tcsh 中使用 `setenv VCS_HOME /实际路径`；`VERDI_HOME` 同理。脚本自身通过 Bash 运行，但交互终端可以是其他 shell。

默认按截图中的 `$VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab` 与 `pli.a` 查找；也支持 `linux64`、`NOVAS_HOME`，或者显式设置 `VERDI_PLI_DIR`，也可同时设置 `VERDI_TAB` 和 `VERDI_PLI`。`VCS=/实际路径/vcs` 可指定可执行程序。不要将许可证写入仓库或脚本。

### 使用 `bsub_cmd`

脚本如果在 `PATH` 中找到 `bsub_cmd`，默认使用它提交编译和每次仿真；否则直接运行 `vcs` / `simv`。也可明确选择：

```sh
env BSUB_CMD='' ./run.sh                         # 在已分配计算节点中直接执行
env BSUB_CMD='bsub -K -q your_queue' ./run.sh   # 示例：使用站点实际队列，阻塞直到结束
```

`BSUB_CMD` 以空格拆分为命令和参数，不执行 shell 求值；交互式 alias 不会自动继承。在 Bash 终端中，如站点的 `bsub_cmd` 是 Bash 函数，应先 `export -f bsub_cmd` 或提供可执行包装脚本；csh/tcsh 环境建议提供可执行包装脚本。**包装器必须等待任务完成、返回真实退出码，并在共享文件系统上保留当前工作目录。** 脚本通过任务退出后写入的状态文件检测“只提交、不等待”的包装器；检测到异步返回时会报错，任务可能仍在后台排队/执行，需先按站点规则处理，不能把它当成功。原截图里的 `set -e` 本身无法保证异步任务的结果已返回。

### 脚本实际命令与 testbench 参数

编译会使用 `-f filelist.f`、`-full64 -sverilog -debug_access+all`、`-P novas.tab pli.a`，并额外指定 `+define+MDM_SEC_FSDB`、`-top tb_mdm_sec` 和 testbench 参数；缺少 `+define+MDM_SEC_FSDB` 或 `+FSDB=...` 时当前 testbench **不会**生成 FSDB。`run.sh` 会显式传入 `+VECTORS=...` 和 `+FSDB=...`。本仓库的 `tb_mdm_sec.sv` 在一个仿真进程中读取整份向量并自检，不使用截图中注释掉的 `+TEST/+ENC_ALG/+INT_ALG` 来选择用例；运行那些参数并不会替代 `+VECTORS`。

默认结果在每次新建的独立目录，实际完整路径由脚本打印：

```text
tb/runs/mdm_sec_XXXXXXXX/
├── vc -> 原始 design/vc             # 指向同一 RTL 的符号链接
├── tb/
│   ├── compile.log                  # VCS 编译日志
│   ├── regression.log               # 2641 包自检日志
│   ├── sim.log                      # 20 个定向包及波形日志
│   ├── simv  simv.daidir/
│   └── waves.fsdb                   # 20 包原生 FSDB
├── aes/                             # 默认 AES 块仿真，RUN_AES=0 时不存在
│   ├── compile.log  sim.log  simv  simv.daidir/
│   └── aes_waves.fsdb
└── *.status                         # 实际作业退出状态
```

每次运行新建目录并重新编译，不删除或复用旧 `simv`、日志或波形。`RUN_ROOT=/其他可写目录` 可指定输出目录；该目录必须在批处理计算节点可见。注意输出目录必须允许创建符号链接，FSDB 可能较大。

成功条件：脚本退出码为 0，`regression.log` 含 `PASS 2641 packet vectors` 和并行覆盖 PASS，`tb/sim.log` 含正确的 `AES_LOW_AREA` 和 `AES_INTEGRITY_TIMING_OPT` 配置、`PASS directed waveform cases` 和 `PASS 20 packet vectors`，`aes/sim.log` 含正确的 `AES_LOW_AREA`、`BALANCED_TIMING_OPT` 及 `PASS 8 AES blocks`，两份 FSDB 均非空。禁用某项时只检查其余启用的项目。脚本检查这些条件，但**不会解析 FSDB 内部事件**；请用本机 Verdi 打开脚本打印的 `simv.daidir` 与 `waves.fsdb`：

```sh
verdi -simflow -dbdir /脚本打印的路径/tb/simv.daidir \
      -ssf /脚本打印的路径/tb/waves.fsdb
```

观察 `tb_mdm_sec.wave_case_id`、`wave_phase` 和 DUT 的命令/输入/响应/输出握手；定向用例 11 为模式 5 认证成功，12 为篡改验证码的预期失败。模式 5 比较失败时 RTL 仍输出明文，系统必须丢弃未认证数据。

## 5. 可选配置

使用 `env` 可在 Bash 和 csh/tcsh 终端均传递本次运行的环境变量；不要写成 `./run.sh AES_LOW_AREA=0`（脚本不接受这样的命令行参数）：

```sh
env RUN_FULL=0 ./run.sh                          # 跳过 2641 包，仍跑 20 个定向包 + 8 AES
env RUN_AES=0 ./run.sh                           # 只跑包级 testbench，不编译 AES testbench
env AES_LOW_AREA=0 ./run.sh                      # 选择原 5 拍高速 AES；默认是 50 拍低面积
env AES_LOW_AREA=2 ./run.sh                      # cipher 原 balanced；integrity 5 拍时序候选
env AES_LOW_AREA=2 AES_INTEGRITY_TIMING_OPT=0 ./run.sh  # integrity 回退原 balanced
env FSDB_MDA=1 ./run.sh                          # 额外 dump 包缓冲数组，波形更大
env AES_BLOCKS=515 ./run.sh                      # AES 回归全部 515 块并生成对应 FSDB
env FSDB_FULL=1 ./run.sh                         # 2641 包也生成 regression.fsdb，可能很大
env RUN_ROOT=/design/tb/sim_outputs ./run.sh     # 可选，路径按本机情况修改
```

默认 `RUN_AES=1` 使用 `filelist_aes.f` 和 `tb_aes_random.sv` 单独编译；输出在同一次运行目录的 `aes/` 下，包含 `compile.log`、`sim.log`、`simv.daidir` 和 `aes_waves.fsdb`。当 `AES_LOW_AREA=2` 时，独立 AES 测试也按 `AES_INTEGRITY_TIMING_OPT` 选择候选或原版；该变量默认 1，仅影响脚本的仿真参数，不设置综合参数。`AES_BLOCKS` 范围为 2～515。`FSDB_FULL=1` 需要 `RUN_FULL=1`，在 `tb/regression.fsdb` 额外记录完整回归；失败时可参考部分波形调试，但失败文件不算通过。`AES_LOW_AREA=1/0/2` 的 50/5/5 拍为单块原语时序，不是整包延迟。`VCS_EXTRA_FLAGS` 可传空格分隔的本地 VCS 额外选项，不进行 shell 求值。

## 6. `u_aes/g_fast` 可见但 `u_core` 没有波形

此 U 网脚本生成的是 VCS/Verdi **FSDB**，不是外网 Verilator 的 VCD；外网旧版 `--trace-depth 4` 的 VCD 问题不能直接当作本 FSDB 的原因。当前包级 testbench 在传入 `+FSDB=...` 后调用 `$fsdbDumpvars(0,tb_mdm_sec)`，请求递归 dump 普通信号；脚本的 VCS 编译包含 `-debug_access+all -kdb -lca`。`FSDB_MDA=1` 只额外 dump 包缓冲的存储数组，与 AES 普通信号无关。实际 FSDB 内容仍需在本地 VCS/Verdi 中检查。

为缩短排查时间，可从 `mdm_sec_u/design/tb` 再运行一次（自动新建目录，不覆盖旧运行）：

```sh
env AES_LOW_AREA=0 RUN_FULL=0 FSDB_FULL=0 ./run.sh
# 下列路径是示例；全部替换成脚本打印的同一次 Fresh output directory：
grep -E 'Writing packet FSDB|DIRECTED configuration|PASS directed waveform|PASS 20 packet' "/实际打印的路径/mdm_sec_XXXXXXXX/tb/sim.log"
grep -Ei 'fsdb|pli|warning|error' "/实际打印的路径/mdm_sec_XXXXXXXX/tb/compile.log" "/实际打印的路径/mdm_sec_XXXXXXXX/tb/sim.log"
verdi -simflow -dbdir "/实际打印的路径/mdm_sec_XXXXXXXX/tb/simv.daidir" -ssf "/实际打印的路径/mdm_sec_XXXXXXXX/tb/waves.fsdb"
```

预期配置行包含 `MAX_BYTES=2048 AES_LOW_AREA=0`。`RUN_FULL=0` 只跳过 2641 包回归，仍运行 20 个定向包；如果站点使用 `bsub_cmd`，仍需采用第 4 节的阻塞提交方式。不要把 `tb/` 的设计数据库配给 `aes/aes_waves.fsdb`，也不要混用不同运行的数据库和 FSDB。独立 AES 测试要使用同一运行的 `aes/simv.daidir` 和 `aes/aes_waves.fsdb`：

```sh
# 将示例路径替换为脚本打印的同一次运行路径
verdi -simflow -dbdir "/实际打印的路径/mdm_sec_XXXXXXXX/aes/simv.daidir" -ssf "/实际打印的路径/mdm_sec_XXXXXXXX/aes/aes_waves.fsdb"
```

不要用 `verdi -f filelist.f -ssf .../aes/aes_waves.fsdb`：`filelist.f` 包含的是包级 `tb_mdm_sec`，而该 FSDB 来自独立的 `tb_aes_random`。只重新读取 filelist 也不能保证继承生成 FSDB 时 VCS 的参数覆盖；两个 testbench 源码默认参数均为 1，可能显示 `g_low_area`。应加载生成该 FSDB 的 `simv.daidir`，以使用对应的设计数据库。

包级原高速核路径有两份，分别是 `tb_mdm_sec.dut.u_cipher.u_aes.g_fast.u_core` 和 `tb_mdm_sec.dut.u_integrity.u_aes.g_fast.u_core`；独立 AES 波形则是 `tb_aes_random.dut.g_fast.u_core`。仅 `AES_LOW_AREA=0` 是 `g_fast`，默认值 1 是 `g_low_area`；2 时 cipher 为 `g_balanced`、integrity 默认是 `g_balanced_timing`，回退选项为 0 时 integrity 也为 `g_balanced`。对于 0，`g_low_area` 不是选中的分支：如果看到低面积层次但 `u_aes.clk` 有波形，优先检查是否加载了旧设计数据库或旧信号列表，并用同次运行的数据库和 FSDB 新开 Verdi；外层 `u_aes.clk` 对各配置共用，不能单独证明内核匹配。`g_fast` 是 generate 块，内部时钟完整路径含 `g_fast.u_core.clk`。

先加入 `tb_mdm_sec.wave_case_id`，放大用例 1（加密 AES）、4（完整性 AES）或 6（两路 AES），同时加入相应实例的 `start/ready/busy/done`、`state/pair/round_state/key_reg/rcon`。接受请求为 `start && ready`，工作时 `pair` 经历 0～4；空闲时或未选 AES 的用例不会持续变化。

请区分设计树中层次或信号不存在、信号加入波形后无值、以及信号有值但没有变化：源码树可见不代表 FSDB 确实包含数据。若检查后仍有问题，保留运行命令、对应 `tb/compile.log`、`tb/sim.log`、FSDB 文件名及波形截图，按现场数据安全要求脱敏，禁止发送真实密钥。非空 FSDB 或自检 PASS 均不单独证明内部波形已记录。

## 7. 检查、故障与边界

- 可执行 `./run.sh --check-files` 只检查当前配置需要的文件是否可读、非空，不启动 VCS；文件缺失时请转入完整包。该检查不检测内容损坏或版本混用。需要修改 filelist 时，建议修改外网模板并重新打包。
- `VCS not found`、PLI 缺失或许可证错误：在 U 网检查工具路径、可读性、许可与 C/C++ 工具；查看对应 `compile.log`。不同 Verdi/VCS 版本需匹配。
- 仿真 `$fatal`、找不到向量、PASS 缺失或 FSDB 为空均视为失败；查看对应 `regression.log` 或 `sim.log`。失败运行目录可能有部分文件，不等于有效波形。
- 算法、背压和期望输出由 testbench 直接比较；外网参考期望已写入向量。`wave_vectors.cases.txt` 只是用例说明，不是仿真激励文件。
- 外层 Git 仓库仍保留开发用 Makefile；它不进入转网包，也不参与 U 网 `run.sh`。真实 VCS/Verdi、本站 `bsub_cmd` 和 FSDB 需要在用户 U 网验证；模拟工具或其他仿真器的结果不能替代该验证。
