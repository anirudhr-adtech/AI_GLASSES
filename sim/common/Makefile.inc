# Common Makefile include for AI Glasses SoC verification
# Include this from per-subsystem Makefiles

VERILATOR     ?= /usr/local/bin/verilator
SURELOG       ?= /usr/local/bin/surelog
SIM_COMMON    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SIM_MAIN      := $(SIM_COMMON)/sim_main.cpp
TOP_DIR       := $(abspath $(SIM_COMMON)/../..)
WAVE_DIR      := $(TOP_DIR)/sim/waves
LOG_DIR       := $(TOP_DIR)/sim/logs

# Verilator flags
VFLAGS        := --cc --exe --build -j 4 --trace --timing
VFLAGS        += -Wno-lint
VFLAGS        += --Mdir $(OBJ_DIR)

# Detect all TB files in tb/ directory
TB_SRCS       := $(wildcard $(TB_DIR)/tb_*.v)
TB_NAMES      := $(basename $(notdir $(TB_SRCS)))
TB_BINS       := $(addprefix $(OBJ_DIR)/V, $(TB_NAMES))

# Per-subsystem -y flags (set by each subsystem Makefile)
# YDIRS = -y ../

.PHONY: all clean lint report waves

all: $(TB_NAMES)

# Pattern rule: build one TB
$(OBJ_DIR)/V%: $(TB_DIR)/tb_%.v $(wildcard $(RTL_DIR)/*.v) $(SIM_MAIN)
	@mkdir -p $(OBJ_DIR) $(LOG_DIR) $(WAVE_DIR)
	$(VERILATOR) $(VFLAGS) $(YDIRS) \
		--top-module $(notdir $(basename $<)) \
		--Mdir $(OBJ_DIR)/$(notdir $(basename $<)) \
		$< $(SIM_MAIN) \
		-CFLAGS '-DTOP_HEADER=\"V$(notdir $(basename $<)).h\" -DTOP_CLASS=V$(notdir $(basename $<))' \
		2>&1 | tee $(LOG_DIR)/$(notdir $(basename $<))_build.log
	@echo "Built: $@"

# Pattern rule: compile and run one TB
tb_%: $(TB_DIR)/tb_%.v $(wildcard $(RTL_DIR)/*.v) $(SIM_MAIN)
	@mkdir -p $(OBJ_DIR)/$@ $(LOG_DIR) $(WAVE_DIR)
	@echo "=== Building $@ ==="
	@$(VERILATOR) $(VFLAGS) $(YDIRS) \
		--top-module $@ \
		--Mdir $(OBJ_DIR)/$@ \
		$< $(SIM_MAIN) \
		-CFLAGS '-DTOP_HEADER=\"V$@.h\" -DTOP_CLASS=V$@' \
		2>&1 | tee $(LOG_DIR)/$@_build.log
	@echo "=== Running $@ ==="
	@$(OBJ_DIR)/$@/V$@ 2>&1 | tee $(LOG_DIR)/$@_sim.log
	@echo ""

# Run TB with VCD waveform
waves_%: tb_%
	VCD_FILE=$(WAVE_DIR)/$*.vcd $(OBJ_DIR)/tb_$*/Vtb_$* 2>&1 | tee $(LOG_DIR)/tb_$*_sim.log

# Verilator lint-only on all RTL
lint:
	@echo "=== Lint: $(SUBSYSTEM) ==="
	@for f in $(RTL_DIR)/*.v; do \
		echo "  Lint: $$(basename $$f)"; \
		$(VERILATOR) --lint-only -Wall $(YDIRS) $$f 2>&1 | tee -a $(LOG_DIR)/$(SUBSYSTEM)_lint.log; \
	done

# Surelog parse
surelog:
	@echo "=== Surelog: $(SUBSYSTEM) ==="
	$(SURELOG) $(wildcard $(RTL_DIR)/*.v) -parse 2>&1 | tee $(LOG_DIR)/$(SUBSYSTEM)_surelog.log

# Report: extract PASS/FAIL from simulation logs
report:
	@echo "=== $(SUBSYSTEM) Results ==="
	@pass=0; fail=0; total=0; \
	for log in $(LOG_DIR)/tb_*_sim.log; do \
		[ -f "$$log" ] || continue; \
		total=$$((total + 1)); \
		if grep -q "ALL TESTS PASSED\|PASSED" "$$log" 2>/dev/null && ! grep -q "FAILED\|FAIL:" "$$log" 2>/dev/null; then \
			pass=$$((pass + 1)); \
		else \
			fail=$$((fail + 1)); \
			echo "  FAIL: $$(basename $$log .log)"; \
		fi; \
	done; \
	echo "  Total: $$total  Pass: $$pass  Fail: $$fail"

clean:
	rm -rf $(OBJ_DIR) $(LOG_DIR)/$(SUBSYSTEM)_*.log $(LOG_DIR)/tb_*_sim.log $(LOG_DIR)/tb_*_build.log
