PYTHON ?= python3
VERILATOR ?= $(shell command -v verilator 2>/dev/null || command -v verilator-cli 2>/dev/null)
YOSYS ?= $(shell command -v yosys 2>/dev/null || command -v yowasp-yosys 2>/dev/null)
BUILD_DIR ?= build/rtl
JOBS ?= 2
CHECK_MAX_BYTES ?= 2048
CHECK_AES_LOW_AREA ?= 1
CHECK_AES_INTEGRITY_TIMING_OPT ?= 1
SYNTH_MAX_BYTES ?= 16
SYNTH_AES_LOW_AREA ?= 1
SYNTH_AES_INTEGRITY_TIMING_OPT ?= 1
SYNTH_BALANCED_TIMING_OPT ?= 0
BUFFER_CAP_BYTES ?= 2052
BUFFER_READ_PORTS ?= 2
AREA_BASE_REF ?= 711947b1c08a16688d1521be45426868f4fd03e9
WAVE_AES_LOW_AREA ?= 1
WAVE_AES_BLOCKS ?= 8
WAVE_MAX_BYTES ?= 512
WAVE_DIR ?= $(BUILD_DIR)/waveforms
WAVE_VARIANT = $(if $(filter 0,$(WAVE_AES_LOW_AREA)),fast,$(if $(filter 2,$(WAVE_AES_LOW_AREA)),balanced,low_area))

# Optional Synopsys VCS/Verdi flow. VERDI_HOME or NOVAS_HOME may point to
# different releases; users can also pass VERDI_PLI_DIR or the two files directly.
VCS ?= $(if $(and $(strip $(VCS_HOME)),$(wildcard $(VCS_HOME)/bin/vcs)),$(VCS_HOME)/bin/vcs,vcs)
VERDI ?= $(if $(and $(strip $(VERDI_HOME)),$(wildcard $(VERDI_HOME)/bin/verdi)),$(VERDI_HOME)/bin/verdi,verdi)
VCS_FLAGS ?= -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb -lca +memcbk
VCS_EXTRA_FLAGS ?=
VCS_SIM_FLAGS ?= +fsdb+autoflush
VERDI_PLI_DIR ?= $(patsubst %/novas.tab,%,$(firstword $(foreach root,$(VERDI_HOME) $(NOVAS_HOME),$(wildcard $(root)/share/PLI/VCS/LINUX64/novas.tab $(root)/share/PLI/VCS/linux64/novas.tab))))
VERDI_TAB ?= $(if $(strip $(VERDI_PLI_DIR)),$(VERDI_PLI_DIR)/novas.tab,)
VERDI_PLI ?= $(if $(strip $(VERDI_PLI_DIR)),$(VERDI_PLI_DIR)/pli.a,)
FSDB_DIR ?= $(WAVE_DIR)
FSDB_MDA ?= 0
# Same-machine development generates vectors on demand by default. This
# optional prebuilt mode reads existing inputs without Python prerequisites.
# The U-network transfer bundle instead uses tools/u_network/run.sh, not Make.
FSDB_PREBUILT ?= 0
FSDB_VECTOR_DIR ?= $(BUILD_DIR)
ifeq ($(FSDB_PREBUILT),1)
FSDB_PACKET_VECTOR = $(FSDB_VECTOR_DIR)/wave_vectors.txt
FSDB_AES_VECTOR = $(FSDB_VECTOR_DIR)/aes_vectors.txt
FSDB_PACKET_VECTOR_DEPS =
FSDB_AES_VECTOR_DEPS =
else ifeq ($(FSDB_PREBUILT),0)
FSDB_PACKET_VECTOR = $(BUILD_DIR)/wave_vectors.txt
FSDB_AES_VECTOR = $(BUILD_DIR)/aes_vectors.txt
FSDB_PACKET_VECTOR_DEPS = $(BUILD_DIR)/wave_vectors.txt $(BUILD_DIR)/wave_vectors.cases.txt
FSDB_AES_VECTOR_DEPS = $(BUILD_DIR)/aes_vectors.txt
else
$(error FSDB_PREBUILT must be 0 or 1)
endif
VCS_AES_CYCLES = $(if $(filter 1,$(WAVE_AES_LOW_AREA)),50,5)
VCS_PACKET_BUILD = $(BUILD_DIR)/vcs_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)
VCS_AES_BUILD = $(BUILD_DIR)/vcs_aes_$(WAVE_AES_LOW_AREA)

# Some PyPI verilator-cli wheels omit the compiler's PCH include flag. Native
# Verilator installations use their own settings; override VMAKEFLAGS if needed.
VMAKEFLAGS ?= $(if $(findstring verilator-cli,$(notdir $(VERILATOR))),CFG_CXXFLAGS_PCH_I=-include,)

AES_RTL := rtl/mdm_aes_sbox.v rtl/mdm_aes_blocks.v rtl/mdm_aes_balanced_blocks.v \
           rtl/mdm_aes128_serial.v rtl/mdm_aes128_fast.v rtl/mdm_aes128_balanced.v \
           rtl/mdm_aes128_balanced_timing.v rtl/mdm_aes128.v
RTL := $(AES_RTL) rtl/mdm_snow3g.v rtl/mdm_zuc.v rtl/mdm_packet_buffer.v \
       rtl/mdm_cipher.v rtl/mdm_integrity.v rtl/mdm_sec.v
HEADERS := rtl/mdm_sboxes.vh rtl/mdm_aes_sbox.vh rtl/mdm_aes_mix_balanced.vh

