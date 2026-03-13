#!/bin/bash
###############################################################################
# Netgen LVS Script — NPU Subsystem
# Usage:  bash scripts/pv/lvs_npu.sh
# Run from: pd/ directory
###############################################################################

set -e

PDK_ROOT="${PDK_ROOT:?Set PDK_ROOT environment variable}"
RESULTS_DIR="results/pv"
NETLIST="results/synth/npu_top_netlist.v"
GDS="results/pv/npu_top.gds"
LVS_REPORT="${RESULTS_DIR}/npu_lvs_report.txt"

mkdir -p "$RESULTS_DIR"

echo "============================================"
echo " Running LVS: Netgen"
echo " Netlist: $NETLIST"
echo " GDS:     $GDS"
echo "============================================"

# Extract SPICE from Magic GDS
magic -dnull -noconsole -T ${PDK_ROOT}/sky130A/libs.tech/magic/sky130A.tech <<EOF
gds read ${GDS}
load npu_top
extract all
ext2spice lvs
ext2spice -o ${RESULTS_DIR}/npu_top_extracted.spice
quit -noprompt
EOF

echo "Extracted SPICE: ${RESULTS_DIR}/npu_top_extracted.spice"

# Run Netgen LVS comparison
netgen -batch lvs \
    "${RESULTS_DIR}/npu_top_extracted.spice npu_top" \
    "${NETLIST} npu_top" \
    ${PDK_ROOT}/sky130A/libs.tech/netgen/sky130A_setup.tcl \
    ${LVS_REPORT}

echo "============================================"
echo " LVS Report: ${LVS_REPORT}"
echo "============================================"

# Check result
if grep -q "Final result: Circuits match" "$LVS_REPORT"; then
    echo "LVS PASSED: Circuits match!"
    exit 0
else
    echo "LVS FAILED: Circuits do not match"
    echo "Check ${LVS_REPORT} for details"
    exit 1
fi
