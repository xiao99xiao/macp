PREFIX ?= /usr/local

.PHONY: build install uninstall install-skill

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/macp $(PREFIX)/bin/macp

uninstall:
	rm -f $(PREFIX)/bin/macp

install-skill:
	macp install-skill
