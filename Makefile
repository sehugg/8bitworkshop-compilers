
BUILDDIR=$(CURDIR)/embuild
OUTPUTDIR=$(CURDIR)/output
MAKEFILESDIR=$(CURDIR)/makefiles
FSDIR=$(OUTPUTDIR)/fs
WASMDIR=$(OUTPUTDIR)/wasm

FILE_PACKAGER=python3 $(EMSDK)/upstream/emscripten/tools/file_packager.py

# WASI toolchain (https://github.com/WebAssembly/wasi-sdk)
WASI_SDK ?= $(HOME)/wasi-sdk
WASI_CC = $(WASI_SDK)/bin/clang
WASI_STRIP = $(WASI_SDK)/bin/strip
WASI_SYSROOT = $(WASI_SDK)/share/wasi-sysroot
WASI_CFLAGS = --sysroot=$(WASI_SYSROOT)

# automake >= 1.17 ships a config.sub that knows wasm32-wasi; yasm's bundled
# copy is too old. Found at build time, used by yasm.wasi.
NEW_CONFIG_SUB = $(shell ls /opt/homebrew/share/automake-*/config.sub /usr/share/automake-*/config.sub 2>/dev/null | tail -1)
NEW_CONFIG_GUESS = $(shell ls /opt/homebrew/share/automake-*/config.guess /usr/share/automake-*/config.guess 2>/dev/null | tail -1)

ALLTARGETS=cc65 sdcc 6809tools yasm verilator zmac smlrc nesasm merlin32 c2t makewav fastbasic dasm Silice wiz cc2600 cc7800 nesfab

.PHONY: clean clobber prepare $(ALLTARGETS) test test.acme test.dasm test.yasm \
	test.vasm test.zmac test.naken_asm test.c2t test.makewav test.merlin32 \
	test.smlrc test.cc2600 test.cc7800 test.nesfab test.cc65 test.nesasm

test: test.acme test.dasm test.yasm test.vasm test.zmac test.naken_asm \
	test.c2t test.makewav test.merlin32 test.smlrc \
	test.cc2600 test.cc7800 test.nesfab test.cc65 test.nesasm
	@echo 'All tests passed.'

all: $(ALLTARGETS)

prepare:
	mkdir -p $(OUTDIR) $(BUILDDIR) $(OUTPUTDIR) $(FSDIR) $(WASMDIR)
	@test -x "$(WASI_CC)" || { echo 'wasi-sdk not found at $(WASI_SDK). Set WASI_SDK=... or install https://github.com/WebAssembly/wasi-sdk.'; exit 1; }

# smoke test for the Emscripten toolchain (only needed for emcc-based targets)
check.emcc:
	@emcc --version || { echo 'Emscripten not found. Install https://github.com/emscripten-core/emsdk first.'; exit 1; }
	@emcc -s USE_BOOST_HEADERS=1 -o /tmp/emcctest.out test.c

clean:
	rm -fr $(BUILDDIR)
	rm -fr $(OUTPUTDIR)

clobber: clean
	git submodule foreach --recursive git clean -xfd

copy.%: prepare
	echo "Copying $* to $(BUILDDIR)"
	mkdir -p $(BUILDDIR)/$*
	cd $* && git archive HEAD | tar x -C $(BUILDDIR)/$*

$(FSDIR)/fs%.js: $(BUILDDIR)/%/fsroot
	cd $< && $(FILE_PACKAGER) \
		$(FSDIR)/fs$*.data \
		--preload * \
		--separate-metadata \
		--js-output=$@

# WASI filesystems: zip up fsroot; contents unpack at the WASI root dir.
# Naming matches the IDE convention (src/worker/fs/<tool>-fs.zip).
# Only tools that ship runtime data (headers/libs) get a fsroot, e.g. sdcc, cc65.
$(FSDIR)/%-fs.zip: $(BUILDDIR)/%/fsroot
	cd $< && zip -qr $@ .

%.js: %
	sed -r 's/(return \w+)[.]ready/\1;\/\/.ready/' < $< > $@

%.wasm: %.js
	cp $*.wasm $*.js $(WASMDIR)/
	#node -e "require('$*.js')().then((m)=>{m.callMain(['--help'])})" 2> $*.stderr 1> $*.stdout
	-node -e "require('$*.js')({arguments:['--help']})" 2> $*.stderr 1> $*.stdout

EMCC_FLAGS= -Os -s PURE_WASI=1-s FORCE_FILESYSTEM=1

### cc65 (WASI)

# The runtime libraries (6502 code) are build-time data for ld65, not wasm:
# build the native host tools + all target libs in the copy first, then the
# wasm binaries. Native and wasm src builds share wrk/, so the wasm build
# must happen after the native one (it recompiles from source).
# lib/ and target/ are gitignored upstream, so they cannot come from the
# submodule working tree - always build them fresh.
cc65.wasi: copy.cc65
	cd $(BUILDDIR)/cc65/src && make mostlyclean
	cd $(BUILDDIR)/cc65/src && make -j 4 ar65 ca65 cc65
	cd $(BUILDDIR)/cc65/libsrc && PATH="$(BUILDDIR)/cc65/bin:$$PATH" make -j 4
	cd $(BUILDDIR)/cc65/src && make mostlyclean
	cd $(BUILDDIR)/cc65/src && PATH="$(WASI_SDK)/bin:$$PATH" \
		make -j 4 cc65 ca65 ld65 \
		CC="$(WASI_CC) $(WASI_CFLAGS)" \
		AR="$(WASI_SDK)/bin/llvm-ar" \
		USER_CFLAGS="-O2 -D_WASI_EMULATED_GETPID" \
		LDLIBS="-lwasi-emulated-getpid" \
		EXE_SUFFIX=.wasm \
		BUILD_ID="Git $$(cd $(CURDIR)/cc65 && git rev-parse --short HEAD)"

