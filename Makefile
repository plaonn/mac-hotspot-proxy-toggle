PREFIX ?= /usr/local
DESTDIR ?=

BINDIR ?= $(PREFIX)/bin
LIBEXECDIR ?= $(PREFIX)/libexec
ETCDIR ?= $(PREFIX)/etc
HELPER_BUILD_DIR ?= .build
HELPER_BIN := $(HELPER_BUILD_DIR)/hotspot-proxy-toggle-helper

INSTALL ?= /usr/bin/install
MKDIR_P ?= /bin/mkdir -p
RM ?= /bin/rm

.PHONY: all build-helper install uninstall test

all: build-helper

build-helper:
	BUILD_DIR="$(HELPER_BUILD_DIR)" ./scripts/build-helper.sh >/dev/null

install: build-helper
	$(MKDIR_P) "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBEXECDIR)" "$(DESTDIR)$(ETCDIR)"
	$(INSTALL) -m 755 "bin/hotspot-proxy-toggle" "$(DESTDIR)$(BINDIR)/hotspot-proxy-toggle"
	$(INSTALL) -m 755 "$(HELPER_BIN)" "$(DESTDIR)$(LIBEXECDIR)/hotspot-proxy-toggle-helper"
	$(INSTALL) -m 644 "config.example" "$(DESTDIR)$(ETCDIR)/hotspot-proxy-toggle.conf.example"

uninstall:
	$(RM) -f "$(DESTDIR)$(BINDIR)/hotspot-proxy-toggle"
	$(RM) -f "$(DESTDIR)$(LIBEXECDIR)/hotspot-proxy-toggle-helper"
	$(RM) -f "$(DESTDIR)$(ETCDIR)/hotspot-proxy-toggle.conf.example"

test:
	./scripts/validate.sh
