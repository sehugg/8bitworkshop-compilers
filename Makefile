
BUILDDIR=$(CURDIR)/embuild
OUTPUTDIR=$(CURDIR)/output
MAKEFILESDIR=$(CURDIR)/makefiles
FSDIR=$(OUTPUTDIR)/fs
WASMDIR=$(OUTPUTDIR)/wasm

FILE_PACKAGER=python3 $(EMSDK)/upstream/emscripten/tools/file_packager.py
ALLTARGETS=cc65 sdcc 6809tools yasm verilator zmac smlrc nesasm merlin32 batariBasic c2t makewav fastbasic dasm

.PHONY: clean clobber prepare $(ALLTARGETS)

all: $(ALLTARGETS)

prepare:
	mkdir -p $(OUTDIR) $(BUILDDIR) $(OUTPUTDIR) $(FSDIR) $(WASMDIR)
	@emcc --version || { echo 'Emscripten not found. Install https://github.com/emscripten-core/emsdk first.'; exit 1; }

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

%.js: %
	sed -r 's/(return \w+)[.]ready/\1;\/\/.ready/' < $< > $@
	cp $@ $(WASMDIR)/

%.wasm: %.js
	cp $*.wasm $(WASMDIR)/

EMCC_FLAGS= \
	--memory-init-file 0 \
	-s MODULARIZE=1 \
	-s 'EXTRA_EXPORTED_RUNTIME_METHODS=["FS","callMain"]' \
	-s FORCE_FILESYSTEM=1 \
	-lworkerfs.js

### cc65

cc65: copy.cc65
	cd cc65 && make
	cd $(BUILDDIR)/cc65 && make -f $(MAKEFILESDIR)/Makefile.cc65 binaries OUTDIR=$(WASMDIR)
	cd cc65 && make -f $(MAKEFILESDIR)/Makefile.cc65 filesystems OUTDIR=$(FSDIR)

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
  --enable-m6502-port    \
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
	cd $(BUILDDIR)/sdcc/sdcc && emconfigure ./configure $(SDCC_CONFIG) $(SDCC_EMCC_CONFIG) EMMAKEN_CFLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS)"
	sed -i 's/#define HAVE_BACKTRACE_SYMBOLS_FD 1//g' $(BUILDDIR)/sdcc/sdcc/sdccconf.h
	# can't generate multiple modules w/ different export names
	cd $(BUILDDIR)/sdcc/sdcc/src && emmake make EMMAKEN_CFLAGS="$(EMCC_FLAGS) $(SDCC_FLAGS) -s EXPORT_NAME=sdcc"
	cp $(BUILDDIR)/sdcc/sdcc/bin/sdcc* $(WASMDIR)

sdcc.fsroot:
	rm -fr $(BUILDDIR)/sdcc/fsroot
	mkdir -p $(BUILDDIR)/sdcc/fsroot
	ln -s $(CURDIR)/sdcc/sdcc/device/include $(BUILDDIR)/sdcc/fsroot/include
	ln -s $(CURDIR)/sdcc/sdcc/device/lib/build $(BUILDDIR)/sdcc/fsroot/lib

sdcc: prepare copy.sdcc sdcc.build sdcc.fsroot $(FSDIR)/fssdcc.js \
$(BUILDDIR)/sdcc/sdcc/bin/sdcc.wasm

### 6809tools

6809tools.libs:
	cd 6809tools/lwtools && make
	cd 6809tools/cmoc && ./configure && make

6809tools.wasm: copy.6809tools
	cd $(BUILDDIR)/6809tools/lwtools && emmake make lwasm EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=lwasm"
	cd $(BUILDDIR)/6809tools/lwtools && emmake make lwlink EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=lwlink"
	cd $(BUILDDIR)/6809tools/cmoc && emconfigure ./configure --prefix=/share EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0"
	cd $(BUILDDIR)/6809tools/cmoc/src && emmake make cmoc EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0 -s EXPORT_NAME=cmoc"

6809tools: 6809tools.libs 6809tools.wasm \
$(BUILDDIR)/6809tools/lwtools/lwasm/lwasm.wasm \
$(BUILDDIR)/6809tools/lwtools/lwlink/lwlink.wasm \
$(BUILDDIR)/6809tools/cmoc/src/cmoc.wasm

### yasm

yasm.libs:
	cd yasm && sh autogen.sh && ./configure && make

yasm.wasm: copy.yasm
	cd $(BUILDDIR)/yasm && sh autogen.sh && emconfigure ./configure --prefix=/share
	cd yasm && cp --preserve=mode genperf* gp-* re2c* genmacro* genversion* genstring* genmodule* $(BUILDDIR)/yasm/
	cd $(BUILDDIR)/yasm && emmake make yasm EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=yasm"

yasm: yasm.libs yasm.wasm $(BUILDDIR)/yasm/yasm.wasm

### verilator

verilator.libs:
	cd verilator && autoconf && ./configure && make

verilator.wasm: copy.verilator
	cd $(BUILDDIR)/verilator && autoconf && emconfigure ./configure --prefix=/share
	cp /usr/include/FlexLexer.h $(BUILDDIR)/verilator/include
	sed -i 's/-lstdc++/#-lstdc++/g' $(BUILDDIR)/verilator/src/Makefile_obj
	cd $(BUILDDIR)/verilator/src && emmake make ../bin/verilator_bin EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=verilator_bin -s INITIAL_MEMORY=67108864 -s ALLOW_MEMORY_GROWTH=1"

verilator: verilator.libs verilator.wasm $(BUILDDIR)/verilator/bin/verilator_bin.wasm

