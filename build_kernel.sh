#!/bin/bash -e
#
# Copyright (c) 2009-2012 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

unset KERNEL_REL
unset STABLE_PATCH
unset RC_KERNEL
unset RC_PATCH
unset BUILD
unset CC
unset LINUX_GIT
unset LATEST_GIT
unset DEBUG_SECTION

unset LOCAL_PATCH_DIR

config="omap2plus_defconfig"

ARCH=$(uname -m)
CCACHE=ccache

DIR=$PWD

CORES=1
if test "-$ARCH-" = "-x86_64-" || test "-$ARCH-" = "-i686-"
then
 CORES=$(cat /proc/cpuinfo | grep processor | wc -l)
 let CORES=$CORES+1
fi

unset GIT_OPTS
unset GIT_NOEDIT
LC_ALL=C git help pull | grep -m 1 -e "--no-edit" &>/dev/null && GIT_NOEDIT=1

if [ "${GIT_NOEDIT}" ] ; then
	echo "Detected git 1.7.10 or later, this script will pull via [git pull --no-edit]"
	GIT_OPTS+="--no-edit"
fi

mkdir -p ${DIR}/deploy/

function git_kernel_torvalds {
	echo "pulling from torvalds kernel.org tree"
	git pull ${GIT_OPTS} git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git master --tags || true
}

function git_kernel_stable {
	echo "fetching from stable kernel.org tree"
	git fetch git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git master --tags || true
}

function git_kernel {
	echo "BEGIN: git_Kernel"
	if [ -f ${LINUX_GIT}/.git/config ] ; then
		if [ -f ${LINUX_GIT}/version.sh ] ; then
			echo ""
			echo "Error, LINUX_GIT in system.sh is improperly set, do not clone a git tree on top of another.."
			echo ""
			echo "Quick Fix:"
			echo "example: cd ~/"
			echo "example: git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
			echo "example: Set: LINUX_GIT=~/linux-stable/ in system.sh"
			echo ""
			exit
		fi

		cd ${LINUX_GIT}/
		echo "Debug: LINUX_GIT setup..."
		#pwd
		#cat .git/config
		echo "Updating LINUX_GIT tree via: git fetch"
		git fetch || true
		cd -

		if [ ! -f ${DIR}/KERNEL/.git/config ] ; then
			rm -rf ${DIR}/KERNEL/ || true
			git clone --shared ${LINUX_GIT} ${DIR}/KERNEL
		fi

		cd ${DIR}/KERNEL/
		#So we are now going to assume the worst, and create a new master branch
		git am --abort || echo "git tree is clean..."
		git add .
		git commit --allow-empty -a -m 'empty cleanup commit'

		git checkout origin/master -b tmp-master
		git branch -D master || true

		git checkout origin/master -b master
		git branch -D tmp-master || true #&>/dev/null

		git pull ${GIT_OPTS} || true

		if [ ! "${LATEST_GIT}" ] ; then
			if [ "${RC_PATCH}" ] ; then
				git tag | grep v${RC_KERNEL}${RC_PATCH} &>/dev/null || git_kernel_torvalds
				git branch -D v${RC_KERNEL}${RC_PATCH}-${BUILD} &>/dev/null || true
				git checkout v${RC_KERNEL}${RC_PATCH} -b v${RC_KERNEL}${RC_PATCH}-${BUILD}
			elif [ "${STABLE_PATCH}" ] ; then
				git tag | grep v${KERNEL_REL}.${STABLE_PATCH} &>/dev/null || git_kernel_stable
				git branch -D v${KERNEL_REL}.${STABLE_PATCH}-${BUILD} &>/dev/null || true
				git checkout v${KERNEL_REL}.${STABLE_PATCH} -b v${KERNEL_REL}.${STABLE_PATCH}-${BUILD}
			else
				git tag | grep v${KERNEL_REL} | grep -v rc &>/dev/null || git_kernel_torvalds
				git branch -D v${KERNEL_REL}-${BUILD} &>/dev/null || true
				git checkout v${KERNEL_REL} -b v${KERNEL_REL}-${BUILD}
			fi
		else
			git branch -D top-of-tree &>/dev/null || true
			git checkout v${KERNEL_REL} -b top-of-tree
			git describe
			git pull ${GIT_OPTS} git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git master || true
		fi

		git describe

		cd ${DIR}/
	else
		echo ""
		echo "ERROR: LINUX_GIT variable in system.sh seems invalid, i'm not finding a valid git tree..."
		echo ""
		echo "Quick Fix:"
		echo "example: cd ~/"
		echo "example: git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
		echo "example: Set: LINUX_GIT=~/linux-stable/ in system.sh"
		echo ""
		exit
	fi
	echo "END git_kernel"
}

