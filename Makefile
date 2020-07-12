
.PHONY: clean clobber prepare cc65

OUTDIR=./bin
BUILDDIR=./embuild

all: prepare cc65

prepare:
	mkdir -p $(OUTDIR) $(BUILDDIR)
	@emcc --version || { echo 'Emscripten not found. Install https://github.com/emscripten-core/emsdk first.'; exit 1; }

clean:
	rm -f $(OUTDIR)/*
	rm -fr $(BUILDDIR)

clobber: clean
	cd cc65 && make clean

copy.%:
	echo "Copying $* to $(BUILDDIR)"
	mkdir -p $(BUILDDIR)/$*
	cd $* && git archive HEAD | tar x -C ../$(BUILDDIR)/$*

cc65: copy.cc65
	cd cc65 && make
	cd $(BUILDDIR)/cc65 && make -f ../../makefiles/Makefile.cc65 binaries OUTDIR=../../$(OUTDIR)
	cd cc65 && make -f ../makefiles/Makefile.cc65 filesystems OUTDIR=../$(OUTDIR)
