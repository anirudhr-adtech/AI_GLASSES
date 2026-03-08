# Makefile for AXI subsystem verification
SUBSYSTEM := axi
RTL_DIR   := $(CURDIR)
TB_DIR    := $(CURDIR)/tb
OBJ_DIR   := $(CURDIR)/obj_dir

# Module search paths for this subsystem
# Includes riscv/ for axilite_interconnect and sim/common/ for BFMs (L2 integration)
YDIRS     := -y $(RTL_DIR)/ -y $(RTL_DIR)/../riscv/ -y $(RTL_DIR)/../../sim/common/

include ../../sim/common/Makefile.inc