.PHONY: all test example lint test-style test-specs test-aes test-aes-balanced-blocks test-aes-hierarchy test-fast test-balanced test-balanced-fallback test-aes-formal area-aes-balanced area-aes-timing test-primitives test-lanes test-buffer test-packet test-tiny test-boundaries test-directed test-vcd-check test-vcd-trace test-vcs-flow test-u-network wave wave-packet wave-aes fsdb fsdb-packet fsdb-aes fsdb-check-packet-vectors fsdb-check-aes-vectors verdi-packet verdi-aes yosys-check yosys-parameters synth-generic synth-aes synth-buffer area-compare clean
all: test

test: lint test-style test-specs example test-aes test-aes-balanced-blocks test-primitives test-lanes test-buffer test-packet test-tiny test-boundaries test-fast test-balanced test-balanced-fallback test-directed test-vcd-check test-vcd-trace test-vcs-flow test-u-network

# Synthetic VCDs exercise hierarchy, variant and activity checks, including
# rejection of the previous depth-4 packet trace.
test-vcd-check:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/test_vcd_check.py

# These verify command wiring with mocks, not real VCS/PLI or FSDB contents.
test-vcs-flow:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/test_vcs_fsdb_flow.py

test-u-network:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/test_u_network_flow.py

test-style:
	$(PYTHON) tests/check_rtl_style.py

# DOCX integrity, source/RTL interface consistency; uses Python stdlib only.
test-specs:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/test_rtl_specs.py

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
	$(VERILATOR) --language 1364-2005 --lint-only -Irtl --top-module mdm_sec -GAES_LOW_AREA=0 $(RTL)
	$(VERILATOR) --language 1364-2005 --lint-only -Irtl --top-module mdm_sec -GAES_LOW_AREA=2 $(RTL)

$(BUILD_DIR)/aes_vectors.txt: tests/gen_aes_vectors.py tests/reference_model.py sec_core/aes/sec_aes_core_enc.py
	@mkdir -p $(@D)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/gen_aes_vectors.py $@

$(BUILD_DIR)/aes_balanced_stage_vectors.txt: tests/gen_aes_balanced_stage_vectors.py sec_core/aes/sec_aes_core_enc.py
	@mkdir -p $(@D)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/gen_aes_balanced_stage_vectors.py $@

$(BUILD_DIR)/tb_aes_balanced_blocks/Vtb_aes_balanced_blocks: $(AES_RTL) $(HEADERS) tests/rtl/tb_aes_balanced_blocks.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_aes_balanced_blocks --Mdir $(abspath $(@D)) $(AES_RTL) tests/rtl/tb_aes_balanced_blocks.sv

test-aes-balanced-blocks: $(BUILD_DIR)/aes_balanced_stage_vectors.txt $(BUILD_DIR)/tb_aes_balanced_blocks/Vtb_aes_balanced_blocks
	$(BUILD_DIR)/tb_aes_balanced_blocks/Vtb_aes_balanced_blocks +VECTORS=$(abspath $(BUILD_DIR)/aes_balanced_stage_vectors.txt)

$(BUILD_DIR)/tb_aes_small/Vtb_aes_random: $(AES_RTL) $(HEADERS) tests/rtl/tb_aes_random.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_aes_random --Mdir $(abspath $(@D)) $(AES_RTL) tests/rtl/tb_aes_random.sv

$(BUILD_DIR)/tb_aes_fast/Vtb_aes_random: $(AES_RTL) $(HEADERS) tests/rtl/tb_aes_random.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_aes_random -GTEST_AES_LOW_AREA=0 --Mdir $(abspath $(@D)) $(AES_RTL) tests/rtl/tb_aes_random.sv

$(BUILD_DIR)/tb_aes_balanced/Vtb_aes_random: $(AES_RTL) $(HEADERS) tests/rtl/tb_aes_random.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_aes_random -GTEST_AES_LOW_AREA=2 --Mdir $(abspath $(@D)) $(AES_RTL) tests/rtl/tb_aes_random.sv

$(BUILD_DIR)/tb_aes_balanced_timing/Vtb_aes_random: $(AES_RTL) $(HEADERS) tests/rtl/tb_aes_random.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_aes_random -GTEST_AES_LOW_AREA=2 -GTEST_BALANCED_TIMING_OPT=1 \
		--Mdir $(abspath $(@D)) $(AES_RTL) tests/rtl/tb_aes_random.sv

test-aes: $(BUILD_DIR)/aes_vectors.txt $(BUILD_DIR)/tb_aes_small/Vtb_aes_random $(BUILD_DIR)/tb_aes_fast/Vtb_aes_random $(BUILD_DIR)/tb_aes_balanced/Vtb_aes_random $(BUILD_DIR)/tb_aes_balanced_timing/Vtb_aes_random
	$(BUILD_DIR)/tb_aes_small/Vtb_aes_random +VECTORS=$(abspath $(BUILD_DIR)/aes_vectors.txt)
	$(BUILD_DIR)/tb_aes_fast/Vtb_aes_random +VECTORS=$(abspath $(BUILD_DIR)/aes_vectors.txt)
	$(BUILD_DIR)/tb_aes_balanced/Vtb_aes_random +VECTORS=$(abspath $(BUILD_DIR)/aes_vectors.txt)
	$(BUILD_DIR)/tb_aes_balanced_timing/Vtb_aes_random +VECTORS=$(abspath $(BUILD_DIR)/aes_vectors.txt)

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

