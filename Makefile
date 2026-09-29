# Driver CP-D90DW — compilação Universal (arm64 + x86_64)

ARCHS    ?= -arch arm64 -arch x86_64
MINOS    ?= -mmacosx-version-min=11.0
CFLAGS   ?= -O2 -Wall -Wextra -Werror
BUILD    := build

FILTER   := $(BUILD)/rastertomitsud90
CMDFILT  := $(BUILD)/commandtomitsud90
PRINTTOOL := $(BUILD)/cpd90-print
COMMON   := src/mitsud90_common.c src/mitsud90_common.h
PPD      := ppd/CPD90Universal.ppd

.PHONY: all tools test clean pkg pkg-public

all: $(FILTER) $(CMDFILT) $(PRINTTOOL) $(PPD)

$(PPD): tools/gen_ppd.py src/mitsud90_common.h
	python3 tools/gen_ppd.py $@
	cupstestppd -W all $@ | grep -vE 'Falta ficheiro|nome padrão da Adobe|Missing|should be the Adobe standard' || true

$(FILTER): src/rastertomitsud90.c $(COMMON) | $(BUILD)
	clang $(ARCHS) $(MINOS) $(CFLAGS) -o $@ $< src/mitsud90_common.c -lcups -lcupsimage
	codesign --force --sign - $@

$(CMDFILT): src/commandtomitsud90.c $(COMMON) | $(BUILD)
	clang $(ARCHS) $(MINOS) $(CFLAGS) -o $@ $< src/mitsud90_common.c -lcups
	codesign --force --sign - $@

$(BUILD)/Version.swift: src/mitsud90_common.h | $(BUILD)
	sed -n 's/^#define DRIVER_VERSION "\(.*\)"/let version = "\1"/p' $< > $@

$(PRINTTOOL): src/cpd90-print/main.swift $(BUILD)/Version.swift | $(BUILD)
	swiftc -O -target arm64-apple-macos11 -o $@.arm64 $^
	swiftc -O -target x86_64-apple-macos11 -o $@.x86_64 $^
	lipo -create -output $@ $@.arm64 $@.x86_64 && rm $@.arm64 $@.x86_64
	codesign --force --sign - $@

tools: $(BUILD)/printer_emulator $(BUILD)/mkraster

$(BUILD)/printer_emulator: tools/printer_emulator.c | $(BUILD)
	clang -O2 -Wall -o $@ $<

$(BUILD)/mkraster: tools/mkraster.c | $(BUILD)
	clang -O2 -Wall -o $@ $< -lcups

$(BUILD):
	mkdir -p $@

# Testes com o emulador de impressora (tools/printer_emulator.c).
test: $(FILTER) $(CMDFILT) $(PRINTTOOL) tools
	[ -f build/testdata/ras/ME_15x20-1.ras ] || tools/make_rasters.sh
	tools/test_status.sh
	tools/test_calibration.sh
	tools/test_cpd90_print.sh

clean:
	rm -rf $(BUILD)

# Pacote para uso pessoal com os perfis ICC do próprio utilizador:
#   make pkg ICC_DIR=/pasta/com/os/perfis
pkg: all
	ICC_DIR="$(ICC_DIR)" PUBLIC=0 packaging/build_pkg.sh
	PUBLIC=0 packaging/verify_pkg.sh

# Pacote público: sem perfis ICC nem ficheiros da Mitsubishi.
pkg-public: all
	PUBLIC=1 packaging/build_pkg.sh
	PUBLIC=1 packaging/verify_pkg.sh
