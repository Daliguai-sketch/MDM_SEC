# 5 拍 balanced AES 的模块层次与面积查看

## 模块划分

`mdm_aes128_balanced` 对应这里的 `aes_core_balance`；它的组合子模块定义在 `rtl/mdm_aes_balanced_blocks.v`。划分参考原 Python 模型 `sec_core/aes/sec_aes_core_enc.py` 的 `key_expansion`、`sub_bytes`、`shift_rows`、`mix_columns` 和 `add_round_key`。数据按 AES 列优先、最高字节在前；每拍仍组合完成连续两轮，没有在新模块之间增加寄存器。

```text
mdm_sec
├─ u_cipher.u_aes.g_balanced.u_core     # 加密通道的 mdm_aes128_balanced
└─ u_integrity.u_aes.g_balanced.u_core  # 完整性通道的独立 AES
   ├─ u_initial_add_round_key             # 输入块与初始 key 异或
   ├─ u_key_expand1                       # 第一轮密钥扩展
   │  ├─ u_subword.g_byte[0..3].u_sbox   # RotWord 后的 4 个 S-box
   │  └─ u_word_xor                       # 第一轮密钥字异或
   ├─ u_key_expand2                       # 第二轮的优化密钥扩展
   │  └─ u_subword.g_byte[0..3].u_sbox   # 另 4 个 S-box
   ├─ u_round1                            # 第一轮，固定做 MixColumns
   │  ├─ u_subbytes.g_byte[0..15].u_sbox # 16 个数据 S-box
   │  ├─ u_shift_rows                     # 固定字节置换
   │  ├─ u_mix_columns.g_column[0..3].u_mix_column
   │  └─ u_add_round_key
   └─ u_round2                            # 第二轮，第 10 轮旁路 MixColumns
      ├─ u_subbytes.g_byte[0..15].u_sbox
      ├─ u_shift_rows
      ├─ u_mix_columns.g_column[0..3].u_mix_column
      └─ u_add_round_key
```

图中展示 RTL 源码的逻辑层次；工具可能为 generate 插入 `genblk`、对参数模块改名，或在优化后移除连线模块。每个 `u_sbox` 还包含 `u_top`、`u_nonlinear`、`u_bottom`。每个 AES 核共 40 个 S-box、8 个 32 位列混合模块；两路是独立硬件，不共享密钥或轮运算。

第二轮密钥扩展仍使用原 balanced 核的化简 XOR 方程，列混合仍使用 `mdm_aes_mix_balanced.vh` 中的 88-XOR 网络。`u_round1` 静态去掉末轮旁路，`u_round2` 仅在 `pair=4` 时旁路。接口、`start && ready` 接收、E5 输出、5 拍最小启动间隔和末拍接收下一块的行为均不变；默认 `AES_LOW_AREA` 仍为 1。

## 用现有 `rc_flow` 综合

1. 确认流程读取**同一版本**的 `mdm_aes128_balanced.v` 和新增 `mdm_aes_balanced_blocks.v`；还需要 `mdm_aes_blocks.v`、`mdm_aes_sbox.v`、`mdm_aes_mix_balanced.vh`，以及头文件的 include 路径。仓库 `rtl/files.f` 和转网包 `mdm_sec_rtl.vc` 已更新；现场综合若使用自己的 filelist，也要同步更新。
2. 在顶层 RTL **展开时**将 `mdm_sec.AES_LOW_AREA` 设为 `2`，并重新从 RTL 展开：默认值 `1` 选择的是 50 拍串行核。可通过现场综合 Tcl 覆盖顶层参数；如果现场流程不支持传参，可在**独立综合源码副本**中将 `rtl/mdm_sec.v` 的默认值改为 `2`，同时确认脚本没有其他覆盖。不要仅设置同名 shell 环境变量。
3. 按现场原命令运行 `rc_flow -top mdm_sec -syn rtl3`。仓库没有该包装器及其 Tcl，因此不能假定它支持哪些额外命令行参数。检查展开日志和层次，确认 cipher 与 integrity 均选择 balanced 核，并定位上述子模块。
4. 用现场综合工具的**分层面积报告**查看实例；如果流程自动 flatten/ungroup，层次可能消失，需按现场工具版本和脚本暂时保留要分析的层次，再生成报告。本 RTL 未强制 `keep_hierarchy`/`dont_touch`。保留层次可能限制跨模块优化，不能将该结果直接当作正常 flatten 后的最终 PPA；应另跑正常优化版本并用目标库、相同约束及 STA 比较。

报告的父级面积通常可能包含子级，具体以工具的 inclusive / exclusive 定义为准。不要把 `u_round1` 和其 `u_subbytes`、`u_mix_columns` 再相加；两路 AES 也应分别检查。ShiftRows 主要是连线，显示零逻辑单元不等于物理布线没有代价。

## 本地可复现的通用层次报告

有 Yosys 和 Python 时，在仓库根目录运行：

```sh
make test-aes-hierarchy  # 综合独立核、检查模块数量，并检查顶层两路均选择 2
make synth-aes SYNTH_AES_LOW_AREA=2  # 完整单核分层统计：build/rtl/synth-aes-2.log
make area-aes-balanced   # 与原 5 拍高速核同口径比较
```

`test-aes-hierarchy` 使用 `synth -noabc`，直接输出各实例**包含子层次**的通用单元数。以下是本次 Yosys 0.64 的示例，不是标准单元面积、门等效数或 STA：

| 单核层次 | 通用单元数 | 包含范围 |
| --- | ---: | --- |
| `u_core` 本层 | 689 | 控制、状态/数据寄存器、选择等，不含下列子模块 |
| `u_initial_add_round_key` | 128 | 输入的 128-bit XOR |
| `u_key_expand1` | 612 | 含 4 个 S-box 和密钥字 XOR |
| `u_key_expand2` | 612 | 含 4 个 S-box 和优化 XOR |
| `u_round1` | 2,384 | 含 16 个 S-box、4 列混合和 AddRoundKey |
| `u_round2` | 2,512 | 同上，另含末轮旁路选择 |
| **单核合计** | **6,937** | 上述互不重叠的本层和直接子模块之和 |

例如 `u_round1` 内的 `u_subbytes` 为 1,904、`u_mix_columns` 为 352、`u_add_round_key` 为 128、`u_shift_rows` 为 0；这些都已包含在 `u_round1` 的 2,384 中。每个 8-bit S-box 为 119 个通用单元，每列 88 个 XOR；以上数字和层次是否保留均随综合工具及选项变化，必须以实际工艺报告为准。
