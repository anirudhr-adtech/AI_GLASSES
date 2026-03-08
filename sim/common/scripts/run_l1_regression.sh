#!/bin/bash
# L1 Regression: Build + Run all 120 TBs with Verilator
# Usage: bash run_l1_regression.sh [subsystem]
# If subsystem is given, only run that one.

TOP_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
SIM_MAIN="$TOP_DIR/sim/common/sim_main.cpp"
OBJ_BASE="$TOP_DIR/sim/obj_dir"
LOG_DIR="$TOP_DIR/sim/logs"
VERILATOR="/usr/local/bin/verilator"
VFLAGS="--cc --exe --build -j 4 --trace --timing -Wno-lint"

mkdir -p "$OBJ_BASE" "$LOG_DIR"

# Counters
total=0; pass=0; fail=0; build_fail=0

# Determine subsystems to run
if [ -n "$1" ]; then
    SUBSYSTEMS="$1"
else
    SUBSYSTEMS="npu riscv ddr axi audio camera i2c spi soc"
fi

for subsys in $SUBSYSTEMS; do
    RTL_DIR="$TOP_DIR/rtl/$subsys"
    TB_DIR="$RTL_DIR/tb"

    # Build -y flags: include own RTL dir + common dirs needed
    YDIRS="-y $RTL_DIR"

    # Some subsystems need cross-references
    case $subsys in
        riscv)
            YDIRS="$YDIRS -y $TOP_DIR/rtl/riscv"
            ;;
        soc)
            for d in npu riscv ddr axi audio camera i2c spi soc; do
                YDIRS="$YDIRS -y $TOP_DIR/rtl/$d"
            done
            ;;
    esac

    # Find all TBs
    for tb_file in "$TB_DIR"/tb_*.v; do
        [ -f "$tb_file" ] || continue
        tb_name="$(basename "$tb_file" .v)"
        total=$((total + 1))

        obj="$OBJ_BASE/$tb_name"
        build_log="$LOG_DIR/${tb_name}_build.log"
        sim_log="$LOG_DIR/${tb_name}_sim.log"

        # Build
        $VERILATOR $VFLAGS $YDIRS \
            --top-module "$tb_name" \
            --Mdir "$obj" \
            "$tb_file" "$SIM_MAIN" \
            -CFLAGS "-DTOP_HEADER=\\\"V${tb_name}.h\\\" -DTOP_CLASS=V${tb_name}" \
            > "$build_log" 2>&1

        if [ $? -ne 0 ]; then
            build_fail=$((build_fail + 1))
            echo "BUILD_FAIL [$subsys] $tb_name"
            continue
        fi

        # Run (timeout 30s)
        timeout 30 "$obj/V${tb_name}" > "$sim_log" 2>&1
        rc=$?

        # Check results
        if [ $rc -eq 124 ]; then
            fail=$((fail + 1))
            echo "TIMEOUT    [$subsys] $tb_name"
        elif grep -qiE "ALL TESTS PASSED|ALL.*PASSED|SIMULATION PASSED|>>> ALL TESTS PASSED <<<|RESULT: ALL TESTS PASSED" "$sim_log" 2>/dev/null; then
            pass=$((pass + 1))
            echo "PASS       [$subsys] $tb_name"
        elif grep -qiE "[0-9]+ PASSED, 0 FAILED|PASSED: [0-9]+.*FAILED: 0" "$sim_log" 2>/dev/null; then
            pass=$((pass + 1))
            echo "PASS       [$subsys] $tb_name"
        else
            fail=$((fail + 1))
            echo "FAIL       [$subsys] $tb_name"
            # Show last few lines for diagnosis
            tail -5 "$sim_log" | sed 's/^/  > /'
        fi
    done
done

echo ""
echo "============================================"
echo "L1 REGRESSION SUMMARY"
echo "============================================"
echo "Total:      $total"
echo "Pass:       $pass"
echo "Fail:       $fail"
echo "Build Fail: $build_fail"
echo "============================================"
