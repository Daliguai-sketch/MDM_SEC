# RTL 设计规格书

五份 Word 文档状态均为 **V0.2 Draft，待评审**。V0.2 补充算法、S 盒、流程/时序/设计框图，不改变 RTL。SNOW/ZUC 文档的相关 RTL 最早基线为 `938ac3409dbcf2c2bc4244f4b3d60f1b19da0c4c`；AES 和顶层以与文档同一 Git 提交中的 RTL 为准：

| 文档 | 对应实际 Verilog 模块 | 内容范围 |
|---|---|---|
| [aes_core_spec.docx](aes_core_spec.docx) | `mdm_aes128` | AES-128 包装器及 50/5/5 拍模式，包括 balanced 时序候选 |
| [aes_balanced_core_spec.docx](aes_balanced_core_spec.docx) | `mdm_aes128_balanced`、`mdm_aes128_balanced_timing` | 5 拍 balanced 原版和完整性时序候选的架构、接口、验证和 PPA 限制 |
| [snow3g_core_spec.docx](snow3g_core_spec.docx) | `mdm_snow3g` | SNOW 3G 密钥流、初始化及暂停协议 |
| [zuc_core_spec.docx](zuc_core_spec.docx) | `mdm_zuc` | ZUC-128 密钥流、初始化及暂停协议 |
| [mdm_sec_spec.docx](mdm_sec_spec.docx) | `mdm_sec` | 六种包模式、两条独立算法通道、共享缓冲及顶层接口 |

V0.2 增加了 AES 轮变换、完整正向 S 盒、密钥扩展、轮密钥加和 5/50 拍时序；SNOW S1/S2、SQ 表及 ZUC S0/S1 表、LFSR/F 及启动/暂停时序；顶层补充 EEA2、EIA1/2/3、`u_cipher`、`u_integrity` 和两通道交互、依赖保护、握手时序。`u_inte` 是用户对完整性通道的称呼，实际 RTL 实例名为 `u_integrity`。

图形使用英文信号/算法标记，并由中文图题及正文解释；波形分清采样沿前后的数据，阶段示意图不承诺固定延迟。正文及 S 盒表在 Word 中可编辑；框图是嵌入的 PNG，生成代码可维护并可替换图像。工艺、时序和功耗等未提供的结果标记为 TBD；历史 Yosys 通用单元统计不代表工艺面积或签核。Word 中的目录条目可跳转到章节，但不含自动页码。

## 维护与检查

正文的可版本化源文件位于 [`src/`](src/)，每个 Markdown 内的标准图片链接指向 [`figures/`](figures/)，在仓库中也可以直接阅读。图形由 [`tools/generate_rtl_specs.py`](../../tools/generate_rtl_specs.py) 和 [`tools/spec_diagrams.py`](../../tools/spec_diagrams.py) 本地生成、保存并嵌入 Word；不得只改 PNG 而不同步生成代码。图中的抽象连接不代表新增寄存器，具体时序以正文和 RTL 为准。

需要修改时先编辑 Markdown 或图形生成代码，再重新生成；生成会覆盖同名 Word，直接在 Word 中做的修改不会自动回写源文件。目录和图题编号随源文件生成，修改标题或增删图后需重新生成。多份文档可能共用图形；如果共享图形生成结果变化，`--only` 会拒绝覆盖其他未选文档所用的图，应一次重生所有受影响的文档或直接全量生成。

在具有 Python 的**文档维护环境**中，可选安装依赖并重新生成：

```sh
python3 -m pip install -r docs/specs/requirements.txt
python3 tools/generate_rtl_specs.py
# 或只生成某一份，避免覆盖其他 Word 文档：
python3 tools/generate_rtl_specs.py --only aes_balanced_core_spec
python3 tests/test_rtl_specs.py
# 使用 Verilator 验证顶层规格中的逐沿 NULL 算法时序和反压示例
make test-spec-timing
```

`test_rtl_specs.py` 仅依赖 Python 标准库：检查 DOCX ZIP/XML、正文与源文件一致性、目录链接、图形文件与 Word 内嵌内容逐字节一致、必备框图、RTL 顶层端口，以及 AES、SNOW SQ、ZUC S0/S1 的全部 256 个表项；还对 SNOW 的反馈 XOR 矩阵与文档 GF 公式做全输入比较。`test-spec-timing` 使用 Verilator 核对单个 EEA0/EIA0 示例的 E0～E10 采样沿、启动、反压、响应及结果，并已加入 `make test`。两者都不替代设计评审、实际 Word 排版检查或完整验证签核。

相同依赖和字体环境下，生成器的 ZIP 时间戳及元数据固定，输出可逐字节重现；不同系统的可用字体可能改变图像渲染结果。最终交付仍应在目标 Word 环境检查字体、分页和打印效果。

文档生成与 RTL 仿真无关：**U 网运行预生成向量的 VCS/Verdi 流程不要求安装 Python 或本目录的依赖**，请继续使用 [`docs/u_network_test.md`](../u_network_test.md)。
