# 1 Introduction

## 1.1 Purpose

本文描述 MDM_SEC 工程中 ZUC-128 密钥流原语的 RTL 接口、运算、状态组织和集成约束，供硬件设计、验证、综合及系统集成评审。用户所称 **zuc_core** 对应实际模块 `mdm_zuc`；仓库中没有独立的 `zuc_core` Verilog module。

本文依据当前 RTL 说明可观察行为。所有目标工艺的面积、功耗、时钟和时序结果在具备库、约束和工具报告前保留 TBD；已有功能回归不是算法认证或工艺签核。

## 1.2 Scope

本规范覆盖 128-bit key/IV 初始化、16 级 LFSR、比特重组、非线性函数、32 次混合更新、一次丢弃和 32-bit 密钥流输出。模块不输入消息、不计算 MAC，也不直接接受 COUNT/BEARER/DIRECTION。

MDM_SEC 中 `mdm_cipher` 的独立实例为 EEA3 提供密钥流；`mdm_integrity` 的另一个独立实例用于 EIA3 消息认证。协议 IV 生成、字节计数、XOR 和 MAC 均在外围实现，而非本原语端口。

## 1.3 Defines, Symbols, and Abbreviations

| 术语 | 定义 |
| --- | --- |
| ZUC-128 | 128-bit key、128-bit IV 的 ZUC 密钥流原语；不涉及 ZUC-256。 |
| LFSR | 16 级、每级 31 bit 的状态寄存器，RTL 为 `s[0:15]`。 |
| p | `2^31 - 1`，ZUC LFSR 运算使用的模数。 |
| BR | Bit Reconstruction，按固定片段组合得到 X0、X1、X2、X3。 |
| F / W | 非线性函数及其 32-bit 组合结果；并包含 R1、R2 状态。 |
| L1 / L2 | 对 32-bit 字进行异或和固定旋转的线性变换。 |
| S0 / S1 | 两种 8-bit 非线性替换表，交替应用到 32-bit 字节。 |
| Z | 密钥流字，`Z = W XOR X3`。 |
| E0 / En | E0 为 start 采样沿；En 为其后的第 n 个上升沿。 |
| EEA3 / EIA3 | 分别基于 ZUC 的 3GPP 机密性和完整性构造，由外围实现。 |

## 1.4 Design Features

| 项目 | 当前实现 |
| --- | --- |
| 模块/文件 | `mdm_zuc`，`rtl/mdm_zuc.v`；ZUC S-box 函数位于 `rtl/mdm_sboxes.vh`。 |
| Key / IV / word | 128 / 128 / 32 bit；key/IV 字节按高位字节先的顺序装载。 |
| 初始化 | start 后 32 个 INIT 状态更新沿和 1 个 DISCARD 更新沿。 |
| 密钥流吞吐 | WORK 且不重启/复位时 `valid && advance` 最多每拍消费 1 个 32-bit 字。 |
| 暂停 | WORK 中 `advance=0` 时所有算法状态及组合输出保持。 |
| 重启 | 任意状态 `start=1` 均优先装载新 key/IV，不提供 busy/ready。 |
| 时钟 / 复位 | 单时钟上升沿；异步低有效复位；释放同步由系统提供。 |

## 1.5 References

| 编号 | 资料与用途 |
| --- | --- |
| R1 | 3GPP TS 35.222, EEA3 & EIA3 Document 2: ZUC specification，ZUC 原语定义。 |
| R2 | 3GPP TS 35.221, Document 1: EEA3 and EIA3 specifications，协议构造。 |
| R3 | 3GPP TS 35.223, Document 3: Implementors' test data；规范版本以项目配置为准。 |
| R4 | 3GPP TS 33.401 Annex B/C，LTE EEA/EIA 用法和测试背景。 |
| R5 | `rtl/mdm_zuc.v`, `rtl/mdm_sboxes.vh`, `tests/rtl/tb_primitives.sv`, `docs/verification.md`。 |
| R6 | 3GPP 35 系列规范索引：https://www.3gpp.org/DynaReport/35-series.htm |

