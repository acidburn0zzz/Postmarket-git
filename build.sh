#!/bin/sh -e
# Copyright 2020 Oliver Smith
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build postmarketOS release images, without including personalizations such as
# custom SSH keys, custom package signing keys, a custom hostname etc.
#
# See the *_values functions below to configure which devices, UIs, ... are
# built by default.

BRANCH="$1"
DEVICE="$2"
UI="$3"
ONDEV="$4"
KERNEL="$5"
DEMO_PASSWORD="147147"
DATE="$(date +%Y%m%d)"
PMAPORTS_DIR="" # Filled in pmbootstrap_prepare()
WORK_DIR="" # Filled in pmbootstrap_prepare()
IMAGES_DIR="$(realpath "$(dirname "$0")")/out"

# Configuration: devices
device_values() {
	[ -n "$DEVICE" ] && echo "$DEVICE" && return
	echo "
		pine64-pinephone
	"
}

# Configuration: user interfaces
# $1: device
ui_values() {
	[ -n "$UI" ] && echo "$UI" && return
	case "$1" in
		nokia-n900) echo "i3wm" ;;
		*) echo "phosh plasma-mobile" ;;
	esac
}

# Configuration: kernel packages
# Some devices have multiple kernels available. Select or more kernels to build
# here.
# $1: device
kernel_values() {
	[ -n "$KERNEL" ] && echo "$KERNEL" && return
	case "$1" in
		qemu-amd64)
			echo "virt"
			;;
	esac
}

# Configuration: additional packages per user interface
# These packages make sense with a given UI, but are not part of the
# postmarketos-ui-* package, as they could not be uninstalled then (pmb#1933).
# For consistency with the other *_values() functions above, the values should
# be separated with spaces.
# $1: UI
ui_additional_packages_values() {
	case "$1" in
		phosh)
			echo "
				firefox
				gedit
				gnome-calculator
				gnome-clocks
			"
			;;
	esac
}

# Configuration: on-device installer
# Build with disabled and enabled on-device installer by default
ondev_values() {
	[ -n "$ONDEV" ] && echo "$ONDEV" && return
	echo "0 1"
}

check_usage() {
	if [ -z "$BRANCH" ] || [ "$BRANCH" = "-h" ]; then
		echo "usage: build.sh BRANCH [DEVICE [UI [ONDEV [KERNEL]]]]"
		echo "arguments:"
		echo "  BRANCH  pmaports.git branch to be used"
		echo "  DEVICE  device code name from pmbootstrap init"
		echo "  UI      user interface name from pmbootstrap init"
		echo "  ONDEV   1: enable on-device-installer, 0: disable"
		echo "  KERNEL  kernel from pmbootstrap init"
		exit 1
	fi
}

check_env() {
	if [ "$POSTMARKETOS_ALLOW_LOCAL_PKGS" = "1" ]; then
		echo "WARNING: POSTMARKETOS_ALLOW_LOCAL_PKGS is set." \
			"Locally built packages and installation keys will" \
			"be included in the installation image!"
	fi
}

pmbootstrap_prepare() {
	echo ":: prepare pmbootstrap"
	pmbootstrap work_migrate

	# Fill PMAPORTS_DIR, WORK_DIR
	PMAPORTS_DIR="$(pmbootstrap -q config aports)"
	WORK_DIR="$(pmbootstrap -q config work)"
	if ! [ -d "$PMAPORTS_DIR" ]; then
		echo "ERROR: failed to determine pmaports dir"
		exit 1
	fi
	if ! [ -d "$WORK_DIR" ]; then
		echo "ERROR: failed to determine work dir"
		exit 1
	fi

	# Overwrite pmbootstrap.cfg to be sure that we don't have unexpected
	# options set
	JOBS="$(pmbootstrap -q config jobs)"
	CCACHE_SIZE="$(pmbootstrap -q config ccache_size)"
	cat <<-EOF > ~/.config/pmbootstrap.cfg
	[pmbootstrap]
	aports = $PMAPORTS_DIR
	ccache_size = $CCACHE_SIZE
	jobs = $JOBS
	work = $WORK_DIR

	boot_size = 128
	device = qemu-amd64
	extra_packages = none
	hostname = none
	install_build_pkgs = False
	is_default_channel = False
	kernel =
	keymap =
	nonfree_firmware = True
	nonfree_userland = False
	ssh_keys = False
	timezone = Europe/Berlin
	ui =
	ui_extras = False
	user = user
	EOF

	if [ "$POSTMARKETOS_ALLOW_LOCAL_PKGS" != "1" ]; then
		pmbootstrap -q -y zap -p
	fi

	cd "$PMAPORTS_DIR"
}

checkout_branch() {
	echo ":: git checkout $BRANCH"


	if [ -n "$(git status --porcelain)" ]; then
		echo "ERROR: pmaports worktree is not clean: $PMAPORTS_DIR"
		exit 1
	fi
	git checkout "$BRANCH"
}


