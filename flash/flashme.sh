#!/bin/bash
d=$(dirname $0)
dtb_id=a02


usage() {
	echo "Usage: $0 <device>"
	echo "Example: sudo $0 /dev/mmcblk0"
}

this_user="$(whoami)"
if [ "${this_user}" != "root" ]; then
	echo "ERROR: This script requires root privilege" > /dev/stderr
	usage
	exit 1
fi

if [ -z "$1" ] ; then
	usage
	exit 1
fi

if [ ! -b $1 ] ; then
	echo "$1 does not exist"
	exit 1
fi

device=$1

block_array=$(blkid ${device}* | sed -n -r -e "s#^${device}([^:]+):\s+PARTLABEL=[\"]([^\"]+)[\"].*#[\2]=${device}\1 #p")
eval "declare -xA block_devs=( $block_array )"

md5sum --status -c ./hash.md5 || { echo -e "One or more files are corrupt or missing.\n" ; md5sum -c ./hash.md5 | grep "FAILED" ; exit 1 ; }

if [ ! -f partitions ] ; then
	echo "The $d/partitions file is missing"
	exit 1
fi


source ./partitions

declare -i rc=0
for pn in ${!partitions[@]} ; do
	block_dev=${block_devs[$pn]}
	if [ -z "$block_dev" ] ; then
		echo "There was no partition named $pn on device $device"
		rc+=1
	else
		block_devs[$pn]=$block_dev
	fi
done

if [ $rc -ne 0 ] ; then
	echo "$rc errors were encountered."
	exit 1
fi

set -e

for p in ${partitions[@]} ; do
	eval $p
	echo "Flashing $d/$part_file to ${block_devs[$part_name]} ($part_name)"
	dd if=$part_file of=${block_devs[$part_name]} conv=fsync
done
