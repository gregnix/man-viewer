# man-viewer Makefile -- Install / Test

PREFIX     ?= /usr/local
INSTALLDIR := $(PREFIX)/lib/tcltk/man-viewer
USERDIR    := $(HOME)/lib/tcltk/man-viewer
BINDIR     := $(PREFIX)/bin

.PHONY: install install-user install-bin uninstall test pkgindex help

help:
	@echo "Targets:"
	@echo "  make install        # Module nach $(INSTALLDIR)"
	@echo "  make install-bin    # Tools nach $(BINDIR)"
	@echo "  make install-user   # nach $(USERDIR)"
	@echo "  make pkgindex       # pkgIndex.tcl neu generieren"
	@echo "  make test           # Tests"

install:
	mkdir -p $(INSTALLDIR)
	cp -r lib/tm/. $(INSTALLDIR)/

install-bin:
	mkdir -p $(BINDIR)
	cp bin/md2roff bin/n2html bin/n2md bin/n2pdf bin/n2roff bin/n2svg $(BINDIR)/

install-user:
	mkdir -p $(USERDIR)
	cp -r lib/tm/. $(USERDIR)/

uninstall:
	rm -rf $(INSTALLDIR)

pkgindex:
	tclsh tools/generate-pkgindex.tcl lib/tm --write

test:
	cd tests && tclsh run-all-tests.tcl
