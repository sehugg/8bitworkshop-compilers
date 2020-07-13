
BUILDDIR=$(CURDIR)/embuild
OUTPUTDIR=$(CURDIR)/output
MAKEFILESDIR=$(CURDIR)/makefiles
FSDIR=$(OUTPUTDIR)/fs
WASMDIR=$(OUTPUTDIR)/wasm

FILE_PACKAGER=python $(EMSDK)/upstream/emscripten/tools/file_packager.py

.PHONY: clean clobber prepare cc65 sdcc 6809tools yasm

all: cc65 sdcc 6809tools yasm

prepare:
	mkdir -p $(OUTDIR) $(BUILDDIR) $(OUTPUTDIR) $(FSDIR) $(WASMDIR)
	@emcc --version || { echo 'Emscripten not found. Install https://github.com/emscripten-core/emsdk first.'; exit 1; }

clean:
	rm -fr $(BUILDDIR)
	rm -fr $(OUTPUTDIR)

clobber: clean
	cd cc65 && make clean
	cd sdcc/sdcc && git clean -f

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
	cp $*.wasm $(WASMDIR)/

###

cc65: copy.cc65
	cd cc65 && make
	cd $(BUILDDIR)/cc65 && make -f $(MAKEFILESDIR)/Makefile.cc65 binaries OUTDIR=$(WASMDIR)
	cd cc65 && make -f $(MAKEFILESDIR)/Makefile.cc65 filesystems OUTDIR=$(FSDIR)

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

EMCC_FLAGS= \
	--memory-init-file 0 \
	-s MODULARIZE=1 \
	-s 'EXTRA_EXPORTED_RUNTIME_METHODS=["FS","callMain"]' \
	-s FORCE_FILESYSTEM=1

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
$(BUILDDIR)/sdcc/sdcc/bin/sdcc.js

###

6809tools.libs:
	cd 6809tools/lwtools && make
	cd 6809tools/cmoc && ./configure && make

6809tools.wasm: copy.6809tools
	cd $(BUILDDIR)/6809tools/lwtools && emmake make lwasm EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=lwasm"
	cd $(BUILDDIR)/6809tools/lwtools && emmake make lwlink EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=lwlink"
	cd $(BUILDDIR)/6809tools/cmoc && emconfigure ./configure EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0"
	cd $(BUILDDIR)/6809tools/cmoc/src && emmake make cmoc EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s DISABLE_EXCEPTION_CATCHING=0 -s EXPORT_NAME=cmoc"

6809tools: 6809tools.libs 6809tools.wasm \
$(BUILDDIR)/6809tools/lwtools/lwasm/lwasm.js \
$(BUILDDIR)/6809tools/lwtools/lwlink/lwlink.js \
$(BUILDDIR)/6809tools/cmoc/src/cmoc.js

###

yasm.libs:
	cd yasm && sh autogen.sh && ./configure && make

yasm.wasm: copy.yasm
	cd $(BUILDDIR)/yasm && sh autogen.sh && emconfigure ./configure
	cd yasm && cp --preserve=mode genperf* gp-* re2c* genmacro* genversion* genstring* genmodule* $(BUILDDIR)/yasm/
	cd $(BUILDDIR)/yasm && emmake make yasm EMMAKEN_CFLAGS="$(EMCC_FLAGS) -s EXPORT_NAME=yasm"

yasm: yasm.libs yasm.wasm $(BUILDDIR)/yasm/yasm.js
