# 5 拍 balanced-opt AES：选择、层次与综合

## 三种实现与接口

`mdm_sec.AES_LOW_AREA` 是 elaboration 时的三值选择，两个通道使用相同模式，但各有独立的 AES 状态与密钥，并不共享块核。

| `AES_LOW_AREA` | 实现 | 块延迟 / 最小启动间隔 | 单核通用单元数 | 包装器路径 |
| --- | --- | --- | ---: | --- |
| 0 | fast（原高速） | 5 / 5 拍 | 7,321 | `g_fast.u_core` |
| 1（默认） | serial（低面积） | 50 / 50 拍 | 2,179 | `g_low_area.u_core` |
| 2 | balanced-opt（深度导向） | 5 / 5 拍 | 7,097 | `g_balanced_timing.u_core` |

单元数均为 Yosys 0.71 的 `synth -noabc; check -assert; stat` 单核结果，各种通用单元按一个计数；不是物理面积或 STA。参见下方方法与限制。

原 balanced 实现及其 `g_balanced.u_core` 路径已删除。模式 2 下 **cipher 与 integrity 均各自例化一个 `mdm_aes128_balanced_timing`**。保留的旧参数 `AES_INTEGRITY_TIMING_OPT`（顶层）与 `BALANCED_TIMING_OPT`（单核包装器）默认均为 1，作用是迁移保护：模式 2 必须为 1，显式指定 0 会拒绝展开，不会静默切换版本；模式 0/1 下允许 0 或 1，且不影响所选内核。其他值无效。仅设置旧参数不会把默认的模式 1 变为模式 2。

fast 和 balanced-opt 在 E0 的 `start && ready` 接收输入，在 E5 输出 `done/block_out`，E5 可以同时接收下一块；serial 相应为 E50。上述周期是原语接口协议，**不是 375 MHz 或任何目标频率已收敛的承诺，也不是包级延迟**。

## balanced-opt 的层次

下面是 RTL 逻辑名；工具可能增加 generate 层次、展平、改名或优化掉连线。两条通道各有一份同样结构：

```text
mdm_sec
├─ u_cipher.u_aes.g_balanced_timing.u_core
└─ u_integrity.u_aes.g_balanced_timing.u_core
   ├─ u_initial_add_round_key                  # 输入 block XOR key
   ├─ u_key_expand1 / u_key_expand2            # 各含 4 个分层密钥 S-box
   ├─ u_round1                                # 正常轮
   │  ├─ u_subbytes.g_byte[0..15].u_sbox     # 每轮 16 个数据 S-box
   │  ├─ u_shift_rows
   │  ├─ u_mix_columns.g_column[0..3].u_mix_column
   │  └─ u_add_round_key
   └─ u_round2
      ├─ u_subbytes.g_byte[0..15].u_sbox
      ├─ u_shift_rows
      ├─ u_mix_columns.g_column[0..3].u_mix_column
      ├─ u_add_round_key                      # 正常轮，供 round_state 反馈
      └─ g_last_add_round_key.u_add_round_key # 末轮旁路，供 block_out
```

第一轮始终做 MixColumns。第二轮的普通输出在 `pair=0..3` 写回 `round_state`；第 10 轮的独立输出从 ShiftRows 直接 XOR 轮密钥，仅在 `pair=4` 写入 `block_out`。普通反馈数据不再经过末轮选择 mux；E5 接收新块时原有初始状态装载优先级保持不变。

单核有 32 个数据 S-box 和 8 个密钥 S-box。数据 S-box 使用与 `mdm_aes_sbox` 相同的 Boyar–Peralta 方程，但将 `u_top/u_nonlinear/u_bottom` 三层合并到 `mdm_aes_sbox_timing` 中，以便跨这些边界综合优化；两个密钥扩展内的 8 个 S-box 仍保留三层。每核共 8 个 32 位列混合和 4 个 128 位 AddRoundKey。ShiftRows 为连线，零逻辑单元不代表物理布线没有代价。保留层次不保证综合工具得到更短延时。

列混合以 `a,b,c,d` 为列的四个字节并行计算，例如第一个输出为 `xtime(a XOR b) XOR b XOR c XOR d`。显式共享相邻字节 XOR 并平衡项，RTL 中每输出至多经过三级两输入 XOR（AddRoundKey 之前）。该结构经独立矩阵全输入 SAT 检查；逻辑级数与模块边界不是工艺映射后的 cell 延时。

