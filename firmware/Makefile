# ================================================================
# AI Glasses SoC — Firmware Build System
# ================================================================

# Toolchain
CROSS    = riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size

# Flags
ARCH     = -march=rv32im_zicsr -mabi=ilp32
CFLAGS   = $(ARCH) -nostdlib -nostartfiles -ffreestanding -O2 -Wall
CFLAGS  += -I include
LDFLAGS  = $(ARCH) -nostdlib -nostartfiles -Wl,--gc-sections

# Directories
BUILD    = build
TESTS    = tests

# Boot ROM
BOOT_SRC = boot_stub.S
BOOT_LD  = boot_rom.ld
BOOT_ELF = $(BUILD)/boot_rom.elf
BOOT_HEX = $(BUILD)/boot_rom.hex
BOOT_DIS = $(BUILD)/boot_rom.dis

# Test firmware sources
TEST_SRCS = $(wildcard $(TESTS)/*.c)
TEST_NAMES = $(notdir $(basename $(TEST_SRCS)))
TEST_HEXES = $(addprefix $(BUILD)/, $(addsuffix .hex, $(TEST_NAMES)))

# Common sources for all tests
CRT0     = crt0.S
TEST_LD  = sram_exec.ld

# ================================================================
# Targets
# ================================================================
.PHONY: all clean boot tests

all: boot tests

boot: $(BOOT_HEX)

tests: $(TEST_HEXES)

# ================================================================
# Boot ROM build
# ================================================================
$(BOOT_HEX): $(BOOT_SRC) $(BOOT_LD) | $(BUILD)
	$(CC) $(CFLAGS) -T $(BOOT_LD) $(BOOT_SRC) -o $(BOOT_ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 $(BOOT_ELF) $@
	$(OBJDUMP) -d $(BOOT_ELF) > $(BOOT_DIS)
	@echo "Boot ROM: $@"
	@$(SIZE) $(BOOT_ELF)

# ================================================================
# Test firmware build (pattern rule)
# ================================================================
$(BUILD)/%.hex: $(TESTS)/%.c $(CRT0) $(TEST_LD) | $(BUILD)
	$(CC) $(CFLAGS) -T $(TEST_LD) $(CRT0) $< -o $(BUILD)/$*.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 --change-addresses=-0x10000000 $(BUILD)/$*.elf $@
	$(OBJDUMP) -d $(BUILD)/$*.elf > $(BUILD)/$*.dis
	@echo "Firmware: $@"
	@$(SIZE) $(BUILD)/$*.elf

# ================================================================
# Build directory
# ================================================================
$(BUILD):
	mkdir -p $(BUILD)

# ================================================================
# Clean
# ================================================================
clean:
	rm -rf $(BUILD)
