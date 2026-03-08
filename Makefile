# Top-level Makefile for AI Glasses SoC Verification
SUBSYSTEMS := npu audio camera axi ddr riscv i2c spi soc

.PHONY: verify-l1 verify-l2 verify-l3 verify-all lint report clean $(SUBSYSTEMS)

# L1: Run all module-level TBs
verify-l1:
	@echo "========================================"
	@echo "  Level 1: Module-Level Verification"
	@echo "========================================"
	@pass=0; fail=0; \
	for sub in $(SUBSYSTEMS); do \
		echo "--- $$sub ---"; \
		$(MAKE) -C rtl/$$sub all 2>&1; \
	done
	@$(MAKE) report

# L2: Run subsystem-level integration TBs (placeholder)
verify-l2:
	@echo "L2 subsystem tests not yet implemented"

# L3: Run SoC-level tests (placeholder)
verify-l3:
	@echo "L3 SoC tests not yet implemented"

verify-all: verify-l1 verify-l2 verify-l3

# Per-subsystem targets
$(SUBSYSTEMS):
	$(MAKE) -C rtl/$@ all

# Lint all subsystems
lint:
	@for sub in $(SUBSYSTEMS); do \
		$(MAKE) -C rtl/$$sub lint; \
	done

# Report across all subsystems
report:
	@echo ""
	@echo "========================================"
	@echo "  Verification Summary"
	@echo "========================================"
	@for sub in $(SUBSYSTEMS); do \
		$(MAKE) --no-print-directory -C rtl/$$sub report; \
	done

clean:
	@for sub in $(SUBSYSTEMS); do \
		$(MAKE) -C rtl/$$sub clean; \
	done
	rm -rf sim/logs/* sim/waves/*
