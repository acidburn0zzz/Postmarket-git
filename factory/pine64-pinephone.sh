#!/bin/sh -e
# Copyright 2020 Oliver Smith
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The pinephone factory image consists of three layers of postmarketOS:
# 1. final rootfs (with phosh)
# 2. on-device installer
# 3. factorytest: tool by Martijn to test various functions of the device and finally flashing the image to the eMMC
# The factorytest image is flashed to an SD card and plugged into each PinePhone at the factory.

ARCH="aarch64"
TOPDIR="$(realpath "$(dirname "$0")")/.."
BRANCH="v20.05"
DEVICE="pine64-pinephone"
UI="phosh"
ONDEV=1
DATE="$(date +%Y%m%d)"
IMAGE_L2="$TOPDIR/out/$DEVICE/$DEVICE-$DATE-$UI-$BRANCH-installer.img"
IMAGE_L2_SIZE="$TOPDIR/out/$DEVICE/$DEVICE-$DATE-$UI-$BRANCH-installer.filesize"
IMAGE_L2_BMAP="$IMAGE_L2.bmap"
IMAGE_L2_XZ="$IMAGE_L2.xz"
FACTORY_APKS_DIR="$TOPDIR/out/$DEVICE/$DEVICE-$DATE-$UI-$BRANCH-factory-apks"
IMAGE_L3="$TOPDIR/out/$DEVICE/$DEVICE-$DATE-$UI-$BRANCH-factory.img"
IMAGE_L3_XZ="$IMAGE_L3.xz"
TEMP_DIR="$TOPDIR/_temp"

check_depends() {
	cmds="bmaptool pmbootstrap"
	for cmd in $cmds; do
		command -v "$cmd" >/dev/null && continue
		echo "ERROR: make sure you have these programs installed: $cmds"
		exit 1
	done
}

build_layer_2() {
	if [ -e "$IMAGE_L2" ] || [ -e "$IMAGE_L2_XZ" ]; then
		echo "## build layer 2 image (exists, skipping)"
		return
	fi

	echo "## build layer 2 image"
	NO_COMPRESS=1 ./build.sh "$BRANCH" "$DEVICE" "$UI" "$ONDEV"
}

bmap_layer_2() {
	if [ -e "$IMAGE_L2_BMAP" ]; then
		echo "## create bmap of layer 2 image (exists, skipping)"
		return
	fi
	echo "## create bmap of layer 2 image"
	bmaptool create -o "$IMAGE_L2_BMAP" "$IMAGE_L2"
}

xz_layer_2() {
	if [ -e "$IMAGE_L2_XZ" ]; then
		echo "## compress layer 2 (exists, skipping)"
		return
	fi

	echo "## compress layer 2"
	wc -c "$IMAGE_L2" | wc -c > "$IMAGE_L2_SIZE"
	xz -T0 "$IMAGE_L2"
}

pmbootstrap_reset() {
	pmbootstrap_prepare
	checkout_branch "$BRANCH"
	pmbootstrap config device "$DEVICE"
	pmbootstrap config ui "none"
	pmbootstrap config hostname "pinephone-factory"
	pmbootstrap config user "demo"
	pmbootstrap -y zap -p

	mkdir -p "$PMAPORTS_DIR/custom-factory"
	if [ ! -e "$PMAPORTS_DIR/custom-factory/factory" ]; then
		ln -sf "$TOPDIR/factory/pmaports/" \
			"$PMAPORTS_DIR/custom-factory/factory"
	fi

	cd "$TOPDIR"
}

build_factory_apks() {
	if [ -d "$FACTORY_APKS_DIR" ]; then
		echo "## build factory apks (exists, skipping)"
		return
	fi

	# Build postmarketos-boot-factorytest and depends
	echo "## build factory apks (1/2): postmarketos-boot-factorytest"
	pmbootstrap_reset
	pmbootstrap build --arch="$ARCH" postmarketos-boot-factorytest

	# Build osimage from layer 2 image
	echo "## build factory apks (2/2): osimage"
	[ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
	mkdir -p "$TEMP_DIR"
	cd "$TEMP_DIR"

	echo "postmarketOS $BRANCH ($DATE)" > "label.txt"
	cp "$IMAGE_L2_SIZE" "filesize.txt"
	cp "$IMAGE_L2_XZ" "os.img.xz"
	cp "$IMAGE_L2_BMAP" "os.img.bmap"
	pmbootstrap \
		build \
		--src="$TEMP_DIR" \
		--arch="$ARCH" \
		osimage-pmos-systemimage

	cd "$TOPDIR"
	rm -rf "$TEMP_DIR"

	# Move packages dir
	sudo mv "$WORK_DIR/packages/stable/" "$FACTORY_APKS_DIR"
	sudo chown -R "$(id -u):$(id -g)" "$FACTORY_APKS_DIR"
}

build_layer_3() {
	if [ -e "$IMAGE_L3" ] || [ -e "$IMAGE_L3_XZ" ]; then
		echo "## build layer 3 image (exists, skipping)"
		return
	fi
	
	echo "## build layer 3 image"
	pmbootstrap_reset

	sudo mkdir -p "$WORK_DIR/packages/stable/$ARCH"
	sudo cp "$FACTORY_APKS_DIR/$ARCH"/* \
		"$WORK_DIR/packages/stable/$ARCH/"

	yes | pmbootstrap install \
		--add="postmarketos-boot-factorytest,osimage"
	sudo mv "$WORK_DIR/chroot_native/home/pmos/rootfs/$DEVICE.img" \
		"$IMAGE_L3"
	sudo chown "$(id -u):$(id -g)" "$IMAGE_L3"
}

xz_layer_3() {
	if [ -e "$IMAGE_L3_XZ" ]; then
		echo "## compress layer 3 image (exists, skipping)"
		return
	fi

	echo "## compress layer 3 image"
	xz -T0 "$IMAGE_L3"
}

cd "$TOPDIR"
. ./common.sh
check_depends
build_layer_2
bmap_layer_2
xz_layer_2
build_factory_apks
build_layer_3
xz_layer_3
echo "## done with factory image"
