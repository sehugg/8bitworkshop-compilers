
BUILDDIR=$(CURDIR)/embuild
OUTPUTDIR=$(CURDIR)/output
MAKEFILESDIR=$(CURDIR)/makefiles
FSDIR=$(OUTPUTDIR)/fs
WASMDIR=$(OUTPUTDIR)/wasm

FILE_PACKAGER=python3 $(EMSDK)/upstream/emscripten/tools/file_packager.py
ALLTARGETS=cc65 sdcc 6809tools yasm verilator zmac smlrc nesasm merlin32 batariBasic c2t makewav fastbasic dasm Silice wiz

.PHONY: clean clobber prepare $(ALLTARGETS)

all: $(ALLTARGETS)

prepare:
	mkdir -p $(OUTDIR) $(BUILDDIR) $(OUTPUTDIR) $(FSDIR) $(WASMDIR)
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

%.js: %
	sed -r 's/(return \w+)[.]ready/\1;\/\/.ready/' < $< > $@

%.wasm: %.js
	cp $*.wasm $*.js $(WASMDIR)/
	#node -e "require('$*.js')().then((m)=>{m.callMain(['--help'])})" 2> $*.stderr 1> $*.stdout
	-node -e "require('$*.js')({arguments:['--help']})" 2> $*.stderr 1> $*.stdout

EMCC_FLAGS= -Os \
	--memory-init-file 0 \
	-s MODULARIZE=1 \
	-s 'EXPORTED_RUNTIME_METHODS=[\"FS\",\"callMain\"]' \
	-s FORCE_FILESYSTEM=1 \
	-s ALLOW_MEMORY_GROWTH=1 \
	-lworkerfs.js

### cc65

cc65.wasm: copy.cc65
	mkdir -p cc65/target/none
	cd cc65 && make -j 4
	cd $(BUILDDIR)/cc65 && emmake make -j 4 cc65 CC=emcc EXE_SUFFIX= LDFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=cc65"
	cd $(BUILDDIR)/cc65 && emmake make -j 4 ca65 CC=emcc EXE_SUFFIX= LDFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=ca65"
	cd $(BUILDDIR)/cc65 && emmake make -j 4 ld65 CC=emcc EXE_SUFFIX= LDFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=ld65"

$(FSDIR)/fs65-%.js:
	cd cc65 && $(FILE_PACKAGER) $(FSDIR)/fs65-$*.data --separate-metadata --js-output=$@ \
	--preload include asminc cfg/$** lib/$** target/$**

$(BUILDDIR)/65-%/fsroot:
	mkdir -p $@ $@/cfg $@/lib $@/target
	cp -rp cc65/include cc65/asminc $@
	cp -rp cc65/cfg/$** $@/cfg/
	cp -rp cc65/lib/$** $@/lib/
	cp -rpf cc65/target/$** $@/target/

cc65.filesystems: $(FSDIR)/fs65-nes.js $(FSDIR)/fs65-apple2.js $(FSDIR)/fs65-c64.js\
	$(FSDIR)/fs65-atari.js $(FSDIR)/fs65-none.js\
	$(FSDIR)/fs65-vic20.js $(FSDIR)/fs65-atari2600.js \
	$(FSDIR)/fs65-pce.js

cc65: cc65.wasm cc65.filesystems \
	$(BUILDDIR)/cc65/bin/cc65.wasm \
	$(BUILDDIR)/cc65/bin/ca65.wasm \
	$(BUILDDIR)/cc65/bin/ld65.wasm

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

### yasm

yasm.libs:
	cd yasm && sh autogen.sh && ./configure && make

yasm.wasm: copy.yasm
	cd $(BUILDDIR)/yasm && sh autogen.sh && autoreconf -ivf && emconfigure ./configure --prefix=/share
	cd yasm && cp --preserve=mode genperf* gp-* re2c* genmacro* genversion* genstring* genmodule* $(BUILDDIR)/yasm/
	cd $(BUILDDIR)/yasm && emmake make yasm EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=yasm"

yasm: yasm.libs yasm.wasm $(BUILDDIR)/yasm/yasm.wasm

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

### zmac

zmac.wasm: copy.zmac
	cd $(BUILDDIR)/zmac && emmake make EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=zmac"

zmac: zmac.wasm $(BUILDDIR)/zmac/zmac.wasm

### smlrc

# requires nasm
smlrc.libs:
	cd SmallerC && make

smlrc.wasm: copy.SmallerC
	sed -i 's/^CC = /#CC =/g' $(BUILDDIR)/SmallerC/common.mk 
	cd $(BUILDDIR)/SmallerC && emmake make smlrc EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=smlrc"

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
	cd $(BUILDDIR)/nesasm/source && emmake make EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=nesasm"

nesasm: nesasm.wasm $(BUILDDIR)/nesasm/nesasm.wasm

### merlin32

merlin32.wasm: copy.merlin32
	#sed -i 's/^CC/#CC/g' $(BUILDDIR)/merlin32/Source/Makefile
	cd $(BUILDDIR)/merlin32/Source && emmake make EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=merlin32"

merlin32: merlin32.wasm $(BUILDDIR)/merlin32/Source/merlin32.wasm

### batariBasic

batariBasic.wasm: copy.batariBasic
	cd $(BUILDDIR)/batariBasic/source && emmake make EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=batariBasic"

batariBasic: batariBasic.wasm $(BUILDDIR)/batariBasic/source/2600basic.wasm

### c2t

c2t.wasm: copy.c2t
	sed -i 's/gcc /emcc $(EMCC_FLAGS) /g' $(BUILDDIR)/c2t/Makefile
	cd $(BUILDDIR)/c2t && emmake make EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=c2t -s WASM=0"

c2t: c2t.wasm $(BUILDDIR)/c2t/bin/c2t.js

### makewav
### TODO: asm.js only

makewav.wasm: copy.makewav
	cd $(BUILDDIR)/makewav && emmake make makewav CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=makewav -s WASM=0"

makewav: makewav.wasm $(BUILDDIR)/makewav/makewav.js

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

### DASM

dasm.wasm: copy.dasm
	cd $(BUILDDIR)/dasm/src && emmake make -j 4 dasm CC="emcc $(EMCC_FLAGS) -s EXPORT_NAME=dasm"

dasm: dasm.wasm $(BUILDDIR)/dasm/src/dasm.wasm

### naken_asm

naken_asm.wasm: copy.naken_asm
	cd $(BUILDDIR)/naken_asm && emconfigure ./configure
	sed -i 's/ -DREADLINE/ /g' $(BUILDDIR)/naken_asm/config.mak
	sed -i 's/ -lreadline/ /g' $(BUILDDIR)/naken_asm/config.mak
	sed -i 's|$$(CC) -o ../naken_util|echo |g' $(BUILDDIR)/naken_asm/build/Makefile
	cd $(BUILDDIR)/naken_asm && emmake make all CC=emcc EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=naken_asm"

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

## vasm

vasm.wasm: copy.vasm
	sed -i 's/gcc/emcc /g' $(BUILDDIR)/vasm/Makefile
	cd $(BUILDDIR)/vasm && emmake make CPU=arm SYNTAX=std EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=vasm"

vasm: vasm.wasm $(BUILDDIR)/vasm/vasmarm_std.wasm

## acme

acme.wasm: copy.acme
	sed -i 's/gcc/emcc /g' $(BUILDDIR)/acme/src/Makefile
	cd $(BUILDDIR)/acme/src && emmake make EMCC_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=acme"

acme: acme.wasm $(BUILDDIR)/acme/src/acme.wasm

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