function patch_kernel {
	cd ${DIR}/KERNEL
	export DIR GIT_OPTS
	/bin/bash -e ${DIR}/patch.sh || { git add . ; exit 1 ; }

	git add .
	if [ "${RC_PATCH}" ] ; then
		git commit --allow-empty -a -m ''$RC_KERNEL''$RC_PATCH'-'$BUILD' patchset'
	elif [ "${STABLE_PATCH}" ] ; then
		git commit --allow-empty -a -m ''$KERNEL_REL'.'$STABLE_PATCH'-'$BUILD' patchset'
	else
		git commit --allow-empty -a -m ''$KERNEL_REL'-'$BUILD' patchset'
	fi

#Test Patches:
#exit

	if [ "${LOCAL_PATCH_DIR}" ] ; then
		for i in ${LOCAL_PATCH_DIR}/*.patch ; do patch  -s -p1 < $i ; done
		BUILD+='+'
	fi

	cd ${DIR}/
}

function bisect_kernel {
 cd ${DIR}/KERNEL
 #usb works on omap4 panda, but broken on omap3 beagle..
 git bisect start
 git bisect good v3.2
 git bisect bad  v3.3-rc1
 git bisect good 2ac9d7aaccbd598b5bd19ac40761b723bb675442

 cd ${DIR}/
}

function copy_defconfig {
  cd ${DIR}/KERNEL/
  make ARCH=arm CROSS_COMPILE=${CC} distclean
  make ARCH=arm CROSS_COMPILE=${CC} ${config}
  cp -v .config ${DIR}/patches/ref_${config}
  cp -v ${DIR}/patches/defconfig .config
  cd ${DIR}/
}

function make_menuconfig {
  cd ${DIR}/KERNEL/
  make ARCH=arm CROSS_COMPILE=${CC} menuconfig
  cp -v .config ${DIR}/patches/defconfig
  cd ${DIR}/
}

function make_kernel {
	cd ${DIR}/KERNEL/
	echo "make -j${CORES} ARCH=arm LOCALVERSION=-${BUILD} CROSS_COMPILE=\"${CCACHE} ${CC}\" ${CONFIG_DEBUG_SECTION} zImage modules"
	time make -j${CORES} ARCH=arm LOCALVERSION=-${BUILD} CROSS_COMPILE="${CCACHE} ${CC}" ${CONFIG_DEBUG_SECTION} zImage modules

	echo "make -j${CORES} ARCH=arm LOCALVERSION=-${BUILD} CROSS_COMPILE=\"${CCACHE} ${CC}\" ${CONFIG_DEBUG_SECTION} dtbs"
	time make -j${CORES} ARCH=arm LOCALVERSION=-${BUILD} CROSS_COMPILE="${CCACHE} ${CC}" ${CONFIG_DEBUG_SECTION} dtbs

	KERNEL_UTS=$(cat ${DIR}/KERNEL/include/generated/utsrelease.h | awk '{print $3}' | sed 's/\"//g' )
	if [ -f ./arch/arm/boot/zImage ] ; then
		cp arch/arm/boot/zImage ${DIR}/deploy/${KERNEL_UTS}.zImage
		cp .config ${DIR}/deploy/${KERNEL_UTS}.config
	else
		echo "Error: make zImage modules failed"
		exit
	fi
	cd ${DIR}/
}

function make_uImage {
	cd ${DIR}/KERNEL/
	echo "make -j${CORES} ARCH=arm LOCALVERSION=-${BUILD} CROSS_COMPILE=\"${CCACHE} ${CC}\" ${CONFIG_DEBUG_SECTION} uImage"
	time make -j${CORES} ARCH=arm LOCALVERSION=-${BUILD} CROSS_COMPILE="${CCACHE} ${CC}" ${CONFIG_DEBUG_SECTION} uImage
	KERNEL_UTS=$(cat ${DIR}/KERNEL/include/generated/utsrelease.h | awk '{print $3}' | sed 's/\"//g' )
	if [ -f ./arch/arm/boot/uImage ] ; then
		cp arch/arm/boot/uImage ${DIR}/deploy/${KERNEL_UTS}.uImage
	else
		echo "Error: make uImage failed"
		exit
	fi
	cd ${DIR}/
}

function make_modules_pkg {
  cd ${DIR}/KERNEL/

  echo ""
  echo "Building Module Archive"
  echo ""

  rm -rf ${DIR}/deploy/mod &> /dev/null || true
  mkdir -p ${DIR}/deploy/mod
  make ARCH=arm CROSS_COMPILE=${CC} modules_install INSTALL_MOD_PATH=${DIR}/deploy/mod
  echo "Building ${KERNEL_UTS}-modules.tar.gz"
  cd ${DIR}/deploy/mod
  tar czf ../${KERNEL_UTS}-modules.tar.gz *
  cd ${DIR}/
}

function make_headers_pkg {
  cd ${DIR}/KERNEL/

  echo ""
  echo "Building Header Archive"
  echo ""

  rm -rf ${DIR}/deploy/headers &> /dev/null || true
  mkdir -p ${DIR}/deploy/headers/usr
  make ARCH=arm CROSS_COMPILE=${CC} headers_install INSTALL_HDR_PATH=${DIR}/deploy/headers/usr
  cd ${DIR}/deploy/headers
  echo "Building ${KERNEL_UTS}-headers.tar.gz"
  tar czf ../${KERNEL_UTS}-headers.tar.gz *
  cd ${DIR}/
}

  /bin/bash -e ${DIR}/tools/host_det.sh || { exit 1 ; }

if [ -e ${DIR}/system.sh ]; then
  . system.sh
  . version.sh
	GCC="gcc"
	if [ "x${GCC_OVERRIDE}" != "x" ] ; then
		GCC="${GCC_OVERRIDE}"
	fi
	echo ""
	echo "Using : $(LC_ALL=C ${CC}${GCC} --version)"
	echo ""

if [ "${LATEST_GIT}" ] ; then
	echo ""
	echo "Warning LATEST_GIT is enabled from system.sh I hope you know what your doing.."
	echo ""
fi

	unset CONFIG_DEBUG_SECTION
	if [ "${DEBUG_SECTION}" ] ; then
		CONFIG_DEBUG_SECTION="CONFIG_DEBUG_SECTION_MISMATCH=y"
	fi

  git_kernel
  patch_kernel
#  bisect_kernel
  copy_defconfig
  make_menuconfig
	if [ "x${GCC_OVERRIDE}" != "x" ] ; then
		sed -i -e 's:CROSS_COMPILE)gcc:CROSS_COMPILE)'$GCC_OVERRIDE':g' ${DIR}/KERNEL/Makefile
	fi
	make_kernel
if [ "${BUILD_UIMAGE}" ] ; then
	make_uImage
else
  echo ""
  echo "NOTE: If you'd like to build a uImage, make sure to enable BUILD_UIMAGE variables in system.sh"
  echo "Currently Safe for current TI devices."
  echo ""
fi
	make_modules_pkg
	make_headers_pkg
	if [ "x${GCC_OVERRIDE}" != "x" ] ; then
		sed -i -e 's:CROSS_COMPILE)'$GCC_OVERRIDE':CROSS_COMPILE)gcc:g' ${DIR}/KERNEL/Makefile
	fi
else
  echo ""
  echo "ERROR: Missing (your system) specific system.sh, please copy system.sh.sample to system.sh and edit as needed."
  echo ""
  echo "example: cp system.sh.sample system.sh"
  echo "example: gedit system.sh"
  echo ""
fi

