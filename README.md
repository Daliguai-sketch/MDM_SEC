# MDM_SEC RTL

本仓库提供可综合的 3GPP 安全处理 RTL，并保留原有 Python 模型和测试数据。顶层为 [`rtl/mdm_sec.v`](rtl/mdm_sec.v)：128 位数据接口、16 位字节数、独立加密和完整性通道，以及六种处理模式。模式 2–5 在输入装载完成后同拍启动两条通道，模式 2、3、5 按字等待所需 MAC 或加解密结果；并不保证每拍都同时推进。模式 5 提取解密结果尾部 4 字节验证码，并计算和比较 MAC。算法支持 SNOW 3G、AES-128、ZUC 和 NULL。

## 快速运行

需要 Python 3、GNU Make、C++ 编译器及支持 `--binary --timing` 的 Verilator 5：

```sh
make example              # 可直接运行的 AES 双通道使用示例
make test                 # Verilog lint、编码规范、原语、通道、缓存及端到端回归
make yosys-check          # Yosys 结构检查，默认 2048 字节配置
make yosys-parameters     # 检查非法 MAX_BYTES 参数被拒绝
make synth-generic        # 可选：16 字节配置通用综合，非物理面积
```

也可从 PyPI 安装 `verilator` 和 `yowasp-yosys`；Makefile 自动查找 `verilator`/`verilator-cli` 和 `yosys`/`yowasp-yosys`。工具路径可用 `VERILATOR=...`、`YOSYS=...` 覆盖。Python 的 `pycryptodome` 是可选依赖：安装后额外独立交叉检查 AES；未安装时固定向量和 RTL 回归仍可运行。生成文件位于忽略目录 `build/rtl/`。

**从例化、握手及运行示例入手，请看 [`docs/quickstart.md`](docs/quickstart.md)；接口时序、模式语义、字节对齐、溢出处理及限制见 [`docs/rtl_interface.md`](docs/rtl_interface.md)，测试记录见 [`docs/verification.md`](docs/verification.md)。** 顶层输入和输出为 128 位，内部加密/完整性通道以 32 位字工作。AES 原语每 5 拍处理一个 128 位块，SNOW 3G/ZUC 初始化后每拍处理 32 位；整个包还包括装载、初始化、MAC 和输出握手，不能据此认为整包只需 5 拍或 1 拍。

可综合模块是 Verilog `.v`，`.vh` 为 Verilog include 文件；验证环境的 testbench 使用 SystemVerilog `.sv`。状态机的状态寄存器、组合次态和输出/数据逻辑分离；Verilog 源码逐行至多一个代码分号。

AES S 盒的布尔电路改写自 BearSSL 的 MIT 许可实现，版权与许可原文保留在 [`rtl/mdm_aes_sbox.vh`](rtl/mdm_aes_sbox.vh)。
