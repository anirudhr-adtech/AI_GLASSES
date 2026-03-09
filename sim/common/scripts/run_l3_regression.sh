#!/bin/bash
# ================================================================
# L3 Cross-Subsystem Regression Script
# Builds firmware, builds TB, runs all L3 tests
# ================================================================
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
FW_DIR="$PROJECT_ROOT/firmware"
SOC_DIR="$PROJECT_ROOT/rtl/soc"
OBJ_DIR="$SOC_DIR/obj_dir/tb_l3_top"

echo "================================================================"
echo "L3 Cross-Subsystem Regression"
echo "================================================================"

# Build firmware
echo ""
echo "--- Building firmware ---"
cd "$FW_DIR"
make clean >/dev/null 2>&1 || true
make all 2>&1 | grep -E '(Error|Firmware|Boot)' || true

# Build testbench (only if binary doesn't exist)
echo ""
echo "--- Building testbench ---"
cd "$SOC_DIR"
if [ ! -f "$OBJ_DIR/Vtb_l3_top" ]; then
    rm -rf obj_dir/tb_l3_top
    make tb_l3_top 2>&1 | grep -E '(Building|Built|Error)' || true
fi

# Copy boot ROM
cp "$FW_DIR/build/boot_rom.hex" "$OBJ_DIR/"

# Run all tests
echo ""
echo "--- Running L3 tests ---"
cd "$OBJ_DIR"

TESTS="test_boot_uart test_sram test_periph_walk test_uart_echo test_timer_irq test_gpio test_spi_regs test_i2c_regs test_npu_regs test_timer_gpio test_multi_periph"

pass=0
fail=0
total=0

for test in $TESTS; do
    total=$((total + 1))
    cp "$FW_DIR/build/${test}.hex" test_firmware.hex
    result=$(timeout 120 ./Vtb_l3_top 2>&1 | grep 'RESULT' | sed 's/^.*RESULT: //')
    if echo "$result" | grep -q "PASSED"; then
        printf "  PASS: %-20s %s\n" "$test" "$result"
        pass=$((pass + 1))
    else
        printf "  FAIL: %-20s %s\n" "$test" "$result"
        fail=$((fail + 1))
    fi
done

echo ""
echo "================================================================"
echo "L3 Results: $pass/$total passed, $fail failed"
if [ $fail -eq 0 ]; then
    echo "ALL L3 TESTS PASSED"
else
    echo "SOME L3 TESTS FAILED"
    exit 1
fi
echo "================================================================"
