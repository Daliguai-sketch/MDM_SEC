# 5 拍 balanced AES：层次、面积和完整性时序候选

## 选择与协议

`mdm_sec.AES_LOW_AREA` 默认仍为 `1`（50 拍串行 AES），设为 `0` 为原 5 拍高速 AES，设为 `2` 为 5 拍 balanced AES。两个通道各有独立的 AES 状态和密钥，不共享块核。`AES_LOW_AREA=2` 时，新增的顶层参数 `AES_INTEGRITY_TIMING_OPT` 只控制完整性通道：

| 参数 | `u_cipher` | `u_integrity` |
| --- | --- | --- |
| `AES_INTEGRITY_TIMING_OPT=1`（默认） | 原 `mdm_aes128_balanced` | 新 `mdm_aes128_balanced_timing` |
| `AES_INTEGRITY_TIMING_OPT=0` | 原 `mdm_aes128_balanced` | 原 `mdm_aes128_balanced`（用于回退和 A/B 对比） |

该选项只对 `AES_LOW_AREA=2` 生效；取值只能为 0 或 1。独立使用 `mdm_aes128` 时，包装器参数 `BALANCED_TIMING_OPT` 默认 **0**；`mdm_integrity` 默认传入 **1**，顶层可用 `AES_INTEGRITY_TIMING_OPT` 覆盖。参数在 elaboration 时确定，不是运行时选择。默认 `AES_LOW_AREA` 没有改变，仅设置 `AES_INTEGRITY_TIMING_OPT=1` 不会选中 balanced 核。

两个 balanced 实现均在 E0 的 `start && ready` 接收输入，在 E5 输出 `done/block_out`，最小启动间隔为 5 拍；E5 可以同时接受下一块，不增加时钟域或修改外部端口。5 拍是功能周期协议，**不是 375 MHz 或任何目标频率已收敛的承诺**。

## 原 balanced 核的层次

`mdm_aes128_balanced` 对应原先的 `aes_core_balance`，组合模块定义在 `rtl/mdm_aes_balanced_blocks.v`，划分参考项目 Python AES 的 `key_expansion`、`sub_bytes`、`shift_rows`、`mix_columns` 和 `add_round_key`。cipher 始终使用该结构；完整性回退时也使用独立的相同结构：

```text
u_aes.g_balanced.u_core
├─ u_initial_add_round_key
├─ u_key_expand1
│  ├─ u_subword.g_byte[0..3].u_sbox  # 每个含 u_top/u_nonlinear/u_bottom
│  └─ u_word_xor
├─ u_key_expand2
│  └─ u_subword.g_byte[0..3].u_sbox
├─ u_round1
│  ├─ u_subbytes.g_byte[0..15].u_sbox
│  ├─ u_shift_rows
│  ├─ u_mix_columns.g_column[0..3].u_mix_column
│  └─ u_add_round_key
└─ u_round2  # pair=4 时旁路 MixColumns
   ├─ u_subbytes.g_byte[0..15].u_sbox
   ├─ u_shift_rows
   ├─ u_mix_columns.g_column[0..3].u_mix_column
   └─ u_add_round_key
```

原版单核共 40 个分层 S-box、8 个 32 位列混合和 3 个 AddRoundKey。ShiftRows 主要是连线，综合报告中为零逻辑单元不等于物理布线没有代价。实例能否保留取决于综合的 flatten/ungroup 设置；相同的层次也各自在两条通道独立存在。

## 完整性时序候选的结构

此前现场报告的 `round_state_reg_99_ → round_state_reg_2_` 路径经过两轮 S-box 和 MixColumns；图中实例是 RTL 逻辑名，工具可能加入 `genblk`、展平模块、改名或优化掉连线：

