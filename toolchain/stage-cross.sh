#!/bin/bash
# LFS chapters 5 and 6: cross toolchain and cross-compiled temporary tools.
# Runs as the unprivileged 'lfs' user with the clean environment from
# LFS 4.4 (build-toolchain.sh sets that up). Commands follow the book;
# deviations are marked "BlankOS:".
set -euo pipefail
: "${LFS:?}" "${LFS_TGT:?}" "${SRC:?}" "${WORK:?}" "${LOGS:?}" "${STAMPS:?}"
umask 022

msg() { printf '\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

# unpack TARBALL STEP: build STEP() inside the extracted source tree.
step() {
	local tarball=$1 fn=$2
	if [[ -e $STAMPS/$fn ]]; then
		msg "skip $fn (done)"
		return
	fi
	msg "$fn"
	rm -rf "$WORK" && mkdir -p "$WORK"
	tar -xf "$SRC/$tarball" -C "$WORK"
	cd "$WORK"/*/ || exit 1
	local start=$SECONDS
	# errexit is ignored inside `if` conditions, so capture the status
	# explicitly to make every failing command abort the step.
	local rc
	set +e
	(set -e; "$fn") > "$LOGS/$fn.log" 2>&1
	rc=$?
	set -e
	if ((rc != 0)); then
		tail -n 60 "$LOGS/$fn.log"
		echo "FAILED: $fn (full log: $LOGS/$fn.log)" >&2
		exit 1
	fi
	cd /
	rm -rf "$WORK"
	touch "$STAMPS/$fn"
	msg "$fn done in $((SECONDS - start))s"
}

# ---------------------------------------------------------------- ch. 5

binutils_pass1() {
	mkdir -v build && cd build
	../configure --prefix="$LFS/tools" \
		--with-sysroot="$LFS" \
		--target="$LFS_TGT" \
		--disable-nls \
		--enable-gprofng=no \
		--disable-werror \
		--enable-new-dtags \
		--enable-default-hash-style=gnu
	make
	make install
}

gcc_libs_in_tree() {
	tar -xf "$SRC/mpfr-4.2.2.tar.xz" && mv -v mpfr-4.2.2 mpfr
	tar -xf "$SRC/gmp-6.3.0.tar.xz"  && mv -v gmp-6.3.0 gmp
	tar -xf "$SRC/mpc-1.4.1.tar.xz"  && mv -v mpc-1.4.1 mpc
	sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
}

gcc_pass1() {
	gcc_libs_in_tree
	mkdir -v build && cd build
	../configure \
		--target="$LFS_TGT" \
		--prefix="$LFS/tools" \
		--with-glibc-version=2.44 \
		--with-sysroot="$LFS" \
		--with-newlib \
		--without-headers \
		--enable-default-pie \
		--enable-default-ssp \
		--disable-fixincludes \
		--disable-nls \
		--disable-shared \
		--disable-multilib \
		--disable-threads \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libquadmath \
		--disable-libssp \
		--disable-libvtv \
		--disable-libstdcxx \
		--enable-languages=c,c++
	make
	make install
	cat ../gcc/{limitx,glimits,limity}.h > \
		"$("$LFS_TGT"-gcc -print-file-name=include)/limits.h"
}

linux_headers() {
	make mrproper
	make headers
	find usr/include -type f ! -name '*.h' -delete
	cp -rv usr/include "$LFS/usr"
}

glibc_cross() {
	ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
	ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
	patch -Np1 -i "$SRC/glibc-fhs-1.patch"
	patch -Np1 -i "$SRC/glibc-2.44-upstream_fixes-1.patch"
	mkdir -v build && cd build
	echo "rootsbindir=/usr/sbin" > configparms
	../configure \
		--prefix=/usr \
		--host="$LFS_TGT" \
		--build="$(../scripts/config.guess)" \
		--disable-nscd \
		libc_cv_slibdir=/usr/lib \
		--enable-kernel=5.10
	make
	make DESTDIR="$LFS" install
	sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"

	# Sanity check from the book: the cross compiler must link against
	# the new glibc and use the right dynamic loader.
	echo 'int main(){}' | "$LFS_TGT"-gcc -x c - -v -Wl,--verbose &> dummy.log
	"$LFS_TGT"-readelf -l a.out | grep -q ': /lib64/ld-linux-x86-64.so.2'
	rm -v a.out dummy.log
}

libstdcxx() {
	mkdir -v build && cd build
	../libstdc++-v3/configure \
		--host="$LFS_TGT" \
		--build="$(../config.guess)" \
		CXX="$LFS_TGT-gcc" \
		--prefix=/usr \
		--disable-multilib \
		--disable-nls \
		--disable-libstdcxx-pch \
		--with-gxx-include-dir="/tools/$LFS_TGT/include/c++/16.2.0"
	make
	make DESTDIR="$LFS" install
	rm -v "$LFS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

# ---------------------------------------------------------------- ch. 6

m4_tmp() {
	cat > "$LFS/usr/share/config.site" << EOF
ac_cv_func_posix_spawn_file_actions_addchdir=yes
ac_cv_func_posix_spawn_file_actions_addfchdir=yes
EOF
	./configure --prefix=/usr --host="$LFS_TGT" --build="$(build-aux/config.guess)"
	make
	make DESTDIR="$LFS" install
}

ncurses_tmp() {
	mkdir build
	pushd build
	../configure --prefix="$LFS/tools" AWK=gawk
	make -C include
	make -C progs tic
	install progs/tic "$LFS/tools/bin"
	popd
	./configure --prefix=/usr \
		--host="$LFS_TGT" \
		--build="$(./config.guess)" \
		--mandir=/usr/share/man \
		--with-manpage-format=normal \
		--with-shared \
		--without-normal \
		--with-cxx-shared \
		--without-debug \
		--without-ada \
		--disable-stripping \
		AWK=gawk
	make
	make DESTDIR="$LFS" install
	ln -sv libncursesw.so "$LFS/usr/lib/libncurses.so"
	sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
}

bash_tmp() {
	./configure --prefix=/usr \
		--build="$(sh support/config.guess)" \
		--host="$LFS_TGT" \
		--without-bash-malloc \
		--docdir=/usr/share/doc/bash-5.3
	make
	make DESTDIR="$LFS" install
	ln -sv bash "$LFS/bin/sh"
}

coreutils_tmp() {
	./configure --prefix=/usr \
		--host="$LFS_TGT" \
		--build="$(build-aux/config.guess)" \
		--enable-install-program=hostname
	make
	make DESTDIR="$LFS" install
	mv -v "$LFS/usr/bin/chroot" "$LFS/usr/sbin"
	mkdir -pv "$LFS/usr/share/man/man8"
	mv -v "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8"
	sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8"
}

diffutils_tmp() {
	./configure --prefix=/usr --host="$LFS_TGT" \
		gl_cv_func_strcasecmp_works=yes \
		--build="$(./build-aux/config.guess)"
	make
	make DESTDIR="$LFS" install
}

file_tmp() {
	mkdir build
	pushd build
	../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib
	make
	popd
	./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess)"
	make FILE_COMPILE="$(pwd)/build/src/file"
	make DESTDIR="$LFS" install
	rm -v "$LFS/usr/lib/libmagic.la"
}

findutils_tmp() {
	./configure --prefix=/usr --localstatedir=/var/lib/locate \
		--host="$LFS_TGT" --build="$(build-aux/config.guess)"
	make
	make DESTDIR="$LFS" install
}

gawk_tmp() {
	sed -i 's/extras//' Makefile.in
	./configure --prefix=/usr --host="$LFS_TGT" --build="$(build-aux/config.guess)"
	make
	make DESTDIR="$LFS" install
}

# grep, sed: build-aux/config.guess lives under ./build-aux
simple_tmp() {
	./configure --prefix=/usr --host="$LFS_TGT" --build="$(build-aux/config.guess)"
	make
	make DESTDIR="$LFS" install
}

gzip_tmp() {
	./configure --prefix=/usr --host="$LFS_TGT"
	make
	make DESTDIR="$LFS" install
}

xz_tmp() {
	./configure --prefix=/usr \
		--host="$LFS_TGT" \
		--build="$(build-aux/config.guess)" \
		--disable-static \
		--docdir=/usr/share/doc/xz-5.8.3
	make
	make DESTDIR="$LFS" install
	rm -v "$LFS/usr/lib/liblzma.la"
}

binutils_pass2() {
	sed '6031s/$add_dir//' -i ltmain.sh
	mkdir -v build && cd build
	../configure \
		--prefix=/usr \
		--build="$(../config.guess)" \
		--host="$LFS_TGT" \
		--disable-nls \
		--enable-shared \
		--enable-gprofng=no \
		--disable-werror \
		--enable-64-bit-bfd \
		--enable-new-dtags \
		--enable-default-hash-style=gnu
	make
	make DESTDIR="$LFS" install
	rm -v "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

gcc_pass2() {
	gcc_libs_in_tree
	mkdir -v build && cd build
	../configure \
		--build="$(../config.guess)" \
		--host="$LFS_TGT" \
		--target="$LFS_TGT" \
		--prefix=/usr \
		--with-build-sysroot="$LFS" \
		--enable-default-pie \
		--enable-default-ssp \
		--disable-fixincludes \
		--disable-nls \
		--disable-multilib \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libquadmath \
		--disable-libsanitizer \
		--disable-libssp \
		--disable-libvtv \
		--enable-languages=c,c++ \
		CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++" \
		LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc" \
		target_configargs=gcc_cv_target_thread_file=posix
	make
	make DESTDIR="$LFS" install
	ln -sv gcc "$LFS/usr/bin/cc"
}

# ------------------------------------------------------------------ run

step binutils-2.47.tar.xz        binutils_pass1
step gcc-16.2.0.tar.xz           gcc_pass1
step linux-7.3.tar.xz            linux_headers
step glibc-2.44.tar.xz           glibc_cross
step gcc-16.2.0.tar.xz           libstdcxx

step m4-1.4.21.tar.xz            m4_tmp
step ncurses-6.6.tar.gz          ncurses_tmp
step bash-5.3.tar.gz             bash_tmp
step coreutils-9.11.tar.xz       coreutils_tmp
step diffutils-3.12.tar.xz       diffutils_tmp
step file-5.48.tar.gz            file_tmp
step findutils-4.11.0.tar.xz     findutils_tmp
step gawk-5.4.1.tar.xz           gawk_tmp
grep_tmp()  { simple_tmp; }
sed_tmp()   { simple_tmp; }
make_tmp()  { simple_tmp; }
patch_tmp() { simple_tmp; }
tar_tmp()   { simple_tmp; }
step grep-3.12.tar.xz            grep_tmp
step gzip-1.14.tar.xz            gzip_tmp
step make-4.4.1.tar.gz           make_tmp
step patch-2.8.tar.xz            patch_tmp
step sed-4.10.tar.xz             sed_tmp
step tar-1.35.tar.xz             tar_tmp
step xz-5.8.3.tar.xz             xz_tmp
step binutils-2.47.tar.xz        binutils_pass2
step gcc-16.2.0.tar.xz           gcc_pass2

msg "Cross toolchain and temporary tools complete"
