###############################################################################
# Makefile — AI Glasses SoC Physical Design Flow
# Target PDK: SKY130 HD (open-source)
# Tools: Yosys (synth), OpenSTA (timing), OpenROAD (PnR), Magic (DRC), Netgen (LVS)
#
# Prerequisites:
#   - PDK_ROOT env var pointing to SKY130 PDK installation
#   - Yosys, OpenSTA (sta), OpenROAD (openroad), Magic, Netgen installed
#
# Usage:
#   make synth_npu       # Synthesize NPU subsystem
#   make sta_npu         # Run STA on NPU (3 corners)
#   make pnr_npu         # Place and route NPU
#   make drc_npu         # DRC check on NPU
#   make lvs_npu         # LVS check on NPU
#   make npu             # Full NPU flow (synth → STA → PnR → DRC → LVS)
#   make synth_soc       # Synthesize full SoC
#   make check_tools     # Verify all tools are installed
#   make check_pdk       # Verify PDK is available
#   make clean           # Remove all outputs
###############################################################################

.PHONY: all npu soc synth_npu sta_npu pnr_npu drc_npu lvs_npu \
        synth_soc sta_soc check_tools check_pdk clean help

# ==============================================================
# Environment checks
# ==============================================================
PDK_ROOT ?= /home/anirudh/.volare/volare/sky130/versions/78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc
export PDK_ROOT

# ==============================================================
# Directories
# ==============================================================
RESULTS     := results
SYNTH_DIR   := $(RESULTS)/synth
STA_DIR     := $(RESULTS)/sta
PNR_DIR     := $(RESULTS)/pnr
PV_DIR      := $(RESULTS)/pv
LOG_DIR     := logs

# ==============================================================
# Output files
# ==============================================================
NPU_NETLIST := $(SYNTH_DIR)/npu_top_netlist.v
SOC_NETLIST := $(SYNTH_DIR)/soc_top_netlist.v
NPU_DEF     := $(PNR_DIR)/npu_top_routed.def

# ==============================================================
# Default target
# ==============================================================
all: npu

help:
	@echo "Available targets:"
	@echo "  make check_tools   - Verify PD tools are installed"
	@echo "  make check_pdk     - Verify SKY130 PDK is accessible"
	@echo "  make synth_npu     - Yosys synthesis (NPU subsystem)"
	@echo "  make sta_npu       - OpenSTA multi-corner analysis (NPU)"
	@echo "  make pnr_npu       - OpenROAD place & route (NPU)"
	@echo "  make drc_npu       - Magic DRC check (NPU)"
	@echo "  make lvs_npu       - Netgen LVS check (NPU)"
	@echo "  make npu           - Full NPU flow"
	@echo "  make synth_soc     - Yosys synthesis (full SoC)"
	@echo "  make clean         - Remove all outputs"

# ==============================================================
# Tool checks
# ==============================================================
check_tools:
	@echo "Checking PD tools..."
	@which yosys    >/dev/null 2>&1 && echo "  [OK] yosys:    $$(yosys --version 2>/dev/null | head -1)"    || echo "  [MISSING] yosys"
	@which sta      >/dev/null 2>&1 && echo "  [OK] OpenSTA:  $$(sta -version 2>/dev/null | head -1)"      || echo "  [MISSING] sta (OpenSTA)"
	@which openroad >/dev/null 2>&1 && echo "  [OK] openroad: $$(openroad -version 2>/dev/null | head -1)" || echo "  [MISSING] openroad"
	@which magic    >/dev/null 2>&1 && echo "  [OK] magic:    $$(magic --version 2>/dev/null | head -1)"   || echo "  [MISSING] magic"
	@which netgen   >/dev/null 2>&1 && echo "  [OK] netgen:   available"                                    || echo "  [MISSING] netgen"
	@which klayout  >/dev/null 2>&1 && echo "  [OK] klayout:  available"                                    || echo "  [OPTIONAL] klayout (viewer)"