```text
mdm_sec
├─ u_cipher.u_aes.g_balanced.u_core          # 原 balanced，保持原组合实现
└─ u_integrity.u_aes.g_balanced_timing.u_core  # 5 拍时序候选
   ├─ u_initial_add_round_key                 # 输入 block XOR key
   ├─ u_key_expand1 / u_key_expand2           # 各含 4 个原分层 S-box
   ├─ u_round1                               # 正常轮
   │  ├─ u_subbytes.g_byte[0..15].u_sbox    # 16 个平坦 S-box
   │  ├─ u_shift_rows
   │  ├─ u_mix_columns.g_column[0..3].u_mix_column
   │  └─ u_add_round_key                     # MixColumns 后 XOR key
   └─ u_round2
      ├─ u_subbytes.g_byte[0..15].u_sbox
      ├─ u_shift_rows
      ├─ u_mix_columns.g_column[0..3].u_mix_column
      ├─ u_add_round_key                     # 普通轮，供 round_state 反馈
      └─ g_last_add_round_key.u_add_round_key # 末轮旁路，供 block_out
```

第一轮始终做 MixColumns。第二轮的普通输出固定执行 MixColumns；仅在 `pair=0..3` 写回 `round_state`。第 10 轮的独立输出从 ShiftRows 直接 XOR 轮密钥，仅在 `pair=4` 写入 `block_out`。因此候选 RTL 的普通反馈数据不再经过末轮选择 mux；若 E5 接收新块，原有初始状态装载优先级保持不变。

候选版的 32 个**数据** S-box 使用与原 `mdm_aes_sbox` 相同的 Boyar–Peralta 方程，但将原来内部 `u_top/u_nonlinear/u_bottom` 的三层逻辑放在一个 `mdm_aes_sbox_timing` 模块中，以便综合跨这些边界优化；`u_sbox` 本身仍可报告面积。两次密钥扩展的 8 个 S-box 和 cipher 版的所有 S-box 仍保留原三层。展平内部 S-box 层次不保证综合工具实际得到更短延时。

候选版列混合以 `a,b,c,d` 为列的四个字节并行计算，例如第一个输出为 `xtime(a XOR b) XOR b XOR c XOR d`。显式共享相邻字节 XOR 并平衡项，RTL 中每输出至多经过三级两输入 XOR；原 cipher 核仍使用 `mdm_aes_mix_balanced.vh` 的 88-XOR、最大深度 5 网络。两个网络均经全输入形式检查。逻辑级数和模块边界不是工艺映射后的 cell 延时。

## 通用结构比较（不是 STA）

本次 Yosys 0.71、同一 `synth -noabc; check -assert; flatten` 口径下：

| 单个 5 拍 AES 核 | 原 balanced | 完整性时序候选 |
| --- | ---: | ---: |
| 通用单元数 | 6,937 | 7,097（+160，+2.31%） |
| `round_state[99]` Q 到 `round_state[2]` D 的最长单位权重拓扑 | 65 级 | 61 级 |
| 任意 `round_state` Q 到 `round_state` D 的最长单位权重拓扑 | 68 级 | 66 级 |
| `u_round1` / `u_round2` 含子级单元数 | 2,384 / 2,512 | 2,464 / 2,592 |

这是**未映射的通用逻辑统计**：每种通用门计 1，不含工艺门延时、驱动、负载、布线、时钟和 PVT，RTL 位号也不保证对应现场综合网表的同名路径。不能由级数变化推算节省的 ps、标准单元面积或 375 MHz 是否达标。综合后的父级统计通常包含子级，不能重复累加。可运行：

```sh
make test-aes-hierarchy  # 两种核的分层结构、顶层默认和回退选择
make area-aes-timing     # 同工具同口径重新生成上述通用结构比较
make test-aes-formal     # MixColumns/S-box SAT 和两次整核等价
# 单核包含子模块的报告：分别使用目录，避免覆盖日志
make synth-aes BUILD_DIR=build/aes-original SYNTH_AES_LOW_AREA=2 SYNTH_BALANCED_TIMING_OPT=0
make synth-aes BUILD_DIR=build/aes-timing SYNTH_AES_LOW_AREA=2 SYNTH_BALANCED_TIMING_OPT=1
# 顶层通用综合 A/B：缓存映射到通用触发器，非实际 SRAM/物理面积
make synth-generic BUILD_DIR=build/top-original SYNTH_MAX_BYTES=2048 SYNTH_AES_LOW_AREA=2 SYNTH_AES_INTEGRITY_TIMING_OPT=0
make synth-generic BUILD_DIR=build/top-timing SYNTH_MAX_BYTES=2048 SYNTH_AES_LOW_AREA=2 SYNTH_AES_INTEGRITY_TIMING_OPT=1
```