$(BUILD_DIR)/tb_buffer_min/Vtb_packet_buffer: rtl/mdm_packet_buffer.v tests/rtl/tb_packet_buffer.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_packet_buffer -GTEST_CAP=1 -GTEST_READ_PORTS=2 --Mdir $(abspath $(@D)) $^

$(BUILD_DIR)/tb_buffer_one_read/Vtb_packet_buffer: rtl/mdm_packet_buffer.v tests/rtl/tb_packet_buffer.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_packet_buffer -GTEST_CAP=64 -GTEST_READ_PORTS=1 --Mdir $(abspath $(@D)) $^

$(BUILD_DIR)/tb_buffer_full/Vtb_packet_buffer: rtl/mdm_packet_buffer.v tests/rtl/tb_packet_buffer.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_packet_buffer -GTEST_CAP=65536 -GTEST_READ_PORTS=2 --Mdir $(abspath $(@D)) $^

test-buffer: $(BUILD_DIR)/tb_packet_buffer/Vtb_packet_buffer $(BUILD_DIR)/tb_buffer_min/Vtb_packet_buffer \
             $(BUILD_DIR)/tb_buffer_one_read/Vtb_packet_buffer $(BUILD_DIR)/tb_buffer_full/Vtb_packet_buffer
	$(BUILD_DIR)/tb_packet_buffer/Vtb_packet_buffer
	$(BUILD_DIR)/tb_buffer_min/Vtb_packet_buffer
	$(BUILD_DIR)/tb_buffer_one_read/Vtb_packet_buffer
	$(BUILD_DIR)/tb_buffer_full/Vtb_packet_buffer

# A compact directed suite uses the same self-checking packet bench as the
# regression. Its trace-enabled binary does not write VCD unless +WAVE is set.
$(BUILD_DIR)/wave_vectors.txt: tests/gen_wave_vectors.py tests/reference_model.py \
       sec_core/aes/sec_aes_core_enc.py sec_core/snow3g/sec_snow3g_core.py sec_core/zuc/sec_zuc_core.py
	@mkdir -p $(@D)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/gen_wave_vectors.py $@

$(BUILD_DIR)/wave_vectors.cases.txt: $(BUILD_DIR)/wave_vectors.txt
	@test -f "$@" || PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/gen_wave_vectors.py "$(BUILD_DIR)/wave_vectors.txt"

$(BUILD_DIR)/tb_wave_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv Makefile
	@test -n "$(VERILATOR)" || { echo 'Install Verilator (or set VERILATOR=...)'; exit 1; }
	@case "$(WAVE_AES_LOW_AREA)" in 0|1|2) ;; *) echo 'WAVE_AES_LOW_AREA must be 0, 1 or 2'; exit 1;; esac
	@test $(WAVE_MAX_BYTES) -ge 512 -a $(WAVE_MAX_BYTES) -le 65535 || { echo 'WAVE_MAX_BYTES must be 512..65535 for the directed suite'; exit 1; }
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing --trace --trace-depth 5 -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_MAX_BYTES=$(WAVE_MAX_BYTES) -GTEST_AES_LOW_AREA=$(WAVE_AES_LOW_AREA) --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv
	@touch $@

test-directed: $(BUILD_DIR)/wave_vectors.txt $(BUILD_DIR)/wave_vectors.cases.txt $(BUILD_DIR)/tb_wave_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)/Vtb_mdm_sec
	$(BUILD_DIR)/tb_wave_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/wave_vectors.txt) +DIRECTED_COVERAGE +CASE_LOG

# Exercise the real packet trace recipe during make test; do not leave a VCD.
test-vcd-trace: $(BUILD_DIR)/wave_vectors.txt $(BUILD_DIR)/tb_wave_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)/Vtb_mdm_sec
	@set -eu; trace=$$(mktemp "$(abspath $(BUILD_DIR))/packet-vcd.XXXXXXXX"); \
		trap 'rm -f "$$trace"' EXIT; \
		$(BUILD_DIR)/tb_wave_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)/Vtb_mdm_sec \
			+VECTORS=$(abspath $(BUILD_DIR)/wave_vectors.txt) +DIRECTED_COVERAGE "+WAVE=$$trace"; \
		$(PYTHON) tests/check_vcd.py packet "$$trace"

# Persistent VCD files are written only by explicit waveform targets.
$(BUILD_DIR)/tb_wave_aes_$(WAVE_AES_LOW_AREA)/Vtb_aes_random: $(AES_RTL) $(HEADERS) tests/rtl/tb_aes_random.sv Makefile
	@test -n "$(VERILATOR)" || { echo 'Install Verilator (or set VERILATOR=...)'; exit 1; }
	@case "$(WAVE_AES_LOW_AREA)" in 0|1|2) ;; *) echo 'WAVE_AES_LOW_AREA must be 0, 1 or 2'; exit 1;; esac
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing --trace -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_aes_random -GTEST_AES_LOW_AREA=$(WAVE_AES_LOW_AREA) --Mdir $(abspath $(@D)) $(AES_RTL) tests/rtl/tb_aes_random.sv
	@touch $@