check_pdk:
	@echo "Checking SKY130 PDK..."
	@test -n "$(PDK_ROOT)" || (echo "  [ERROR] PDK_ROOT not set" && exit 1)
	@test -f "$(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" \
		&& echo "  [OK] TT liberty" || echo "  [MISSING] TT liberty"
	@test -f "$(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_100C_1v60.lib" \
		&& echo "  [OK] SS liberty" || echo "  [MISSING] SS liberty"
	@test -f "$(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ff_n40C_1v95.lib" \
		&& echo "  [OK] FF liberty" || echo "  [MISSING] FF liberty"
	@test -f "$(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef" \
		&& echo "  [OK] Cell LEF" || echo "  [MISSING] Cell LEF"

# ==============================================================
# NPU Flow
# ==============================================================
npu: synth_npu sta_npu pnr_npu drc_npu lvs_npu
	@echo "============================================"
	@echo " NPU Physical Design Flow Complete"
	@echo "============================================"

synth_npu: $(NPU_NETLIST)
$(NPU_NETLIST):
	@mkdir -p $(SYNTH_DIR) $(LOG_DIR)
	@echo "[SYNTH] NPU subsystem → $(NPU_NETLIST)"
	yosys -c scripts/synth/synth_npu.tcl 2>&1 | tee $(LOG_DIR)/synth_npu.log
	@echo "[SYNTH] Done. Check $(SYNTH_DIR)/npu_top_area.rpt"

sta_npu: $(NPU_NETLIST)
	@mkdir -p $(STA_DIR) $(LOG_DIR)
	@echo "[STA] NPU 3-corner analysis"
	sta scripts/sta/run_sta_npu.tcl 2>&1 | tee $(LOG_DIR)/sta_npu.log
	@echo "[STA] Done. Reports in $(STA_DIR)/npu_*.rpt"

pnr_npu: $(NPU_NETLIST)
	@mkdir -p $(PNR_DIR) $(LOG_DIR)
	@echo "[PNR] NPU place & route"
	openroad -exit scripts/pnr/pnr_npu.tcl 2>&1 | tee $(LOG_DIR)/pnr_npu.log
	@echo "[PNR] Done. DEF: $(NPU_DEF)"

drc_npu: $(NPU_DEF)
	@mkdir -p $(PV_DIR) $(LOG_DIR)
	@echo "[DRC] NPU layout check"
	magic -dnull -noconsole -T $(PDK_ROOT)/sky130A/libs.tech/magic/sky130A.tech \
		< scripts/pv/drc_npu.tcl 2>&1 | tee $(LOG_DIR)/drc_npu.log
	@echo "[DRC] Done. Report: $(PV_DIR)/npu_drc_report.txt"

lvs_npu: $(NPU_DEF)
	@mkdir -p $(PV_DIR) $(LOG_DIR)
	@echo "[LVS] NPU layout vs schematic"
	bash scripts/pv/lvs_npu.sh 2>&1 | tee $(LOG_DIR)/lvs_npu.log

# ==============================================================
# Full SoC Flow
# ==============================================================
synth_soc: $(SOC_NETLIST)
$(SOC_NETLIST):
	@mkdir -p $(SYNTH_DIR) $(LOG_DIR)
	@echo "[SYNTH] Full SoC → $(SOC_NETLIST)"
	yosys -c scripts/synth/synth_soc.tcl 2>&1 | tee $(LOG_DIR)/synth_soc.log
	@echo "[SYNTH] Done. Check $(SYNTH_DIR)/soc_top_area.rpt"

sta_soc: $(SOC_NETLIST)
	@mkdir -p $(STA_DIR) $(LOG_DIR)
	@echo "[STA] SoC 3-corner analysis"
	sta scripts/sta/run_sta_soc.tcl 2>&1 | tee $(LOG_DIR)/sta_soc.log
	@echo "[STA] Done. Reports in $(STA_DIR)/soc_*.rpt"

# ==============================================================
# Clean
# ==============================================================
clean:
	rm -rf $(RESULTS) $(LOG_DIR)
	@echo "Cleaned all PD outputs"

clean_synth:
	rm -rf $(SYNTH_DIR)
	@echo "Cleaned synthesis outputs"
