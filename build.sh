#!/bin/bash
# build.sh - sestaví .deb balíček
# Volitelné prostředí: SKIP_CHECKS=1 přeskočí lint a testy
# (CI je spouští jako samostatné joby)
set -euo pipefail

PROJECT="rk3399-fanctl"
DIST_DIR="dist"

# Verze: z Makefile, z tagu, nebo fallback
if [ -n "${VERSION:-}" ]; then
    : # předáno zvenčí (CI release workflow)
else
    VERSION=$(grep '^VERSION' Makefile | head -1 | awk '{print $3}')
fi

PKG_DIR="${DIST_DIR}/${PROJECT}_${VERSION}"

echo ">> Sestavuji ${PROJECT} verze ${VERSION}"

# Lint a testy - přeskočíme pokud CI je spouští samostatně
if [ "${SKIP_CHECKS:-0}" != "1" ]; then
    if command -v shellcheck >/dev/null 2>&1; then
        echo ">> shellcheck"
        shellcheck -s sh -x \
            scripts/rk3399-fanctl \
            scripts/common.sh \
            scripts/dtb-lib.sh \
            scripts/kernel-hook.sh \
            scripts/calibrate-lib.sh \
            scripts/monitor-lib.sh
    else
        echo ">> shellcheck není nainstalován, přeskakuji"
    fi

    echo ">> testy"
    make test
fi

echo ">> Čistím dist/"
rm -rf "$DIST_DIR"
mkdir -p "$PKG_DIR"

echo ">> Kopíruji DEBIAN soubory"
mkdir -p "$PKG_DIR/DEBIAN"
cp debian/control "$PKG_DIR/DEBIAN/control"
cp debian/postinst "$PKG_DIR/DEBIAN/postinst"
cp debian/postrm  "$PKG_DIR/DEBIAN/postrm"
cp debian/prerm   "$PKG_DIR/DEBIAN/prerm"
chmod 0755 "$PKG_DIR/DEBIAN/postinst" \
           "$PKG_DIR/DEBIAN/postrm" \
           "$PKG_DIR/DEBIAN/prerm"

echo ">> Instaluji soubory"
make install DESTDIR="$PKG_DIR" --no-print-directory

echo ">> Sestavuji .deb"
dpkg-deb --build --root-owner-group "$PKG_DIR" \
    "${DIST_DIR}/${PROJECT}_${VERSION}.deb"

echo ""
echo "✓ Hotovo: ${DIST_DIR}/${PROJECT}_${VERSION}.deb"
echo "  Instalace: sudo dpkg -i ${DIST_DIR}/${PROJECT}_${VERSION}.deb"
