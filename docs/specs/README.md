# RTL 设计规格书

五份可编辑的 Word 文档状态均为 **V0.1 Draft，待评审**。SNOW/ZUC 文档基于 RTL 提交 `938ac3409dbcf2c2bc4244f4b3d60f1b19da0c4c`；AES 和顶层文档已更新，以与文档同一 Git 提交中的 RTL 为准：

| 文档 | 对应实际 Verilog 模块 | 内容范围 |
|---|---|---|
| [aes_core_spec.docx](aes_core_spec.docx) | `mdm_aes128` | AES-128 包装器及 50/5/5 拍模式，包括 balanced 时序候选 |
| [aes_balanced_core_spec.docx](aes_balanced_core_spec.docx) | `mdm_aes128_balanced`、`mdm_aes128_balanced_timing` | 5 拍 balanced 原版和完整性时序候选的架构、接口、验证和 PPA 限制 |
| [snow3g_core_spec.docx](snow3g_core_spec.docx) | `mdm_snow3g` | SNOW 3G 密钥流、初始化及暂停协议 |
| [zuc_core_spec.docx](zuc_core_spec.docx) | `mdm_zuc` | ZUC-128 密钥流、初始化及暂停协议 |
| [mdm_sec_spec.docx](mdm_sec_spec.docx) | `mdm_sec` | 六种包模式、两条独立算法通道、共享缓冲及顶层接口 |

文档分别包括算法背景、架构图、时序、接口、子模块、流水/依赖、资源、综合、功耗、调试、验证及 Open Issue。工艺、时序和功耗等未提供的结果标记为 TBD；历史 Yosys 通用单元统计不代表工艺面积或签核。Word 中的目录条目可跳转到章节，但不含自动页码。

## 维护与检查

正文的可版本化源文件位于 [`src/`](src/)，架构图由 [`tools/generate_rtl_specs.py`](../../tools/generate_rtl_specs.py) 生成并嵌入 Word。需要修改时建议先编辑对应 Markdown，再重新生成；生成会覆盖同名 Word，因此直接在 Word 中做的修改不会自动回写源文件。目录随源文件生成，修改标题后需重新生成。

在具有 Python 的**文档维护环境**中，可选安装依赖并重新生成：

```sh
python3 -m pip install -r docs/specs/requirements.txt
python3 tools/generate_rtl_specs.py
# 或只生成某一份，避免覆盖其他 Word 文档：
python3 tools/generate_rtl_specs.py --only aes_balanced_core_spec
python3 tests/test_rtl_specs.py
```

测试脚本仅依赖 Python 标准库，检查 DOCX ZIP/XML、正文与源文件一致性、目录链接、图、章节以及全部 RTL 顶层端口的名称/方向/位宽；它不替代设计评审、实际 Word 排版检查或验证签核。相同依赖和字体环境下，生成器的 ZIP 时间戳及元数据固定，输出可逐字节重现；不同系统的可用字体可能改变图像渲染结果。

文档生成与 RTL 仿真无关：**U 网运行预生成向量的 VCS/Verdi 流程不要求安装 Python 或本目录的依赖**，请继续使用 [`docs/u_network_test.md`](../u_network_test.md)。
