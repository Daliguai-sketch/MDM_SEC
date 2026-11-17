# 六模式 RTL 验证记录

以下为加入模式 5 和模式 2–5 同拍启动、按数据依赖等待后的回归结果。环境：Verilator 5.38、Yosys 0.64（YoWASP）、Python 3.11、PyCryptodome 3.23。命令从仓库根目录执行。

| 命令 | 结果 |
|---|---|
| `make example` | PASS：模式 4 的 AES-CTR/AES-CMAC 命令、输入、响应和输出握手示例；MAC 和密文另与 PyCryptodome 计算结果核对 |
| `make test -j 2` | PASS：使用示例、Verilog-2005 lint、三段式状态机/逐行分号/扩展名检查；AES/SNOW 3G/ZUC 原语及通道；16-bank 缓存；2641 个默认容量、240 个最小容量及 12 个最大容量包向量 |
| `make yosys-check` | PASS：`MAX_BYTES=2048`，不使用 `-sv` 的 Verilog 前端、层次展开、优化及 `check -assert`，报告 0 个问题 |
| `make yosys-check CHECK_MAX_BYTES=65535 BUILD_DIR=build/rtl-maxcheck` | PASS：最大容量参数的 RTL 层次/结构检查，报告 0 个问题；不是把该容量全部映射为触发器的面积综合 |
| `make yosys-parameters` | PASS：`MAX_BYTES=0` 和 `65536` 均由参数检查在 Yosys 展开阶段拒绝 |
| `make synth-generic` | PASS：`MAX_BYTES=16`，`synth -noabc` 后 `check -assert` 报告 0 个问题 |
| `python3 -S tests/gen_vectors.py ...`、`tests/gen_tiny_vectors.py ...` 和 `tests/gen_boundary_vectors.py ...` | PASS：无第三方 Python 包时均能生成向量，输出与启用 PyCryptodome 交叉检查的生成结果逐字节一致 |

六种模式均验证 4×4 算法组合、128 位 A/B 字节对齐、空段、响应和输出停顿及复位。模式 2–5 的所有合法向量均检查两条通道恰好一次、同拍启动；针对每个模式的定向长包，分别覆盖 4 种加密算法（包括 EEA0）× 3 种非空完整性算法，确认每种组合至少有一拍两条通道实际同时传输。定向覆盖记录中模式 2/3/4/5 各有 12 种组合；模式 2/3/5 分别有 12/5/5 个用例实际遇到依赖等待。测试还检查模式 2 不提前加密附加 MAC、模式 3/5 不读取此前未提交的结果字节、通道输入在停顿时保持稳定，以及每种双通道模式在实际并发传输后复位并能处理后续包。

模式 5 包含模式 2→5 同参数往返、解密后的四个验证码字节分别篡改、A 和密文载荷篡改、正确与错误验证码、跨 32/128 位边界、仅 4 字节验证码、`B<4` 拒绝、提取后复位、跨命令清除、背压以及最大 65535 字节输入。测试逐项比较提取值、计算的 MAC、相等标志、长度和所有输出 beat；最大长度同时检查 AES 末块启动数和 16 位字节计数不回绕。正常和最大长度的 AES-CTR/CMAC 参考结果均额外用 PyCryptodome 核对。

`make synth-generic` 在上述工具版本下统计到整个层次 **65,169 个通用逻辑/触发器单元**。这是 `MAX_BYTES=16`、未运行 ABC 目标库映射的结构统计，包含将小容量缓存和查找表映射为通用逻辑的结果；它不是标准单元面积、门等效数、默认 2048 字节配置面积，也不是频率或时序签核。实际面积和时序必须在目标工艺、存储宏及约束下确定。

`rsp_mac_match` 只是两个 32 位值的比较，错误时模块仍输出解密数据；EIA0 不提供完整性保护。系统必须自行丢弃未认证数据并完成协议和安全处理。已知向量来源及接口限制见 [rtl_interface.md](rtl_interface.md)。