## 同口径通用逻辑比较（不是 STA）

以下为 Yosys 0.71、单核 `synth -noabc; check -assert; flatten` 结果：

| 指标 | fast | balanced-opt |
| --- | ---: | ---: |
| 通用单元数 | 7,321 | 7,097（−224，−3.06%） |
| `ltp -noff` 最长未加权拓扑 | 70 级 | 67 级 |
| `round_state[99]` Q 到 `round_state[2]` D 最长单位权重拓扑 | 62 级 | 61 级 |
| 任意 `round_state` Q 到 `round_state` D 最长单位权重拓扑 | 70 级 | 66 级 |

这些是**未映射通用逻辑统计**：每种通用门计 1，不含工艺门延时、驱动、负载、布线、时钟和 PVT，RTL 位号也不保证对应现场综合网表的同名路径。不能由级数变化推算节省的 ps、标准单元面积或 375 MHz 是否达标。

同版本 Yosys 非 flatten 的 balanced-opt 层次统计如下。父级含子级，不能把轮级数字和其下的子项重复相加；`u_core` 本层为 689 个。

| 层次 / 范围 | 含子级通用单元数 |
| --- | ---: |
| `u_initial_add_round_key` | 128 |
| `u_key_expand1` / `u_key_expand2` | 612 / 612 |
| `u_round1` | 2,464 |
| ↳ `u_subbytes` / `u_mix_columns` / `u_add_round_key` / `u_shift_rows` | 1,904 / 432 / 128 / 0 |
| `u_round2`，含独立末轮处理 | 2,592 |
| 单核合计（本层和直接子模块之和） | 7,097 |

```sh
make test-aes-hierarchy  # 检查 balanced-opt 的结构及顶层两路独立实例
make test-aes-formal     # MixColumns/S-box SAT 和 fast 对 balanced-opt 整核等价
make area-aes-balanced   # 三个单核的通用单元及最长拓扑比较
make area-aes-timing     # 两个单核指定状态路径及最长状态反馈拓扑比较
make synth-aes BUILD_DIR=build/aes-fast SYNTH_AES_LOW_AREA=0
make synth-aes BUILD_DIR=build/aes-opt SYNTH_AES_LOW_AREA=2
```

## 现场综合和 STA

1. 同步**整套同一版本** RTL 和 filelist。`rtl/mdm_aes128_balanced_timing.v`、`rtl/mdm_aes_balanced_blocks.v`、`rtl/mdm_aes_blocks.v`、`rtl/mdm_aes_sbox.v` 及其他依赖均须读取；仓库 `rtl/files.f`、转网 `mdm_sec_rtl.vc` 与打包清单已同步，现场自有清单应删除已退役文件并重新核对 include 路径。
2. 分别使用 `AES_LOW_AREA=0/1/2` 从 RTL 重新展开，固定相同工艺库、PVT、时钟、uncertainty、I/O、优化 effort 和保层策略。模式 2 的旧顶层参数应保持默认 1；不能再用它切回原 balanced。仿真脚本的环境变量不会自动传给综合流程。
3. 按现场既有的 `rc_flow -top mdm_sec -syn rtl3` 流程综合；仓库没有该包装器和 Tcl，不假定它支持其他命令行选项。确认展开后的 cipher 和 integrity 两路均为 `g_balanced_timing`，并重新核对 SDC、路径组、`dont_touch`、时钟/复位及层次匹配，避免旧路径静默漏约束。不能通过 false path 或 multicycle 隐藏真实的一拍反馈路径。
4. 分别检查两个通道的 setup/hold、全设计 WNS/TNS、关键路径和面积，包含 `round_state`、`key_reg`、`block_out` 及外围路径；再进行所需工艺角与布局布线后 STA。保层面积报告和正常优化 PPA 应分别生成，本 RTL 未强制 `keep_hierarchy`/`dont_touch`。

用户曾反馈现场将 cipher 也选为候选核后综合无违例且回归通过；现场副本、约束和报告不在仓库，不能据此替代当前代码的多角物理签核。规格、测试与局限见 [balanced-opt 规格书](specs/aes_balanced_core_spec.docx) 和 [验证记录](verification.md)。
