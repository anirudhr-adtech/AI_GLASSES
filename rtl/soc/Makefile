# Makefile for SoC top-level subsystem verification
SUBSYSTEM := soc
RTL_DIR   := $(CURDIR)
TB_DIR    := $(CURDIR)/tb
OBJ_DIR   := $(CURDIR)/obj_dir

# Module search paths for this subsystem (includes all subsystems)
YDIRS     := -y $(RTL_DIR)/ -y $(RTL_DIR)/../riscv/ -y $(RTL_DIR)/../npu/ -y $(RTL_DIR)/../axi/ -y $(RTL_DIR)/../ddr/ -y $(RTL_DIR)/../audio/ -y $(RTL_DIR)/../camera/ -y $(RTL_DIR)/../i2c/ -y $(RTL_DIR)/../spi/ -y $(RTL_DIR)/../../sim/common/

include ../../sim/common/Makefile.inc
