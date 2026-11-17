PYTHON ?= python3
VERILATOR ?= $(shell command -v verilator 2>/dev/null || command -v verilator-cli 2>/dev/null)
YOSYS ?= $(shell command -v yosys 2>/dev/null || command -v yowasp-yosys 2>/dev/null)
BUILD_DIR ?= build/rtl
JOBS ?= 2
CHECK_MAX_BYTES ?= 2048
SYNTH_MAX_BYTES ?= 16
# Some PyPI verilator-cli wheels omit the compiler's PCH include flag. Native
# Verilator installations use their own settings; override VMAKEFLAGS if needed.
VMAKEFLAGS ?= $(if $(findstring verilator-cli,$(notdir $(VERILATOR))),CFG_CXXFLAGS_PCH_I=-include,)

RTL := rtl/mdm_aes128.v rtl/mdm_snow3g.v rtl/mdm_zuc.v \
       rtl/mdm_packet_buffer.v rtl/mdm_cipher.v rtl/mdm_integrity.v rtl/mdm_sec.v
HEADERS := rtl/mdm_sboxes.vh rtl/mdm_aes_sbox.vh

.PHONY: all test example lint test-style test-primitives test-lanes test-buffer test-packet test-tiny test-boundaries yosys-check yosys-parameters synth-generic clean
all: test

test: lint test-style example test-primitives test-lanes test-buffer test-packet test-tiny test-boundaries

test-style:
	$(PYTHON) tests/check_rtl_style.py

# Small self-checking integration example; the testbench is simulation-only.
$(BUILD_DIR)/tb_quickstart/Vtb_mdm_sec_quickstart: $(RTL) $(HEADERS) examples/tb_mdm_sec_quickstart.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec_quickstart --Mdir $(abspath $(@D)) $(RTL) examples/tb_mdm_sec_quickstart.sv

example: $(BUILD_DIR)/tb_quickstart/Vtb_mdm_sec_quickstart
	$<

lint:
	@test -n "$(VERILATOR)" || { echo 'Install Verilator (or set VERILATOR=...)'; exit 1; }
	$(VERILATOR) --language 1364-2005 --lint-only -Irtl --top-module mdm_sec $(RTL)

$(BUILD_DIR)/tb_primitives/Vtb_primitives: $(RTL) $(HEADERS) tests/rtl/tb_primitives.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_primitives --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_primitives.sv

test-primitives: $(BUILD_DIR)/tb_primitives/Vtb_primitives
	$< +SBOX=$(abspath tests/rtl/aes_sbox.hex)

$(BUILD_DIR)/tb_lanes/Vtb_lanes: $(RTL) $(HEADERS) tests/rtl/tb_lanes.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_lanes --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_lanes.sv

test-lanes: $(BUILD_DIR)/tb_lanes/Vtb_lanes
	$<

$(BUILD_DIR)/tb_packet_buffer/Vtb_packet_buffer: rtl/mdm_packet_buffer.v tests/rtl/tb_packet_buffer.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_packet_buffer --Mdir $(abspath $(@D)) rtl/mdm_packet_buffer.v tests/rtl/tb_packet_buffer.sv

test-buffer: $(BUILD_DIR)/tb_packet_buffer/Vtb_packet_buffer
	$<

$(BUILD_DIR)/packet_vectors.txt: tests/gen_vectors.py tests/reference_model.py \
       sec_core/aes/sec_aes_core_enc.py sec_core/snow3g/sec_snow3g_core.py sec_core/zuc/sec_zuc_core.py
	@mkdir -p $(@D)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/gen_vectors.py $@

$(BUILD_DIR)/tb_mdm_sec/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

test-packet: $(BUILD_DIR)/packet_vectors.txt $(BUILD_DIR)/tb_mdm_sec/Vtb_mdm_sec
	$(BUILD_DIR)/tb_mdm_sec/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/packet_vectors.txt) +REQUIRE_PARALLEL_COVERAGE

$(BUILD_DIR)/tiny_vectors.txt: tests/gen_tiny_vectors.py tests/reference_model.py \
       sec_core/aes/sec_aes_core_enc.py sec_core/snow3g/sec_snow3g_core.py sec_core/zuc/sec_zuc_core.py
	@mkdir -p $(@D)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/gen_tiny_vectors.py $@

$(BUILD_DIR)/tb_tiny/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_MAX_BYTES=1 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

test-tiny: $(BUILD_DIR)/tiny_vectors.txt $(BUILD_DIR)/tb_tiny/Vtb_mdm_sec
	$(BUILD_DIR)/tb_tiny/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/tiny_vectors.txt)

$(BUILD_DIR)/boundary_vectors.txt: tests/gen_boundary_vectors.py tests/reference_model.py \
       sec_core/aes/sec_aes_core_enc.py sec_core/snow3g/sec_snow3g_core.py sec_core/zuc/sec_zuc_core.py
	@mkdir -p $(@D)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/gen_boundary_vectors.py $@

$(BUILD_DIR)/tb_boundaries/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_MAX_BYTES=65535 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

test-boundaries: $(BUILD_DIR)/boundary_vectors.txt $(BUILD_DIR)/tb_boundaries/Vtb_mdm_sec
	$(BUILD_DIR)/tb_boundaries/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/boundary_vectors.txt)

yosys-check:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES $(CHECK_MAX_BYTES); proc; opt; check -assert; stat' > $(BUILD_DIR)/yosys-check.log
	@tail -55 $(BUILD_DIR)/yosys-check.log

# Invalid MAX_BYTES must fail specifically at the elaboration guard.
yosys-parameters:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	@for value in 0 65536; do \
		if $(YOSYS) -Q -T -p "read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES $$value" > $(BUILD_DIR)/invalid-$$value.log 2>&1; then \
			echo "FAIL: MAX_BYTES=$$value was accepted"; exit 1; \
		fi; \
		grep -q 'ERROR: System task' $(BUILD_DIR)/invalid-$$value.log || { cat $(BUILD_DIR)/invalid-$$value.log; exit 1; }; \
	done
	@echo 'PASS invalid MAX_BYTES parameters rejected by elaboration guard'

# Generic pre-technology mapping sanity check, NOT physical area/timing.
# This maps memories to flip-flops; use target SRAMs for real implementation.
synth-generic:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES $(SYNTH_MAX_BYTES); synth -top mdm_sec -noabc; check -assert; stat' > $(BUILD_DIR)/synth-generic.log
	@tail -65 $(BUILD_DIR)/synth-generic.log

clean:
	rm -rf $(BUILD_DIR)
