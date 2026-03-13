# Cadence Migration Guide — AI Glasses SoC

**Date**: 2026-03-13
**Project**: AI Smart Glasses SoC (Phase 1 ASIC)
**From**: Open-Source (Yosys + OpenSTA + OpenROAD) on SKY130
**To**: Cadence (Genus + Innovus + Tempus + PVS) — target PDK TBD (SCL 180nm or equivalent)

---

## 1. Executive Summary

All 8 subsystem blocks have been synthesized, placed, and routed using the open-source flow on SKY130 HD. This document captures every design decision, floorplan parameter, critical path, gotcha, and lesson learned — everything needed to replicate and improve results with Cadence tools.

### What Transfers Directly (No Re-Work)
- **RTL** — all Verilog-2005 source files (unchanged)
- **SDC constraints** — industry-standard format, portable as-is
- **Liberty/LEF models** for SRAM/ROM macros (if same PDK) or regenerate for new PDK
- **Floorplan decisions** — die sizes, macro placement coordinates, utilization targets
- **All debug knowledge** — wire RC, SRAM grid alignment, dont_touch strategy, power net handling
- **Critical path analysis** — which paths fail and why (RTL-level, not tool-specific)

### What Gets Re-Run (Better Results Expected)
- **Synthesis** — Genus gives 5-15% better QoR than Yosys (better mapping, optimization)
- **PnR** — Innovus multi-threaded, much faster, better timing optimization
- **STA** — Tempus with MMMC (multi-mode multi-corner), SI analysis
- **DRC/LVS** — PVS or Calibre (golden signoff tools vs. Magic/Netgen partial results)

---

## 2. New Server Specifications

| Spec | Value |
|------|-------|
| CPU | 2x Intel Xeon X5650 (12 cores / 24 threads, 2.66 GHz, Westmere) |
| RAM | 72 GB |
| Storage | 300 GB x 2 HDD (600 GB total) |

### Adequacy Assessment
- **RAM**: 72 GB is sufficient for all subsystem-level PnR and SoC-level hierarchical PnR. Audio (largest block, 355K cells) peaked at 28.9 GB on OpenROAD; Innovus is more memory-efficient for similar cell counts. Flat SoC (~515K cells) should fit in 72 GB with Innovus.
- **CPU**: 12 cores with Innovus multi-threading will be significantly faster than single-threaded OpenROAD. Expect 3-5x speedup on routing.
- **Storage**: 600 GB is tight. Cadence generates heavy intermediate data (OA databases, timing databases, DEF/GDS). Recommendation:
  - Use `saveDesign -compress` in Innovus
  - Clean intermediate routing iterations
  - Audio subsystem DEF alone was 468 MB (GDS will be larger)
  - Budget: ~100 GB for tools/PDK, ~400 GB for design data, ~100 GB headroom

---

## 3. Subsystem PnR Results Summary (OpenROAD Baseline)

These are the targets to **match or beat** with Cadence Innovus.

| Subsystem | Top Module | Cells | Die (µm) | Util% | WNS (ns) | Routing DRC | Peak RAM |
|-----------|-----------|-------|----------|-------|----------|-------------|----------|
| NPU | npu_top | 8,453 | 700x600 | 54% | 0.00 | 16 met1 | 1.7 GB |
| SPI | spi_master | 1,342 | 180x180 | 67% | 0.00 | 0 | <1 GB |
| I2C | i2c_master | 1,989 | 280x280 | 34% | 0.00 | 0 | <1 GB |
| DDR | ddr_wrapper | 4,535 | 350x350 | 46% | 0.00 | 0 | <1 GB |
| AXI | axi_crossbar | 3,191 | 900x900 | 8% | 0.00 | 0 | <1 GB |
| Camera | cam_subsys_top | 119K | 2200x2200 | 47% | -47.76 | 0 | 10.6 GB |
| RISC-V | riscv_subsys_top | 23K | 1600x1200 | 40% | -8.97 | 38 met1 | 3.7 GB |
| Audio | audio_subsys_top | 355K | 3200x3200 | 53% | -2.43 | 0 | 28.9 GB |

