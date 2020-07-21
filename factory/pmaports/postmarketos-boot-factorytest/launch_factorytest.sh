#!/bin/sh

if [ $(tty) = "/dev/tty1" ]; then
	export XDG_RUNTIME_DIR=/tmp
	dbus-launch cage factorytest hwtest
fi
