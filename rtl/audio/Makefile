# Makefile for Audio subsystem verification
SUBSYSTEM := audio
RTL_DIR   := $(CURDIR)
TB_DIR    := $(CURDIR)/tb
OBJ_DIR   := $(CURDIR)/obj_dir

# Module search paths for this subsystem
# Includes ddr/ for axi_mem_model and sim/common/ for I2S BFM (L2 integration)
YDIRS     := -y $(RTL_DIR)/ -y $(RTL_DIR)/../ddr/ -y $(RTL_DIR)/../../sim/common/

include ../../sim/common/Makefile.inc
