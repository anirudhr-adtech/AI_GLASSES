# Makefile for RISC-V subsystem verification
SUBSYSTEM := riscv
RTL_DIR   := $(CURDIR)
TB_DIR    := $(CURDIR)/tb
OBJ_DIR   := $(CURDIR)/obj_dir

# Module search paths for this subsystem
# Includes sim/common/ for uart_monitor BFM (L2 integration)
YDIRS     := -y $(RTL_DIR)/ -y $(RTL_DIR)/../../sim/common/

include ../../sim/common/Makefile.inc