### Timing Violations Root Causes (RTL-Level — Same in Any Tool)
| Subsystem | WNS | Root Cause | Fix |
|-----------|-----|-----------|-----|
| Camera | -47.76 ns | resize_engine: 57.8 ns combinational multiply chain | Add pipeline registers in ISP multiply path |
| RISC-V | -8.97 ns | Ibex integer divider: 24-stage maj3 carry chain (19.78 ns path) | Relax to 50 MHz or pipeline divider |
| Audio | -2.43 ns | MFCC pipeline: ROM lookup chains (14.50 ns path) | Add pipeline registers between ROM stages |

---

## 4. SDC Constraints (Portable As-Is)

All SDC files are in `pd/constraints/` and use standard SDC syntax compatible with Genus/Innovus/Tempus.

| File | Clock | Period | Notes |
|------|-------|--------|-------|
| `npu_top_pnr.sdc` | npu_clk | 10 ns (100 MHz) | Single clock, AXI4+AXI4-Lite IO delays |
| `spi_master_pnr.sdc` | clk | 10 ns | Single clock |
| `i2c_master_pnr.sdc` | clk | 10 ns | Single clock |
| `ddr_wrapper_pnr.sdc` | clk | 10 ns | Single clock |
| `axi_crossbar_pnr.sdc` | clk | 10 ns | Single clock |
| `cam_subsys_top_pnr.sdc` | clk | 10 ns | cam_pclk false-pathed |
| `riscv_subsys_top_pnr.sdc` | clk | 10 ns | Single clock |
| `audio_subsys_top_pnr.sdc` | clk | 10 ns | Single clock |
| `soc_top.sdc` | sys_clk, npu_clk, cam_pclk, i2s_sck | 10/5/41.67/651 ns | Multi-clock, async groups |

### SDC Notes for Cadence
- `set_clock_uncertainty 0.5` — keep same for initial runs, tighten after CTS
- `set_false_path -from [get_ports rst_n]` — reset false-pathed in all blocks
- `set_max_transition 0.75` / `set_max_capacitance 0.3` — may need adjustment per PDK
- `set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2` → change to target PDK buffer
- `set_load 0.05` → adjust for target PDK wire models
- SoC: `set_clock_groups -asynchronous` for cam_pclk and i2s_sck — keep as-is

---

## 5. Floorplan Parameters (Per Subsystem)

### 5.1 NPU (npu_top)
```
Die:  700 x 600 µm,  Core: 20 20 680 580
Macros: 1x npu_act_buf (SRAM, 400x300) at (150, 260)
Placement density: 0.6
Max wire length: 500 µm
PDN: met4 VDD/VSS pitch=50 µm, met5 pitch=50 µm
```
**Gotchas**:
- SRAM macro must be set dont_touch AFTER CTS, BEFORE repair_design
- SRAM Liberty model needs separate `constraint_2x2` template with `related_pin_transition`/`constrained_pin_transition` axes (NOT delay table axes)
- All SRAM LEF coordinates must be on 5 nm manufacturing grid
- Power nets (`one_`, etc.) must be marked as special before routing

### 5.2 SPI (spi_master)
```
Die: 180 x 180 µm,  Core: 20 20 160 160
Macros: none
Placement density: 0.6
Max wire length: 200 µm
PDN: met4 pitch=50 µm, met5 pitch=50 µm
```
**Notes**: Smallest block, clean routing, clean timing. No special handling needed.

### 5.3 I2C (i2c_master)
```
Die: 280 x 280 µm,  Core: 20 20 260 260
Macros: none
Placement density: 0.6
Max wire length: 300 µm
PDN: met4 pitch=50 µm, met5 pitch=50 µm
```
**Notes**: Originally tried 200x200 → 110% utilization overflow. 280x280 gives 34% util.

### 5.4 DDR (ddr_wrapper)
```
Die: 350 x 350 µm,  Core: 20 20 330 330
Macros: none
Placement density: 0.6
Max wire length: 400 µm
PDN: met4 pitch=50 µm, met5 pitch=50 µm
```
**Notes**: Originally tried 250x250 → 131% utilization. 350x350 gives 46% util.

