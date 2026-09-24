# Build the Klaus Dormann functional-test binaries via ca65 + ld65.
# Targets the cc65 toolchain (apt-get install cc65 on Debian / Ubuntu).
# If ca65 is missing, the build prints a friendly message and exits 1;
# the C test harness (test_dormann.out) reports SKIP in that case.

SRCS = 6502_functional_test.ca65 \
       65C02_extended_opcodes_test.ca65 \
       6502_decimal_test.ca65

OUT_DIR = out
BINS = $(addprefix $(OUT_DIR)/,$(SRCS:.ca65=.bin))

all: check-ca65 $(BINS)

check-ca65:
	@command -v ca65 >/dev/null 2>&1 || { \
	  echo "error: ca65 (cc65 toolchain) not on PATH."; \
	  echo "       install with: sudo apt-get install cc65"; \
	  exit 1; \
	}

$(OUT_DIR)/%.bin: %.ca65 example.cfg | $(OUT_DIR)
	ca65 -l $(OUT_DIR)/$*.lst -o $(OUT_DIR)/$*.o $<
	ld65 $(OUT_DIR)/$*.o -o $@ -m $(OUT_DIR)/$*.map -C example.cfg

$(OUT_DIR):
	@mkdir -p $(OUT_DIR)

clean:
	rm -rf $(OUT_DIR)

.PHONY: all check-ca65 clean