# Packet traces include both AES u_core instances (depth 5), without tracing
# the large shared-buffer memory arrays. The checker verifies core activity.
wave-packet: $(BUILD_DIR)/wave_vectors.txt $(BUILD_DIR)/wave_vectors.cases.txt $(BUILD_DIR)/tb_wave_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)/Vtb_mdm_sec
	@mkdir -p "$(WAVE_DIR)"
	@rm -f "$(WAVE_DIR)/mdm_sec_$(WAVE_VARIANT).vcd"
	$(BUILD_DIR)/tb_wave_packet_$(WAVE_MAX_BYTES)_$(WAVE_AES_LOW_AREA)/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/wave_vectors.txt) +DIRECTED_COVERAGE +CASE_LOG \
		"+WAVE=$(abspath $(WAVE_DIR)/mdm_sec_$(WAVE_VARIANT).vcd)"
	$(PYTHON) tests/check_vcd.py packet "$(WAVE_DIR)/mdm_sec_$(WAVE_VARIANT).vcd"

wave-aes: $(BUILD_DIR)/aes_vectors.txt $(BUILD_DIR)/tb_wave_aes_$(WAVE_AES_LOW_AREA)/Vtb_aes_random
	@test $(WAVE_AES_BLOCKS) -ge 2 -a $(WAVE_AES_BLOCKS) -le $$(wc -l < "$(BUILD_DIR)/aes_vectors.txt") || { echo 'WAVE_AES_BLOCKS must be 2..the number of AES vectors'; exit 1; }
	@mkdir -p "$(WAVE_DIR)"
	@rm -f "$(WAVE_DIR)/aes128_$(WAVE_VARIANT).vcd"
	$(BUILD_DIR)/tb_wave_aes_$(WAVE_AES_LOW_AREA)/Vtb_aes_random +VECTORS=$(abspath $(BUILD_DIR)/aes_vectors.txt) +LIMIT=$(WAVE_AES_BLOCKS) +CASE_LOG \
		"+WAVE=$(abspath $(WAVE_DIR)/aes128_$(WAVE_VARIANT).vcd)"
	$(PYTHON) tests/check_vcd.py aes "$(WAVE_DIR)/aes128_$(WAVE_VARIANT).vcd"

wave: wave-packet wave-aes
	@echo "Waveforms written to $(WAVE_DIR)"

# Native FSDB requires licensed VCS plus the Verdi PLI. Keep all VCS-generated
# csrc, simv.daidir, KDB and logs in separate configuration-specific folders.
$(VCS_PACKET_BUILD)/simv: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv Makefile
	@command -v "$(VCS)" >/dev/null 2>&1 || { echo 'Install/configure VCS (or set VCS=/absolute/path/to/vcs)'; exit 1; }
	@case "$(WAVE_AES_LOW_AREA)" in 0|1|2) ;; *) echo 'WAVE_AES_LOW_AREA must be 0, 1 or 2'; exit 1;; esac
	@test $(WAVE_MAX_BYTES) -ge 512 -a $(WAVE_MAX_BYTES) -le 65535 || { echo 'WAVE_MAX_BYTES must be 512..65535 for the directed suite'; exit 1; }
	@if [ ! -f "$(VERDI_TAB)" ] || [ ! -f "$(VERDI_PLI)" ]; then echo 'Verdi PLI not found: set VERDI_HOME/NOVAS_HOME, VERDI_PLI_DIR, or VERDI_TAB and VERDI_PLI'; exit 1; fi
	@mkdir -p "$(@D)"
	cd "$(@D)" && "$(VCS)" $(VCS_FLAGS) $(VCS_EXTRA_FLAGS) +define+MDM_SEC_FSDB \
		+incdir+$(abspath rtl) -top tb_mdm_sec \
		-pvalue+tb_mdm_sec.TEST_MAX_BYTES=$(WAVE_MAX_BYTES) -pvalue+tb_mdm_sec.TEST_AES_LOW_AREA=$(WAVE_AES_LOW_AREA) \
		-P "$(abspath $(VERDI_TAB))" "$(abspath $(VERDI_PLI))" $(abspath $(RTL)) $(abspath tests/rtl/tb_mdm_sec.sv) -o simv -l vcs_compile.log
	@test -x "$@" || { echo 'VCS did not produce an executable simv'; exit 1; }
	@touch "$@"

$(VCS_AES_BUILD)/simv: $(AES_RTL) $(HEADERS) tests/rtl/tb_aes_random.sv Makefile
	@command -v "$(VCS)" >/dev/null 2>&1 || { echo 'Install/configure VCS (or set VCS=/absolute/path/to/vcs)'; exit 1; }
	@case "$(WAVE_AES_LOW_AREA)" in 0|1|2) ;; *) echo 'WAVE_AES_LOW_AREA must be 0, 1 or 2'; exit 1;; esac
	@if [ ! -f "$(VERDI_TAB)" ] || [ ! -f "$(VERDI_PLI)" ]; then echo 'Verdi PLI not found: set VERDI_HOME/NOVAS_HOME, VERDI_PLI_DIR, or VERDI_TAB and VERDI_PLI'; exit 1; fi
	@mkdir -p "$(@D)"
	cd "$(@D)" && "$(VCS)" $(VCS_FLAGS) $(VCS_EXTRA_FLAGS) +define+MDM_SEC_FSDB \
		+incdir+$(abspath rtl) -top tb_aes_random -pvalue+tb_aes_random.TEST_AES_LOW_AREA=$(WAVE_AES_LOW_AREA) \
		-P "$(abspath $(VERDI_TAB))" "$(abspath $(VERDI_PLI))" $(abspath $(AES_RTL)) $(abspath tests/rtl/tb_aes_random.sv) -o simv -l vcs_compile.log
	@test -x "$@" || { echo 'VCS did not produce an executable simv'; exit 1; }
	@touch "$@"