# 2 Microarchitecture

## 2.1 Background (Algorithm Principle)

ZUC 状态包含 16 个 31-bit LFSR 字和两个 32-bit 非线性寄存器。BR 从 LFSR 重组 X0～X3；函数 F 根据 X0～X2、R1、R2 形成 W 和下一组 R1/R2；输出密钥流字为 `W XOR X3`。LFSR 使用模 `p=2^31-1` 的运算。

RTL 的 BR 和非线性逻辑（右端均取更新前状态）如下；32-bit 加法按模 2^32 截断：

```text
X0 = {s[15][30:15], s[14][15:0]}
X1 = {s[11][15:0],  s[9][30:15]}
X2 = {s[7][15:0],   s[5][30:15]}
X3 = {s[2][15:0],   s[0][30:15]}
W  = (X0 XOR R1) + R2
W1 = R1 + X1;  W2 = R2 XOR X2
R1_next = S(L1({W1[15:0], W2[31:16]}))
R2_next = S(L2({W2[15:0], W1[31:16]}))
Z = W XOR X3
```

`L1(x)=x XOR ROTL32(x,2) XOR ROTL32(x,10) XOR ROTL32(x,18) XOR ROTL32(x,24)`；`L2(x)` 的旋转量为 8、14、22、30。`S(x)` 从高字节到低字节依次采用 S0、S1、S0、S1。

LFSR 反馈等价于在模 p 下相加 `s0 + 2^8*s0 + 2^20*s4 + 2^21*s10 + 2^17*s13 + 2^15*s15`；INIT 再加入 `W[31:1]`，DISCARD/WORK 不加入。RTL `add31` 使用进位回卷，`rot31` 实现 31-bit 旋转；反馈数值为零时映射为 `31'h7fffffff`。每次更新旧 `s[1]…s[15]` 移入 `s[0]…s[14]`，反馈进入 `s[15]`。

### 2.1.1 Key / IV 初始化

对 i=0…15，令 `K_i=key[127-8*i -: 8]`、`IV_i=iv[127-8*i -: 8]`，启动时装载 `s[i]={K_i,D_i,IV_i}`，共 31 bit。`r1/r2` 和 `init_count` 清零。D 常量由 RTL `d_const` 给出：

| i | D_i（15-bit hex） | i | D_i（15-bit hex） |
| --- | --- | --- | --- |
| 0 | 44d7 | 8 | 4d78 |
| 1 | 26bc | 9 | 2f13 |
| 2 | 626b | 10 | 6bc4 |
| 3 | 135e | 11 | 1af1 |
| 4 | 5789 | 12 | 5e26 |
| 5 | 35e2 | 13 | 3c4d |
| 6 | 7135 | 14 | 789a |
| 7 | 09af | 15 | 47ac |

## 2.2 Microarchitecture Analysis

### 2.2.1 Top Level Diagram

[[DIAGRAM:zuc]]

工作时 BR 和 F 在同一组合周期由当前寄存器值计算；INIT 将 W 的高 31 bit 注入 LFSR。图中的逻辑块不代表各有一级寄存器或深流水。

### 2.2.2 Timing Requirement

假设 E0 采样 `start=1`，其后无复位或重新启动；输出按上升沿前后的区别描述。

| 时刻 | RTL 行为 | 输出 / 接收 |
| --- | --- | --- |
| E0 | 载入 16 个 `{K,D,IV}` 和零化 R1/R2，进入 INIT。 | `valid=0`。 |
| E1～E32 | 32 次 INIT 更新，反馈包含 `W[31:1]`。 | 不输出有效密钥流，忽略 advance。 |
| E33 | 执行一次不注入 W 的 DISCARD 更新并进入 WORK。 | 更新后 `valid=1`，组合输出首字。 |
| E34 | 若 `advance=1`，接收首字并同时推进。 | 沿前消费 Z0；沿后输出 Z1。 |
| E35 以后 | `advance=1` 连续推进；`advance=0` 保持。 | 最多 1 字/周期。 |

