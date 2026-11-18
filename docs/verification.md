# 六模式 RTL 验证记录

以下为共享原地缓存和可选低面积/高速 AES 的回归。环境：Verilator 5.38、Yosys 0.64（YoWASP）、Python 3.11、PyCryptodome 3.23。命令从仓库根目录执行；`build/` 是生成目录。

| 命令 | 结果 |
|---|---|
| `make test -j 2` | PASS：两个 AES 配置的 Verilog-2005 lint、编码检查、原语、通道、缓存、示例和端到端回归 |
| `make test-aes` | PASS：两种配置各 515 个 AES 块，逐块与参考模型比较，并逐块独立交叉检查 PyCryptodome；检查 50/5 拍延迟、最早连续启动、busy 时无效请求、输入变化和中途复位 |
| `make test-buffer` | PASS：1、64、259、65536 字节及单双读口配置；非对齐 1～16 字节写、独立读、同拍写前旧值/写后新值，以及完整 16 位地址回绕 |
| `make test-packet` | PASS：低面积 AES、`MAX_BYTES=2048`，2641 个包；模式 2/3/4/5 各 12 种非空完整性算法组合实际发生同拍传输 |
| `make test-tiny` / `make test-boundaries` | PASS：低面积 AES、最小容量 240 个包，最大容量 12 个包；包括模式 2 的 MAC 追加跨 `ffff→0000` |
| `make test-fast` | PASS：高速 AES 的原语、通道、2641 个默认容量包和 12 个最大容量包；同样覆盖模式 2–5 的 12 种并发组合和最大地址回绕 |
| `make test-directed`，以及 `make test-directed WAVE_AES_LOW_AREA=0` | PASS：两种 AES 配置各 20 个定向包，覆盖六种模式、认证成功/失败、MAC/明密文依赖等待、原地覆盖保护和同沿读旧值 |
| `make wave`，以及 `make wave WAVE_AES_LOW_AREA=0` | PASS：两种配置分别生成包和 AES VCD；自检并检查 VCD 内部时间、信号、模式 5 成功/失败事件和 AES 固定答案，见 [waveforms.md](waveforms.md) |
| `make test-vcs-flow` | PASS：使用模拟工具检查 VCS/Verdi 命令参数、PLI 路径、配置选择和失败处理；**不生成或验证真正的 FSDB** |
| `make example` | PASS：模式 4 AES-CTR/AES-CMAC 命令、输入、响应和输出握手；MAC 和密文另与 PyCryptodome 核对 |
| `make yosys-check`、`make yosys-check CHECK_MAX_BYTES=65535` | PASS：低面积配置，默认与最大参数的 Verilog 前端、层次展开、优化及 `check -assert` 报告 0 问题；最大容量只检查结构，不将其全部映射成触发器 |
| `make yosys-check CHECK_MAX_BYTES=65535 CHECK_AES_LOW_AREA=0` | PASS：高速配置、最大容量层次和结构检查 0 问题 |
| `make yosys-parameters` | PASS：`MAX_BYTES=0/65536`、`AES_LOW_AREA=2/3`、缓存容量 `0/65537` 和读口数 `0/3` 在 Yosys 展开时由参数检查拒绝 |
| `make area-compare` | PASS：同一 Yosys 配置重现优化前后单 AES、单/双缓冲及默认 2048 字节顶层对比，全部 `check -assert` 为 0 问题；详见 [area_optimization.md](area_optimization.md) |

`make test` 的大规模包回归合计 5,546 次：低面积版 2641 + 240 + 12，高速版 2641 + 12；另默认运行 20 个低面积定向包，高速定向包可用上表命令单独运行。六种模式覆盖 4×4 算法组合、128 位 A/B 字节对齐、空段、响应和输出背压以及复位。模式 2–5 的所有合法向量均检查两条通道恰好一次、同拍启动。每种模式的定向长包覆盖 4 种加密算法（包括 EEA0）× 3 种非空完整性算法，确认每种组合至少有一拍两条通道实际同时传输。

波形定向包中，低面积/高速配置的用例 7 分别有 210/30 拍原文等待和 53/8 拍 MAC 等待，均有 9 次同沿读旧值；用例 8 和 18 分别有 1398/3 拍结果依赖等待。用例 11/12 分别认证成功/失败。所有这些结果均由 testbench 自检，具体观察方法见 [waveforms.md](waveforms.md)。

在原有的大规模包回归定向覆盖中，模式 2/3/5 分别有 10/3/3 个用例实际遇到原有 MAC/结果依赖等待；高速版分别为 10/5/5。对于模式 2/4，两个配置下各 12 个定向组合都覆盖了原地覆盖保护等待，也覆盖了同拍读取原始字节并写回的情况。测试逐拍检查不可在完整性读取之前覆盖原文，模式 2 不提前加密附加 MAC，模式 3/5 不读取此前未提交的结果字节，且通道输入停顿时保持稳定。每种双通道模式均在实际并发传输后复位，并继续处理后续包。

模式 5 包含模式 2→5 同参数往返、解密后的四个验证码字节分别篡改、A 和密文载荷篡改、正确与错误验证码、跨 32/128 位边界、仅 4 字节验证码、`B<4` 拒绝、提取后复位、跨命令清除、背压以及最大 65535 字节输入。测试逐项比较提取值、计算的 MAC、相等标志、长度和所有输出 beat；最大长度同时检查 AES 末块启动数和 16 位字节计数不回绕。正常和最大长度的 AES-CTR/CMAC 参考结果均额外用 PyCryptodome 核对。

AES 固定答案采用 FIPS-197：`000102...0f` 密钥、`001122...ff` 输入、`69c4e0d86a7b0430d8cdb78070b4c55a` 输出；原语测试还覆盖全部 256 个新旧 S-box 值，以及 SNOW 3G、ZUC 已知答案。使用 `python3 -S` 对 AES、默认包、最小容量包、最大容量包和波形定向包的向量生成器重新生成，均与启用 PyCryptodome 的结果逐字节一致。没有 PyCryptodome 时仍会跑参考模型和固定答案，但会跳过其独立交叉检查。

新增 VCS/Verdi FSDB 接口时，使用四态 Icarus 仿真器（WebAssembly 版本）分别运行了低面积和高速配置的 20 个包定向用例、各 8 个 AES 块，均通过；启用 FSDB 宏的两个 bench 也完成了 HDL 编译检查。本次环境没有 VCS、Verdi 及其授权，尚未实际链接 Verdi PLI、生成或打开原生 FSDB；请在本地按 [synopsys_fsdb.md](synopsys_fsdb.md) 运行验证。

综合结果为通用逻辑/触发器单元数量，不是标准单元面积、SRAM 实际面积、最大频率或签核结果。使用何种 SRAM、端口和读写碰撞语义会显著改变实现；见 [area_optimization.md](area_optimization.md)。

`rsp_mac_match` 只是两个 32 位值的比较，错误时模块仍输出解密数据；EIA0 不提供完整性保护。系统必须自行丢弃未认证数据并完成协议和安全处理。已知向量来源及接口限制见 [rtl_interface.md](rtl_interface.md)。