下表以 Yosys 0.71 同口径展示可查看的直接子层次；`u_round1` 的子项**已包含在该轮数值内**，不应再次加到总数。候选的 128 个末轮 XOR 与原版第二轮 128 个旁路 MUX 在该口径下数量相同；两轮各增加的 80 个通用单元来自列混合。目标库下的面积和时序可能不同。

| 层次 / 范围 | 原 balanced | 完整性候选 |
| --- | ---: | ---: |
| `u_core` 本层，不含下列子模块 | 689 | 689 |
| `u_initial_add_round_key` | 128 | 128 |
| `u_key_expand1` / `u_key_expand2`，各含子级 | 612 / 612 | 612 / 612 |
| `u_round1`，含子级 | 2,384 | 2,464 |
| ↳ `u_subbytes` / `u_mix_columns` / `u_add_round_key` / `u_shift_rows` | 1,904 / 352 / 128 / 0 | 1,904 / 432 / 128 / 0 |
| `u_round2`，含子级及末轮处理 | 2,512 | 2,592 |
| **单核合计**（本层和直接子模块之和） | **6,937** | **7,097** |

## 用现场 `rc_flow` 验证

1. 同步**整套同一版本** RTL 和 filelist。新增文件 `rtl/mdm_aes128_balanced_timing.v` 必须与 `mdm_aes128_balanced.v`、`mdm_aes_balanced_blocks.v`、`mdm_aes_blocks.v`、`mdm_aes_sbox.v`、`mdm_aes_mix_balanced.vh` 和其他 RTL 一起读取。仓库 `rtl/files.f`、转网 `mdm_sec_rtl.vc` 和打包清单已包含新文件；现场自有 filelist 也需同步。
2. 对比两次从 RTL 重新 elaboration：均设 `AES_LOW_AREA=2`，分别设 `AES_INTEGRITY_TIMING_OPT=0/1`；其他库、PVT、时钟、uncertainty、I/O、优化 effort 和保层策略保持一致。顶层默认 `AES_LOW_AREA=1`；如现场包装不支持传参数，可在**独立综合源码副本**修改顶层默认值后确认没有其他覆盖。仅设置仿真环境变量不会改变综合参数。
3. 按现场原流程 `rc_flow -top mdm_sec -syn rtl3` 综合。仓库没有该包装器和 Tcl，不能假定额外命令行选项。检查展开日志：cipher 应为 `g_balanced`，完整性候选应为 `g_balanced_timing`；若选回退则完整性也为 `g_balanced`。
4. 新增分支改变了完整性 AES 的**层次路径**。重新核对 SDC、路径分组、`dont_touch`、时钟/复位、层次匹配及例外是否仍作用于正确对象，不能让旧实例名匹配失败后静默漏约束。不要通过 false path 或 multicycle 隐藏真实的一拍反馈路径。
5. 分别查看 cipher、integrity 的 setup/hold、关键路径和 WNS/TNS，包括 `round_state`、`key_reg`、`block_out` 及其外围路径；检查 S-box、列混合、MUX、驱动和负载。候选结构可能改变关键路径位置或增加面积，目标仍是全设计满足约束而非仅改善一条路径。
6. 前期报告为 `ZeroWireload` 且时钟理想化；完成目标工艺综合后，还需进行含布线、时钟树、实际约束和全部所需角落的 STA，并按现场流程验证复位和功能。保层面积报告与正常优化的 PPA 报告应分别生成；本 RTL 未强制 `keep_hierarchy`/`dont_touch`。
