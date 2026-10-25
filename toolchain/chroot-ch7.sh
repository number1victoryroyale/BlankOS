#!/bin/bash
# LFS chapter 7 (inside the chroot): directory layout, essential files and
# the additional temporary tools. Sources are at /sources.
set -euo pipefail
source /blankos-toolchain/chroot-lib.sh

if [[ ! -e $STAMPS/ch7-layout ]]; then
	msg "7.5/7.6 directories and essential files"
	mkdir -pv /{boot,home,mnt,opt,srv}
	mkdir -pv /etc/{opt,sysconfig}
	mkdir -pv /lib/firmware
	mkdir -pv /media/{floppy,cdrom}
	mkdir -pv /usr/{,local/}{include,src}
	mkdir -pv /usr/lib/locale
	mkdir -pv /usr/local/{bin,lib,sbin}
	mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
	mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
	mkdir -pv /usr/{,local/}share/man/man{1..8}
	mkdir -pv /var/{cache,local,log,mail,opt,spool}
	mkdir -pv /var/lib/{color,misc,locate}
	ln -sfv /run /var/run
	ln -sfv /run/lock /var/lock
	install -dv -m 0750 /root
	install -dv -m 1777 /tmp /var/tmp

	ln -sfv /proc/self/mounts /etc/mtab
	cat > /etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF
	# Same accounts as the book; the real ones are owned later by the
	# 'filesystem' package. BlankOS: 'builder' replaces 'tester' and is
	# the unprivileged user makepkg runs as.
	cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF
	cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF
	ensure_builder
	touch /var/log/{btmp,lastlog,faillog,wtmp}
	chgrp -v utmp /var/log/lastlog
	chmod -v 664 /var/log/lastlog
	chmod -v 600 /var/log/btmp
	touch "$STAMPS/ch7-layout"
fi

gettext_tmp() {
	./configure --disable-shared
	make
	cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}

bison_tmp() {
	./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
	make
	make install
}

perl_tmp() {
	sh Configure -des \
		-D prefix=/usr \
		-D vendorprefix=/usr \
		-D useshrplib \
		-D privlib=/usr/lib/perl5/5.44/core_perl \
		-D archlib=/usr/lib/perl5/5.44/core_perl \
		-D sitelib=/usr/lib/perl5/5.44/site_perl \
		-D sitearch=/usr/lib/perl5/5.44/site_perl \
		-D vendorlib=/usr/lib/perl5/5.44/vendor_perl \
		-D vendorarch=/usr/lib/perl5/5.44/vendor_perl
	make
	make install
}

zlib_tmp() {
	./configure --prefix=/usr
	make
	make install
	rm -fv /usr/lib/libz.a
}

mpdecimal_tmp() {
	./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpdecimal-4.0.1
	make
	make install
}

python_tmp() {
	./configure --prefix=/usr \
		--enable-shared \
		--without-ensurepip \
		--without-static-libpython
	make
	make install
}

texinfo_tmp() {
	./configure --prefix=/usr
	make
	make install
}

utillinux_tmp() {
	mkdir -pv /var/lib/hwclock
	./configure --libdir=/usr/lib \
		--runstatedir=/run \
		--disable-chfn-chsh \
		--disable-login \
		--disable-nologin \
		--disable-su \
		--disable-setpriv \
		--disable-runuser \
		--disable-pylibmount \
		--disable-static \
		--disable-liblastlog2 \
		--without-python \
		ADJTIME_PATH=/var/lib/hwclock/adjtime \
		--docdir=/usr/share/doc/util-linux-2.42.2
	make
	make install
}

step gettext-1.0.tar.xz          gettext_tmp
step bison-3.8.2.tar.xz          bison_tmp
step perl-5.44.0.tar.xz          perl_tmp
step zlib-1.3.2.tar.gz           zlib_tmp
step mpdecimal-4.0.1.tar.gz      mpdecimal_tmp
step Python-3.14.7.tar.xz        python_tmp
step texinfo-7.3.tar.xz          texinfo_tmp
step util-linux-2.42.2.tar.xz    utillinux_tmp

msg "Chapter 7 temporary tools complete"