# src/Makefile honors CC/AR/USER_CFLAGS/EXE_SUFFIX overrides; LLVM ar is
# required (host ar corrupts wasm object archives). Compile-time data dirs
# default to /share/cc65/{include,asminc,cfg,lib,target}, so the fs zips use
# that layout (absolute paths resolve against the preopened WASI root).

# Per-platform fs packages, like the old Emscripten fs65-<platform>.js/.data
# but as WASI zips named cc65-fs-<platform>.zip (IDE loads
# src/worker/fs/<name>.zip and unpacks it at the WASI root). Each zip carries
# the shared include/asminc plus only that platform's cfg/lib/target data; the
# glob patterns are chosen so they don't bleed across platforms (e.g.
# cfg/atari* would also match atari2600.cfg).
CC65_PLATFORMS=none nes pce atari2600 atari8 vic20 apple2 c64

# The monolithic zip (every platform) - handy for tests / other tooling.
$(BUILDDIR)/cc65/fsroot: cc65.wasi
	rm -rf $@ && mkdir -p $@/share/cc65/cfg $@/share/cc65/lib $@/share/cc65/target
	cp -rp $(BUILDDIR)/cc65/include $(BUILDDIR)/cc65/asminc $@/share/cc65/
	cp -rp $(BUILDDIR)/cc65/cfg/* $@/share/cc65/cfg/
	cp -rp $(BUILDDIR)/cc65/lib/* $@/share/cc65/lib/
	cp -rpf $(BUILDDIR)/cc65/target/* $@/share/cc65/target/

$(BUILDDIR)/fs65-%/fsroot: cc65.wasi
	rm -rf $@ && mkdir -p $@/share/cc65/cfg $@/share/cc65/lib $@/share/cc65/target
	cp -rp $(BUILDDIR)/cc65/include $(BUILDDIR)/cc65/asminc $@/share/cc65/
	cd $(BUILDDIR)/cc65 && \
	case $* in \
	nes)       c="cfg/nes*";          l="lib/nes*";        t="target/nes";; \
	pce)       c="cfg/pce*";          l="lib/pce*";        t="target/pce";; \
	c64)       c="cfg/c64*";          l="lib/c64*";        t="target/c64";; \
	vic20)     c="cfg/vic20*";        l="lib/vic20*";      t="target/vic20";; \
	apple2)    c="cfg/apple2*";       l="lib/apple2*";     t="target/apple2 target/apple2enh";; \
	atari8)    c="cfg/atari.cfg cfg/atari-*.cfg cfg/atarixl*"; l="lib/atari.lib lib/atarixl.lib"; t="target/atari target/atarixl";; \
	atari2600) c="cfg/atari2600*";    l="lib/atari2600*";  t="";; \
	none)      c="";                  l="lib/none.lib";    t="";; \
	esac; \
	for f in $$c; do cp -rp $$f $@/share/cc65/cfg/; done; \
	for f in $$l; do cp -rp $$f $@/share/cc65/lib/; done; \
	for f in $$t; do cp -rp $$f $@/share/cc65/target/; done

$(FSDIR)/cc65-fs-%.zip: $(BUILDDIR)/fs65-%/fsroot
	cd $< && zip -qr $(abspath $@) .

cc65: cc65.wasi $(FSDIR)/cc65-fs.zip $(CC65_PLATFORMS:%=$(FSDIR)/cc65-fs-%.zip)
	cp $(BUILDDIR)/cc65/bin/cc65.wasm $(WASMDIR)/cc65.wasm
	cp $(BUILDDIR)/cc65/bin/ca65.wasm $(WASMDIR)/ca65.wasm
	cp $(BUILDDIR)/cc65/bin/ld65.wasm $(WASMDIR)/ld65.wasm

### sdcc

SDCC_CONFIG=\
  --disable-mcs51-port   \
  --enable-z80-port      \
  --enable-z180-port     \
  --disable-r2k-port     \
  --disable-r3ka-port    \
  --enable-gbz80-port    \
  --disable-tlcs90-port  \
  --enable-ez80_z80-port \
  --disable-ds390-port   \
  --disable-ds400-port   \
  --disable-pic14-port   \
  --disable-pic16-port   \
  --disable-hc08-port    \
  --disable-s08-port     \
  --disable-stm8-port    \
  --disable-pdk13-port   \
  --disable-pdk14-port   \
  --disable-pdk15-port   \
  --disable-pdk16-port   \
  --enable-mos6502-port    \
  --enable-non-free      \
  --disable-doc          \
  --disable-libgc        

SDCC_EMCC_CONFIG=--disable-ucsim --disable-device-lib --disable-packihx --disable-sdcpp --disable-sdcdb --disable-sdbinutils

SDCC_FLAGS= \
	-s USE_BOOST_HEADERS=1 \
	-s ERROR_ON_UNDEFINED_SYMBOLS=0

sdcc.build:
	cd sdcc/sdcc && ./configure $(SDCC_CONFIG) && make
	cd $(BUILDDIR)/sdcc/sdcc/support/sdbinutils && ./configure && make
	cp -rp sdcc/sdcc/bin/makebin $(BUILDDIR)/sdcc/sdcc/bin/
	cd $(BUILDDIR)/sdcc/sdcc && emconfigure ./configure $(SDCC_CONFIG) $(SDCC_EMCC_CONFIG) EMCC_FLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS)"
	sed -i 's/#define HAVE_BACKTRACE_SYMBOLS_FD 1//g' $(BUILDDIR)/sdcc/sdcc/sdccconf.h
	# can't generate multiple modules w/ different export names
	cd $(BUILDDIR)/sdcc/sdcc/src && emmake make EMCC_FLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdcc" LDFLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdcc"
	#cp $(BUILDDIR)/sdcc/sdcc/bin/sdcc* $(WASMDIR)

sdcc.asm:
	cd $(BUILDDIR)/sdcc/sdcc/sdas/as6500 && emmake make EMCC_FLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdas6500" LDFLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdas6500"

sdcc.fsroot:
	rm -fr $(BUILDDIR)/sdcc/fsroot
	mkdir -p $(BUILDDIR)/sdcc/fsroot
	ln -s $(CURDIR)/sdcc/sdcc/device/include $(BUILDDIR)/sdcc/fsroot/include
	ln -s $(CURDIR)/sdcc/sdcc/device/lib/build $(BUILDDIR)/sdcc/fsroot/lib

sdcc: prepare copy.sdcc sdcc.build sdcc.asm sdcc.fsroot \
	$(FSDIR)/fssdcc.js \
	$(BUILDDIR)/sdcc/sdcc/src/sdcc.wasm \
	$(BUILDDIR)/sdcc/sdcc/bin/sdas6500.wasm
	$(EMSDK)/upstream/bin/wasm-opt --strip -Oz $(BUILDDIR)/sdcc/sdcc/src/sdcc.wasm -o $(WASMDIR)/sdcc.wasm

### 6809tools

export PATH := $(CURDIR)/6809tools/lwtools/lwasm:$(PATH)
export PATH := $(CURDIR)/6809tools/lwtools/lwar:$(PATH)
export PATH := $(CURDIR)/6809tools/lwtools/lwlink:$(PATH)

6809tools.libs:
	cd 6809tools/lwtools && make -j 4
	cd 6809tools/cmoc && ./configure && autoreconf -ivf && make -j 4

6809tools.wasm: copy.6809tools
	cd $(BUILDDIR)/6809tools/lwtools && emmake make -j 4 lwasm EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=lwasm"
	cd $(BUILDDIR)/6809tools/lwtools && emmake make -j 4 lwlink EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=lwlink"
	cd $(BUILDDIR)/6809tools/cmoc && emconfigure ./configure --prefix=/share EMCC_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0"
	cd $(BUILDDIR)/6809tools/cmoc/src && emmake make -j 4 cmoc EMCC_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0 -s EXPORT_NAME=cmoc"

6809tools: 6809tools.libs 6809tools.wasm \
$(BUILDDIR)/6809tools/lwtools/lwasm/lwasm.wasm \
$(BUILDDIR)/6809tools/lwtools/lwlink/lwlink.wasm \
$(BUILDDIR)/6809tools/cmoc/src/cmoc.wasm

### yasm (WASI)
# build machine needs re2c, bison, autoconf/automake; native build tools
# (genmodule etc.) are rebuilt via CC_FOR_BUILD=cc using cross-compile detection

yasm.wasi: copy.yasm
	cd $(BUILDDIR)/yasm && sh autogen.sh && autoreconf -ivf
	[ -n "$(NEW_CONFIG_SUB)" ] && cp $(NEW_CONFIG_SUB) $(NEW_CONFIG_GUESS) $(BUILDDIR)/yasm/config/ || true
	cd $(BUILDDIR)/yasm && ./configure CC="$(WASI_CC) $(WASI_CFLAGS)" \
		CFLAGS="-std=c99 -O2 -D_GNU_SOURCE" --host=wasm32-wasi
	sed -i.bak 's|tmpfile()|fopen("yasm-dbg.out", "w+")|' \
		$(BUILDDIR)/yasm/modules/objfmts/dbg/dbg-objfmt.c
	cd $(BUILDDIR)/yasm && PATH="$(WASI_SDK)/bin:$$PATH" make -j 4 yasm
	cp $(BUILDDIR)/yasm/yasm $(BUILDDIR)/yasm/yasm.wasm

yasm: yasm.wasi
	cp $(BUILDDIR)/yasm/yasm.wasm $(WASMDIR)/yasm.wasm

### verilator

verilator.libs:
	cp /usr/include/FlexLexer.h ./verilator/include
	cd verilator && autoconf && ./configure && make -j 4

verilator.update:
	cd $(BUILDDIR)/verilator/src && emmake make -j 4 ../bin/verilator_bin EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=verilator_bin -s INITIAL_MEMORY=67108864 -s ALLOW_MEMORY_GROWTH=1"

verilator.prepare: copy.verilator
	cd $(BUILDDIR)/verilator && autoconf && emconfigure ./configure --prefix=/share
	cp /usr/include/FlexLexer.h $(BUILDDIR)/verilator/include
	#sed -i 's/-lstdc++/#-lstdc++/g' $(BUILDDIR)/verilator/src/Makefile_obj

verilator: verilator.libs verilator.prepare verilator.update $(BUILDDIR)/verilator/bin/verilator_bin.wasm

### zmac (WASI)
# doc is a build-time generator run on the host; zmac.c is generated by yacc

zmac.wasi: copy.zmac
	cd $(BUILDDIR)/zmac && cc -Wall -DMK_DOC -o doc doc.c && ./doc > /dev/null
	cd $(BUILDDIR)/zmac && PATH="$(WASI_SDK)/bin:$$PATH" make doc.o \
		CC="$(WASI_CC) $(WASI_CFLAGS)" CFLAGS="-O2"
	cd $(BUILDDIR)/zmac && PATH="$(WASI_SDK)/bin:$$PATH" make zmac \
		CC="$(WASI_CC) $(WASI_CFLAGS)" CXX="$(WASI_SDK)/bin/clang++ $(WASI_CFLAGS)" \
		CFLAGS="-O2 -include unistd.h" CXXFLAGS="-O2"
	cp $(BUILDDIR)/zmac/zmac $(BUILDDIR)/zmac/zmac.wasm

zmac: zmac.wasi
	cp $(BUILDDIR)/zmac/zmac.wasm $(WASMDIR)/zmac.wasm

### smlrc (WASI)
# SmallerC core compiler; include/lib runtime data packaged as fs zip

smlrc.wasi: copy.SmallerC
	cd $(BUILDDIR)/SmallerC && PATH="$(WASI_SDK)/bin:$$PATH" \
		make smlrc CC="$(WASI_CC) $(WASI_CFLAGS)" CFLAGS="-O2 -DPATH_PREFIX=\"/share\""
	cp $(BUILDDIR)/SmallerC/smlrc $(BUILDDIR)/SmallerC/smlrc.wasm

smlrc.fsroot:
	rm -fr $(BUILDDIR)/smlrc/fsroot
	mkdir -p $(BUILDDIR)/smlrc/fsroot/include $(BUILDDIR)/smlrc/fsroot/lib
	cp -rL SmallerC/v0100/include/. $(BUILDDIR)/smlrc/fsroot/include/
	cp -rL SmallerC/v0100/lib/. $(BUILDDIR)/smlrc/fsroot/lib/
	rm -f $(BUILDDIR)/smlrc/fsroot/lib/lc?.a $(BUILDDIR)/smlrc/fsroot/lib/*.exe

smlrc: smlrc.wasi smlrc.fsroot $(FSDIR)/smlrc-fs.zip
	cp $(BUILDDIR)/SmallerC/smlrc.wasm $(WASMDIR)/smlrc.wasm

### nesasm (WASI)

# old K&R-style C: NULL-to-int assigns etc.; system() (develo box) is
# stubbed out -- not available in WASI
NESASM_CFLAGS = -O2 -std=gnu99 -Wno-error=incompatible-function-pointer-types \
	-Wno-error=int-conversion -Wno-error=implicit-function-declaration -Wno-error=implicit-int

nesasm.wasi: copy.nesasm
	sed -i.bak 's/^\t*\tsystem(cmd);/\t\t\/* system() unavailable in WASI *\//' $(BUILDDIR)/nesasm/source/main.c
	cd $(BUILDDIR)/nesasm/source && PATH="$(WASI_SDK)/bin:$$PATH" \
		make CC="$(WASI_CC) $(WASI_CFLAGS)" CFLAGS="$(NESASM_CFLAGS)"

nesasm: nesasm.wasi
	cp $(BUILDDIR)/nesasm/nesasm $(WASMDIR)/nesasm.wasm

### c2t (WASI)
# c2t.h ships pre-generated in the submodule (loader code, built with cl65);
# do NOT regenerate it, the host toolchain may not assemble it cleanly

c2t.wasi: copy.c2t
	cd $(BUILDDIR)/c2t && mkdir -p bin && \
		$(WASI_CC) $(WASI_CFLAGS) -Wall -I. -O3 -o bin/c2t.wasm c2t.c -lm

c2t: c2t.wasi
	cp $(BUILDDIR)/c2t/bin/c2t.wasm $(WASMDIR)/c2t.wasm

### makewav (WASI)

makewav.wasi: copy.makewav
	cd $(BUILDDIR)/makewav && PATH="$(WASI_SDK)/bin:$$PATH" make makewav \
		CC="$(WASI_CC) $(WASI_CFLAGS)" CFLAGS="-O3" LDFLAGS=""
	cp $(BUILDDIR)/makewav/makewav $(BUILDDIR)/makewav/makewav.wasm

makewav: makewav.wasi
	cp $(BUILDDIR)/makewav/makewav.wasm $(WASMDIR)/makewav.wasm

### merlin32 (WASI)
# setjmp/longjmp needs wasm exception handling; libsetjmp supplies
# __wasm_longjmp. GNUmakefile is patched rather than CFLAGS-overridden
# because its -DMACRO_DIR quoting only survives inside the recipe

merlin32.wasi: copy.merlin32
	sed -i.bak 's/CFLAGS+=-O3 -Wall -DMACRO_DIR/CFLAGS+=-O3 -Wall -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false -DMACRO_DIR/' \
		$(BUILDDIR)/merlin32/Source/GNUmakefile
	sed -i.bak 's|\$$(CC) \$$(OBJECTS) -o \$$@|$$(CC) $$(OBJECTS) -o $$@ -lsetjmp|' \
		$(BUILDDIR)/merlin32/Source/GNUmakefile
	cd $(BUILDDIR)/merlin32/Source && PATH="$(WASI_SDK)/bin:$$PATH" \
		make -f GNUmakefile CC="$(WASI_CC) $(WASI_CFLAGS) -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false"
	cp $(BUILDDIR)/merlin32/Source/merlin32 $(BUILDDIR)/merlin32/Source/merlin32.wasm

merlin32: merlin32.wasi
	cp $(BUILDDIR)/merlin32/Source/merlin32.wasm $(WASMDIR)/merlin32.wasm

### liblzg
### TODO

### fastbasic

export PATH := $(CURDIR)/mkatr:$(PATH)

fastbasic.wasm: copy.fastbasic
	sed -i 's/^CXX=/#CXX=/g' $(BUILDDIR)/fastbasic/Makefile
	cd $(BUILDDIR)/fastbasic && make build build/gen build/gen/int build/obj/cxx-int build/gen/csynt
	cd $(BUILDDIR)/fastbasic && emmake make build/compiler/fastbasic-int build/compiler/fastbasic-fp \
		OPTFLAGS="-O3 $(EMCC_FLAGS) -s EXPORT_NAME=fastbasic"

fastbasic.libs:
	cd mkatr && make && cd ..
	cd fastbasic && make ASMFLAGS="-I cc65/asminc -D NO_SMCODE"

fastbasic: fastbasic.libs fastbasic.wasm \
	$(BUILDDIR)/fastbasic/build/bin/fastbasic-int.wasm \
	$(BUILDDIR)/fastbasic/build/bin/fastbasic-fp.wasm

### dasm (WASI)

dasm.wasi: copy.dasm
	cd $(BUILDDIR)/dasm/src && PATH="$(WASI_SDK)/bin:$$PATH" \
		make -j 4 dasm CC="$(WASI_CC) $(WASI_CFLAGS)" CFLAGS="-O2 -std=c99"
	cp $(BUILDDIR)/dasm/src/dasm $(BUILDDIR)/dasm/src/dasm.wasm

dasm: dasm.wasi
	cp $(BUILDDIR)/dasm/src/dasm.wasm $(WASMDIR)/dasm.wasm

### naken_asm (WASI)
# simulator + prog objects use signals/serial, which WASI lacks — dropped;
# simulate_init_* symbols stubbed for the link

naken_asm.wasi: copy.naken_asm
	cd $(BUILDDIR)/naken_asm && ./configure > /dev/null
	sed -i.bak 's|^CC=gcc|CC=$(WASI_CC) $(WASI_CFLAGS)|' $(BUILDDIR)/naken_asm/config.mak
	sed -i.bak 's| -DREADLINE| |g' $(BUILDDIR)/naken_asm/config.mak
	sed -i.bak 's| -lreadline| |g' $(BUILDDIR)/naken_asm/config.mak
	sed -i.bak 's|\$$(CC) -o ../naken_util|echo |g' $(BUILDDIR)/naken_asm/build/Makefile
	sed -i.bak 's/\$$(SIM_OBJS)//g' $(BUILDDIR)/naken_asm/build/Makefile
	sed -i.bak 's/\$$(PROG_OBJS)//g' $(BUILDDIR)/naken_asm/build/Makefile
	sed -i.bak 's|naken_asm.a \\|naken_asm.a stubs.o \\|' $(BUILDDIR)/naken_asm/build/Makefile
	mkdir -p $(BUILDDIR)/naken_asm/build/asm $(BUILDDIR)/naken_asm/build/disasm \
		$(BUILDDIR)/naken_asm/build/common $(BUILDDIR)/naken_asm/build/table \
		$(BUILDDIR)/naken_asm/build/fileio
	printf 'void simulate_init_%s(void) {}\n' 1802 6502 65816 avr8 lc3 mips msp430 stm8 tms9900 z80 \
		> $(BUILDDIR)/naken_asm/build/stubs.c
	$(WASI_CC) $(WASI_CFLAGS) -c -o $(BUILDDIR)/naken_asm/build/stubs.o $(BUILDDIR)/naken_asm/build/stubs.c
	cd $(BUILDDIR)/naken_asm && PATH="$(WASI_SDK)/bin:$$PATH" make -C build -j 4

naken_asm: naken_asm.wasi
	cp $(BUILDDIR)/naken_asm/naken_asm $(WASMDIR)/naken_asm.wasm

### cc2600 (WASI, Rust)
# needs the wasm32-wasip1 rust target: rustup target add wasm32-wasip1
# fetches crates from crates.io on first build (cargo registry cache)

cc2600.wasi: copy.cc2600
	cd $(BUILDDIR)/cc2600 && cargo build --release --target wasm32-wasip1
	cp $(BUILDDIR)/cc2600/target/wasm32-wasip1/release/cc2600.wasm $(WASMDIR)/cc2600.wasm

cc2600.fsroot: copy.cc2600
	rm -fr $(BUILDDIR)/cc2600/fsroot && mkdir -p $(BUILDDIR)/cc2600/fsroot
	cp -rp cc2600/headers $(BUILDDIR)/cc2600/fsroot/

cc2600: cc2600.wasi cc2600.fsroot $(FSDIR)/cc2600-fs.zip

### cc7800 (WASI, Rust)
# cc7800 depends on a sibling ../cc6502 crate; the cc6502 submodule is copied there

cc7800.wasi: copy.cc7800 copy.cc6502
	cd $(BUILDDIR)/cc7800 && cargo build --release --target wasm32-wasip1
	cp $(BUILDDIR)/cc7800/target/wasm32-wasip1/release/cc7800.wasm $(WASMDIR)/cc7800.wasm

cc7800.fsroot: copy.cc7800
	rm -fr $(BUILDDIR)/cc7800/fsroot && mkdir -p $(BUILDDIR)/cc7800/fsroot
	cp -rp cc7800/headers $(BUILDDIR)/cc7800/fsroot/

cc7800: cc7800.wasi cc7800.fsroot $(FSDIR)/cc7800-fs.zip

### nesfab (WASI)
# uses the sehugg/nesfab fork's built-in ARCH=WASI target (wasm EH, NO_THREAD);
# needs Homebrew boost headers (BOOST_INCLUDE) and wasi-sdk

nesfab.wasi: copy.nesfab
	cd $(BUILDDIR)/nesfab && make -j 4 ARCH=WASI wasi \
		WASI_SDK_PATH=$(WASI_SDK) OBJDIR=obj_wasi
	cp $(BUILDDIR)/nesfab/nesfab.wasm $(WASMDIR)/nesfab.wasm

nesfab.fsroot: copy.nesfab
	rm -fr $(BUILDDIR)/nesfab/fsroot && mkdir -p $(BUILDDIR)/nesfab/fsroot
	cp -rp nesfab/lib $(BUILDDIR)/nesfab/fsroot/

nesfab: nesfab.wasi nesfab.fsroot $(FSDIR)/nesfab-fs.zip

test.nesasm: nesasm
	rm -fr $(BUILDDIR)/test-nesasm && mkdir -p $(BUILDDIR)/test-nesasm
	cp $(WASMDIR)/nesasm.wasm tests/nesasm/test.asm tests/nesasm/chr.bin $(BUILDDIR)/test-nesasm/
	cd $(BUILDDIR)/test-nesasm && $(WASIRUN) --dir=. nesasm.wasm test.asm
	cmp tests/nesasm/test.expected $(BUILDDIR)/test-nesasm/test.nes
	@echo 'test.nesasm OK'

test.cc65: cc65
	rm -fr $(BUILDDIR)/test-cc65 && mkdir -p $(BUILDDIR)/test-cc65
	cp $(WASMDIR)/cc65.wasm $(WASMDIR)/ca65.wasm $(WASMDIR)/ld65.wasm tests/cc65/*.c $(BUILDDIR)/test-cc65/
	unzip -oq $(FSDIR)/cc65-fs-nes.zip -d $(BUILDDIR)/test-cc65
	cd $(BUILDDIR)/test-cc65 && $(WASIRUN) --dir=.::/ cc65.wasm -t nes -T -o test.s test.c
	cd $(BUILDDIR)/test-cc65 && $(WASIRUN) --dir=.::/ ca65.wasm -o test.o test.s
	cd $(BUILDDIR)/test-cc65 && $(WASIRUN) --dir=.::/ ld65.wasm -t nes -o test.nes test.o /share/cc65/lib/nes.lib
	cmp tests/cc65/test.s.expected $(BUILDDIR)/test-cc65/test.s
	cmp tests/cc65/test.nes.expected $(BUILDDIR)/test-cc65/test.nes
	@echo 'test.cc65 OK'

test.cc2600: cc2600
	rm -fr $(BUILDDIR)/test-cc2600 && mkdir -p $(BUILDDIR)/test-cc2600
	cp $(WASMDIR)/cc2600.wasm tests/cc2600/example_helloworld.c $(BUILDDIR)/test-cc2600/
	unzip -oq $(FSDIR)/cc2600-fs.zip -d $(BUILDDIR)/test-cc2600
	cd $(BUILDDIR)/test-cc2600 && $(WASIRUN) --dir=. cc2600.wasm -I headers -S -o example_helloworld.asm example_helloworld.c
	cmp tests/cc2600/example_helloworld.expected $(BUILDDIR)/test-cc2600/example_helloworld.asm
	@echo 'test.cc2600 OK'

test.cc7800: cc7800
	rm -fr $(BUILDDIR)/test-cc7800 && mkdir -p $(BUILDDIR)/test-cc7800
	cp $(WASMDIR)/cc7800.wasm tests/cc7800/test_helloworld.c $(BUILDDIR)/test-cc7800/
	unzip -oq $(FSDIR)/cc7800-fs.zip -d $(BUILDDIR)/test-cc7800
	cd $(BUILDDIR)/test-cc7800 && $(WASIRUN) --dir=. cc7800.wasm -I headers -S -o test_helloworld.s test_helloworld.c
	cmp tests/cc7800/test_helloworld.expected $(BUILDDIR)/test-cc7800/test_helloworld.s
	@echo 'test.cc7800 OK'

test.nesfab: nesfab
	rm -fr $(BUILDDIR)/test-nesfab && mkdir -p $(BUILDDIR)/test-nesfab
	cp $(WASMDIR)/nesfab.wasm $(BUILDDIR)/test-nesfab/
	unzip -oq $(FSDIR)/nesfab-fs.zip -d $(BUILDDIR)/test-nesfab
	cp -rp tests/nesfab/hello_world $(BUILDDIR)/test-nesfab/
	cd $(BUILDDIR)/test-nesfab && $(WASIRUN) --dir=. nesfab.wasm -I lib -o main.nes hello_world/main.fab
	cmp tests/nesfab/main.expected $(BUILDDIR)/test-nesfab/main.nes
	@echo 'test.nesfab OK'

### Silice

# https://sourceforge.net/projects/libuuid/files/latest/download
# emconfigure ./configure --prefix=/home/hugg/emsdk/upstream/emscripten/system
# emmake make install

Silice.wasm: copy.Silice
	cp -rp Silice/src/libs/* $(BUILDDIR)/Silice/src/libs/
	mkdir -p $(BUILDDIR)/Silice/BUILD/build-silice
	sed -i 's/4.2.1/0/g' $(BUILDDIR)/Silice/antlr/antlr4-cpp-runtime-4.7.2-source/CMakeLists.txt
	cd $(BUILDDIR)/Silice/BUILD/build-silice && emmake cmake -DCMAKE_BUILD_TYPE=Release -G "Unix Makefiles" ../..
	cd $(BUILDDIR)/Silice/BUILD/build-silice && emmake make -j8 EMCC_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0 -s EXPORT_NAME=silice"

Silice.fsroot:
	rm -fr $(BUILDDIR)/Silice/fsroot
	mkdir -p $(BUILDDIR)/Silice/fsroot
	ln -s $(CURDIR)/Silice/frameworks $(BUILDDIR)/Silice/fsroot

Silice: Silice.wasm $(BUILDDIR)/Silice/BUILD/build-silice/silice.wasm Silice.fsroot $(FSDIR)/fsSilice.js

### wiz

wiz.wasm: copy.wiz
	sed -i 's/__EMSCRIPTEN__/__XXXEMSRC__/g' $(BUILDDIR)/wiz/src/wiz/wiz.cpp
	sed -i 's/-fno-rtti//g' $(BUILDDIR)/wiz/Makefile
	sed -i 's/ -lm --bind / -lm /g' $(BUILDDIR)/wiz/Makefile
	sed -i 's/ -s NO_FILESYSTEM=1 / /g' $(BUILDDIR)/wiz/Makefile
	sed -i 's/ -s WASM=0 / /g' $(BUILDDIR)/wiz/Makefile
	cd $(BUILDDIR)/wiz && emmake make CC=emcc LXXFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=wiz"

wiz.fsroot:
	rm -fr $(BUILDDIR)/wiz/fsroot
	mkdir -p $(BUILDDIR)/wiz/fsroot
	ln -s $(CURDIR)/wiz/common $(BUILDDIR)/wiz/fsroot

wiz: wiz.wasm $(BUILDDIR)/wiz/bin/wiz.wasm wiz.fsroot $(FSDIR)/fswiz.js

### armips

armips.wasm: copy.armips
	cp -rp armips/ext/filesystem $(BUILDDIR)/armips/ext
	sed -i 's/int result = wmain(argc,wargv);/int result=99; try { result = wmain(argc,wargv); } catch (const std::exception \&exc) { std::cerr << "FATAL EXCEPTION: " << exc.what() << std::endl; }/g' $(BUILDDIR)/armips/Main/main.cpp
	sed -i 's/Global.multiThreading = true;/Global.multiThreading = false;/g' $(BUILDDIR)/armips/Core/Assembler.cpp
	cd $(BUILDDIR)/armips && mkdir -p build
	cd $(BUILDDIR)/armips/build && emmake cmake -DCMAKE_BUILD_TYPE=Release ..
	cd $(BUILDDIR)/armips/build && emmake make -j2 EMCC_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0 -s EXPORT_NAME=armips -DGHC_OS_LINUX -DGHC_OS_DETECTED"

armips: armips.wasm $(BUILDDIR)/armips/build/armips.wasm

## vasm (WASI)

vasm.wasi: copy.vasm
	cd $(BUILDDIR)/vasm && PATH="$(WASI_SDK)/bin:$$PATH" \
		make CPU=arm SYNTAX=std CC="$(WASI_CC) $(WASI_CFLAGS)" \
		CFLAGS="-std=c99 -O2 -Wall -Wpedantic -DUNIX -D_GNU_SOURCE"

vasm: vasm.wasi
	cp $(BUILDDIR)/vasm/vasmarm_std $(WASMDIR)/vasm.wasm

## acme (WASI)

acme.wasi: copy.acme
	cd $(BUILDDIR)/acme/src && PATH="$(WASI_SDK)/bin:$$PATH" \
		make CC="$(WASI_CC) $(WASI_CFLAGS)" CFLAGS="-O3 -Wall -Wstrict-prototypes"
	cp $(BUILDDIR)/acme/src/acme $(BUILDDIR)/acme/src/acme.wasm

acme: acme.wasi
	cp $(BUILDDIR)/acme/src/acme.wasm $(WASMDIR)/acme.wasm

# run WASI binaries with wasmtime by default; override e.g. WASIRUN=wasmer make test.acme
WASIRUN ?= wasmtime

test.acme: acme
	rm -fr $(BUILDDIR)/test-acme && mkdir -p $(BUILDDIR)/test-acme
	cp $(WASMDIR)/acme.wasm tests/acme/*.a $(BUILDDIR)/test-acme/
	cd $(BUILDDIR)/test-acme && $(WASIRUN) --dir=. acme.wasm -o 6502.prg 6502.a
	cmp tests/acme/6502.expected $(BUILDDIR)/test-acme/6502.prg
	@echo 'test.acme OK'

test.dasm: dasm
	rm -fr $(BUILDDIR)/test-dasm && mkdir -p $(BUILDDIR)/test-dasm
	cp $(WASMDIR)/dasm.wasm tests/dasm/*.asm $(BUILDDIR)/test-dasm/
	cd $(BUILDDIR)/test-dasm && $(WASIRUN) --dir=. dasm.wasm test.asm -otest.bin -ltest.lst
	cmp tests/dasm/test.expected $(BUILDDIR)/test-dasm/test.bin
	@echo 'test.dasm OK'

test.yasm: yasm
	rm -fr $(BUILDDIR)/test-yasm && mkdir -p $(BUILDDIR)/test-yasm
	cp $(WASMDIR)/yasm.wasm tests/yasm/*.asm $(BUILDDIR)/test-yasm/
	cd $(BUILDDIR)/test-yasm && $(WASIRUN) --dir=. yasm.wasm -f elf -o test.o test.asm
	cmp tests/yasm/test.expected $(BUILDDIR)/test-yasm/test.o
	@echo 'test.yasm OK'

test.vasm: vasm
	rm -fr $(BUILDDIR)/test-vasm && mkdir -p $(BUILDDIR)/test-vasm
	cp $(WASMDIR)/vasm.wasm tests/vasm/*.asm $(BUILDDIR)/test-vasm/
	cd $(BUILDDIR)/test-vasm && $(WASIRUN) --dir=. vasm.wasm -Fbin -o test.bin test.asm
	cmp tests/vasm/test.expected $(BUILDDIR)/test-vasm/test.bin
	@echo 'test.vasm OK'

test.zmac: zmac
	rm -fr $(BUILDDIR)/test-zmac && mkdir -p $(BUILDDIR)/test-zmac
	cp $(WASMDIR)/zmac.wasm tests/zmac/*.z80 $(BUILDDIR)/test-zmac/
	cd $(BUILDDIR)/test-zmac && $(WASIRUN) --dir=. zmac.wasm test.z80
	cmp tests/zmac/test.expected $(BUILDDIR)/test-zmac/zout/test.cim
	@echo 'test.zmac OK'

test.naken_asm: naken_asm
	rm -fr $(BUILDDIR)/test-naken_asm && mkdir -p $(BUILDDIR)/test-naken_asm
	cp $(WASMDIR)/naken_asm.wasm tests/naken_asm/*.asm $(BUILDDIR)/test-naken_asm/
	cd $(BUILDDIR)/test-naken_asm && $(WASIRUN) --dir=. naken_asm.wasm -o test.bin test.asm
	cmp tests/naken_asm/test.expected $(BUILDDIR)/test-naken_asm/test.bin
	@echo 'test.naken_asm OK'

test.c2t: c2t
	rm -fr $(BUILDDIR)/test-c2t && mkdir -p $(BUILDDIR)/test-c2t
	cp $(WASMDIR)/c2t.wasm tests/c2t/* $(BUILDDIR)/test-c2t/
	cd $(BUILDDIR)/test-c2t && $(WASIRUN) --dir=. c2t.wasm -2 test.mon test.wav
	cmp tests/c2t/test.expected $(BUILDDIR)/test-c2t/test.wav
	@echo 'test.c2t OK'

test.makewav: makewav
	rm -fr $(BUILDDIR)/test-makewav && mkdir -p $(BUILDDIR)/test-makewav
	cp $(WASMDIR)/makewav.wasm tests/makewav/* $(BUILDDIR)/test-makewav/
	cd $(BUILDDIR)/test-makewav && $(WASIRUN) --dir=. makewav.wasm -b2K test.bin
	cmp tests/makewav/test.expected $(BUILDDIR)/test-makewav/test.wav
	@echo 'test.makewav OK'

test.merlin32: merlin32
	rm -fr $(BUILDDIR)/test-merlin32 && mkdir -p $(BUILDDIR)/test-merlin32
	cp $(WASMDIR)/merlin32.wasm tests/merlin32/*.s $(BUILDDIR)/test-merlin32/
	cd $(BUILDDIR)/test-merlin32 && $(WASIRUN) --dir=. merlin32.wasm test.s
	cmp tests/merlin32/test.expected $(BUILDDIR)/test-merlin32/test
	@echo 'test.merlin32 OK'

test.smlrc: smlrc
	rm -fr $(BUILDDIR)/test-smlrc && mkdir -p $(BUILDDIR)/test-smlrc
	cp $(WASMDIR)/smlrc.wasm tests/smlrc/*.c $(BUILDDIR)/test-smlrc/
	cd $(BUILDDIR)/test-smlrc && $(WASIRUN) --dir=. smlrc.wasm -seg32 test.c test.asm
	cmp tests/smlrc/test.expected $(BUILDDIR)/test-smlrc/test.asm
	@echo 'test.smlrc OK'

## tcc

tinycc.build:
	cd tinycc && ./configure && make cross-arm

tinycc.wasm: copy.tinycc
	cd $(BUILDDIR)/tinycc && emconfigure ./configure --cpu=i386 #--cross-prefix=$(CURDIR)/tinycc
	cd $(BUILDDIR)/tinycc && emmake make EXESUF=.js tccdefs_.h arm-tcc.js LDFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=armtcc"

tinycc.fsroot:
	rm -fr $(BUILDDIR)/tinycc/fsroot
	mkdir -p $(BUILDDIR)/tinycc/fsroot
	cp -pv tinycc/*.o tinycc/*.a $(BUILDDIR)/tinycc/fsroot

tinycc: tinycc.build tinycc.wasm tinycc.fsroot $(BUILDDIR)/tinycc/arm-tcc.wasm