# These checks deliberately have no generator prerequisites in prebuilt mode.
# Missing transferred inputs are errors, never an excuse to regenerate them.
fsdb-check-packet-vectors: $(FSDB_PACKET_VECTOR_DEPS)
	@test -r "$(FSDB_PACKET_VECTOR)" -a -s "$(FSDB_PACKET_VECTOR)" || { echo 'Packet vectors missing, unreadable or empty: $(FSDB_PACKET_VECTOR)'; exit 1; }

fsdb-check-aes-vectors: $(FSDB_AES_VECTOR_DEPS)
	@test -r "$(FSDB_AES_VECTOR)" -a -s "$(FSDB_AES_VECTOR)" || { echo 'AES vectors missing, unreadable or empty: $(FSDB_AES_VECTOR)'; exit 1; }

fsdb-packet: fsdb-check-packet-vectors $(VCS_PACKET_BUILD)/simv
	@case "$(FSDB_MDA)" in 0|1) ;; *) echo 'FSDB_MDA must be 0 or 1'; exit 1;; esac
	@mkdir -p "$(FSDB_DIR)"
	@rm -f "$(FSDB_DIR)/mdm_sec_$(WAVE_VARIANT).fsdb" "$(VCS_PACKET_BUILD)/sim.log"
	cd "$(VCS_PACKET_BUILD)" && ./simv "+VECTORS=$(abspath $(FSDB_PACKET_VECTOR))" +DIRECTED_COVERAGE +CASE_LOG \
		"+FSDB=$(abspath $(FSDB_DIR)/mdm_sec_$(WAVE_VARIANT).fsdb)" $(if $(filter 1,$(FSDB_MDA)),+FSDB_MDA,) $(VCS_SIM_FLAGS) -l sim.log
	@grep -Fq 'DIRECTED configuration MAX_BYTES=$(WAVE_MAX_BYTES) AES_LOW_AREA=$(WAVE_AES_LOW_AREA)' "$(VCS_PACKET_BUILD)/sim.log" || { echo 'Packet VCS parameter mismatch; inspect $(VCS_PACKET_BUILD)/sim.log'; exit 1; }
	@grep -Fq 'PASS directed waveform cases:' "$(VCS_PACKET_BUILD)/sim.log" && grep -Fq 'PASS 20 packet vectors (MAX_BYTES=$(WAVE_MAX_BYTES))' "$(VCS_PACKET_BUILD)/sim.log" || { echo 'Packet self-check/coverage did not pass; inspect $(VCS_PACKET_BUILD)/sim.log'; exit 1; }
	@test -s "$(FSDB_DIR)/mdm_sec_$(WAVE_VARIANT).fsdb" || { echo 'Packet FSDB missing or empty; inspect $(VCS_PACKET_BUILD)/sim.log'; exit 1; }
	@echo 'PASS packet self-check and nonempty FSDB: $(FSDB_DIR)/mdm_sec_$(WAVE_VARIANT).fsdb'

fsdb-aes: fsdb-check-aes-vectors $(VCS_AES_BUILD)/simv
	@test $(WAVE_AES_BLOCKS) -ge 2 -a $(WAVE_AES_BLOCKS) -le $$(wc -l < "$(FSDB_AES_VECTOR)") || { echo 'WAVE_AES_BLOCKS must be 2..the number of AES vectors'; exit 1; }
	@mkdir -p "$(FSDB_DIR)"
	@rm -f "$(FSDB_DIR)/aes128_$(WAVE_VARIANT).fsdb" "$(VCS_AES_BUILD)/sim.log"
	cd "$(VCS_AES_BUILD)" && ./simv "+VECTORS=$(abspath $(FSDB_AES_VECTOR))" +LIMIT=$(WAVE_AES_BLOCKS) +CASE_LOG \
		"+FSDB=$(abspath $(FSDB_DIR)/aes128_$(WAVE_VARIANT).fsdb)" $(VCS_SIM_FLAGS) -l sim.log
	@grep -Fq 'PASS $(WAVE_AES_BLOCKS) AES blocks, $(VCS_AES_CYCLES)-cycle latency/II,' "$(VCS_AES_BUILD)/sim.log" || { echo 'AES self-check or AES_LOW_AREA parameter did not pass; inspect $(VCS_AES_BUILD)/sim.log'; exit 1; }
	@test -s "$(FSDB_DIR)/aes128_$(WAVE_VARIANT).fsdb" || { echo 'AES FSDB missing or empty; inspect $(VCS_AES_BUILD)/sim.log'; exit 1; }
	@echo 'PASS AES self-check and nonempty FSDB: $(FSDB_DIR)/aes128_$(WAVE_VARIANT).fsdb'

fsdb: fsdb-packet fsdb-aes
	@echo "FSDB waveforms written to $(FSDB_DIR)"

verdi-packet:
	@command -v "$(VERDI)" >/dev/null 2>&1 || { echo 'Configure Verdi (or set VERDI=/absolute/path/to/verdi)'; exit 1; }
	@test -s "$(FSDB_DIR)/mdm_sec_$(WAVE_VARIANT).fsdb" -a -d "$(VCS_PACKET_BUILD)/simv.daidir" || { echo 'Run make fsdb-packet with the same parameters first'; exit 1; }
	cd "$(VCS_PACKET_BUILD)" && "$(VERDI)" -simflow -dbdir simv.daidir -ssf "$(abspath $(FSDB_DIR)/mdm_sec_$(WAVE_VARIANT).fsdb)"

