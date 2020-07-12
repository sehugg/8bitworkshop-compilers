
.PHONY: clean prepare cc65

OUTDIR=./bin

all: prepare cc65

prepare:
	mkdir -p $(OUTDIR)
	@emcc || echo 'Emscripten not found. Install https://github.com/emscripten-core/emsdk first.' && exit 1

clean:
	rmdir $(OUTDIR)/*

cc65:
	cd cc65 && make -f ../makefiles/Makefile.cc65
