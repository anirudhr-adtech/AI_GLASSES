# Makefile for NPU subsystem verification
SUBSYSTEM := npu
RTL_DIR   := $(CURDIR)
TB_DIR    := $(CURDIR)/tb
OBJ_DIR   := $(CURDIR)/obj_dir

# Module search paths for this subsystem
# Includes ddr/ for axi_mem_model (L2 integration) and sim/common/ for BFMs
YDIRS     := -y $(RTL_DIR)/ -y $(RTL_DIR)/../ddr/ -y $(RTL_DIR)/../../sim/common/

include ../../sim/common/Makefile.inc
