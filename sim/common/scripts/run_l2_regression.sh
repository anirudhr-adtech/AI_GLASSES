#!/bin/bash
# L2 Regression: Build + Run all 9 L2 integration TBs with Verilator
# Usage: bash run_l2_regression.sh [subsystem]
# If subsystem is given, only run that one (e.g., "npu", "audio").

TOP_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
SIM_MAIN="$TOP_DIR/sim/common/sim_main.cpp"
OBJ_BASE="$TOP_DIR/sim/obj_dir"
LOG_DIR="$TOP_DIR/sim/logs"
VERILATOR="/usr/local/bin/verilator"
VFLAGS="--cc --exe --build -j 4 --trace --timing -Wno-lint"

mkdir -p "$OBJ_BASE" "$LOG_DIR"

# Counters
total=0; pass=0; fail=0; build_fail=0

# L2 TB name suffix
L2_SUFFIX="_integ"

# Determine subsystems to run
if [ -n "$1" ]; then
    SUBSYSTEMS="$1"
else
    SUBSYSTEMS="npu audio camera riscv ddr axi i2c spi soc"
fi

# Simulation timeout per TB (seconds) — L2 tests may take longer than L1
SIM_TIMEOUT=120

for subsys in $SUBSYSTEMS; do
    RTL_DIR="$TOP_DIR/rtl/$subsys"
    TB_DIR="$RTL_DIR/tb"
    tb_file="$TB_DIR/tb_${subsys}${L2_SUFFIX}.v"

    # Check TB exists
    if [ ! -f "$tb_file" ]; then
        echo "SKIP       [$subsys] tb_${subsys}${L2_SUFFIX} (file not found)"
        continue
    fi

    tb_name="tb_${subsys}${L2_SUFFIX}"
    total=$((total + 1))

    # Build -y flags: include own RTL dir + sim/common for BFMs
    YDIRS="-y $RTL_DIR -y $TOP_DIR/sim/common"

    # Add cross-subsystem dependencies per subsystem
    case $subsys in
        npu)
            YDIRS="$YDIRS -y $TOP_DIR/rtl/ddr"
            ;;
        audio)
            YDIRS="$YDIRS -y $TOP_DIR/rtl/ddr"
            ;;
        camera)
            YDIRS="$YDIRS -y $TOP_DIR/rtl/ddr"
            ;;
        ddr)
            ;;
        axi)
            YDIRS="$YDIRS -y $TOP_DIR/rtl/riscv"
            ;;
        riscv)
            ;;
        soc)
            for d in npu riscv ddr axi audio camera i2c spi; do
                YDIRS="$YDIRS -y $TOP_DIR/rtl/$d"
            done
            ;;
    esac

    obj="$OBJ_BASE/$tb_name"
    build_log="$LOG_DIR/${tb_name}_build.log"
    sim_log="$LOG_DIR/${tb_name}_sim.log"

    echo -n "Building   [$subsys] $tb_name ... "

    # Build
    $VERILATOR $VFLAGS $YDIRS \
        --top-module "$tb_name" \
        --Mdir "$obj" \
        "$tb_file" "$SIM_MAIN" \
        -CFLAGS "-DTOP_HEADER=\\\"V${tb_name}.h\\\" -DTOP_CLASS=V${tb_name}" \
        > "$build_log" 2>&1

    if [ $? -ne 0 ]; then
        build_fail=$((build_fail + 1))
        echo "BUILD_FAIL"
        tail -5 "$build_log" | sed 's/^/  > /'
        continue
    fi
    echo "OK"

    # Run
    echo -n "Running    [$subsys] $tb_name ... "
    timeout $SIM_TIMEOUT "$obj/V${tb_name}" > "$sim_log" 2>&1
    rc=$?

    # Check results
    if [ $rc -eq 124 ]; then
        fail=$((fail + 1))
        echo "TIMEOUT (${SIM_TIMEOUT}s)"
    elif grep -qiE "ALL TESTS PASSED|ALL.*PASSED|SIMULATION PASSED|>>> ALL TESTS PASSED <<<|RESULT: ALL TESTS PASSED" "$sim_log" 2>/dev/null; then
        pass=$((pass + 1))
        echo "PASS"
    elif grep -qiE "[0-9]+ PASSED, 0 FAILED|PASSED: [0-9]+.*FAILED: 0" "$sim_log" 2>/dev/null; then
        pass=$((pass + 1))
        echo "PASS"
    else
        fail=$((fail + 1))
        echo "FAIL"
        tail -5 "$sim_log" | sed 's/^/  > /'
    fi
done

echo ""
echo "============================================"
echo "L2 INTEGRATION REGRESSION SUMMARY"
echo "============================================"
echo "Total:      $total"
echo "Pass:       $pass"
echo "Fail:       $fail"
echo "Build Fail: $build_fail"
echo "============================================"

if [ $fail -eq 0 ] && [ $build_fail -eq 0 ] && [ $total -gt 0 ]; then
    echo ">>> ALL L2 TESTS PASSED <<<"
    exit 0
else
    echo ">>> SOME L2 TESTS FAILED <<<"
    exit 1
fi
