PREFIX ?= /usr/local
DESTDIR ?=

BINDIR ?= $(PREFIX)/bin
LIBEXECDIR ?= $(PREFIX)/libexec
ETCDIR ?= $(PREFIX)/etc
HELPER_BUILD_DIR ?= .build
HELPER_BIN := $(HELPER_BUILD_DIR)/hotspot-proxy-toggle-helper
MENU_BAR_BIN := $(HELPER_BUILD_DIR)/hotspot-proxy-toggle-menu
APP_BUNDLE := $(HELPER_BUILD_DIR)/MHP.app

INSTALL ?= /usr/bin/install
CP_R ?= /bin/cp -R
MKDIR_P ?= /bin/mkdir -p
RM ?= /bin/rm

.PHONY: all build-helper build-menu-bar build-app install uninstall test

all: build-helper build-menu-bar build-app

build-helper:
	BUILD_DIR="$(HELPER_BUILD_DIR)" ./scripts/build-helper.sh >/dev/null

build-menu-bar:
	BUILD_DIR="$(HELPER_BUILD_DIR)" ./scripts/build-menu-bar.sh >/dev/null

build-app:
	BUILD_DIR="$(HELPER_BUILD_DIR)" ./scripts/build-app.sh >/dev/null

install: build-helper build-menu-bar build-app
	$(MKDIR_P) "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBEXECDIR)" "$(DESTDIR)$(ETCDIR)"
	$(INSTALL) -m 755 "bin/hotspot-proxy-toggle" "$(DESTDIR)$(BINDIR)/hotspot-proxy-toggle"
	$(INSTALL) -m 755 "$(HELPER_BIN)" "$(DESTDIR)$(LIBEXECDIR)/hotspot-proxy-toggle-helper"
	$(INSTALL) -m 755 "$(MENU_BAR_BIN)" "$(DESTDIR)$(LIBEXECDIR)/hotspot-proxy-toggle-menu"
	$(RM) -rf "$(DESTDIR)$(LIBEXECDIR)/MHP.app"
	$(CP_R) "$(APP_BUNDLE)" "$(DESTDIR)$(LIBEXECDIR)/MHP.app"
	$(INSTALL) -m 644 "config.example" "$(DESTDIR)$(ETCDIR)/hotspot-proxy-toggle.conf.example"

uninstall:
	$(RM) -f "$(DESTDIR)$(BINDIR)/hotspot-proxy-toggle"
	$(RM) -f "$(DESTDIR)$(LIBEXECDIR)/hotspot-proxy-toggle-helper"
	$(RM) -f "$(DESTDIR)$(LIBEXECDIR)/hotspot-proxy-toggle-menu"
	$(RM) -rf "$(DESTDIR)$(LIBEXECDIR)/MHP.app"
	$(RM) -f "$(DESTDIR)$(ETCDIR)/hotspot-proxy-toggle.conf.example"

test:
	./scripts/validate.sh
