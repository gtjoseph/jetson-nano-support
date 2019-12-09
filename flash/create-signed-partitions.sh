#!/bin/bash

# Copyright (c) 2019, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# This is a script to generate the SD card flashable image for
# jetson-nano platform

set -e

function usage()
{
	if [ -n "${1}" ]; then
		echo "${1}"
	fi

	echo "Usage:"
	echo "${script_name} -r <revision>"
	echo "	revision	- SKU revision number"
	echo "Example for board rev a02:"
	echo "${script_name} -r 200"
	exit 1
}

function check_pre_req()
{
	this_user="$(whoami)"
	if [ "${this_user}" != "root" ]; then
		echo "ERROR: This script requires root privilege" > /dev/stderr
		usage
		exit 1
	fi

	while [ -n "${1}" ]; do
		case "${1}" in
		-h | --help)
			usage
			;;
		-r | --revision)
			[ -n "${2}" ] || usage "Not enough parameters"
			rev="${2}"
			shift 2
			;;
		*)
			usage "Unknown option: ${1}"
			;;
		esac
	done

	case "${rev}" in
	"100")
		dtb_id="a01"
		;;
	"200")
		dtb_id="a02"
		;;
	"300")
		dtb_id="b00"
		;;
	*)
		usage "Incorrect Revision - Supported revisions - 100, 200, 300"
		;;
	esac

	if [ ! -f "${l4t_dir}/flash.sh" ]; then
		echo "ERROR: ${l4t_dir}/flash.sh is not found" > /dev/stderr
		usage
	fi

	if [ ! -d "${bootloader_dir}" ]; then
		echo "ERROR: ${bootloader_dir} directory not found" > /dev/stderr
		usage
	fi

}

function create_signed_images()
{
	echo "${script_name} - creating signed images"

	# Generate flashcmd.txt for signing images
	BOARDID="3448" FAB="${rev}" "${l4t_dir}/flash.sh" "--no-flash" "--no-systemimg" "p3448-0000-sd" "mmcblk0p1"

	if [ ! -f "${bootloader_dir}/flashcmd.txt" ]; then
		echo "ERROR: ${bootloader_dir}/flashcmd.txt not found" > /dev/stderr
		exit 1
	fi

	# Generate signed images
	sed -i 's/flash; reboot/sign/g' "${l4t_dir}/bootloader/flashcmd.txt"
	pushd "${bootloader_dir}" > /dev/null 2>&1
	bash ./flashcmd.txt
	popd > /dev/null

	if [ ! -d "${signed_image_dir}" ]; then
		echo "ERROR: ${bootloader_dir}/signed directory not found" > /dev/stderr
		exit 1
	fi
}

function create_partitions()
{
	echo "${script_name} - create partitions"

	partitions=(\
		'part_num=2;part_name=TBC;part_size=131072;part_file=nvtboot_cpu.bin.encrypt' \
		'part_num=3;part_name=RP1;part_size=458752;part_file=tegra210-p3448-0000-p3449-0000-${dtb_id}.dtb.encrypt' \
		'part_num=4;part_name=EBT;part_size=589824;part_file=cboot.bin.encrypt' \
		'part_num=5;part_name=WB0;part_size=65536;part_file=warmboot.bin.encrypt' \
		'part_num=6;part_name=BPF;part_size=196608;part_file=sc7entry-firmware.bin.encrypt' \
		'part_num=7;part_name=TOS;part_size=589824;part_file=tos-mon-only.img.encrypt' \
		'part_num=8;part_name=EKS;part_size=65536;part_file=eks.img' \
		'part_num=9;part_name=LNX;part_size=655360;part_file=boot.img.encrypt' \
		'part_num=10;part_name=DTB;part_size=458752;part_file=tegra210-p3448-0000-p3449-0000-${dtb_id}.dtb.encrypt' \
		'part_num=11;part_name=RP4;part_size=131072;part_file=rp4.blob' \
		'part_num=12;part_name=BMP;part_size=81920;part_file=bmp.blob' \
	)

	part_type=8300 # Linux Filesystem
	echo "declare -A partitions=(\\" > "${signed_image_dir}/partitions"
	for part in "${partitions[@]}"; do
		eval "$part"
		echo "[$part_name]='$part' \\" >> "${signed_image_dir}/partitions"
	done
	echo ")" >> "${signed_image_dir}/partitions"
}

script_name="$(basename "${0}")"
l4t_dir="$(cd "$(dirname "${0}")" && pwd)"
bootloader_dir="${l4t_dir}/bootloader"
signed_image_dir="${bootloader_dir}/signed"
dtb_id="a02"
loop_dev=""
tmpdir=""

echo "********************************************"
echo "     Jetson-Nano SD Image Creation Tool     "
echo "********************************************"

check_pre_req "${@}"
create_signed_images
create_partitions

echo "********************************************"
echo "   Jetson-Nano SD Image Creation Complete   "
echo "********************************************"