# $1: device
verify_device() {
	for dir in device/*/device-$1; do
		[ -d "$dir" ] && return
	done

	echo "ERROR: device not found: $1"
	exit 1
}

# $1: UI
verify_ui() {
	[ "$1" = "none" ] && return
	[ -d "main/postmarketos-ui-$1" ] && return

	echo "ERROR: UI not found: $1"
	exit 1
}

# $1: ondev argument (0 or 1)
verify_ondev() {
	if [ "$1" != "0" ] && [ "$1" != "1" ]; then
		echo "ERROR: ONDEV must be '0' or '1', not '$1'"
		exit 1
	fi
}

QUEUE=""
QUEUE_TOTAL=0
QUEUE_CURRENT=0

# Print a nice filename to stdout, something like:
# "pine64-pinephone-20200630-plasma-mobile-v20.05-installer.img"
# $1: device
# $2: UI
# $3: ondev
# $4: kernel
get_filename() {
	printf "%s" "$1-$DATE-$2-$BRANCH"
	if [ -n "$4" ]; then
		printf "%s" "-$4"
	fi
	if [ "$3" -eq 1 ]; then
		printf "%s" "-installer"
	fi
	printf ".img\n"
}

# Process the request to build one image: perform sanity checks on the
# parameters and add it to the queue.
# $1: device
# $2: UI
# $3: ondev (1: enable, 0: disable)
# $4: kernel
fill_queue_with_image() {
	verify_device "$1"
	verify_ui "$2"
	verify_ondev "$3"

	local filename_xz="$(get_filename "$1" "$2" "$3" "$4").xz"
	if [ -e "$IMAGES_DIR/$1/$filename_xz" ]; then
		echo "- $filename_xz (exists, skipping)"
		return
	fi

	echo "- $filename_xz"

	QUEUE="$QUEUE
		build_image $1 $2 $3 $4
	"
	QUEUE_TOTAL=$((QUEUE_TOTAL+1))
}

fill_queue_with_images() {
	local device
	local ui
	local ondev
	local kernel

	echo ":: fill queue"
	for device in $(device_values); do
		for ui in $(ui_values "$device"); do
			for ondev in $(ondev_values); do
				kernels="$(kernel_values "$device")"
				if [ -n "$kernels" ]; then
					for kernel in $kernels; do
						fill_queue_with_image \
							"$device" \
							"$ui" \
							"$ondev" \
							"$kernel"
					done
				else
					fill_queue_with_image \
						"$device" \
						"$ui" \
						"$ondev"
				fi
			done
		done
	done
}

# $1: device
# $2: UI
# $3: on-device installer (1) or not (0)
# $4: kernel
build_image() {
	local filename="$(get_filename "$1" "$2" "$3" "$4")"
	local device="$1"
	local ui="$2"
	local ondev="$3"
	local kernel="$4"
	local log="$IMAGES_DIR/$device/$filename.log"

	QUEUE_CURRENT=$((QUEUE_CURRENT+1))
	echo "[$QUEUE_CURRENT/$QUEUE_TOTAL] $filename.xz"

	# Various pmbootstrap configurations
	pmbootstrap -q config device "$device"
	pmbootstrap -q config ui "$ui"
	pmbootstrap -q config kernel "$kernel"
	pmbootstrap -q config hostname "$device"

	# Build "pmbootstrap install" command
	install_args=""
	if [ "$3" -eq 1 ]; then
		install_args="$install_args--ondev "
	fi
	add="$(ui_additional_packages_values "$ui" | tr ' ' ',')"
	if [ -n "$add" ]; then
		install_args="$install_args--add=$add "
	fi
	if [ "$POSTMARKETOS_ALLOW_LOCAL_PKGS" != "1" ]; then
		install_args="$install_args--no-local-pkgs "
	fi

	# Prepare log file
	mkdir -p "$IMAGES_DIR/$device"
	( echo "This image was generated with:"
	  echo "https://gitlab.com/postmarketOS/postmarketos-images"
	  echo "---"
	  echo "DATE: $(date)"
	  echo "BRANCH (PMAPORTS): $BRANCH"
	  echo "DEVICE: $device"
	  echo "UI: $ui"
	  echo "ON-DEVICE INSTALLER ENABLED: $ondev"
	  [ -n "$KERNEL" ] && echo "KERNEL: $kernel"
	  echo "PMBOOTSTRAP INSTALL ARGS: $install_args"
	  echo "---" ) > "$log"

	# pmbootstrap zap
	echo "  pmbootstrap -q -y zap -p"
	pmbootstrap -q -y zap -p

	# pmbootstrap install
	echo "  pmbootstrap -q install $install_args"
	echo "  => $log"
	printf "%s\n%s\n" "$DEMO_PASSWORD" "$DEMO_PASSWORD" \
		| pmbootstrap --log="$log" -q install $install_args

	# Copy and compress resulting image (-T0: multithreading)
	echo "  xz $filename"
	cp "$WORK_DIR/chroot_native/home/pmos/rootfs/$device.img" \
		"$IMAGES_DIR/$device/$filename"
	xz -T0 "$IMAGES_DIR/$device/$filename"
}

run_queue() {
	echo ":: run queue"
	echo "$QUEUE" | while read -r line; do
		$line
	done
}

check_usage
check_env
pmbootstrap_prepare
checkout_branch
fill_queue_with_images
run_queue

echo ":: done"
