# Copyright 2020 Oliver Smith
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Code shared between build.sh and factory/*.sh

PMAPORTS_DIR="" # Filled in pmbootstrap_prepare()
WORK_DIR="" # Filled in pmbootstrap_prepare()
CONFIG=~/.config/pmbootstrap-images.cfg
PMBOOTSTRAP="$(which pmbootstrap)"

pmbootstrap() {
	"$PMBOOTSTRAP" -c "$CONFIG" "$@"
}

pmbootstrap_default_cfg() {
	"$PMBOOTSTRAP" "$@"
}

pmbootstrap_prepare() {
	echo ":: prepare pmbootstrap"
	pmbootstrap_default_cfg work_migrate

	# Fill PMAPORTS_DIR, WORK_DIR
	PMAPORTS_DIR="$(pmbootstrap_default_cfg -q config aports)"
	WORK_DIR="$(pmbootstrap_default_cfg -q config work)"
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
	JOBS="$(pmbootstrap_default_cfg -q config jobs)"
	CCACHE_SIZE="$(pmbootstrap_default_cfg -q config ccache_size)"
	cat <<-EOF > "$CONFIG"
	[pmbootstrap]
	aports = $PMAPORTS_DIR
	ccache_size = $CCACHE_SIZE
	jobs = $JOBS
	work = $WORK_DIR

	boot_size = 128
	device = qemu-amd64
	extra_packages = none
	hostname = none
	build_pkgs_on_install = False
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