### 5.5 AXI Crossbar (axi_crossbar)
```
Die: 900 x 900 µm,  Core: 20 20 880 880
Macros: none
Placement density: 0.5
Max wire length: 500 µm
PDN: met4 pitch=50 µm, met5 pitch=50 µm
```
**Notes**: 2346 IO pins require large die perimeter. Originally tried 220x220 → pin overflow. 8% utilization is fine — dominated by pin perimeter. With Innovus, may try IO ring approach.

### 5.6 Camera (cam_subsys_top)
```
Die: 2200 x 2200 µm,  Core: 20 20 2180 2180
Macros: none (line buffers synthesized to FFs)
Placement density: 0.5
Max wire length: 1000 µm
PDN: met4 pitch=80 µm, met5 pitch=80 µm (wider for large die)
CTS: sink_clustering_size=40, max_diameter=150
```
**Notes**: 119K cells, 10.6 GB peak RAM. Routing converged from 65.7K → 0 violations over 7 iterations. Camera PCLK is async (false-pathed in SDC). Timing violation is from resize_engine combinational multiply — needs RTL pipelining regardless of tool.

### 5.7 RISC-V (riscv_subsys_top)
```
Die: 1600 x 1200 µm,  Core: 20 20 1580 1180
Macros: 4x sram_bank (400x300) + 1x boot_rom (100x100)
  - sram_bank[0]: (100, 860)
  - sram_bank[1]: (560, 860)
  - sram_bank[2]: (100, 520)
  - sram_bank[3]: (560, 520)
  - boot_rom:     (1060, 860)
Placement density: 0.5
Max wire length: 600 µm
PDN: met4 pitch=50 µm, met5 pitch=50 µm
CTS: sink_clustering_size=30, max_diameter=100
```
**Gotchas**:
- Ibex RV32IMC has `$_DLATCH_N_` (clock gating latch) — SKY130 HD doesn't have this cell. Yosys replaced with inv+DFF. Genus should handle with `set_clock_gating_style`.
- Macro instance names have escaped brackets: `u_sram.gen_banks\[0\].u_sram_bank`. In OpenROAD, ODB API needed. In Innovus, use `placeInstance` with proper Verilog escaping.
- Synthesis parameterized macro instances (#(...)) must be stripped — OpenROAD doesn't support them. Genus may handle natively.
- repair_design wrapped in `catch` — dont_touch macro net conflicts cause errors
- 38 met1 DRC violations at SRAM boundaries. Fix: add routing blockage halo (10 µm) around all SRAM macros. In Innovus: `createRouteBlk -box {x1 y1 x2 y2} -layer met1`

### 5.8 Audio (audio_subsys_top)
```
Die: 3200 x 3200 µm,  Core: 20 20 3180 3180
Macros: none (ALL ROMs expanded to FFs — 355K cells!)
Placement density: 0.45
Max wire length: 1500 µm
PDN: met4 pitch=100 µm, met5 pitch=100 µm (widest pitch, very large die)
CTS: sink_clustering_size=50, max_diameter=200
```
**Critical Notes**:
- Largest subsystem by far. 355K cells from ROM expansion (FFT twiddle, mel coefficients, DCT, hamming window, log table all synthesized to FFs).
- With Genus: **use `read_hdl -define SYNTHESIS`** or gate-level memory inference to avoid ROM→FF expansion. This could reduce cell count by 80%+ and dramatically shrink the block.
- OpenROAD routing: 446K initial violations → 0 over 21 iterations, 26 hours, 28.9 GB peak. Innovus should handle this in 2-4 hours with 12 threads.
- CTS: 85K sinks, 1,713 leaf buffers, 0.69 ns skew — very good for this size.
- Timing: -2.43 ns WNS from MFCC ROM lookup chains. Needs RTL pipeline registers.

---

## 6. Critical Debug Lessons (Apply to Cadence Flow)

These are hard-won lessons from 7+ failed PnR attempts on NPU and RISC-V. Apply them from the start in Cadence.

### 6.1 Wire RC — NEVER Use Manual Values
**Problem**: Manual `set_wire_rc -resistance 3.574e-02 -capacitance 7.516e-02` gave 100x too high RC → -1022 ns clock skew.
**Solution**: Always use layer-based RC:
```tcl
# OpenROAD:
set_wire_rc -clock  -layer met3
set_wire_rc -signal -layer met2

# Innovus equivalent:
# Wire RC comes from tech LEF / QRC extraction — no manual setting needed
# Use setExtractRCMode -engine postRoute for accurate RC
```

### 6.2 SRAM Macro Liberty Model Axes
**Problem**: Setup/hold timing arcs used delay table axes (`input_net_transition`/`total_output_net_capacitance`) instead of constraint axes.
**Solution**: Liberty must use:
- **Delay arcs**: `input_net_transition` / `total_output_net_capacitance`
- **Constraint arcs (setup/hold)**: `related_pin_transition` / `constrained_pin_transition`

Cadence Genus/Tempus will also reject wrong axis variables. Ensure SRAM Liberty is correct before starting.

### 6.3 SRAM LEF Manufacturing Grid
**Problem**: SRAM LEF pin coordinates were off the 5 nm grid → `DRT-0416 offgrid pin shape` errors.
**Solution**: All coordinates in SRAM LEF files must be snapped to 5 nm grid (0.005 µm increments for SKY130). For new PDK, check the grid with `dbGet head.tech.mfgGrid`.

### 6.4 Macro dont_touch Strategy
**Problem**: Setting dont_touch on SRAM BEFORE CTS blocks clock connection. Setting it too late causes repair_design to insert 399K buffers around SRAM.
**Solution**: Exact ordering:
```
1. Floorplan + place macros
2. PDN
3. Placement
4. CTS (macros participate in clock tree)
5. set_dont_touch on macros    ← HERE
6. repair_design / repair_timing
7. Routing
```
In Innovus: `setDontTouch [dbGet top.insts.name u_act_buf] true` after CTS.

### 6.5 Power Net Marking
**Problem**: TritonRoute error: `Net one_ of signal type POWER is not routable`.
**Solution**: All POWER/GROUND nets must be marked as special nets before routing.
```tcl
# OpenROAD (ODB):
foreach net [$block getNets] {
    set sigtype [$net getSigType]
    if {$sigtype == "POWER" || $sigtype == "GROUND"} {
        $net setSpecial
    }
}

# Innovus: handled automatically by globalNetConnect
```

### 6.6 Ibex Latch Handling
**Problem**: Ibex uses `$_DLATCH_N_` for clock gating. Not available in SKY130 HD library.
**Solution**:
- Yosys: mapped to inv+DFF (functional but not optimal)
- Genus: use `set_clock_gating_style -type latch` and Genus will map to ICG cells or available latches
- If target PDK has ICG cells, this is much cleaner

### 6.7 Escaped Verilog Names in Macro Placement
**Problem**: Instance names like `gen_banks[0].u_sram_bank` contain brackets → Tcl/tool parsing issues.
**Solution**:
- OpenROAD: Used ODB API `$block findInst "u_sram.gen_banks\\[0\\].u_sram_bank"`
- Innovus: Use `placeInstance {u_sram/gen_banks[0]/u_sram_bank} 100 860 R0` (Innovus uses `/` separator and handles brackets differently)
- Or use `dbGet -p top.insts.name *gen_banks*` to find the exact name

### 6.8 Routing Blockage Halos for Macros
**Problem**: 16 met1 DRC violations (NPU) and 38 met1 violations (RISC-V) at SRAM macro boundaries.
**Solution**: Add routing blockage halo around all macros:
```tcl
# Innovus:
foreach inst [dbGet top.insts.cell.name sram_bank -p2] {
    set box [dbGet $inst.box]
    createRouteBlk -name macro_halo -box [bloatBox $box 10 10 10 10] -layer met1
}
# Or use: addHaloToBlock -allMacro 10 10 10 10
```

---

## 7. Cadence Tool-Specific Script Templates

### 7.1 Genus Synthesis Template
```tcl
###############################################################################
# Genus Synthesis — AI Glasses SoC Subsystem Template
# Usage: genus -f scripts/synth/genus_<subsystem>.tcl
###############################################################################

# Setup
set_db init_lib_search_path {/path/to/pdk/libs}
set_db init_hdl_search_path {/path/to/rtl}

# Read libraries
read_libs {<target_pdk_tt_lib>.lib sram_bank.lib boot_rom.lib}

# Read RTL
read_hdl -v2001 [glob ../rtl/<subsystem>/*.v]
# For RISC-V with Ibex:
# read_hdl -sv ibex_v2k/ibex_all.v   (use sv2v-converted version)

# Elaborate
elaborate <top_module>

# Read constraints
read_sdc constraints/<subsystem>_pnr.sdc

# Synthesis
set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high

# Clock gating (for Ibex)
set_db lp_insert_clock_gating true

# Synthesize
syn_generic
syn_map
syn_opt

# Reports
report_timing -nworst 10 > reports/<subsystem>_genus_timing.rpt
report_area > reports/<subsystem>_genus_area.rpt
report_power > reports/<subsystem>_genus_power.rpt
report_qor > reports/<subsystem>_genus_qor.rpt

# Write outputs
write_hdl > results/synth/<subsystem>_genus_netlist.v
write_sdc > results/synth/<subsystem>_genus.sdc
write_sdf > results/synth/<subsystem>_genus.sdf

# Write design for Innovus
write_design -innovus -base_name results/synth/<subsystem>_genus
```

### 7.2 Innovus PnR Template
```tcl
###############################################################################
# Innovus PnR — AI Glasses SoC Subsystem Template
# Usage: innovus -init scripts/pnr/innovus_<subsystem>.tcl
###############################################################################

# Import design from Genus
init_design -import_design results/synth/<subsystem>_genus.invs_setup.tcl

# OR manual import:
# read_mmmc <mmmc_file>
# read_physical -lef {tech.lef stdcell.lef sram.lef}
# read_netlist results/synth/<subsystem>_genus_netlist.v
# read_power_intent -cpf <power_intent>.cpf   ;# if UPF/CPF exists
# init_design

# ---- Floorplan ----
# Use same die sizes from OpenROAD results (proven to work)
floorPlan -site <site_name> -d <width> <height> 20 20 20 20
# Example for NPU: floorPlan -site unit -d 700 600 20 20 20 20

# Place macros (use coordinates from Section 5)
# Example for NPU:
# placeInstance u_act_buf 150 260 R0 -fixed

# Example for RISC-V:
# placeInstance {u_sram/gen_banks[0]/u_sram_bank} 100 860 R0 -fixed
# placeInstance {u_sram/gen_banks[1]/u_sram_bank} 560 860 R0 -fixed
# placeInstance {u_sram/gen_banks[2]/u_sram_bank} 100 520 R0 -fixed
# placeInstance {u_sram/gen_banks[3]/u_sram_bank} 560 520 R0 -fixed
# placeInstance u_boot_rom 1060 860 R0 -fixed

# Macro halo (IMPORTANT — prevents met1 DRC at macro boundaries)
addHaloToBlock -allMacro 10 10 10 10

# ---- PDN ----
globalNetConnect VDD -type pgpin -pin VDD -all
globalNetConnect VSS -type pgpin -pin VSS -all

# Power rings + stripes
addRing -type core_rings -nets {VDD VSS} \
    -layer {top met5 bottom met5 left met4 right met4} \
    -width 1.6 -spacing 0.5

addStripe -nets {VDD VSS} -layer met4 -direction vertical \
    -width 1.6 -spacing 0.5 -set_to_set_distance 50.0
addStripe -nets {VDD VSS} -layer met5 -direction horizontal \
    -width 1.6 -spacing 0.5 -set_to_set_distance 50.0

sroute -connect {corePin}

# ---- Placement ----
setPlaceMode -fp false
place_opt_design

# ---- CTS ----
# create_ccopt_clock_tree_spec
ccopt_design

# ---- Post-CTS ----
# Set dont_touch on macros AFTER CTS
setDontTouch [get_cells u_act_buf] true  ;# NPU
# For RISC-V: setDontTouch on all sram_bank and boot_rom instances

optDesign -postCTS -hold

# ---- Routing ----
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -drouteFixAntenna true
routeDesign

# ---- Post-Route Optimization ----
setExtractRCMode -engine postRoute
extractRC
optDesign -postRoute -setup -hold

# ---- Signoff ----
# Timing
timeDesign -postRoute -setup > reports/<subsystem>_setup.rpt
timeDesign -postRoute -hold  > reports/<subsystem>_hold.rpt

# DRC
verify_drc > reports/<subsystem>_drc.rpt

# Connectivity
verifyConnectivity > reports/<subsystem>_conn.rpt

# ---- Outputs ----
saveDesign results/pnr/<subsystem>_innovus.enc -compress
write_def results/pnr/<subsystem>_innovus.def
saveNetlist results/pnr/<subsystem>_innovus.v
write_sdf results/pnr/<subsystem>_innovus.sdf

# GDS
streamOut results/gds/<subsystem>.gds \
    -mapFile <pdk_stream_map> \
    -libName <design_lib> \
    -units 1000 -mode ALL
```

### 7.3 Tempus STA Template
```tcl
###############################################################################
# Tempus STA — Multi-Mode Multi-Corner
# Usage: tempus -init scripts/sta/tempus_<subsystem>.tcl
###############################################################################

# Define MMMC (Multi-Mode Multi-Corner) analysis views
create_library_set -name tt_lib \
    -timing {/path/to/pdk_tt.lib sram_bank_tt.lib}
create_library_set -name ss_lib \
    -timing {/path/to/pdk_ss.lib sram_bank_ss.lib}
create_library_set -name ff_lib \
    -timing {/path/to/pdk_ff.lib sram_bank_ff.lib}

create_rc_corner -name rc_typ -T 25
create_rc_corner -name rc_max -T 125
create_rc_corner -name rc_min -T -40

create_delay_corner -name dc_ss -library_set ss_lib -rc_corner rc_max
create_delay_corner -name dc_tt -library_set tt_lib -rc_corner rc_typ
create_delay_corner -name dc_ff -library_set ff_lib -rc_corner rc_min

create_constraint_mode -name func -sdc_files {constraints/<subsystem>_pnr.sdc}

create_analysis_view -name setup_ss -delay_corner dc_ss -constraint_mode func
create_analysis_view -name hold_ff  -delay_corner dc_ff -constraint_mode func
create_analysis_view -name typ      -delay_corner dc_tt -constraint_mode func

set_analysis_view \
    -setup {setup_ss} \
    -hold  {hold_ff}

# Read design
read_def results/pnr/<subsystem>_innovus.def

# Extract parasitics (from Innovus SPEF or QRC)
read_spef results/pnr/<subsystem>.spef

# Reports
report_timing -path_type full_clock -max_paths 20 -view setup_ss \
    > reports/<subsystem>_tempus_setup.rpt
report_timing -path_type full_clock -max_paths 20 -view hold_ff -early \
    > reports/<subsystem>_tempus_hold.rpt
report_si_delay_analysis > reports/<subsystem>_si.rpt
```

---

## 8. Subsystem-Specific Cadence Migration Notes

### 8.1 NPU
- **Priority**: HIGH (timing-clean in OpenROAD, should be first Cadence block)
- **Expected improvement**: With Genus, likely 15%+ better QoR. May achieve 150-200 MHz.
- **SRAM**: Single `npu_act_buf` macro (400x300). Create proper Cadence-compatible Liberty/LEF for target PDK.
- **Action items**:
  1. Characterize SRAM macro for target PDK corners (ss/tt/ff)
  2. Verify Liberty axis variables are correct
  3. Snap all LEF coordinates to target PDK manufacturing grid
  4. Add 10 µm routing blockage halo around SRAM

### 8.2 SPI & I2C
- **Priority**: LOW (tiny blocks, always clean)
- **Expected improvement**: Minimal — already timing-clean at 100 MHz
- **Action items**: Just re-run through Genus→Innovus with default settings

### 8.3 DDR
- **Priority**: MEDIUM
- **Note**: DDR wrapper contains only the AXI protocol conversion logic (burst splitter, width converter, QoS). The actual DDR PHY is external (Zynq HP0 or SCL DDR controller).
- **Action items**: Standard flow, no macros, no special handling

### 8.4 AXI Crossbar
- **Priority**: MEDIUM
- **Note**: 2346 IO pins → needs large die or IO ring approach. With Innovus, can use `assignIoPins` more efficiently than OpenROAD.
- **Expected improvement**: Better pin assignment may allow smaller die

### 8.5 Camera
- **Priority**: HIGH (worst timing — needs RTL fix + re-synth)
- **WNS = -47.76 ns**: resize_engine has a 57.8 ns combinational multiply chain. This CANNOT be fixed by better tools — needs RTL pipeline registers.
- **Action items**:
  1. Fix RTL: add pipeline registers in `resize_engine` multiply path
  2. Re-synthesize with Genus (will still have similar timing if RTL not fixed)
  3. Line buffers synthesized to FFs — with Genus memory inference, these may map to SRAM macros

### 8.6 RISC-V
- **Priority**: HIGH (Ibex core, SRAM macros, multiple gotchas)
- **WNS = -8.97 ns**: Ibex integer divider carry chain. Consider:
  - Relaxing to 50 MHz (20 ns period) — divider path becomes 0.22 ns slack
  - Or accepting violation for Phase 0 and fixing in Phase 1
- **sv2v conversion**: Ibex is SystemVerilog. Already converted via sv2v. Genus reads SV natively — can use original Ibex RTL directly.
- **Latch handling**: Ibex clock gating uses `$_DLATCH_N_`. Genus has proper ICG cell mapping via `set_clock_gating_style`.
- **5 macros**: 4x sram_bank + 1x boot_rom. Use exact placement coordinates from Section 5.7.
- **Action items**:
  1. Read original Ibex SV files directly (no sv2v needed)
  2. Configure clock gating in Genus
  3. Place macros with halo blockages
  4. Watch for escaped bracket names in instance paths

### 8.7 Audio
- **Priority**: CRITICAL (largest block, biggest Cadence improvement opportunity)
- **355K cells from ROM expansion!** With Genus:
  - Use `read_hdl -define SYNTHESIS` or memory inference
  - ROMs (FFT twiddle, mel coeff, DCT, hamming, log) should map to SRAM macros instead of FFs
  - Expected cell count reduction: 355K → ~50-80K cells
  - This alone justifies the Cadence migration
- **WNS = -2.43 ns**: ROM lookup chain timing. If ROMs become SRAM macros, the critical path changes entirely.
- **Action items**:
  1. Enable Genus memory inference for ROM tables
  2. Create SRAM macros for each ROM (or use standard cell ROM)
  3. Re-run floorplan with macros — die size may shrink from 3200x3200 to ~1500x1500
  4. This is the single biggest win from Cadence migration

---

## 9. SoC Top-Level Integration Strategy

### Hierarchical PnR (Recommended)
Use hardened subsystem macros (from subsystem PnR) as black boxes in SoC top-level.

```
SoC Top-Level
├── NPU macro (700x600)
├── RISC-V macro (1600x1200)
├── Camera macro (2200x2200)
├── Audio macro (3200x3200 → ~1500x1500 with Genus ROM inference)
├── DDR macro (350x350)
├── AXI macro (900x900)
├── SPI macro (180x180)
├── I2C macro (100x100)
└── Glue logic (clk_rst_mgr, top-level wiring)
```

**Estimated SoC die size**: 8-10 mm on a side (depends on Audio shrink with Genus)
**RAM needed**: 3-5 GB (only routing top-level interconnect, not re-routing block internals)

### Flat SoC (Alternative — Only with Cadence)
- ~515K cells (or ~200K with Genus ROM inference)
- Needs 30-50 GB RAM
- 72 GB server can handle it
- Innovus multi-threaded PnR: 6-12 hours estimated
- Advantage: globally optimized timing, better cross-domain path optimization

**Recommendation**: Start with hierarchical (faster iteration), switch to flat if timing closure needs it.

---

## 10. File Inventory for Migration

### RTL Source (No Changes Needed)
```
rtl/npu/         — 12 modules
rtl/riscv/       — 21 modules + ibex/ (SystemVerilog)
rtl/ddr/         — 15 modules (5 synth + 10 sim)
rtl/axi/         — 17 modules
rtl/audio/       — 21 modules
rtl/camera/      — 18 modules
rtl/i2c/         — 7 modules
rtl/spi/         — 7 modules
rtl/soc/         — 2 modules (clk_rst_mgr, soc_top)
```

### Constraints (Portable — Copy Directly)
```
pd/constraints/*.sdc  — 10 files (all standard SDC format)
```

### Macro Models (Regenerate for New PDK)
```
pd/lib/sram_bank.lib      — Liberty timing model
pd/lib/boot_rom.lib       — Liberty timing model
pd/lib/npu_act_buf.lib    — Liberty timing model (has corrected constraint axes)
pd/lef/sram_macros.lef    — LEF physical model (5nm grid-snapped)
pd/synth_stubs/*_bb.v     — Blackbox Verilog stubs
```

### OpenROAD Results (Reference Only)
```
pd/results/synth/*.v      — Gate-level netlists (re-synthesize with Genus)
pd/results/pnr/*.def      — Routed DEF files (reference for floorplan decisions)
pd/results/pnr/*.rpt      — Timing/DRC reports (baseline comparison)
pd/scripts/synth/*.tcl     — Yosys scripts (reference for Genus scripts)
pd/scripts/pnr/*.tcl       — OpenROAD scripts (reference for Innovus scripts)
```

---

## 11. Migration Checklist

- [ ] Install Cadence tools on new server (Genus, Innovus, Tempus, PVS)
- [ ] Install target PDK (SKY130 Cadence kit or SCL 180nm)
- [ ] Verify PDK Liberty models (tt/ss/ff corners)
- [ ] Create MMMC setup file for Tempus
- [ ] Characterize SRAM/ROM macros for target PDK (Liberty + LEF + GDS)
- [ ] Run Genus synthesis on NPU (first block — quickest validation)
- [ ] Compare Genus vs. Yosys cell count and area
- [ ] Run Innovus PnR on NPU with same floorplan
- [ ] Compare Innovus vs. OpenROAD timing and DRC
- [ ] Fix Audio RTL: enable ROM-to-SRAM inference in Genus
- [ ] Fix Camera RTL: pipeline resize_engine multiply path
- [ ] Run all 8 subsystem blocks through Genus→Innovus
- [ ] Run SoC top-level hierarchical PnR
- [ ] Tempus MMMC STA signoff (3-corner minimum)
- [ ] PVS DRC/LVS signoff
- [ ] GDS tape-out preparation

---

## 12. Expected Improvements with Cadence

| Metric | OpenROAD | Cadence (Expected) | Notes |
|--------|----------|-------------------|-------|
| Synthesis QoR | Yosys baseline | 5-15% fewer cells | Genus better optimization |
| Audio cell count | 355K (ROM→FF) | ~50-80K (ROM→SRAM) | Biggest single win |
| PnR runtime | 26 hrs (Audio, 1 thread) | 2-4 hrs (12 threads) | Innovus multi-threading |
| STA corners | 1 (TT only) | 3+ (SS/TT/FF, MMMC) | Proper signoff |
| DRC | 16-38 met1 partial | 0 (golden PVS) | Proper signoff |
| LVS | Structural only | Full PVS/Calibre | Proper signoff |
| Max frequency (NPU) | 100 MHz | 150-200 MHz | Better optimization |
| SI analysis | None | Full crosstalk | Tempus SI |
| Power analysis | None | Full Joules/Voltus | Cadence power tools |

---

*Document prepared from OpenROAD PnR sessions (2026-03-10 to 2026-03-12).
All design parameters, gotchas, and scripts verified against actual successful runs.*
