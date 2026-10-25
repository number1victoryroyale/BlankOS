#!/bin/bash
# BlankOS: bootstrap pacman + makepkg inside the LFS temporary system so
# that every package from LFS chapter 8 onwards is built as a pacman
# package. Everything installed here is temporary: the real packages from
# pkgs/core replace these files as they get installed.
set -euo pipefail
source /blankos-toolchain/chroot-lib.sh

bzip2_boot() {
	make -f Makefile-libbz2_so
	make clean
	make
	make PREFIX=/usr install
	cp -av libbz2.so.* /usr/lib
	ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
	ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
	cp -v bzip2-shared /usr/bin/bzip2
	rm -fv /usr/lib/libbz2.a
}

zstd_boot() {
	make prefix=/usr
	make prefix=/usr install
	rm -v /usr/lib/libzstd.a
}

# The chapter 6 `file` cannot look inside compressed files, but makepkg
# relies on `file -z` to recognise .tar.{gz,xz,bz2,zst} sources.
file_boot() {
	./configure --prefix=/usr
	make
	make install
}

ninja_boot() {
	python3 configure.py --bootstrap --verbose
	install -vm755 ninja /usr/bin/
}

meson_boot() {
	rm -rf /opt/meson-boot
	cp -a . /opt/meson-boot
	cat > /usr/bin/meson << "EOF"
#!/bin/sh
exec python3 /opt/meson-boot/meson.py "$@"
EOF
	chmod 755 /usr/bin/meson
}

pkgconf_boot() {
	mkdir build && cd build
	meson setup --prefix=/usr --buildtype=release ..
	ninja
	ninja install
	ln -sfv pkgconf /usr/bin/pkg-config
}

openssl_boot() {
	./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
	make
	make install_sw
}

libarchive_boot() {
	./configure --prefix=/usr --disable-static \
		--without-xml2 --without-expat --without-nettle --without-mbedtls \
		--without-lz4 --without-libb2
	make
	make install
}

curl_boot() {
	./configure --prefix=/usr --disable-static \
		--with-openssl --without-libpsl --disable-ldap \
		--without-brotli --without-nghttp2 --without-libidn2
	make
	make install
}

# fakeroot wraps capset() and needs <sys/capability.h>.
libcap_boot() {
	sed -i '/install -m.*STA/d' libcap/Makefile
	make prefix=/usr lib=lib
	make prefix=/usr lib=lib RAISE_SETFCAP=no install
}

fakeroot_boot() {
	./configure --prefix=/usr --libdir=/usr/lib/libfakeroot \
		--disable-static --with-ipc=sysv
	make
	make install
	install -dm755 /etc/ld.so.conf.d
	echo /usr/lib/libfakeroot > /etc/ld.so.conf.d/fakeroot.conf
	touch /etc/ld.so.conf
	grep -q ld.so.conf.d /etc/ld.so.conf || echo 'include /etc/ld.so.conf.d/*.conf' >> /etc/ld.so.conf
	ldconfig
}

pacman_boot() {
	meson setup build --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--buildtype=release \
		-Dcrypto=openssl -Dgpgme=disabled -Dcurl=enabled \
		-Di18n=false -Ddoc=disabled \
		-Dscriptlet-shell=/usr/bin/bash \
		-Dldconfig=/usr/sbin/ldconfig \
		-Dpkg-ext=.pkg.tar.zst -Dsrc-ext=.src.tar.gz
	ninja -C build
	ninja -C build install
}

step bzip2-1.0.8.tar.gz          bzip2_boot
step zstd-1.5.7.tar.gz           zstd_boot
step file-5.48.tar.gz            file_boot
step ninja-1.13.2.tar.gz         ninja_boot
step meson-1.12.0.tar.gz         meson_boot
step pkgconf-3.0.5.tar.xz        pkgconf_boot
step openssl-4.0.1.tar.gz        openssl_boot
step libarchive-3.8.10.tar.xz    libarchive_boot
step curl-8.23.0.tar.xz          curl_boot
step libcap-2.78.tar.xz          libcap_boot
step fakeroot_1.37.1.1.orig.tar.gz fakeroot_boot
step pacman-7.1.0.tar.xz         pacman_boot

msg "Configuring pacman/makepkg for the builder"
# makepkg calls `gettext` for every message; the temporary system only has
# msgfmt & co. A passthrough shim is enough until the gettext package lands.
if [[ ! -x /usr/bin/gettext ]]; then
	printf '#!/bin/sh\nprintf "%%s" "$1"\n' > /usr/bin/gettext
	chmod 755 /usr/bin/gettext
fi
# makepkg exports CHOST=x86_64-pc-linux-gnu and some configure scripts
# (zlib, ...) look for $CHOST-gcc. The temporary gcc only has the
# x86_64-lfs-linux-gnu names; the final gcc package replaces these links.
for t in gcc g++ c++ cc; do
	ln -sfv "$([[ $t == c++ || $t == g++ ]] && echo g++ || echo gcc)" "/usr/bin/x86_64-pc-linux-gnu-$t"
done
install -m644 /blankos-toolchain/makepkg.conf /etc/makepkg.conf
install -m644 /blankos-toolchain/pacman-builder.conf /etc/pacman.conf
install -d /var/lib/pacman /var/cache/pacman/pkg /etc/pacman.d/hooks
# Shadow's configure needs passwd to already exist at its final path
# (LFS 8.30).
touch /usr/bin/passwd
ensure_builder
install -d -o builder -g builder /build/pkg

msg "7.15 cleaning up the temporary system"
rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name \*.la -delete
rm -rf /tools

msg "Builder bootstrap complete"
pacman --version | head -n 3 || true
