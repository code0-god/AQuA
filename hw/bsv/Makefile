SHELL := /bin/bash

BSC ?= bsc
BUILD_DIR := build
BSC_PATH := +:src/common:src/memory:src:tb
BSC_DIRS := -bdir $(BUILD_DIR)/bsc -simdir $(BUILD_DIR)/sim \
            -info-dir $(BUILD_DIR)/info
BSC_COMMON := -p $(BSC_PATH) $(BSC_DIRS) -check-assert \
              -keep-fires -show-schedule

BSV_SOURCE_FILES := \
	src/common/AquaConfig.bsv \
	src/common/AquaTypes.bsv \
	src/common/AquaMath.bsv \
	src/memory/AquaLocalAddr.bsv \
	src/memory/ScratchpadBank.bsv \
	src/memory/ActivationSpad.bsv \
	src/memory/WeightSpad.bsv \
	src/memory/Hp1MetaMem.bsv \
	src/memory/AccumulatorMem.bsv \
	src/ExSIAQuantizer.bsv

BSV_TEST_TOPS := \
	mkTbHardwareContracts \
	mkTbHp1MetaMem \
	mkTbLocalAddr \
	mkTbScratchpadBank \
	mkTbAccumulatorMem

BSV_EXPECT_FAIL_TOPS := mkTbAccumulatorOverflow

SYNTH_TOPS := mkMemorySynthTop

.PHONY: check bsv-test bsv-test-one rtl-one verify clean

check: | $(BUILD_DIR)/bsc $(BUILD_DIR)/sim $(BUILD_DIR)/info
	@set -euo pipefail; \
	for source in $(BSV_SOURCE_FILES); do \
	  echo "[BSC] check $$source"; \
	  $(BSC) -u -sim $(BSC_COMMON) "$$source"; \
	done; \
	for top in $(BSV_TEST_TOPS); do \
	  package="$${top#mk}"; \
	  echo "[BSC] check $$top"; \
	  $(BSC) -u -sim $(BSC_COMMON) -g "$$top" "tb/$$package.bsv"; \
	done

bsv-test: | $(BUILD_DIR)/bsc $(BUILD_DIR)/sim $(BUILD_DIR)/info $(BUILD_DIR)/bin
	@set -euo pipefail; \
	for top in $(BSV_TEST_TOPS); do \
	  package="$${top#mk}"; \
	  echo "[BSC] compile $$top"; \
	  $(BSC) -u -sim $(BSC_COMMON) -g "$$top" "tb/$$package.bsv"; \
	  $(BSC) -sim $(BSC_COMMON) -e "$$top" \
	    -o "$(BUILD_DIR)/bin/$$package"; \
	  echo "[Bluesim] run $$top"; \
	  "$(BUILD_DIR)/bin/$$package"; \
	done; \
	for top in $(BSV_EXPECT_FAIL_TOPS); do \
	  package="$${top#mk}"; \
	  echo "[BSC] compile expected-failure $$top"; \
	  $(BSC) -u -sim $(BSC_COMMON) -g "$$top" "tb/$$package.bsv"; \
	  $(BSC) -sim $(BSC_COMMON) -e "$$top" \
	    -o "$(BUILD_DIR)/bin/$$package"; \
	  echo "[Bluesim] expect failure $$top"; \
	  output="$$("$(BUILD_DIR)/bin/$$package" 2>&1)"; \
	  printf '%s\n' "$$output"; \
	  if [[ "$$output" != *"Dynamic assertion failed"* \
	        || "$$output" != *"accumulator addition overflow"* ]]; then \
	    echo "$$top did not trigger its expected assertion" >&2; \
	    exit 1; \
	  fi; \
	  echo "PASS expected failure $$top"; \
	done

bsv-test-one: | $(BUILD_DIR)/bsc $(BUILD_DIR)/sim $(BUILD_DIR)/info $(BUILD_DIR)/bin
	@set -euo pipefail; \
	top='$(TOP)'; \
	test -n "$$top" || { echo 'TOP is required' >&2; exit 2; }; \
	package="$${top#mk}"; \
	$(BSC) -u -sim $(BSC_COMMON) -g "$$top" "tb/$$package.bsv"; \
	$(BSC) -sim $(BSC_COMMON) -e "$$top" \
	  -o "$(BUILD_DIR)/bin/$$package"; \
	"$(BUILD_DIR)/bin/$$package"

rtl-one: | $(BUILD_DIR)/bsc $(BUILD_DIR)/info
	@set -euo pipefail; \
	top='$(TOP)'; \
	test -n "$$top" || { echo 'TOP is required' >&2; exit 2; }; \
	package="$${top#mk}"; \
	out="$(BUILD_DIR)/rtl/$$package"; \
	rm -rf "$$out"; \
	mkdir -p "$$out"; \
	$(BSC) -u -verilog -p $(BSC_PATH) \
	  -bdir $(BUILD_DIR)/bsc -info-dir $(BUILD_DIR)/info \
	  -vdir "$$out" -g "$$top" "tb/$$package.bsv"

verify: check bsv-test
	@set -euo pipefail; \
	for top in $(SYNTH_TOPS); do \
	  $(MAKE) rtl-one TOP="$$top"; \
	done

$(BUILD_DIR)/bsc $(BUILD_DIR)/sim $(BUILD_DIR)/info $(BUILD_DIR)/bin:
	@mkdir -p "$@"

clean:
	rm -rf $(BUILD_DIR)