verdi-aes:
	@command -v "$(VERDI)" >/dev/null 2>&1 || { echo 'Configure Verdi (or set VERDI=/absolute/path/to/verdi)'; exit 1; }
	@test -s "$(FSDB_DIR)/aes128_$(WAVE_VARIANT).fsdb" -a -d "$(VCS_AES_BUILD)/simv.daidir" || { echo 'Run make fsdb-aes with the same parameters first'; exit 1; }
	cd "$(VCS_AES_BUILD)" && "$(VERDI)" -simflow -dbdir simv.daidir -ssf "$(abspath $(FSDB_DIR)/aes128_$(WAVE_VARIANT).fsdb)"

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

$(BUILD_DIR)/tb_primitives_fast/Vtb_primitives: $(RTL) $(HEADERS) tests/rtl/tb_primitives.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_primitives -GTEST_AES_LOW_AREA=0 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_primitives.sv

$(BUILD_DIR)/tb_lanes_fast/Vtb_lanes: $(RTL) $(HEADERS) tests/rtl/tb_lanes.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_lanes -GTEST_AES_LOW_AREA=0 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_lanes.sv

$(BUILD_DIR)/tb_packet_fast/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_AES_LOW_AREA=0 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

$(BUILD_DIR)/tb_boundaries_fast/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_AES_LOW_AREA=0 -GTEST_MAX_BYTES=65535 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv


$(BUILD_DIR)/tb_primitives_balanced/Vtb_primitives: $(RTL) $(HEADERS) tests/rtl/tb_primitives.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_primitives -GTEST_AES_LOW_AREA=2 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_primitives.sv

$(BUILD_DIR)/tb_lanes_balanced/Vtb_lanes: $(RTL) $(HEADERS) tests/rtl/tb_lanes.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_lanes -GTEST_AES_LOW_AREA=2 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_lanes.sv

$(BUILD_DIR)/tb_packet_balanced/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_AES_LOW_AREA=2 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

$(BUILD_DIR)/tb_boundaries_balanced/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_AES_LOW_AREA=2 -GTEST_MAX_BYTES=65535 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

$(BUILD_DIR)/tb_packet_balanced_fallback/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_AES_LOW_AREA=2 -GTEST_AES_INTEGRITY_TIMING_OPT=0 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

$(BUILD_DIR)/tb_boundaries_balanced_fallback/Vtb_mdm_sec: $(RTL) $(HEADERS) tests/rtl/tb_mdm_sec.sv
	@mkdir -p $(@D)
	MAKEFLAGS="$(VMAKEFLAGS)" $(VERILATOR) --binary --timing -j $(JOBS) -Wno-TIMESCALEMOD -Irtl \
		--top-module tb_mdm_sec -GTEST_AES_LOW_AREA=2 -GTEST_AES_INTEGRITY_TIMING_OPT=0 -GTEST_MAX_BYTES=65535 --Mdir $(abspath $(@D)) $(RTL) tests/rtl/tb_mdm_sec.sv

# Check that selecting the legacy five-cycle AES propagates through both lanes
# and the top level, including all six packet modes and maximum-size wrap.
test-fast: $(BUILD_DIR)/packet_vectors.txt $(BUILD_DIR)/boundary_vectors.txt $(BUILD_DIR)/tb_primitives_fast/Vtb_primitives \
           $(BUILD_DIR)/tb_lanes_fast/Vtb_lanes $(BUILD_DIR)/tb_packet_fast/Vtb_mdm_sec $(BUILD_DIR)/tb_boundaries_fast/Vtb_mdm_sec
	$(BUILD_DIR)/tb_primitives_fast/Vtb_primitives +SBOX=$(abspath tests/rtl/aes_sbox.hex)
	$(BUILD_DIR)/tb_lanes_fast/Vtb_lanes
	$(BUILD_DIR)/tb_packet_fast/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/packet_vectors.txt) +REQUIRE_PARALLEL_COVERAGE
	$(BUILD_DIR)/tb_boundaries_fast/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/boundary_vectors.txt)

# Full end-to-end regression for the third AES option; does not replace the
# legacy fast or low-area tests and continues to use independent lane cores.
test-balanced: $(BUILD_DIR)/packet_vectors.txt $(BUILD_DIR)/boundary_vectors.txt $(BUILD_DIR)/tb_primitives_balanced/Vtb_primitives \
               $(BUILD_DIR)/tb_lanes_balanced/Vtb_lanes $(BUILD_DIR)/tb_packet_balanced/Vtb_mdm_sec $(BUILD_DIR)/tb_boundaries_balanced/Vtb_mdm_sec
	$(BUILD_DIR)/tb_primitives_balanced/Vtb_primitives +SBOX=$(abspath tests/rtl/aes_sbox.hex)
	$(BUILD_DIR)/tb_lanes_balanced/Vtb_lanes
	$(BUILD_DIR)/tb_packet_balanced/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/packet_vectors.txt) +REQUIRE_PARALLEL_COVERAGE
	$(BUILD_DIR)/tb_boundaries_balanced/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/boundary_vectors.txt)