无暂停时原语工作期理论上限为 `32 × f_clk` bit/s；从 E0 到第 N 个接收沿的间隔为 `33+N` 个周期。该公式不是目标工艺频率或系统吞吐保证。LFSR 的多级 `add31`、BR/F 和输出路径需在目标网表上实际分析。

### 2.2.3 Peripheral Interface

本模块仅有 start、key/IV、advance 和 valid/word 接口，没有长度、结束脉冲、配置总线或输出 FIFO。`word_out` 在 `valid=0` 时仍是组合函数，必须忽略；下游在 WORK 且无 start/复位干扰时以 `valid && advance` 采样。

`start` 在任何状态优先于正常推进；持续拉高会反复装载，故须由上游形成受控脉冲。WORK 中同沿重启时，沿前 `valid` 可能仍为 1，但内部执行重启而不推进旧流；系统应明确终止旧事务并禁止把该字当作新流首字。

### 2.2.4 Sub-modules

| 逻辑块 | RTL 实现与职责 |
| --- | --- |
| 控制状态 | IDLE / INIT / DISCARD / WORK，6-bit `init_count` 计数 0～31。 |
| LFSR | `s[0:15]`，每级 31 bit，包含循环移位、模 p 进位回卷和零表示修正。 |
| BR | 由 4 组固定切片和拼接产生 X0～X3。 |
| 非线性 F | R1/R2、32-bit 加法/XOR、`linear1`、`linear2` 和 `subword`。 |
| S-box | `zuc_s0` / `zuc_s1` 的组合函数；两个 subword 运算各含四次字节替换。 |
| 输出 | `w XOR x3` 的 32-bit 组合逻辑，未额外寄存。 |

### 2.2.5 Pipeline Design

本实现把完整的一个 ZUC 轮更新作为一个状态时钟步，不是能同时装载多个 key/IV 的事务级流水。控制在 INIT/DISCARD 自动推进；WORK 在 `advance` 为 1 时推进，为 0 时冻结。start 覆盖所有状态并优先于推进，reset 优先于 start。

F 的结果到 INIT LFSR 反馈，以及多个 31-bit `add31` 级联到 `s[15]` 是需要重点关注的组合链；实际时序路径由综合、映射和物理约束决定。若后续增加流水，将改变状态递推及外部周期契约，须重新设计与验证。

### 2.2.6 Resource Consumption

| 资源 | RTL 声明/结构，非工艺面积 |
| --- | --- |
| LFSR | 16 × 31 = 496 个声明 bit。 |
| 非线性寄存器 | R1、R2 共 64 个声明 bit。 |
| 控制 | `init_count` 6 bit、`state` 2 bit；上述时序声明合计约 568 bit，实际综合网表可能变化。 |
| 算术/替换 | 多级 31-bit 模 p 加法和旋转、32-bit 加法、两组 L1/L2 与 S0/S1 组合。 |
| 输出寄存器 / SRAM | 均无专门实例。 |
| `mdm_sec` 实例数 | cipher、integrity 各 1 个；密钥流状态独立。 |

### 2.2.7 Synthesis Analysis

| 待填项 | 结果 |
| --- | --- |
| Synopsys 工具版本、目标标准单元库及 PVT | TBD |
| 时钟周期、输入输出延迟和 SDC 文件 | TBD |
| 寄存器/组合单元数、面积和层次报告 | TBD |
| 目标频率、WNS/TNS 和关键路径 | TBD |
| DFT/scan、布线后结果 | TBD |

建议独立以 `mdm_zuc` 为顶层综合并分析工作、启动和输出路径，然后在 `mdm_sec` 层次复核。S-box 函数可能由不同库映射为逻辑或其他结构，不应在没有报告时假定其实际面积。

### 2.2.8 Power Analysis

WORK 停顿使寄存器数据不更新，但 RTL 没有显式时钟门控；组合/时钟网络仍可能消耗动态功耗。具体功耗依赖实现、负载与开关活动，不应填写推测值。

| 待填项 | 结果 |
| --- | --- |
| PVT、频率、负载和工作占空比 | TBD |
| 动态平均/峰值功耗 | TBD |
| 静态/待机功耗 | TBD |
| SAIF/VCD/FSDB 活动来源及覆盖区间 | TBD |

