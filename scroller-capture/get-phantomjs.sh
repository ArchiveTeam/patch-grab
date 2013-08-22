#!/bin/sh

KERNEL=`uname -s`
MACHINETYPE=`uname -m`

if [ "$KERNEL" != "Linux" ]; then
	echo "Cannot get packages for kernel $KERNEL"
	exit 1
fi

case "$MACHINETYPE" in
	'x86_64')
		URL='https://phantomjs.googlecode.com/files/phantomjs-1.9.1-linux-x86_64.tar.bz2'
		;;
	'i686')
		URL='https://phantomjs.googlecode.com/files/phantomjs-1.9.1-linux-i686.tar.bz2'
		;;
	*)
		echo "Cannot get packages for machine type $MACHINETYPE"
		exit 2
		;;
esac

wget $URL