# Exercise the top-level rollback independently, including simultaneous lanes
# and maximum packet capacity; never re-use the candidate's compiled binary.
test-balanced-fallback: $(BUILD_DIR)/packet_vectors.txt $(BUILD_DIR)/boundary_vectors.txt \
                        $(BUILD_DIR)/tb_packet_balanced_fallback/Vtb_mdm_sec $(BUILD_DIR)/tb_boundaries_balanced_fallback/Vtb_mdm_sec
	$(BUILD_DIR)/tb_packet_balanced_fallback/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/packet_vectors.txt) +REQUIRE_PARALLEL_COVERAGE
	$(BUILD_DIR)/tb_boundaries_balanced_fallback/Vtb_mdm_sec +VECTORS=$(abspath $(BUILD_DIR)/boundary_vectors.txt)

# Formal checks use async2sync's reset model; target gate-level and asynchronous
# reset sign-off remain the integrator's responsibility.
test-aes-formal:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog -Irtl rtl/mdm_aes_balanced_blocks.v rtl/mdm_aes128_balanced_timing.v tests/formal/aes_mix_miter.v; prep -top aes_mix_miter -flatten; sat -verify -prove mismatch 0' > $(BUILD_DIR)/aes-mix-formal.log
	@grep -q 'SAT proof finished - no model found: SUCCESS' $(BUILD_DIR)/aes-mix-formal.log
	$(YOSYS) -Q -T -p 'read_verilog -Irtl rtl/mdm_aes_sbox.v rtl/mdm_aes128_balanced_timing.v tests/formal/aes_sbox_timing_miter.v; prep -top aes_sbox_timing_miter -flatten; sat -verify -prove mismatch 0' > $(BUILD_DIR)/aes-sbox-timing-formal.log
	@grep -q 'SAT proof finished - no model found: SUCCESS' $(BUILD_DIR)/aes-sbox-timing-formal.log
	$(YOSYS) -Q -T -p 'read_verilog -Irtl rtl/mdm_aes_sbox.v rtl/mdm_aes_blocks.v rtl/mdm_aes_balanced_blocks.v rtl/mdm_aes128_fast.v rtl/mdm_aes128_balanced.v; hierarchy -check; proc; flatten mdm_aes128_fast mdm_aes128_balanced; opt_clean; equiv_make mdm_aes128_fast mdm_aes128_balanced equiv; hierarchy -check -top equiv; async2sync; equiv_simple; equiv_status -assert' > $(BUILD_DIR)/aes-balanced-equiv.log
	@grep -q 'Equivalence successfully proven' $(BUILD_DIR)/aes-balanced-equiv.log
	$(YOSYS) -Q -T -p 'read_verilog -Irtl rtl/mdm_aes_sbox.v rtl/mdm_aes_blocks.v rtl/mdm_aes_balanced_blocks.v rtl/mdm_aes128_balanced.v rtl/mdm_aes128_balanced_timing.v; hierarchy -check; proc; flatten mdm_aes128_balanced mdm_aes128_balanced_timing; opt_clean; equiv_make -blacklist tests/formal/aes_timing_equiv_blacklist.txt mdm_aes128_balanced mdm_aes128_balanced_timing equiv; hierarchy -check -top equiv; async2sync; equiv_simple; equiv_status -assert' > $(BUILD_DIR)/aes-timing-equiv.log
	@grep -q 'Equivalence successfully proven' $(BUILD_DIR)/aes-timing-equiv.log
	@echo 'PASS both MixColumns/S-box SAT checks and fast/original/timing AES equivalence (async2sync reset model)'

area-aes-balanced:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	$(PYTHON) tests/compare_aes_balanced_area.py --yosys "$(YOSYS)" --output "$(BUILD_DIR)/aes-balanced-area"

# Generic unit-weight graph only: not mapped area, delay, or STA.
area-aes-timing:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	$(PYTHON) tests/compare_aes_timing_structure.py --yosys "$(YOSYS)" --output "$(BUILD_DIR)/aes-timing-structure"

# Check reportable stages in both cores and the default/fallback top choices.
test-aes-hierarchy:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(AES_RTL); hierarchy -check -top mdm_aes128_balanced; synth -top mdm_aes128_balanced -noabc; check -assert; stat; write_json $(BUILD_DIR)/aes-balanced-synth.json' > $(BUILD_DIR)/aes-balanced-synth-hierarchy.log
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(AES_RTL); hierarchy -check -top mdm_aes128_balanced_timing; synth -top mdm_aes128_balanced_timing -noabc; check -assert; stat; write_json $(BUILD_DIR)/aes-balanced-timing-synth.json' > $(BUILD_DIR)/aes-balanced-timing-synth-hierarchy.log
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES 16 -chparam AES_LOW_AREA 2; proc; opt_clean; check -assert; write_json $(BUILD_DIR)/aes-balanced-top.json' > $(BUILD_DIR)/aes-balanced-top-hierarchy.log
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES 16 -chparam AES_LOW_AREA 2 -chparam AES_INTEGRITY_TIMING_OPT 0; proc; opt_clean; check -assert; write_json $(BUILD_DIR)/aes-balanced-top-fallback.json' > $(BUILD_DIR)/aes-balanced-top-fallback-hierarchy.log
	$(PYTHON) tests/check_aes_balanced_hierarchy.py --synth $(BUILD_DIR)/aes-balanced-synth.json --synth-timing $(BUILD_DIR)/aes-balanced-timing-synth.json --top $(BUILD_DIR)/aes-balanced-top.json --top-fallback $(BUILD_DIR)/aes-balanced-top-fallback.json

