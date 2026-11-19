# MDM_SEC RTL

本仓库提供可综合的 3GPP 安全处理 RTL，并保留原有 Python 模型和测试数据。顶层为 [`rtl/mdm_sec.v`](rtl/mdm_sec.v)：128 位数据接口、16 位字节数、独立加密和完整性通道，以及六种处理模式。模式 2–5 在输入装载完成后同拍启动两条通道；原地共享缓冲按字节保护尚未消费的原文或尚未产生的结果，不保证每拍都同时推进。模式 5 提取解密结果尾部 4 字节验证码，并计算和比较 MAC。算法支持 SNOW 3G、AES-128、ZUC 和 NULL。

## 快速运行

需要 Python 3、GNU Make、C++ 编译器及支持 `--binary --timing` 的 Verilator 5：

```sh
make example              # 可直接运行的 AES 双通道使用示例
make test                 # Verilog lint、规格书检查、原语、通道、缓存及端到端回归
make test-directed        # 20 个易于观察的六模式包测试，不生成波形
make wave                 # Verilator：执行自检并生成低面积版 VCD
make wave WAVE_AES_LOW_AREA=0  # Verilator：生成原高速 AES 配置的 VCD
make wave WAVE_AES_LOW_AREA=2  # 生成 5 拍面积优化 AES 配置的 VCD
make test-balanced         # 优化 AES 的原语、双通道和包级回归
make test-aes-formal       # MixColumns SAT + 5 拍核等价（需要 Yosys）
make area-aes-balanced     # 原高速与优化版同条件通用综合对比
make fsdb                 # VCS + Verdi PLI：执行自检并生成 FSDB
make verdi-packet         # 用 Verdi 打开包级 FSDB 和 VCS 设计数据库
make yosys-check          # Yosys 结构检查，默认 2048 字节配置
make yosys-parameters     # 检查非法参数被拒绝
make synth-generic        # 可选：16 字节配置通用综合，非物理面积
make area-compare         # 同条件重现优化前后 AES、缓存和顶层比较
```

也可从 PyPI 安装 `verilator` 和 `yowasp-yosys`；Makefile 自动查找 `verilator`/`verilator-cli` 和 `yosys`/`yowasp-yosys`。工具路径可用 `VERILATOR=...`、`YOSYS=...` 覆盖。Python 的 `pycryptodome` 是可选依赖：安装后额外独立交叉检查 AES；未安装时固定向量和 RTL 回归仍可运行。生成文件位于忽略目录 `build/rtl/`。`make wave` 生成的 VCD 可用 GTKWave 打开；`make fsdb` 需要本地授权的 VCS/Verdi 并通过 Verdi PLI 生成原生 FSDB。两者的命令和依赖不同。

**外网生成向量、U 网无 Makefile/Python，直接用 `run.sh` 运行 VCS/Verdi，请看 [`docs/u_network_test.md`](docs/u_network_test.md)。** 五份 Word RTL 设计规格书及维护方法见 [`docs/specs/`](docs/specs/)，新增 5 拍优化核详见 [`aes_balanced_core_spec.docx`](docs/specs/aes_balanced_core_spec.docx)。从例化、握手及运行示例入手，请看 [`docs/quickstart.md`](docs/quickstart.md)；验证顶层、向量与 `/design/tb/` 输出目录见 [`docs/tb_environment.md`](docs/tb_environment.md)；20 个定向用例及波形查看方法见 [`docs/waveforms.md`](docs/waveforms.md)，同机运行 Synopsys VCS/Verdi 见 [`docs/synopsys_fsdb.md`](docs/synopsys_fsdb.md)；接口时序和限制见 [`docs/rtl_interface.md`](docs/rtl_interface.md)，综合对比、AES 层次及 input buffer 的作用见 [`docs/area_optimization.md`](docs/area_optimization.md)，测试记录见 [`docs/verification.md`](docs/verification.md)。顶层输入和输出为 128 位，内部通道以 32 位字工作。默认 `AES_LOW_AREA=1` 为 50 拍/块；`0` 为原 5 拍高速核；`2` 为新的 5 拍面积优化核。SNOW 3G/ZUC 初始化后每拍处理 32 位。整包还包括装载、依赖等待、MAC 和输出握手，不能将原语拍数当作整包延迟。

可综合模块是 Verilog `.v`，`.vh` 为 Verilog include 文件；验证环境的 testbench 使用 SystemVerilog `.sv`。状态机的状态寄存器、组合次态和输出/数据逻辑分离；Verilog 源码逐行至多一个代码分号。

AES S 盒的布尔电路改写自 BearSSL 的 MIT 许可实现，版权与许可原文保留在 [`rtl/mdm_aes_sbox.v`](rtl/mdm_aes_sbox.v) 和 [`rtl/mdm_aes_sbox.vh`](rtl/mdm_aes_sbox.vh)。5 拍优化版的 MixColumns XOR 电路改写自 Joe Bachir 的 MIT 许可实现；该电路源自 Jeremy Jean 已发表的 88-XOR 工作，版权、许可、出处和字节序改动见 [`rtl/mdm_aes_mix_balanced.vh`](rtl/mdm_aes_mix_balanced.vh)。