### 2.2.9 Debug and Trace

观察 `state`、`init_count`、`s[0/2/4/5/7/9/10/11/13/14/15]`、`x0…x3`、`r1/r2`、`w/w1/w2`、`feedback` 和 `valid/advance/word_out`。重点检查初始化注入、零反馈替换、首字时点和暂停稳定。

内部状态、密钥流、key/IV 均属敏感信息；实际系统波形需受控，不能公开真实密钥。数组调试依赖仿真器的 memory/MDA 支持；综合优化可能改变层次和节点名称。

### 2.2.10 Verification and Acceptance

| 验证项 | 已有证据 / 待办 |
| --- | --- |
| 原语固定答案 | `tb_primitives.sv` 的全零 key/IV：前三字 `27bede74 018082da 87d4e5b6`。 |
| 时序/暂停 | 检查 32 次初始化、一次丢弃、首字、stall 保持及逐拍推进。 |
| 系统模式 | `tb_lanes.sv` 和包级回归覆盖 EEA3/EIA3、消息和背压组合。 |
| 待补 | 真实 VCS/门级、更多独立原语向量、形式/安全评估及目标工艺报告。 |

# 3 I/O Interface

## 3.1 Port Definition

| 信号 | 方向 | 位宽 | 描述 |
| --- | --- | --- | --- |
| `clk` | 输入 | 1 | 上升沿时钟。 |
| `rst_n` | 输入 | 1 | 异步低有效复位，清控制、LFSR 和 R1/R2。 |
| `start` | 输入 | 1 | 任意状态启动或重启；优先于状态推进。 |
| `key` | 输入 | 128 | 启动沿装载，用高位字节到低位字节形成 K0…K15。 |
| `iv` | 输入 | 128 | 启动沿装载，用高位字节到低位字节形成 IV0…IV15。 |
| `advance` | 输入 | 1 | WORK 中为 1 时消费当前字并推进；INIT/DISCARD 忽略。 |
| `valid` | 输出 | 1 | 控制状态为 WORK；不屏蔽同时发生的 start。 |
| `word_out` | 输出 | 32 | 当前组合密钥流字，只有在有效 WORK 的消费协议下使用。 |

## 3.2 Protocol, Reset and Corner Cases

- 异步 reset 中止当前流并清状态；复位释放后需重新 start。释放同步、recovery/removal 由 SoC 时钟复位方案负责。
- `start` 为电平采样，持续为 1 将反复初始化；本核没有 ready。正常使用时一个请求脉冲后等待完整初始化。
- WORK 且 `start=0` 时，`advance=0` 保持当前 `word_out`；`advance=1` 的接收沿取得当前字，然后产生下一字。
- 重新启动时丢弃旧会话；避免同沿将旧 `valid` 与 `advance` 解释为新事务的接收。
- 不检查 key/IV 重用、不提供事务结束或安全密钥管理；上层必须管理这些系统要求。

# 4 Open Issue

| 编号 | 未决事项 / 风险 | 状态与建议负责人 |
| --- | --- | --- |
| ZUC-OI-01 | 标准单元面积、功耗、时钟目标、WNS/TNS 和物理路径缺少项目报告。 | Open；综合/STA/功耗团队。 |
| ZUC-OI-02 | 同沿 start 与输出消费的禁止/丢弃约束需 SoC 接口确认。 | Open；集成和验证团队。 |
| ZUC-OI-03 | 无长度、done 和结果 FIFO；外围必须跟踪消息长度并保护暂停数据。 | Open；系统设计团队。 |
| ZUC-OI-04 | 复位释放同步、CDC 和 DFT/scan 方案待确认。 | Open；SoC/DFT 团队。 |
| ZUC-OI-05 | 无专用状态零化、侧信道/故障防护或安全认证；需要 IV 唯一性和波形访问控制。 | Open；安全团队。 |
| ZUC-OI-06 | 更多独立标准向量、真实 VCS、门级和形式检查待补。 | Open；验证团队。 |