yosys-check:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES $(CHECK_MAX_BYTES) -chparam AES_LOW_AREA $(CHECK_AES_LOW_AREA) -chparam AES_INTEGRITY_TIMING_OPT $(CHECK_AES_INTEGRITY_TIMING_OPT); proc; opt; check -assert; stat' > $(BUILD_DIR)/yosys-check.log
	@tail -55 $(BUILD_DIR)/yosys-check.log

# Invalid parameters must fail specifically at the elaboration guards.
yosys-parameters:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	@for value in 0 65536; do \
		if $(YOSYS) -Q -T -p "read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES $$value" > $(BUILD_DIR)/invalid-$$value.log 2>&1; then \
			echo "FAIL: MAX_BYTES=$$value was accepted"; exit 1; \
		fi; \
		grep -Eq 'ERROR:[[:space:]]*System task' $(BUILD_DIR)/invalid-$$value.log || { cat $(BUILD_DIR)/invalid-$$value.log; exit 1; }; \
	done
	@for value in 3 4; do \
		if $(YOSYS) -Q -T -p "read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam AES_LOW_AREA $$value" > $(BUILD_DIR)/invalid-aes-$$value.log 2>&1; then \
			echo "FAIL: AES_LOW_AREA=$$value was accepted"; exit 1; \
		fi; \
		grep -Eq 'ERROR:[[:space:]]*System task' $(BUILD_DIR)/invalid-aes-$$value.log || { cat $(BUILD_DIR)/invalid-aes-$$value.log; exit 1; }; \
	done
	@for mode in 0 1 2; do \
		if $(YOSYS) -Q -T -p "read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam AES_LOW_AREA $$mode -chparam AES_INTEGRITY_TIMING_OPT 2" > $(BUILD_DIR)/invalid-aes-timing-$$mode.log 2>&1; then \
			echo "FAIL: AES_INTEGRITY_TIMING_OPT=2 was accepted for AES_LOW_AREA=$$mode"; exit 1; \
		fi; \
		grep -Eq 'ERROR:[[:space:]]*System task' $(BUILD_DIR)/invalid-aes-timing-$$mode.log || { cat $(BUILD_DIR)/invalid-aes-timing-$$mode.log; exit 1; }; \
	done
	@for parameters in 'CAP_BYTES 0' 'CAP_BYTES 65537' 'READ_PORTS 0' 'READ_PORTS 3'; do \
		set -- $$parameters; \
		if $(YOSYS) -Q -T -p "read_verilog rtl/mdm_packet_buffer.v; hierarchy -check -top mdm_packet_buffer -chparam $$1 $$2" > $(BUILD_DIR)/invalid-buffer-$$1-$$2.log 2>&1; then \
			echo "FAIL: $$parameters was accepted"; exit 1; \
		fi; \
		grep -Eq 'ERROR:[[:space:]]*System task' $(BUILD_DIR)/invalid-buffer-$$1-$$2.log || { cat $(BUILD_DIR)/invalid-buffer-$$1-$$2.log; exit 1; }; \
	done
	@echo 'PASS invalid MAX_BYTES, AES_LOW_AREA, AES_INTEGRITY_TIMING_OPT and packet-buffer parameters rejected'

# Generic pre-technology mapping sanity check, NOT physical area/timing.
# This maps memories to flip-flops; use target SRAMs for real implementation.
synth-generic:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(RTL); hierarchy -check -top mdm_sec -chparam MAX_BYTES $(SYNTH_MAX_BYTES) -chparam AES_LOW_AREA $(SYNTH_AES_LOW_AREA) -chparam AES_INTEGRITY_TIMING_OPT $(SYNTH_AES_INTEGRITY_TIMING_OPT); synth -top mdm_sec -noabc; check -assert; stat' > $(BUILD_DIR)/synth-generic.log
	@tail -65 $(BUILD_DIR)/synth-generic.log

# Standalone hierarchical reports; each generic cell counts as one regardless
# of technology and no ABC/physical mapping or timing analysis is performed.
synth-aes:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog -Irtl $(AES_RTL); hierarchy -check -top mdm_aes128 -chparam AES_LOW_AREA $(SYNTH_AES_LOW_AREA) -chparam BALANCED_TIMING_OPT $(SYNTH_BALANCED_TIMING_OPT); synth -top mdm_aes128 -noabc; check -assert; stat' > $(BUILD_DIR)/synth-aes-$(SYNTH_AES_LOW_AREA).log
	@tail -85 $(BUILD_DIR)/synth-aes-$(SYNTH_AES_LOW_AREA).log

synth-buffer:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -Q -T -p 'read_verilog rtl/mdm_packet_buffer.v; hierarchy -check -top mdm_packet_buffer -chparam CAP_BYTES $(BUFFER_CAP_BYTES) -chparam READ_PORTS $(BUFFER_READ_PORTS); synth -top mdm_packet_buffer -noabc; check -assert; stat' > $(BUILD_DIR)/synth-buffer-$(BUFFER_CAP_BYTES)-$(BUFFER_READ_PORTS).log
	@tail -30 $(BUILD_DIR)/synth-buffer-$(BUFFER_CAP_BYTES)-$(BUFFER_READ_PORTS).log

# Extract the pre-optimization RTL from Git and reproduce the paired comparison.
area-compare:
	@test -n "$(YOSYS)" || { echo 'Install Yosys (or set YOSYS=...)'; exit 1; }
	$(PYTHON) tests/compare_generic_area.py --yosys "$(YOSYS)" --baseline "$(AREA_BASE_REF)" --output "$(BUILD_DIR)/area-compare"

clean:
	rm -rf $(BUILD_DIR)