### zmac

zmac.wasm: copy.zmac
	cd $(BUILDDIR)/zmac && emmake make EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=zmac"

zmac: zmac.wasm $(BUILDDIR)/zmac/zmac.wasm

### smlrc

# requires nasm
smlrc.libs:
	cd SmallerC && make

smlrc.wasm: copy.SmallerC
	sed -i 's/^CC = /#CC =/g' $(BUILDDIR)/SmallerC/common.mk 
	cd $(BUILDDIR)/SmallerC && emmake make smlrc EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=smlrc"

smlrc.fsroot:
	rm -fr $(BUILDDIR)/smlrc/fsroot
	mkdir -p $(BUILDDIR)/smlrc/fsroot
	ln -s $(CURDIR)/SmallerC/v0100/include $(BUILDDIR)/smlrc/fsroot/include
	ln -s $(CURDIR)/SmallerC/v0100/lib $(BUILDDIR)/smlrc/fsroot/lib
	rm -f $(BUILDDIR)/smlrc/fsroot/lib/lc?.a # remove non-DOS libs

smlrc: smlrc.libs smlrc.wasm $(BUILDDIR)/SmallerC/smlrc.wasm smlrc.fsroot $(FSDIR)/fssmlrc.js

### nesasm

nesasm.wasm: copy.nesasm
	sed -i 's/^CC/#CC/g' $(BUILDDIR)/nesasm/source/Makefile
	cd $(BUILDDIR)/nesasm/source && emmake make EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=nesasm"

nesasm: nesasm.wasm $(BUILDDIR)/nesasm/nesasm.wasm

### merlin32

merlin32.wasm: copy.merlin32
	#sed -i 's/^CC/#CC/g' $(BUILDDIR)/merlin32/Source/Makefile
	cd $(BUILDDIR)/merlin32/Source && emmake make EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=merlin32"

merlin32: merlin32.wasm $(BUILDDIR)/merlin32/Source/merlin32.wasm

### batariBasic

batariBasic.wasm: copy.batariBasic
	cd $(BUILDDIR)/batariBasic/source && emmake make EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=batariBasic"

batariBasic: batariBasic.wasm $(BUILDDIR)/batariBasic/source/2600basic.wasm

### c2t

c2t.wasm: copy.c2t
	sed -i 's/gcc /emcc $(EMCC_FLAGS) /g' $(BUILDDIR)/c2t/Makefile
	cd $(BUILDDIR)/c2t && emmake make EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=c2t -s WASM=0"

c2t: c2t.wasm $(BUILDDIR)/c2t/bin/c2t.js

### makewav
### TODO: asm.js only

makewav.wasm: copy.makewav
	cd $(BUILDDIR)/makewav && emmake make makewav CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=makewav -s WASM=0"

makewav: makewav.wasm $(BUILDDIR)/makewav/makewav.js

### liblzg
### TODO

### fastbasic

fastbasic.wasm: copy.fastbasic
	sed -i 's/^CXX=/#CXX=/g' $(BUILDDIR)/fastbasic/Makefile
	cd $(BUILDDIR)/fastbasic && make build build/gen build/gen/int build/obj/cxx-int build/gen/csynt
	cd $(BUILDDIR)/fastbasic && emmake make build/compiler/fastbasic-int build/compiler/fastbasic-fp \
		OPTFLAGS="-O3 $(EMCC_FLAGS) -s EXPORT_NAME=fastbasic"

fastbasic.libs:
	cd fastbasic && make ASMFLAGS="-I cc65/asminc -D NO_SMCODE"

fastbasic: fastbasic.libs fastbasic.wasm \
	$(BUILDDIR)/fastbasic/build/bin/fastbasic-int.wasm \
	$(BUILDDIR)/fastbasic/build/bin/fastbasic-fp.wasm

### DASM

dasm.wasm: copy.dasm
	cd $(BUILDDIR)/dasm/src && emmake make dasm CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=dasm"

dasm: dasm.wasm $(BUILDDIR)/dasm/src/dasm.wasm

### naken_asm

naken_asm.wasm: copy.naken_asm
	cd $(BUILDDIR)/naken_asm && emconfigure ./configure
	sed -i 's/ -DREADLINE/ /g' $(BUILDDIR)/naken_asm/config.mak
	sed -i 's/ -lreadline/ /g' $(BUILDDIR)/naken_asm/config.mak
	sed -i 's|$$(CC) -o ../naken_util|echo |g' $(BUILDDIR)/naken_asm/build/Makefile
	cd $(BUILDDIR)/naken_asm && emmake make all CC=emcc LDFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=naken_asm"

naken_asm: naken_asm.wasm $(BUILDDIR)/naken_asm/naken_asm.wasm

### Silice

# https://sourceforge.net/projects/libuuid/files/latest/download
# emconfigure ./configure --prefix=/home/hugg/emsdk/upstream/emscripten/system
# emmake make install

Silice.wasm: copy.Silice
	cp -rp Silice/src/libs/* $(BUILDDIR)/Silice/src/libs/
	mkdir -p $(BUILDDIR)/Silice/BUILD/build-silice
	sed -i 's/4.2.1/0/g' $(BUILDDIR)/Silice/antlr/antlr4-cpp-runtime-4.7.2-source/CMakeLists.txt
	cd $(BUILDDIR)/Silice/BUILD/build-silice && emmake cmake -DCMAKE_BUILD_TYPE=Release -G "Unix Makefiles" ../..
	cd $(BUILDDIR)/Silice/BUILD/build-silice && emmake make -j8 EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0 -s EXPORT_NAME=silice"

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
