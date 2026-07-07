PROJECT  := rk3399-fanctl
VERSION  := 0.3.0-dev
DIST_DIR := dist

SCRIPTS := scripts/rk3399-fanctl scripts/common.sh scripts/dtb-lib.sh \
           scripts/kernel-hook.sh scripts/calibrate-lib.sh

.PHONY: all lint test build clean install

all: lint test build

lint:
	@echo ">> shellcheck"
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not installed"; exit 1; }
	shellcheck -s sh -x $(SCRIPTS)

test:
	@echo ">> running tests"
	@for t in tests/test-*.sh; do \
		echo "--- $$t"; \
		sh "$$t" || exit 1; \
	done

build: lint test
	@echo ">> building .deb (stub - see debian/ for full packaging)"
	@bash build.sh

clean:
	rm -rf "$(DIST_DIR)"

install:
	install -d $(DESTDIR)/usr/share/rk3399-fanctl
	install -m 0644 scripts/common.sh scripts/dtb-lib.sh \
	                scripts/calibrate-lib.sh \
	                $(DESTDIR)/usr/share/rk3399-fanctl/
	install -d $(DESTDIR)/usr/sbin
	install -m 0755 scripts/rk3399-fanctl $(DESTDIR)/usr/sbin/rk3399-fanctl
	install -d $(DESTDIR)/etc/kernel/postinst.d
	install -m 0755 scripts/kernel-hook.sh \
	                $(DESTDIR)/etc/kernel/postinst.d/rk3399-fanctl
	install -d $(DESTDIR)/etc/apt/apt.conf.d
	install -m 0644 defaults/apt-hook.conf \
	                $(DESTDIR)/etc/apt/apt.conf.d/99rk3399-fanctl
