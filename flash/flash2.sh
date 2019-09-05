#!/bin/bash

# Copyright (c) 2011-2019, NVIDIA CORPORATION.  All rights reserved.
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


#
# flash.sh: Flash the target board.
#	    flash.sh performs the best in LDK release environment.
#
# Usage: Place the board in recovery mode and run:
#
#	flash.sh [options] <target_board> <root_device>
#
#	for more detail enter 'flash.sh -h'
#
# Examples:
# ./flash.sh <target_board> internal			- boot <target_board> from on-board device (eMMC/SDCARD)
# ./flash.sh <target_board> external			- boot <target_board> from external device
# ./flash.sh <target_board> mmcblk0p1			- boot <target_board> from eMMC
# ./flash.sh <target_board> mmcblk1p1			- boot <target_board> from SDCARD
# ./flash.sh <target_board> sda1			- boot <target_board> from USB device
# ./flash.sh -N <IPaddr>:/nfsroot <target_board> eth0	- boot <target_board> from NFS
# ./flash.sh -k LNX <target_board> mmcblk1p1		- update <target_board> kernel
# ./flash.sh -k EBT <target_board> mmcblk1p1		- update <target_board> bootloader
#
# Optional Environment Variables:
# BCTFILE ---------------- Boot control table configuration file to be used.
# BOARDID ---------------- Pass boardid to override EEPROM value
# BOARDREV --------------- Pass board_revision to override EEPROM value
# BOARDSKU --------------- Pass board_sku to override EEPROM value
# BOOTLOADER ------------- Bootloader binary to be flashed
# BOOTPARTLIMIT ---------- GPT data limit. (== Max BCT size + PPT size)
# BOOTPARTSIZE ----------- Total eMMC HW boot partition size.
# CFGFILE ---------------- Partition table configuration file to be used.
# CMDLINE ---------------- Target cmdline. See help for more information.
# DEVSECTSIZE ------------ Device Sector size. (default = 512Byte).
# DTBFILE ---------------- Device Tree file to be used.
# EMMCSIZE --------------- Size of target device eMMC (boot0+boot1+user).
# FLASHAPP --------------- Flash application running in host machine.
# FLASHER ---------------- Flash server running in target machine.
# INITRD ----------------- Initrd image file to be flashed.
# KERNEL_IMAGE ----------- Linux kernel zImage file to be flashed.
# MTS -------------------- MTS file name such as mts_si.
# MTSPREBOOT ------------- MTS preboot file name such as mts_preboot_si.
# NFSARGS ---------------- Static Network assignments.
#			   <C-ipa>:<S-ipa>:<G-ipa>:<netmask>
# NFSROOT ---------------- NFSROOT i.e. <my IP addr>:/exported/rootfs_dir.
# ODMDATA ---------------- Odmdata to be used.
# PKCKEY ----------------- RSA key file to used to sign bootloader images.
# ROOTFSSIZE ------------- Linux RootFS size (internal emmc/nand only).
# ROOTFS_DIR ------------- Linux RootFS directory name.
# SBKKEY ----------------- SBK key file to used to encrypt bootloader images.
# SCEFILE ---------------- SCE firmware file such as camera-rtcpu-sce.img.
# SPEFILE ---------------- SPE firmware file path such as bootloader/spe.bin.
# FAB -------------------- Target board's FAB ID.
# TEGRABOOT -------------- lowerlayer bootloader such as nvtboot.bin.
# WB0BOOT ---------------- Warmboot code such as nvtbootwb0.bin
#
INFODIVIDER="\
###############################################################################\
";

chkerr ()
{
	if [ $? -ne 0 ]; then
		if [ "$1" != "" ]; then
			echo "$1";
		else
			echo "failed.";
		fi;
		exit 1;
	fi;
	if [ "$1" = "" ]; then
		echo "done.";
	fi;
}

pr_conf()
{
	echo "target_board=${target_board}";
	echo "target_rootdev=${target_rootdev}";
	echo "rootdev_type=${rootdev_type}";
	echo "rootfssize=${rootfssize}";
	echo "odmdata=${odmdata}";
	echo "flashapp=${flashapp}";
	echo "flasher=${flasher}";
	echo "bootloader=${bootloader}";
	echo "tegraboot=${tegraboot}";
	echo "wb0boot=${wb0boot}";
	echo "mtspreboot=${mtspreboot}";
	echo "mts=${mts}";
	echo "bctfile=${bctfile}";
	echo "cfgfile=${cfgfile}";
	echo "kernel_fs=${kernel_fs}";
	echo "kernel_image=${kernel_image}";
	echo "rootfs_dir=${rootfs_dir}";
	echo "nfsroot=${nfsroot}";
	echo "nfsargs=${nfsargs}";
	echo "kernelinitrd=${kernelinitrd}";
	echo "cmdline=${cmdline}";
	echo "boardid=${boardid}";
}

validateIP ()
{
	local ip=$1;
	local ret=1;

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=${IFS};
		IFS='.';
		ip=($ip);
		IFS=${OIFS};
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && \
		   ${ip[2]} -le 255 && ${ip[3]} -le 255 ]];
		ret=$?;
	fi;
	if [ ${ret} -ne 0 ]; then
		echo "Invalid IP address: $1";
		exit 1;
	fi;
}

netmasktbl=(\
	"255.255.255.252" \
	"255.255.255.248" \
	"255.255.255.240" \
	"255.255.255.224" \
	"255.255.255.192" \
	"255.255.255.128" \
	"255.255.255.0" \
	"255.255.254.0" \
	"255.255.252.0" \
	"255.255.248.0" \
	"255.255.240.0" \
	"255.255.224.0" \
	"255.255.192.0" \
	"255.255.128.0" \
	"255.255.0.0" \
	"255.254.0.0" \
	"255.252.0.0" \
	"255.248.0.0" \
	"255.240.0.0" \
	"255.224.0.0" \
	"255.192.0.0" \
	"255.128.0.0" \
	"255.0.0.0" \
);

validateNETMASK ()
{
	local i;
	local nm=$1;
	for (( i=0; i<${#netmasktbl[@]}; i++ )); do
		if [ "${nm}" = ${netmasktbl[$i]} ]; then
			return 0;
		fi;
	done;
	echo "Error: Invalid netmask($1)";
	exit 1;
}

validateNFSargs ()
{
	local a=$2;

	OIFS=${IFS};
	IFS=':';
	a=($a);
	IFS=${OIFS};

	if [ ${#a[@]} -ne 4 ]; then
		echo "Error: Invalid nfsargs($2)";
		exit 1;
	fi;
	validateIP ${a[0]};
	if [ "${serverip}" = "" ]; then
		validateIP ${a[1]};
	fi;
	validateIP ${a[2]};
	validateNETMASK ${a[3]};
	if [ "$1" != "" ]; then
		eval "$1=$2";
	fi;
	return 0;
}

validateNFSroot ()
{
	if [ "$2" = "" ]; then
		return 1;
	fi;
	OIFS=${IFS};
	IFS=':';
	local var=$1;
	local a=($2);
	IFS=${OIFS};
	if [ ${#a[@]} -ne 2 ]; then
		echo "Error: Invalid nfsroot($2)";
		exit 1;
	fi;
	validateIP ${a[0]};
	if [[ "${a[1]}" != /* ]]; then
		echo "Error: Invalid nfsroot($2)";
		exit 1;
	fi;
	eval "${var}=$2";
	return 0;
}

usage ()
{
	state=$1;
	retval=$2;

	if [[ $state == allunknown ]]; then
		echo -e "
Usage: sudo ./flash.sh [options] <target_board> <rootdev>
  Where,
	target board: Valid target board name.
	rootdev: Proper root device.";

	elif [[ $state == rootdevunknown ]]; then
		echo -e "
Usage: sudo ./flash.sh [options] ${target_board} <rootdev>
  Where,
    rootdev for ${target_board}:
	${ROOT_DEV}";

	else
		echo "
Usage: sudo ./flash.sh [options] ${target_board} ${target_rootdev}";
	fi;

	cat << EOF
    options:
        -b <bctfile> --------- Boot control table config file.
        -c <cfgfile> --------- Flash partition table config file.
        -d <dtbfile> --------- device tree file.
        -e <emmc size> ------- Target device's eMMC size.
        -f <flashapp> -------- Path to flash application (tegraflash.py)
        -h ------------------- print this message.
        -k <partition id> ---- partition name or number specified in flash.cfg.
        -m <mts preboot> ----- MTS preboot such as mts_preboot_si.
        -n <nfs args> -------- Static nfs network assignments
                               <Client IP>:<Server IP>:<Gateway IP>:<Netmask>
        -o <odmdata> --------- ODM data.
        -p <bp size> --------- Total eMMC HW boot partition size.
        -r ------------------- skip building and reuse existing system.img.
        -s <PKC key file>----- PKC key used for signing and building bl_update_payload.
                               (obsolete)
        -t <tegraboot> ------- tegraboot binary such as nvtboot.bin
        -u <PKC key file>----- PKC key used for odm fused board.
        -v <SBK key file>----- Secure Boot Key (SBK) key used for ODM fused board.
        -w <wb0boot> --------- warm boot binary such as nvtbootwb0.bin
        -x <tegraid> --------- Tegra CHIPID. default = 0x18(jetson-tx2)
                               0x21(jetson-tx1).
        -y <fusetype> -------- PKC for secureboot, NS for non-secureboot.
        -z <sn> -------------- Serial Number of target board.
        -B <boardid> --------- BoardId.
        -C <cmdline> --------- Kernel commandline arguments.
                               WARNING:
                               Each option in this kernel commandline gets
                               higher preference over the values set by
                               flash.sh. In case of NFS booting, this script
                               adds NFS booting related arguments, if -i option
                               is omitted.
        -F <flasher> --------- Flash server such as cboot.bin.
        -G <file name> ------- Read partition and save image to file.
        -I <initrd> ---------- initrd file. Null initrd is default.
        -K <kernel> ---------- Kernel image file such as zImage or Image.
        -L <bootloader> ------ Bootloader such as cboot.bin or u-boot-dtb.bin.
        -M <mts boot> -------- MTS boot file such as mts_si.
        -N <nfsroot> --------- i.e. <my IP addr>:/my/exported/nfs/rootfs.
        -P <end of PPT + 1> -- Primary GPT start address + size of PPT + 1.
        -R <rootfs dir> ------ Sample rootfs directory.
        -S <size> ------------ Rootfs size in bytes. Valid only for internal
                               rootdev. KiB, MiB, GiB short hands are allowed,
                               for example, 1GiB means 1024 * 1024 * 1024 bytes.
        --no-flash ----------- perform all steps except physically flashing the board.
                               This will create a system.img.
        --no-systemimg ------- Do not create or re-create system.img.
        --bup ---------------- Generate bootloader update payload(BUP).
        --multi-spec---------- Enable support for building multi-spec BUP.
        --clean-up------------ Clean up BUP buffer when multi-spec is enabled.
        --usb-instance <id> -- Specify the USB instance to connect to; integer
                               ID (e.g. 0, 1), bus/dev (e.g. 003/091), or USB
                               port path (e.g. 3-14). The latter is best.
		--no-reboot ---------- Don't reboot the device after flashing.
EOF
	exit $retval;
}

setdflt ()
{
	local var="$1";
	if [ "${!var}" = "" ]; then
		eval "${var}=$2";
	fi;
}

setval ()
{
	local var="$1";
	local val="$2";
	if [ "${!val}" = "" ]; then
		echo "Error: missing $val not defined.";
		exit 1;
	fi;
	eval "${var}=${!val}";
}

mkfilesoft ()
{
	local var="$1";
	local varname="$1name";

	eval "${var}=$2";
	if [ "${!var}" = "" -o ! -f "${!var}" ]; then
		if [ "$3" != "" -a -f "$3" ]; then
			eval "${var}=$3";
		fi;
	fi;
	if [ "${!var}" != "" ]; then
		if [ ! -f ${!var} ]; then
			eval "${var}=\"\"";
			eval "${varname}=\"\"";
			return 1;
		fi;
		eval "${var}=`readlink -f ${!var}`";
		eval "${varname}=`basename ${!var}`";
	fi;
	return 0;
}

mkfilepath ()
{
	local var="$1";
	local varname="$1name";

	eval "${var}=$2";
	setdflt "${var}" "$3";
	if [ "${!var}" != "" ]; then
		eval "${var}=`readlink -f ${!var}`";
		if [ ! -f "${!var}" ]; then
			echo "Error: missing $var (${!var}).";
			usage allknown 1;
		fi;
		eval "${varname}=`basename ${!var}`";
	fi;
}

mkdirpath ()
{
	local var="$1";
	eval "${var}=$2";
	setdflt "$1" "$3";
	if [ "${!var}" != "" ]; then
		eval "${var}=`readlink -f ${!var}`";
		if [ ! -d "${!var}" ]; then
			echo "Error: missing $var (${!var}).";
			usage allknown 1;
		fi;
	fi;
}

getsize ()
{
	local var="$1";
	local val="$2";
	if [[ ${!val} != *[!0-9]* ]]; then
		eval "${var}=${!val}";
	elif [[ (${!val} == *KiB) && (${!val} != *[!0-9]*KiB) ]]; then
		eval "${var}=$(( ${!val%KiB} * 1024 ))";
	elif [[ (${!val} == *MiB) && (${!val} != *[!0-9]*MiB) ]]; then
		eval "${var}=$(( ${!val%MiB} * 1024 * 1024 ))";
	elif [[ (${!val} == *GiB) && (${!val} != *[!0-9]*GiB) ]]; then
		eval "${var}=$(( ${!val%GiB} * 1024 * 1024 * 1024))";
	else
		echo "Error: Invalid $1: ${!val}";
		exit 1;
	fi;
}

validatePartID ()
{
	local idx=0;
	declare -A cf;

	while read aline; do
		if [ "$aline" != "" ]; then
			arr=( $(echo $aline | tr '=' ' ') );
			if [ "${arr[1]}" == "name" ]; then
				if [ "${arr[3]}" == "id" ]; then
					cf[$idx,1]="${arr[2]}";
					cf[$idx,0]="${arr[4]}";
				else
					cf[$idx,0]="${arr[2]}";
				fi
				idx=$((idx+1));
			fi
		fi;
	done < $4;

	if [ "${arr[3]}" == "id" ]; then
		for ((i = 0; i < idx; i++)) do
			if [ "\"$3\"" = "${cf[$i,0]}" -o  \
			     "\"$3\"" = "${cf[$i,1]}" ]; then
				eval "$1=${cf[$i,0]}";
				eval "$2=${cf[$i,1]}";
			return 0;
			fi;
		done;
		echo "Error: invalid partition id ($3)";
		exit 1;
	else
		return 0;
	fi;
}

cp2local ()
{
	local src=$1;
	if [ "${!src}" = "" ]; then return 1; fi;
	if [ ! -f "${!src}" ]; then return 1; fi;
	if [ "$2" = "" ];      then return 1; fi;
	if [ -f $2 -a ${!src} = $2 ]; then
		local sum1=`sum ${!src}`;
		local sum2=`sum $2`;
		if [ "$sum1" = "$sum2" ]; then
			echo "Existing ${src}($2) reused.";
			return 0;
		fi;
	fi;
	echo -n "copying ${src}(${!src})... ";
	cp -f ${!src} $2;
	chkerr;
	return 0;
}

chsuffix ()
{
	local var="$1";
	local fname=`basename "$2"`;
	local OIFS=${IFS};
	IFS='.';
	na=($fname);
	IFS=${OIFS};
	eval "${var}=${na[0]}.${3}";
}

build_fsimg ()
{
	echo "Making $1... ";

	local bcnt=$(( $3 / 512 ));
	local bcntdiv=$(( $3 % 512 ));
	if [ $bcnt -eq 0 -o $bcntdiv -ne 0 ]; then
		echo "Error: $4 file system size has to be 512 bytes allign.";
		exit 1;
	fi
	if [ "$2" != "" -a "$2" != "0" ]; then
		local fc=`printf '%d' $2`;
		local fillc=`printf \\\\$(printf '%02o' $fc)`;
		< /dev/zero head -c $3 | tr '\000' ${fillc} > $1;
		chkerr "making $1 with fillpattern($fillc}) failed.";
	else
		truncate --size $3 $1;
		chkerr "making $1 with zero fillpattern failed.";
	fi;
	loop_dev="$(losetup --show -f "$1")";
	chkerr "mapping $1 to loop device failed.";
	if [ "$4" = "FAT32" ]; then
		mkfs.msdos -I -F 32 "${loop_dev}" > /dev/null 2>&1;
	else
		mkfs -t $4 "${loop_dev}" > /dev/null 2>&1;
	fi;
	chkerr "formating $4 filesystem on $1 failed.";
	mkdir -p mnt;		chkerr "make $4 mount point failed.";
	mount "${loop_dev}" mnt;	chkerr "mount $1 failed.";
	mkdir -p mnt/boot/dtb;	chkerr "make $1/boot/dtb failed.";
	cp -f "${kernel_fs}" mnt/boot;
	chkerr "Copying ${kernel_fs} failed.";
	if [ -f "${dtbfilename}" ]; then
		cp -f "${dtbfilename}" "mnt/boot/dtb/${dtbfilename}";
		chkerr "populating ${dtbfilename} to $1/boot/dtb failed.";
	fi;
	if [ "$4" = "FAT32" ]; then
		touch -f mnt/boot/cmdline.txt > /dev/null 2&>1;
		chkerr "Creating cmdline.txt failed.";
	fi;
	if [ "$5" != "" ]; then
		pushd mnt > /dev/null 2>&1;
		echo -n -e "\tpopulating rootfs from $5 ... ";
		(cd $5; tar cf - *) | tar xf - ; chkerr;
		popd > /dev/null 2>&1;
	fi;
	echo -e -n "\tSync'ing $1 ... ";
	sync; sync; sleep 5;	# Give FileBrowser time to terminate gracefully.
	echo "done.";
	umount "${loop_dev}" > /dev/null 2>&1;
	losetup -d "${loop_dev}" > /dev/null 2>&1;
	rmdir mnt > /dev/null 2>&1;

	if [ "$2" != "" -a -x mksparse ]; then
		echo -e "\tConverting RAW image to Sparse image... ";
		mv -f $1 $1.raw;
		if [ "${BLBlockSize}" != "" ]; then
			blblksizeoption="-b $BLBlockSize";
		fi;
		./mksparse ${blblksizeoption} -v --fillpattern=$2 $1.raw $1; chkerr;
	fi;
	echo "$1 built successfully. ";
}

append_bootargs_to_dtb ()
{
	local trgdtbfilename="${1}";

	dtc -I dtb -O dts "${trgdtbfilename}" -o temp.dts;
	sed -i '/bootargs/d' temp.dts;
	sed -i "/chosen {/ a \\\t\\tbootargs=\"${cmdline} \";" temp.dts;
	dtc -I dts -O dtb temp.dts -o "${trgdtbfilename}";
	rm temp.dts;
}

get_fuse_level ()
{
	local ECID;
	local rcmcmd;
	local inst_args="";
	local idval_1="";
	local idval_2="";
	local flval="";
	local baval="None";
	local flvar="$1";
	local hivar="$2";
	local bavar="$3";

	if [ -f "${BL_DIR}/tegrarcm_v2" ]; then
		rcmcmd="tegrarcm_v2";
	elif [ -f "${BL_DIR}/tegrarcm" ]; then
		rcmcmd="tegrarcm";
	else
		echo "Error: tegrarcm is missing.";
		exit 1;
	fi;
	if [ -n "${usb_instance}" ]; then
		inst_args="--instance ${usb_instance}";
	fi;
	pushd "${BL_DIR}" > /dev/null 2>&1;
	ECID=$(./${rcmcmd} ${inst_args} --uid | grep BR_CID | cut -d' ' -f2);
	popd > /dev/null 2>&1;
	if [ "${ECID}" != "" ]; then
		idval_1="0x${ECID:3:2}";
		eval "${hivar}=\"${idval_1}\"";
		idval_2="0x${ECID:6:2}";

		flval="${ECID:2:1}";
		baval="";
		if [ "${idval_1}" = "0x21" -o "${idval_1}" = "0x12" -o \
			"${idval_1}" = "0x00" -a "${idval_2}" = "0x21" ]; then
			case ${flval} in
			0|1|2) flval="fuselevel_nofuse"; ;;
			3)     flval="fuselevel_production"; ;;
			4)     flval="fuselevel_production"; baval="NS"; ;;
			5)     flval="fuselevel_production"; baval="SBK"; ;;
			6)     flval="fuselevel_production"; baval="PKC"; ;;
			*)     flval="fuselevel_unknown"; ;;
			esac;
			SKIPUID="--skipuid";
			if [ "${idval_1}" = "0x00" ]; then
				eval "${hivar}=\"${idval_2}\"";
			fi;
		elif [ "${idval_1}" = "0x80" ]; then
			if [ "${idval_2}" = "0x19" ]; then
				case ${flval} in
				0|1|2) flval="fuselevel_nofuse"; ;;
				8)     flval="fuselevel_production"; baval="NS"; ;;
				9)     flval="fuselevel_production"; baval="PKC"; ;;
				d)     flval="fuselevel_production"; baval="SBKPKC"; ;;
				esac;
				SKIPUID="--skipuid";
				hwchipid="0x19";
				hwchiprev="${ECID:5:1}";
			fi
		else
			case ${flval} in
			0|1|2) flval="fuselevel_nofuse"; ;;
			8|c)   flval="fuselevel_production"; baval="NS"; ;;
			9|d)   flval="fuselevel_production"; baval="SBK"; ;;
			a)     flval="fuselevel_production"; baval="PKC"; ;;
			e)     flval="fuselevel_production"; baval="SBKPKC"; ;;
			*)     flval="fuselevel_unknown"; ;;
			esac;
		fi;
		eval "${flvar}=\"${flval}\"";
		eval "${bavar}=\"${baval}\"";
	fi;
}

function get_full_path ()
{
	local val="$1";
	local result="$2";
	local fullpath;
	fullpath=$(readlink -f ${val});	# null if path is invalid
	if [ "${fullpath}" == "" ]; then
		echo "Invalid path/filename ${val}";
		exit 1;
	fi;
	eval "${result}=${fullpath}";
}

#
# XXX: This EEPROM read shall be replaced with new FAB agnostic function.
#
get_board_version ()
{
	local args="";
	local __board_id=$1;
	local __board_version=$2;
	local __board_sku=$3;
	local __board_revision=$4;
	local command="dump eeprom boardinfo cvm.bin"
	local boardid;
	local boardversion;
	local boardsku;
	local boardrevision;
	if [ -n "${usb_instance}" ]; then
		args+="--instance ${usb_instance} ";
	fi;
	if [ "${CHIPMAJOR}" != "" ]; then
		args+="--chip \"${CHIPID} ${CHIPMAJOR}\" ";
	else
		args+="--chip ${CHIPID} ";
	fi;
	args+="--applet \"${LDK_DIR}/${SOSFILE}\" ";
	args+="${SKIPUID} ";
	SKIPUID="";
	if [ "${CHIPID}" = "0x19" ]; then
		mkfilesoft soft_fuses     "${TARGET_DIR}/BCT/${SOFT_FUSES}";
		cp2local soft_fuses "${BL_DIR}/${soft_fusesname}";
		args+="--soft_fuses ${soft_fusesname} "
		args+="--bins \"mb2_applet ${MB2APPLET}\" ";
		command+=";reboot recovery"
	fi
	args+="--cmd \"${command}\" ";
	local cmd="./tegraflash.py ${args}";
	pushd "${BL_DIR}" > /dev/null 2>&1;
	if [ "${keyfile}" != "" ]; then
		cmd+="--key \"${keyfile}\" ";
	fi;
	echo "${cmd}";
	eval "${cmd}";
	chkerr "Reading board information failed.";
	if [ "${SKIP_EEPROM_CHECK}" = "" ]; then
		boardid=`./chkbdinfo -i cvm.bin`;
		boardversion=`./chkbdinfo -f cvm.bin`;
		boardsku=`./chkbdinfo -k cvm.bin`;
		boardrevision=`./chkbdinfo -r cvm.bin`;
		chkerr "Parsing board information failed.";
	fi;
	popd > /dev/null 2>&1;
	eval ${__board_id}="${boardid}";
	eval ${__board_version}="${boardversion}";
	eval ${__board_sku}="${boardsku}";
	eval ${__board_revision}="${boardrevision}";
}

#
# EEPROM get board S/N .
#
boardinfo_trk ()
{
	local boardinforom;
	local boardpartnu;
	if [[ -e "${LDK_DIR}/nv_internal_trk.sh" &&
		-e "${BL_DIR}/chkbdinfo" &&
		-e "${BL_DIR}/cvm.bin" ]]; then
		pushd "${BL_DIR}" > /dev/null 2>&1;
		boardinforom=`./chkbdinfo -a cvm.bin`;
		boardpartnu=`./chkbdinfo -p cvm.bin`;
		if [[ "${boardinforom}" != ""] && ["${boardpartnu}" != "" ]]; then
			eval PRODUCT_OUT="${LDK_DIR}" "${LDK_DIR}/nv_internal_trk.sh" "${boardinforom}" "${boardpartnu}";
		fi
		popd > /dev/null 2>&1;
	fi
}

#
# SoC Sanity Check:
#
chk_soc_sanity ()
{
	local mach_dir="";
	local socname="Unknown";
	local opmode="Unknown";

	if [ "${hwchipid}" = "" ]; then
		# Nothing to check against. Just let it go.
		echo "Error: probing the target board failed.";
		echo "       Make sure the target board is connected through ";
		echo "       USB port and is in recovery mode.";
		exit 1;
	fi;

	#
	# Print Target Board Information:
	# NOTE: The list of board listed here may or may not be
	#	supported by the version of BSP(Board Support Package)
	#	that provides this copy of the script. This lists all
	#	of the publicly available Jetson developer platforms.
	#
	case ${hwchipid} in
	0x21) socname="Tegra 210"; mach_dir="t210ref"; ;;
	0x18) socname="Tegra 186"; mach_dir="t186ref"; ;;
	0x19) socname="Tegra 194"; mach_dir="t186ref"; ;;
	esac;

	case ${fuselevel} in
	fuselevel_nofuse) opmode="pre-production"; ;;
	fuselevel_production) opmode="production"; ;;
	esac;

	echo	"# Target Board Information:";
	echo -n "# Name: ${ext_target_board}, Board Family: ${target_board}, ";
	echo	"SoC: ${socname}, ";
	echo	"# OpMode: ${opmode}, Boot Authentication: ${bootauth}, ";
	echo	"${INFODIVIDER}";

	if [ "${CHIPID}" != "" -a "${CHIPID}" != "${hwchipid}" ]; then
		echo -n "Error: The Actual SoC ID(${hwchipid}) ";
		echo -n "mismatches intended ${ext_target_board} ";
		echo "SoC ID(${CHIPID}).";
		exit 1;
	fi;

	if [ "${target_board}" != "${mach_dir}" ]; then
		echo -n "Error: The Actual board family (${mach_dir}) ";
		echo -n "mismatches intended ${ext_target_board} ";
		echo "board family(${target_board}).";
		exit 1;
	fi;

	case ${bootauth} in
	PKC)
		if [ "${keyfile}" = "" ] || [ "${sbk_keyfile}" != "" ]; then
			echo -n "Error: Either RSA key file is not proviced or SBK key ";
			echo "file is provided for PKC protected target board.";
			exit 1;
		fi;
		;;
	SBKPKC)
		if [ "${keyfile}" = "" ] || [ "${sbk_keyfile}" = "" ]; then
			echo -n "Error: Either RSA key file and/or SBK key file ";
			echo "is not proviced for SBK and PKC protected target board.";
			exit 1;
		fi;
		;;
	SBK)
		echo "Error: L4T does not support SBK protected target board.";
		exit 1;
		;;
	NS)
		if [ "${keyfile}" != "" ] || [ "${sbk_keyfile}" != "" ]; then
			echo -n "Error: either RSA key file and/or SBK key file ";
			echo "are proviced for none SBK and PKC protected target board.";
			exit 1;
		fi;
		;;
	*)
		if [ "${dbmaster}" != "" ]; then
			echo -n "Error: The RSA key file is provided for ";
			echo "non-PKC protected target board.";
			exit 1;
		fi;
		;;
	esac;
}

function rootuuid_gen {
	local uuidgen_installed="$(which uuidgen || true)"

	if [ "${uuidgen_installed}" == "" ]; then
		echo "Error: uuidgen not installed! Please provide the UUID or install"
		echo "uuidgen. For example, to install uuidgen for Ubuntu distributions,"
		echo "execute the command 'sudo apt install uuid-runtime'. Otherwise a"
		echo "UUID can be provided by storing a UUID to the file"
		echo "${rootfsuuidfile}."
		usage allunknown 1;
	fi

	rootfsuuid="$(uuidgen)"

	echo "${rootfsuuid}" > "${rootfsuuidfile}"
	echo "Generated UUID ${rootfsuuid} for mounting root partition."
}

function rootuuid_restore {
	local uuid_regex="([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"

	rootfsuuid="$(sed -nr "s/^${uuid_regex}$/\1/p" "${rootfsuuidfile}")"

	if [ "${#rootfsuuid}" != "36" ]; then
		echo "File ${rootfsuuidfile} contains invalid UUID!"
		usage allunknown 1;
	fi

	echo "Using UUID ${rootfsuuid} for mounting root partition."
}

function signimage() {
	pushd "${rootfs_dir}/boot" > /dev/null 2>&1
	${LDK_DIR}/l4t_sign_image.sh \
		--file "${rootfs_dir}/boot/$(basename "$1")" \
		--key "${keyfile}" --chip "${tegraid}";
	chkerr;
	popd > /dev/null 2>&1
}

if [ $# -lt 2 ]; then
	usage allunknown 1;
fi;

nargs=$#;
target_rootdev=${!nargs};
nargs=$(($nargs-1));
ext_target_board=${!nargs};

# NV internal
_nvbrd_trk=0

if [ ! -r ${ext_target_board}.conf ]; then
	echo "Error: Invalid target board - ${ext_target_board}.";
	usage allunknown 1;
fi

# set up LDK_DIR path
LDK_DIR=$(cd `dirname $0` && pwd);
LDK_DIR=`readlink -f "${LDK_DIR}"`;

source ${ext_target_board}.conf

# set up path variables
BL_DIR="${LDK_DIR}/bootloader";
TARGET_DIR="${BL_DIR}/${target_board}";
KERNEL_DIR="${LDK_DIR}/kernel";
export PATH="${KERNEL_DIR}:${PATH}";		# preference on our DTC
DTB_DIR="${KERNEL_DIR}/dtb";
if [ "${BINSARGS}" = "" -a "${BINS}" != "" ]; then			#COMPAT
	BINARGS="--bins \"";						#COMPAT
fi;									#COMPAT
if [ "${BINSARGS}" != "" ]; then
	SKIPUID="--skipuid";
fi;

# Print BSP Info:
#
echo "${INFODIVIDER}";
echo "# L4T BSP Information:";
if [ -f "${LDK_DIR}/nv_tegra/bsp_version" ]; then
	source "${LDK_DIR}/nv_tegra/bsp_version"
	echo "# R${BSP_BRANCH} , REVISION: ${BSP_MAJOR}.${BSP_MINOR}"
elif [ -f "${LDK_DIR}/rootfs/etc/nv_tegra_release" ]; then
	head -n1 "${LDK_DIR}/rootfs/etc/nv_tegra_release" | \
		sed -e s/DATE:/\\n\#\ DATE:/;
else
	echo "# Unknown Release";
fi;
echo "${INFODIVIDER}";

# Determine rootdev_type
#
rootdev_type="external";
if [[ "${target_rootdev}" == "internal" || "${target_rootdev}" == mmcblk0p* || \
      "${target_rootdev}" == ${BOOTDEV} ]]; then
	rootdev_type="internal";
	INITRD="";
elif [ "${target_rootdev}" = "eth0" -o "${target_rootdev}" = "eth1" ]; then
	rootdev_type="network";
elif [[ "${target_rootdev}" != "external" && "${target_rootdev}" != mmcblk1p* && \
	"${target_rootdev}" != sd* ]]; then
	echo "Error: Invalid target rootdev($target_rootdev).";
	usage rootdevunknown 1;
fi;

rootfsuuid="";
rootfsuuidfile="${BL_DIR}/l4t-rootfs-uuid.txt"
read_part_name="";
rcm_boot=0;
no_flash=0;
no_systemimg=0;
reboot_recovery=0;
bup_blob=0;
support_multi_spec=0;
clean_up=0;
PKCKEY="";
opstr+="b:c:d:e:f:hk:m:n:o:p:rs:t:u:v:w:x:y:z:B:C:F:G:I:K:L:M:N:P:R:S:Z:-:";
while getopts "${opstr}" OPTION; do
	case $OPTION in
	b) BCTFILE=${OPTARG}; ;;
	c) CFGFILE=${OPTARG}; ;;
	d) DTBFILE=${OPTARG}; ;;
	e) EMMCSIZE=${OPTARG}; ;;
	f) FLASHAPP=${OPTARG}; ;;
	h) usage allunknown 0; ;;
	k) target_partname=${OPTARG}; ;;	# cmdline only
	m) MTSPREBOOT=${OPTARG}; ;;
	n) NFSARGS=${OPTARG}; ;;
	o) ODMDATA=${OPTARG}; ;;
	p) BOOTPARTSIZE=${OPTARG}; ;;
	r) reuse_systemimg="true"; ;;		# cmdline only
	s) PKCKEY=${OPTARG}; ;;
	t) TEGRABOOT=${OPTARG}; ;;
	u) dbmaster="${OPTARG}"; ;;
	v) SBKKEY=${OPTARG}; ;;
	w) WB0BOOT=${OPTARG}; ;;
	x) tegraid=${OPTARG}; ;;
	y) fusetype=${OPTARG}; ;;
	z) sn=${OPTARG}; ;;
	B) BOARDID=${OPTARG}; ;;
	C) CMDLINE="${OPTARG}"; ;;
	F) FLASHER=${OPTARG}; ;;
	G) read_part_name=${OPTARG}; ;;
	I) INITRD=${OPTARG}; ;;
	K) KERNEL_IMAGE=${OPTARG}; ;;
	L) BOOTLOADER=${OPTARG}; ;;
	M) MTS=${OPTARG}; ;;
	N) NFSROOT=${OPTARG}; ;;
	P) BOOTPARTLIMIT=${OPTARG}; ;;
	R) ROOTFS_DIR=${OPTARG}; ;;
	S) ROOTFSSIZE=${OPTARG}; ;;
	Z) zflag="true"; ;;			# cmdline only
	-) case ${OPTARG} in
	   no-flash) no_flash=1; ;;
	   no-systemimg) no_systemimg=1; ;;
	   reboot-recovery) reboot_recovery=1 ;;
	   rcm-boot) rcm_boot=1; ;;
	   bup) bup_blob=1; ;;
	   multi-spec) support_multi_spec=1; ;;
	   clean-up) clean_up=1; ;;
	   usb-instance)
		usb_instance="${!OPTIND}";
		OPTIND=$(($OPTIND + 1));
		;;
	   image)
		write_image_name="${!OPTIND}";
		OPTIND=$(($OPTIND + 1));
		;;
	   esac;;
	*) usage allunknown 1; ;;
	esac;
done

# allow payload generation to happen without sudo option
if [ ${bup_blob} -eq 0 ]; then
	# if the user is not root, there is not point in going forward
	if [ "${USER}" != "root" ]; then
		echo "flash.sh requires root privilege";
		exit 1;
	fi
fi

#
# -s option is obsolete and is repleced by -u option.
# However, to be compatible with earlier release, -s should still be handled
#
#  If -u is present, simply ignore -s
#  If -u is absent, assign value from -s to -u
#
if [ "${PKCKEY}" != "" ] && [ "${dbmaster}" = "" ]; then
	dbmaster="${PKCKEY}";
fi;

# get key file if -u option provided
keyfile="";
if [ "${dbmaster}" != "" ]; then
	if [[ ${dbmaster} =~ ^/ ]]; then
		keyfile="${dbmaster}";
	else
		keyfile=`readlink -f "${dbmaster}"`;
	fi;
	if [ ! -f "${keyfile}" ]; then
		echo "Error: keyfile ${keyfile} not found";
		exit 1;
	fi;
fi;

# get sbk key file if -v option provided
sbk_keyfile="";
if [ "${SBKKEY}" != "" ]; then
	# when sbk key is present, pkc key must be present
	if [ "${keyfile}" = "" ]; then
		echo "Error: missing PKC key; try -u";
		exit 1;
	fi;

	sbk_keyfile=`readlink -f "${SBKKEY}"`;
	if [ ! -f "${sbk_keyfile}" ]; then
		echo "Error: keyfile ${sbk_keyfile} not found";
		exit 1;
	fi;
fi;

# get the fuse level and update the data accordingly
fuselevel="${FUSELEVEL}";
hwchipid="";
hwchiprev="${CHIPREV}";
if [ "${hwchiprev}" = "" ]; then
	hwchiprev="0";
fi;
bootauth="";
if [ "${fuselevel}" = "" ]; then
	get_fuse_level fuselevel hwchipid bootauth;
	# fuselevel_unknown or empty will be handled as fuselevel_production
	if [ "${fuselevel}" = "fuselevel_unknown" ] || [ "${fuselevel}" = "" ]; then
		fuselevel="fuselevel_production";
	fi;
else
	# can not "--skipuid" when function get_fuse_level is skipped.
	SKIPUID="";
fi;

declare -F -f process_fuse_level > /dev/null 2>&1;
if [ $? -eq 0 ]; then
	process_fuse_level "${fuselevel}";
fi;

#
# Handle -G option for reading partition image to file
#
if [ "${read_part_name}" != "" ]; then
	# Exit if no -k option
	if [ "${target_partname}" = "" ]; then
		echo "Error: missing -k option to specify partition name";
		exit 1;
	fi
	# Exit if --image option is provided for write partition
	if [ "${write_image_name}" != "" ]; then
		echo "Error: not support to write partition while reading partition";
		exit 1;
	fi
	# Exit if path is invalid
	get_full_path ${read_part_name} read_part_name;
fi;

#
# Handle --image option for writing image to specified partition
#
if [ "${write_image_name}" != "" ]; then
	# Exit if no -k option
	if [ "${target_partname}" = "" ]; then
		echo "Error: missing -k option to specify partition name";
		exit 1;
	fi
	# Exit if file does not exist
	if [ ! -f "${write_image_name}" ]; then
		echo "Error: ${write_image_name} does not exist";
		exit 1;
	fi;
	# Exit if path is invalid
	get_full_path ${write_image_name} write_image_name;
fi;

# SoC Sanity Check
if [ ${no_flash} -eq 0 ]; then
	chk_soc_sanity;
fi;

# get the board version and update the data accordingly
declare -F -f process_board_version > /dev/null 2>&1;
if [ $? -eq 0 ]; then
	board_version="${FAB}";
	board_id="${BOARDID}";
	board_sku="${BOARDSKU}";
	board_revision="${BOARDREV}";
	if [ "${board_version}" == "" ]; then
		if [ "${hwchipid}" != "" ]; then
			get_board_version board_id board_version board_sku board_revision;
			_nvbrd_trk=1;
			BOARDID="${board_id}";
			BOARDSKU="${board_sku}";
			FAB="${board_version}";
			BOARDREV="${board_revision}";
		fi;
	fi;
	process_board_version "${board_id}" "${board_version}" "${board_sku}" "${board_revision}" "${hwchiprev}";
fi;

# convert fuselevel to digit string
if [ "${fuselevel}" == "fuselevel_nofuse" ]; then
	fuselevel_s="0";
else
	fuselevel_s="1";
fi;

# Set board spec: BOARD_ID-FAB-BOARDSKU-BOARDREV-NV_PRODUCTION-CHIP_REV-BOARD_NAME-ROOTFS_DEV
if [[ "${CHIPID}" == "0x21" ]]; then
	# For T210, the board_sku and board_rev are not neccessary,
	# and when creating SD card image, it's offline, can't know
	# these information.
	BOARDSKU=""
	BOARDREV=""
fi
spec="${BOARDID}-${FAB}-${BOARDSKU}-${BOARDREV}-${fuselevel_s}-${hwchiprev}-${ext_target_board}-${target_rootdev}";
# Make sure spec length is less than maximum supported by BUP (64)
MAX_SPEC_LEN=64
if ((${#spec} > ${MAX_SPEC_LEN})); then
	echo "Error: spec length exceeds ${MAX_SPEC_LEN}, ${spec}(len=${#spec})"
	exit 1
fi;

# get board SN and Part
if [ ${_nvbrd_trk} -ne 0 ]; then
	timeout 10s cat <(boardinfo_trk);
fi;

###########################################################################
# System default values: should be defined AFTER target_board value.
#
ROOTFS_TYPE="${ROOTFS_TYPE:-ext4}";
DEVSECTSIZE="${DEVSECTSIZE:-512}";		# default sector size = 512
BOOTPARTLIMIT="${BOOTPARTLIMIT:-10485760}";	# 1MiB limit
ACR_TYPE="${ACR_TYPE:-acr-debug}";		# default is acr-debug
fillpat="${FSFILLPATTERN:-0}";			# no cmdline: default=0
boardid="${BOARDID}";
if [ "${tegraid}" = "" ]; then
	tegraid="${CHIPID}";
fi;

if [ -z "${DFLT_KERNEL}" ]; then
	DFLT_KERNEL=${KERNEL_DIR}/Image;
else
	basekernel=`basename "${DFLT_KERNEL}"`;
	if [ "${DFLT_KERNEL}" = "${basekernel}" ]; then
		DFLT_KERNEL="${KERNEL_DIR}/${DFLT_KERNEL}";
	fi;
fi;
if [ -z "${DFLT_KERNEL_FS}" ]; then
	DFLT_KERNEL_FS=${DFLT_KERNEL};
fi;
if [ -z "${DFLT_KERNEL_IMAGE}" ]; then
	DFLT_KERNEL_IMAGE=${DFLT_KERNEL};
fi;

###########################################################################
# System mandatory vars:
#
setval     odmdata	ODMDATA;	# .conf mandatory
setval     rootfs_type	ROOTFS_TYPE;
setval     devsectsize	DEVSECTSIZE;
getsize    rootfssize	ROOTFSSIZE;	# .conf mandatory
getsize    emmcsize	EMMCSIZE;	# .conf mandatory
getsize    bootpartsize	BOOTPARTSIZE;	# .conf mandatory
getsize    bootpartlim	BOOTPARTLIMIT;
mkfilepath flashapp	"${FLASHAPP}"	"${BL_DIR}/tegraflash.py";
mkfilepath flasher	"${FLASHER}"	"${BL_DIR}/cboot.bin";
mkfilepath bootloader	"${BOOTLOADER}"	"${BL_DIR}/cboot.bin";
mkdirpath  rootfs_dir	"${ROOTFS_DIR}"	"${LDK_DIR}/rootfs";
mkfilepath kernel_image	"$KERNEL_IMAGE" "${DFLT_KERNEL_IMAGE}";
mkfilepath kernel_fs	"$KERNEL_IMAGE" "${DFLT_KERNEL_FS}";
mkfilepath bctfile	"${BCTFILE}"	"${TARGET_DIR}/BCT/${EMMC_BCT}";
if [ "${CHIPID}" = "0x19" ]; then
	mkfilepath bctfile1	"${BCTFILE1}"	"${TARGET_DIR}/BCT/${EMMC_BCT1}";
fi;
mkfilepath cfgfile	"${CFGFILE}"	"${TARGET_DIR}/cfg/${EMMC_CFG}";
mkfilepath dtbfile	"${DTBFILE}"	"${DTB_DIR}/${DTB_FILE}";

mkfilesoft kernelinitrd	""	"${BL_DIR}/l4t_initrd.img";
mkfilesoft tegraboot	"${TEGRABOOT}"	"${TARGET_DIR}/nvtboot.bin";
mkfilesoft wb0boot	"${WB0BOOT}"	"${TARGET_DIR}/nvtbootwb0.bin";
mkfilesoft cpu_bootloader	"${BOOTLOADER}"	"";
mkfilesoft mtspreboot	"${MTSPREBOOT}"	"${BL_DIR}/mts_preboot_si";
mkfilesoft mcepreboot	"${MTS_MCE}"	"${BL_DIR}/${MTS_MCE}";
mkfilesoft mtsproper	"${MTSPROPER}"	"${BL_DIR}/${MTSPROPER}";
mkfilesoft mts		"${MTS}"	"${BL_DIR}/mts_si";
mkfilesoft mb1file	"${MB1FILE}"	"${BL_DIR}/mb1_prod.bin";
if [ "${BPFFILE}" != "" -a \
	"${BPFBASEFILE}" != "" -a "${BPFBASEDTBFILE}" != "" -a \
	-f "${BPFBASEFILE}" -a -f "${BPFBASEDTBFILE}" ]; then
	cat "${BPFBASEFILE}" "${BPFBASEDTBFILE}" > "${BPFFILE}";
fi;
mkfilesoft bpffile	"${BPFFILE}"	"${BL_DIR}/bpmp.bin";
mkfilesoft bpfdtbfile	"${BPFDTBFILE}" "${TARGET_DIR}/${BPFDTB_FILE}";
if [ "${bpfdtbfile}" = "" -a "${BPMPDTB_FILE}" != "" ]; then		#COMPAT
	mkfilesoft bpfdtbfile	"${BL_DIR}/${BPMPDTB_FILE}"	"";	#COMPAT
fi;									#COMPAT
mkfilesoft nctfile	"${NCTFILE}"	"${TARGET_DIR}/cfg/${NCT_FILE}";
mkfilesoft tosfile	"${TOSFILE}"	"${TARGET_DIR}/tos.img";
mkfilesoft eksfile	"${EKSFILE}"	"${TARGET_DIR}/eks.img";
mkfilesoft fbfile	"${FBFILE}"	"${BL_DIR}/${FBFILE}";
mkfilesoft bcffile	"${BCFFILE}"	"";
mkfilesoft sosfile	"${SOSFILE}"	"";
mkfilesoft mb2blfile	"${MB2BLFILE}"	"";
mkfilesoft scefile	"${SCEFILE}"	"${BL_DIR}/camera-rtcpu-sce.img";
mkfilesoft camerafw	"${CAMERAFW}"	"";
mkfilesoft spefile	"${SPEFILE}"	"${BL_DIR}/spe.bin";
mkfilesoft drameccfile	"${DRAMECCFILE}"	"${BL_DIR}/dram-ecc.bin";
if [ ! -f "${BL_DIR}/badpage.bin" ]; then
	echo "creating dummy ${BL_DIR}/badpage.bin"
	dd if=/dev/zero of="${BL_DIR}/badpage.bin" bs=4096 count=1;
fi;
mkfilesoft badpagefile	"${BADPAGEFILE}"	"${BL_DIR}/badpage.bin";
mkfilesoft uphy_config    "${TARGET_DIR}/BCT/${UPHY_CONFIG}" "";
mkfilesoft device_config  "${TARGET_DIR}/BCT/${DEVICE_CONFIG}" "";
mkfilesoft misc_cold_boot_config    "${TARGET_DIR}/BCT/${MISC_COLD_BOOT_CONFIG}" "";
mkfilesoft misc_config    "${TARGET_DIR}/BCT/${MISC_CONFIG}" "";
mkfilesoft pinmux_config  "${TARGET_DIR}/BCT/${PINMUX_CONFIG}" "";
mkfilesoft gpioint_config  "${TARGET_DIR}/BCT/${GPIOINT_CONFIG}" "";
mkfilesoft pmic_config    "${TARGET_DIR}/BCT/${PMIC_CONFIG}" "";
mkfilesoft pmc_config     "${TARGET_DIR}/BCT/${PMC_CONFIG}" "";
mkfilesoft prod_config    "${TARGET_DIR}/BCT/${PROD_CONFIG}" "";
mkfilesoft scr_config     "${TARGET_DIR}/BCT/${SCR_CONFIG}" "";
mkfilesoft scr_cold_boot_config     "${TARGET_DIR}/BCT/${SCR_COLD_BOOT_CONFIG}" "";
mkfilesoft dev_params     "${TARGET_DIR}/BCT/${DEV_PARAMS}" "";
mkfilesoft bootrom_config "${TARGET_DIR}/BCT/${BOOTROM_CONFIG}" "";
mkfilesoft soft_fuses     "${TARGET_DIR}/BCT/${SOFT_FUSES}" "";
mkfilesoft tbcfile	"${TBCFILE}"	 "";
mkfilesoft tbcdtbfile	"${TBCDTB_FILE}" "${DTB_DIR}/${DTB_FILE}";
mkfilesoft cbootoptionfile	"${CBOOTOPTION_FILE}"	"${TARGET_DIR}/cbo.dtb";

if [ "${rootdev_type}" = "network" ]; then
	if [ "${NFSROOT}" = "" -a "${NFSARGS}" = "" ]; then
		echo "Error: network argument(s) missing.";
		usage allknown 1;
	fi;
	if [ "${NFSROOT}" != "" ]; then
		validateNFSroot nfsroot "${NFSROOT}";
	fi;
	if [ "${NFSARGS}" != "" ]; then
		validateNFSargs nfsargs "${NFSARGS}";
	fi;
	if [ "${nfsroot}" != "" ]; then
		nfsdargs="root=/dev/nfs rw netdevwait";
		cmdline+="${nfsdargs} ";
		if [ "${nfsargs}" != "" ]; then
			nfsiargs="ip=${nfsargs}";
			nfsiargs+="::${target_rootdev}:off";
		else
			nfsiargs="ip=:::::${target_rootdev}:on";
		fi;
		cmdline+="${nfsiargs} ";
		cmdline+="nfsroot=${nfsroot} ";
	fi;
elif [ "${target_rootdev}" = "cloning_root" ]; then
	if [ "${tegraid}" = "0x18" ]; then
		# TX2
		CMDLINE_ADD="console=ttyS0,115200n8";
	elif [ "${tegraid}" = "0x19" ]; then
		# Xavier
		CMDLINE_ADD="console=ttyTCU0,115200n8";
	else
		echo "Unknown tegraid/board,exiting..";
		exit 1
	fi;
elif [ "${target_rootdev}" == "internal" ] || \
     [ "${target_rootdev}" == "external" ]; then
	# For 'internal' and 'external' target root devices, always use the
	# UUID stored in the file ${rootfsuuidfile} if present. If this file
	# is not present, then try to generate one.
	if [ -f "${rootfsuuidfile}" ]; then
		rootuuid_restore
	fi

	if [ "${rootfsuuid}" == "" ] && [ "${target_partname}" == "" ]; then
		rootuuid_gen
	fi

	if [ "${rootfsuuid}" == "" ]; then
		echo "No UUID found for root partition! If the root partition"
		echo "is not currently being mounted using a partition UUID,"
		echo "then flash the device by specifying the root device that"
		echo "was specified when previously flashing the entire system"
		echo "(eg. /dev/mmcblk0p1). Otherwise, to mount the root"
		echo "partition using a partition UUID please either:"
		echo "1. If you know the UUID for the root partition save it"
		echo "   to the file ${rootfsuuidfile}."
		echo "2. Re-flash entire system to generate a new UUID."
		usage allunknown 1;
	fi

	cmdline+="root=PARTUUID=${rootfsuuid} rw rootwait rootfstype=ext4 "
else
	cmdline+="root=/dev/${target_rootdev} rw rootwait rootfstype=ext4 "
fi;

if [ "${CMDLINE_ADD}" != "" ]; then
	cmdline+="${CMDLINE_ADD} ";
fi;

if [ "${CMDLINE}" != "" ]; then
	for string in ${CMDLINE}; do
		lcl_str=`echo $string | sed "s|\(.*\)=.*|\1|"`
		if [[ "${cmdline}" =~ $lcl_str ]]; then
			cmdline=`echo "$cmdline" | sed "s|$lcl_str=[0-9a-zA-Z:/]*|$string|"`
		else
			cmdline+="${string} ";
		fi
	done
fi;

##########################################################################
if [ "${zflag}" == "true" ]; then
	pr_conf;
	exit 0;
fi;
##########################################################################

pushd $BL_DIR > /dev/null 2>&1;

### Localize files and build TAGS ########################################
# BCT_TAG:::
#
cp2local bctfile "${BL_DIR}/${bctfilename}";
if [ "${CHIPID}" = "0x19" ]; then
	cp2local bctfile1 "${BL_DIR}/${bctfile1name}";
fi;
if [ "${BINSARGS}" != "" ]; then
	# Build up BCT parameters:

	if [ "${uphy_config}" != "" ]; then
		cp2local uphy_config "${BL_DIR}/${uphy_configname}";
		BCTARGS+="--uphy_config ${uphy_configname} ";
	fi;
	if [ "${device_config}" != "" ]; then
		cp2local device_config "${BL_DIR}/${device_configname}";
		BCTARGS+="--device_config ${device_configname} ";
	fi;
	if [ "${misc_cold_boot_config}" != "" ]; then
		cp2local misc_cold_boot_config "${BL_DIR}/${misc_cold_boot_configname}";
		BCTARGS+="--misc_cold_boot_config ${misc_cold_boot_configname} ";
	fi;
	if [ "${misc_config}" != "" ]; then
		cp2local misc_config "${BL_DIR}/${misc_configname}";
		BCTARGS+="--misc_config ${misc_configname} ";
	fi;
	if [ "${pinmux_config}" != "" ]; then
		cp2local pinmux_config "${BL_DIR}/${pinmux_configname}";
		BCTARGS+="--pinmux_config ${pinmux_configname} ";
	fi;
	if [ "${gpioint_config}" != "" ]; then
		cp2local gpioint_config "${BL_DIR}/${gpioint_configname}";
		BCTARGS+="--gpioint_config ${gpioint_configname} ";
	fi;
	if [ "${pmic_config}" != "" ]; then
		cp2local pmic_config "${BL_DIR}/${pmic_configname}";
		BCTARGS+="--pmic_config ${pmic_configname} ";
	fi;
	if [ "${pmc_config}" != "" ]; then
		cp2local pmc_config "${BL_DIR}/${pmc_configname}";
		BCTARGS+="--pmc_config ${pmc_configname} ";
	fi;
	if [ "${prod_config}" != "" ]; then
		cp2local prod_config "${BL_DIR}/${prod_configname}";
		BCTARGS+="--prod_config ${prod_configname} ";
	fi;
	if [ "${scr_config}" != "" ]; then
		cp2local scr_config "${BL_DIR}/${scr_configname}";
		BCTARGS+="--scr_config ${scr_configname} ";
	fi;
	if [ "${scr_cold_boot_config}" != "" ]; then
		cp2local scr_cold_boot_config "${BL_DIR}/${scr_cold_boot_configname}";
		BCTARGS+="--scr_cold_boot_config ${scr_cold_boot_configname} ";
	fi;
	if [ "${bootrom_config}" != "" ]; then
		cp2local bootrom_config "${BL_DIR}/${bootrom_configname}";
		BCTARGS+="--br_cmd_config ${bootrom_configname} ";
	fi;
	if [ "${dev_params}" != "" ]; then
		cp2local dev_params "${BL_DIR}/${dev_paramsname}";
		BCTARGS+="--dev_params ${dev_paramsname} ";
	fi;
	if [ "${BCT}" = "" ]; then
		BCT="--sdram_config";
	fi;
elif [ "${BCT}" = "" ]; then
	BCT="--bct";
fi;

# EBT_TAG:
#
cp2local bootloader "${BL_DIR}/${bootloadername}";
EBT_TAG+="-e s/EBTFILE/${bootloadername}/ ";

# LNX_TAG:
#
localbootfile=boot.img;
rm -f initrd; touch initrd;
if [ ${rcm_boot} -eq 1 ]; then
	if [ "${kernelinitrd}" = "" ]; then
		kernelinitrd=l4t_initrd.img
	fi;
fi;
if [ "$kernelinitrd" != "" -a -f "$kernelinitrd" ]; then
	echo -n "copying initrd(${kernelinitrd})... ";
	cp -f "${kernelinitrd}" initrd;
	chkerr;
	# Code below for the initrd boot. Further details: http://nvbugs/2053323
	if [ "${target_rootdev}" = "cloning_root" ]; then
		clone_restore_dir="${LDK_DIR}/clone_restore"
		if [ ! -f ${clone_restore_dir}/nvbackup_copy_bin.func ]; then
			echo "Error: cloning is not supported."
			exit 1
		fi
		echo "Extract kernel initrd"
		initrddir=$(cd "$(dirname "$0")" && pwd)
		tempinitrd_dir="${initrddir}/temp"
		if [ ! -d "${tempinitrd_dir}" ]; then
			mkdir "${tempinitrd_dir}"
		fi
		temp_initrd="initrd"
		pushd "${tempinitrd_dir}"  > /dev/null 2>&1;
		source "${clone_restore_dir}/nvbackup_copy_bin.func"
		nvbackup_copy_bin "${clone_restore_dir}" \
			"${rootfs_dir}" \
			"${initrddir}/${temp_initrd}" \
			"${clone_restore_dir}/nvbackup_env_binlist.txt" \
			"${spec}"
		if [ $? -ne 0 ]; then
			rm -rf "${tempinitrd_dir}"
			echo "nvbackup_copy_bin: Failed"
			exit 1
		fi
		popd  > /dev/null 2>&1;
		rm -rf "${tempinitrd_dir}"
	fi;
fi;

mkdir -p "${rootfs_dir}/boot" > /dev/null 2>&1;
echo -e -n "\tpopulating kernel to rootfs... ";
cp -f "${kernel_fs}" "${rootfs_dir}/boot"; chkerr;

# Sign kernel image and save the sign header to boot folder
if [ "${tegraid}" = "0x19"  ]; then
	signimage "${kernel_fs}"
fi

echo -e -n "\tpopulating initrd to rootfs... ";
cp -f initrd "${rootfs_dir}/boot"; chkerr;
echo -e -n "\tpopulating ${dtbfile} to rootfs... ";
cp -f "${dtbfile}" "${rootfs_dir}/boot"; chkerr;

# Sign kernel dtb and save the sign header to boot folder
if [ "${tegraid}" = "0x19"  ]; then
	signimage "${dtbfile}"
fi


LNX_TAG+="-e s/LNXNAME/kernel/ ";
LNX_TAG+="-e s/LNXSIZE/67108864/ ";
# Handle where kernel image is specified by -k and --image options
if [ "${write_image_name}" != "" ]; then
	if [ "${target_partname}" = "LNX" ] || [ "${target_partname}" = "kernel" ] \
		|| [ "${target_partname}" = "kernel_b" ]; then
		kernel_image="${write_image_name}";
		write_image_name="";
	fi
fi

if [ "${INITRD_IN_BOOTIMG}" = "yes" ]; then
	ramdisk="${kernelinitrd}";
else
	ramdisk="/dev/null"
fi
echo -n "Making Boot image... ";
MKBOOTARG+="--kernel ${kernel_image} ";
MKBOOTARG+="--ramdisk ${ramdisk} ";
MKBOOTARG+="--board ${target_rootdev} ";
MKBOOTARG+="--output ${localbootfile} ";
./mkbootimg ${MKBOOTARG} --cmdline "${cmdline}" > /dev/null 2>&1;
chkerr;
LNX_TAG+="-e s/LNXFILE/${localbootfile}/ ";

# NCT_TAG:
#
if [ "${bcffile}" != "" ]; then
	cp2local bcffile "${BL_DIR}/${bcffilename}";
	NCTARGS+="--boardconfig ${bcffilename} ";
	NCT_TAG+="-e /NCTFILE/d ";
	NCT_TAG+="-e s/NCTTYPE/data/ ";
elif [ "${boardid}" != "" ]; then
	: # Do nothing
elif [ "${nctfile}" != "" ]; then
	cp2local nctfile "${BL_DIR}/${nctfilename}";
	NCT_TAG+="-e s/NCTFILE/${nctfilename}/ ";
	NCT_TAG+="-e s/NCTTYPE/config_table/ ";
	NCTARGS+="--nct ${nctfilename} ";
else
	NCT_TAG+="-e /NCTFILE/d ";
	NCT_TAG+="-e s/NCTTYPE/data/ ";
fi;

# VER_TAG:
#
if [ "${VERFILENAME}" != "" ]; then
	# NV1: VersionID,ReleaseString
	# NV2: VersionID,ReleaseString,BoardID
	echo "NV2" > "${VERFILENAME}";	# Version file format number
	if [ -f "${LDK_DIR}/nv_tegra/bsp_version" ]; then
		echo "# R${BSP_BRANCH} , REVISION: ${BSP_MAJOR}.${BSP_MINOR}" >> "${VERFILENAME}";
	else
		head -n 1 "${rootfs_dir}/etc/nv_tegra_release" >> "${VERFILENAME}";
	fi;
	echo "BOARDID=${BOARDID} BOARDSKU=${BOARDSKU} FAB=${FAB}" >> "${VERFILENAME}";
	VER_TAG+="-e s/VERFILE/${VERFILENAME}/ ";
else
	VER_TAG+="-e /VERFILE/d ";
fi;

# SOS_TAG: XXX: recovery is yet to be implemented.
#
SOS_TAG+="-e /SOSFILE/d ";
if [ "${sosfile}" != "" ]; then
	cp2local sosfile "${BL_DIR}/${sosfilename}";
	SOSARGS+="--applet ${sosfilename} ";
fi;

# NVC_TAG:== MB2
#
if [ "${tegraboot}" != "" ]; then
	cp2local tegraboot "${BL_DIR}/${tegrabootname}";
	cp2local cpu_bootloader "${BL_DIR}/${cpu_bootloadername}";
	NVC_TAG+="-e s/NXC/NVC/ ";
	NVC_TAG+="-e s/MB2NAME/mb2/ ";
	NVC_TAG+="-e s/NVCTYPE/bootloader/ ";
	NVC_TAG+="-e s/TEGRABOOT/${tegrabootname}/ ";
	NVC_TAG+="-e s/MB2TYPE/mb2_bootloader/ ";
	NVC_TAG+="-e s/NVCFILE/${tegrabootname}/ ";
	NVC_TAG+="-e s/MB2FILE/${tegrabootname}/ ";
else
	NVC_TAG+="-e s/NVCTYPE/data/ ";
	NVC_TAG+="-e s/MB2TYPE/data/ ";
	NVC_TAG+="-e /NVCFILE/d ";
	NVC_TAG+="-e /MB2FILE/d ";
fi;

# MB2BL_TAG:== tboot_recovery
#
if [ "${mb2blfile}" != "" ]; then
	cp2local mb2blfile "${BL_DIR}/${mb2blfilename}";
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="mb2_bootloader ${mb2blfilename}; ";
	fi;
fi;

# MPB_TAG:
#
if [ "${mtspreboot}" != "" ]; then
	cp2local mtspreboot "${BL_DIR}/${mtsprebootname}";
	MPB_TAG+="-e s/MXB/MPB/ ";
	MPB_TAG+="-e s/MPBNAME/mts-preboot/ ";
	MPB_TAG+="-e s/MPBTYPE/mts_preboot/ ";
	MPB_TAG+="-e s/MPBFILE/${mtsprebootname}/ ";
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="mts_preboot ${mtsprebootname}; ";
		if [ "${CHIPID}" = "0x19" ]; then
			cp2local mcepreboot "${BL_DIR}/${mceprebootname}";
			cp2local mtsproper "${BL_DIR}/${mtspropername}";
			MPB_TAG+="-e s/MTSPREBOOT/${mtsprebootname}/ ";
			MPB_TAG+="-e s/MTS_MCE/${mceprebootname}/ ";
			MPB_TAG+="-e s/MTSPROPER/${mtspropername}/ ";
			BINSARGS+="mts_mce ${mceprebootname}; ";
			BINSARGS+="mts_proper ${mtspropername}; ";
		fi;
	else
		MTSARGS+="--preboot ${mtsprebootname} ";
	fi;
else
	MPB_TAG+="-e s/MPBTYPE/data/ ";
	MPB_TAG+="-e /MPBFILE/d ";
fi;

# MBP_TAG:
#
if [ "${mts}" != "" ]; then
	cp2local mts "${BL_DIR}/${mtsname}";
	MBP_TAG+="-e s/MXP/MBP/ ";
	MBP_TAG+="-e s/MBPNAME/mts-bootpack/ ";
	MBP_TAG+="-e s/MBPTYPE/mts_bootpack/ ";
	MBP_TAG+="-e s/MBPFILE/${mtsname}/ ";
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="mts_bootpack ${mtsname}; ";
	else
		MTSARGS+="--bootpack ${mtsname} ";
	fi;
else
	MBP_TAG+="-e s/MBPTYPE/data/ ";
	MBP_TAG+="-e /MBPFILE/d ";
fi;

# MB1_TAG:
#
if [ "${mb1file}" != "" ]; then
	cp2local mb1file "${BL_DIR}/${mb1filename}";
	MB1_TAG+="-e s/MB1NAME/mb1/ ";
	MB1_TAG+="-e s/MB1TYPE/mb1_bootloader/ ";
	MB1_TAG+="-e s/MB1FILE/${mb1filename}/ ";
else
	MB1_TAG+="-e s/MB1TYPE/data/ ";
	MB1_TAG+="-e /MB1FILE/d ";
fi;

# BPF_TAG:
#
if [ "${bpffile}" != "" ]; then
	cp2local bpffile "${BL_DIR}/${bpffilename}";
	BPF_TAG+="-e s/BXF/BPF/ ";
	BPF_TAG+="-e s/BPFNAME/bpmp-fw/ ";
	BPF_TAG+="-e s/BPFFILE/${bpffilename}/ ";
	BPF_TAG+="-e s/BPFSIGN/true/ ";
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="bpmp_fw ${bpffilename}; ";
	fi;
else
	BPF_TAG+="-e /BPFFILE/d ";
	BPF_TAG+="-e s/BPFSIGN/false/ ";
fi;

# BPFDTB_TAG:
if [ "${bpfdtbfile}" != "" ]; then
	cp2local bpfdtbfile "${BL_DIR}/${bpfdtbfilename}";
	BPFDTB_TAG+="-e s/BPFDTB-NAME/bpmp-fw-dtb/ ";
	BPFDTB_TAG+="-e s/BPFDTB-FILE/${bpfdtbfilename}/ ";
	BPFDTB_TAG+="-e s/BPFDTB_FILE/${bpfdtbfilename}/ ";
	BPFDTB_TAG+="-e s/BPMPDTB-SIGN/true/ ";
	BPFDTB_TAG+="-e s/BPMPDTB/${bpfdtbfilename}/ ";			#COMPAT
	BPFDTB_TAG+="-e s/BXF-DTB/BPF-DTB/ ";				#COMPAT
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="bpmp_fw_dtb ${bpfdtbfilename}; ";
	fi;
else
	BPFDTB_TAG+="-e /BPFDTB-FILE/d ";				#COMPAT
	BPFDTB_TAG+="-e s/BPMPDTB-SIGN/false/ ";
fi;

# SCE_TAG:
if [ "${scefile}" != "" -o "${camerafw}" != "" ]; then
	cp2local scefile "${BL_DIR}/${scefilename}";
	cp2local camerafw "${BL_DIR}/${camerafwname}";
	SCE_TAG+="-e s/SCENAME/sce-fw/ ";
	SCE_TAG+="-e s/SCESIGN/true/ ";
	SCE_TAG+="-e s/SCEFILE/${scefilename}/ ";
	SCE_TAG+="-e s/CAMERAFW/${camerafwname}/ ";
else
	SCE_TAG+="-e s/SCESIGN/flase/ ";
	SCE_TAG+="-e /SCEFILE/d ";
fi;

# SPE_TAG:
if [ "${spefile}" != "" ]; then
	cp2local spefile "${BL_DIR}/${spefilename}";
	SPE_TAG+="-e s/SPENAME/spe-fw/ ";
	SPE_TAG+="-e s/SPETYPE/spe_fw/ ";
	SPE_TAG+="-e s/SPEFILE/${spefilename}/ ";
	if [ "${BINSARGS}" != "" -a "${CHIPID}" = "0x19" ]; then
	     BINSARGS+="spe_fw ${spefilename}; ";
	fi;

else
	SPE_TAG+="-e s/SPETYPE/data/ ";
	SPE_TAG+="-e /SPEFILE/d ";
fi;

# DRAMECC_TAG:
if [ "${drameccfile}" != "" ]; then
	cp2local drameccfile "${BL_DIR}/${drameccfilename}";
	DRAMECC_TAG+="-e s/DRAMECCNAME/dram-ecc-fw/ ";
	DRAMECC_TAG+="-e s/DRAMECCTYPE/dram_ecc/ ";
	DRAMECC_TAG+="-e s/DRAMECCFILE/${drameccfilename}/ ";
else
	DRAMECC_TAG+="-e s/DRAMECCTYPE/data/ ";
	DRAMECC_TAG+="-e /DRAMECCFILE/d ";
fi;

# BADPAGE_TAG:
cp2local badpagefile "${BL_DIR}/${badpagefilename}";
BADPAGE_TAG+="-e s/BADPAGENAME/badpage-fw/ ";
BADPAGE_TAG+="-e s/BADPAGETYPE/black_list_info/ ";
BADPAGE_TAG+="-e s/BADPAGEFILE/${badpagefilename}/ ";

# WB0_TAG:
#
if [ "${wb0boot}" != "" ]; then
	cp2local wb0boot "${BL_DIR}/${wb0bootname}";
	WB0_TAG+="-e s/WX0/WB0/ ";
	WB0_TAG+="-e s/SC7NAME/sc7/ ";
	WB0_TAG+="-e s/WB0TYPE/WB0/ ";
	WB0_TAG+="-e s/WB0FILE/${wb0bootname}/ ";
	WB0_TAG+="-e s/WB0BOOT/${wb0bootname}/ ";
else
	WB0_TAG+="-e s/WB0TYPE/data/ ";
	WB0_TAG+="-e /WB0FILE/d ";
fi;

# TOS_TAG:
#
if [ "${tosfile}" != "" ]; then
	cp2local tosfile "${BL_DIR}/${tosfilename}";
	TOS_TAG+="-e s/TXS/TOS/ ";
	TOS_TAG+="-e s/TOSNAME/secure-os/ ";
	TOS_TAG+="-e s/TOSFILE/${tosfilename}/ ";
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="tlk ${tosfilename}; ";
	fi;
else
	TOS_TAG+="-e /TOSFILE/d ";
fi;

# EKS_TAG:
#
EKS_TAG+="-e s/EXS/EKS/ ";
if [ "${eksfile}" != "" ]; then
	cp2local eksfile "${BL_DIR}/${eksfilename}";
	EKS_TAG+="-e s/EKSFILE/${eksfilename}/ ";
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="eks ${eksfilename}; ";
	fi;
else
	EKS_TAG+="-e /EKSFILE/d ";
fi;

# FB_TAG:
#
if [ "${fbfile}" != "" ]; then
	chsuffix fbfilebin ${fbfilename} "bin";
	cp2local fbfile "${BL_DIR}/${fbfilename}";
	FB_TAG+="-e s/FBFILE/${fbfilebin}/ ";
	FB_TAG+="-e s/FX/FB/ ";
	FB_TAG+="-e s/FBNAME/fusebypass/ ";
	FB_TAG+="-e s/FBTYPE/fuse_bypass/ ";
	FB_TAG+="-e s/FBSIGN/true/ ";
	if [[ "${CHIPID}" != "0x19"  ||  "${fuselevel}" = "fuselevel_nofuse" ]]; then
		FBARGS+="--fb ${fbfilebin} "
		FBARGS+="--cmd \"parse fusebypass ${fbfilename} ";
	else
		# T194 nv fused board: skip --fb xxx and "parse fusebypass xxx.xml acr-debug"
		FBARGS+="--cmd \"";
	fi
	if [ "${CHIPID}" = "0x19" ]; then
		if [ "${fuselevel}" = "fuselevel_nofuse" ]; then
			FBARGS+="${ACR_TYPE}; ";
		fi
		if [ ${bup_blob} -ne 0 ]; then
			FBARGS+="sign\" ";
		elif [ ${rcm_boot} -ne 0 ]; then
			FBARGS+="rcmboot\" ";
		else
			FBARGS+="flash;reboot\" ";
		fi
		BINSARGS+="kernel boot.img; "
		BINSARGS+="kernel_dtb ${DTB_FILE}; "
	else
		if [ "${CHIPMAJOR}" != "" ]; then
			FBARGS+="b01-acr-production; ";
		else
			FBARGS+="non-secure; ";
		fi;
		FBARGS+="flash; reboot\" ";
	fi;
else
	FB_TAG+="-e s/FBTYPE/data/ ";
	FB_TAG+="-e s/FBSIGN/false/ ";
	FB_TAG+="-e /FBFILE/d ";
	if [ ${rcm_boot} -ne 0 ]; then
		BINSARGS+="kernel boot.img; "
		BINSARGS+="kernel_dtb ${DTB_FILE}; "
		BINSARGS+="sce_fw ${scefilename}; "
		FBARGS+="--cmd \"rcmboot\" ";
	elif [ ${bup_blob} -ne 0 ]; then
		FBARGS+="--cmd \"sign\" ";
	else
		FBARGS+="--cmd \"flash; reboot\" ";
	fi
fi;

# soft_fuse:
#
if [ "${soft_fuses}" != "" ]; then
	cp2local soft_fuses "${BL_DIR}/${soft_fusesname}";
	NV_ARGS+="--soft_fuses ${soft_fusesname} ";
fi;

# DTB_TAG: Kernel DTB
#
if [ "${dtbfile}" != "" ]; then
	cp2local dtbfile "${BL_DIR}/${dtbfilename}";
	append_bootargs_to_dtb "${dtbfilename}";
	DTB_TAG+="-e s/DXB/DTB/ ";
	DTB_TAG+="-e s/KERNELDTB-NAME/kernel-dtb/ ";
	DTB_TAG+="-e s/DTBFILE/${dtbfilename}/ ";
	DTB_TAG+="-e s/KERNELDTB-FILE/${dtbfilename}/ ";
	DTB_TAG+="-e s/DTB_FILE/${dtbfilename}/ ";			#COMPAT
	if [ "${tegraid}" != "0x18" ] && [ "${tegraid}" != "0x19"  ]; then
		if [ "${keyfile}" != "" -a "${tegraid}" = "0x21" ]; then
			DTBARGS+="--bldtb ${dtbfilename}.signed ";
		else
			DTBARGS+="--bldtb ${dtbfilename} ";
		fi;
	fi
else
	DTB_TAG+="-e /DTBFILE/d ";
	DTB_TAG+="-e /KERNELDTB-FILE/d ";
fi;

# inject board spec info into nv_boot_control.conf
echo "Copying nv_boot_control.conf to rootfs"
cp -f "${BL_DIR}/nv_boot_control.conf" "${rootfs_dir}/etc"
ota_boot_dev="/dev/mmcblk0boot0"
ota_gpt_dev="/dev/mmcblk0boot1"
if [[ "${ext_target_board}" == "jetson-nano-qspi"* ||
	"${ext_target_board}" == "p3448-0000" ||
	"${ext_target_board}" == "p3448-0000-sd" ]]; then
	ota_boot_dev="/dev/mtdblock0"
	ota_gpt_dev="/dev/mtdblock0"
fi
sed -i '/TNSPEC/d' "${rootfs_dir}/etc/nv_boot_control.conf";
sed -i "$ a TNSPEC ${spec}" "${rootfs_dir}/etc/nv_boot_control.conf";
sed -i '/TEGRA_CHIPID/d' "${rootfs_dir}/etc/nv_boot_control.conf";
sed -i "$ a TEGRA_CHIPID ${CHIPID}" "${rootfs_dir}/etc/nv_boot_control.conf";
sed -i '/TEGRA_OTA_BOOT_DEVICE/d' "${rootfs_dir}/etc/nv_boot_control.conf";
sed -i "$ a TEGRA_OTA_BOOT_DEVICE ${ota_boot_dev}" "${rootfs_dir}/etc/nv_boot_control.conf";
sed -i '/TEGRA_OTA_GPT_DEVICE/d' "${rootfs_dir}/etc/nv_boot_control.conf";
sed -i "$ a TEGRA_OTA_GPT_DEVICE ${ota_gpt_dev}" "${rootfs_dir}/etc/nv_boot_control.conf";

# APP_TAG: RootFS
#
# check cases where system.img is not needed
if [ ${bup_blob} -eq 1 ] || [ ${rcm_boot} -eq 1 ] \
    || [ ${no_systemimg} -eq 1 ] \
	|| [ "${read_part_name}" != "" ]; then
	skip_systemimg="true";
fi;
localsysfile=system.img;
APP_TAG+="-e s/APPSIZE/${rootfssize}/ ";

if [ "${target_rootdev}" == "internal" ]; then
	APP_TAG+="-e s/APPUUID/${rootfsuuid}/ ";
else
	APP_TAG+="-e s/APPUUID// ";
fi

if [ "${reuse_systemimg}" = "true" ] || [ "${skip_systemimg}" = "true" ]; then
	APP_TAG+="-e s/APPFILE/${localsysfile}/ ";
	if [ "${skip_systemimg}" != "true" ]; then
		echo "Reusing existing ${localsysfile}... ";
		if [ ! -e "${localsysfile}" ]; then
			echo "file does not exist.";
			exit 1;
		fi;
		echo "done.";
	else
		echo "Skip generating ${localsysfile}";
	fi;
elif [ "${rootdev_type}" = "internal" ]; then
	APP_TAG+="-e s/APPFILE/${localsysfile}/ ";
	if [ "${target_partname}" = "" -o "${target_partname}" = "APP" ]; then
		build_fsimg "$localsysfile" "$fillpat" \
		    "$rootfssize" "$rootfs_type" "$rootfs_dir";
	fi;
elif [ "${rootdev_type}" = "network" -o "${rootdev_type}" = "external" ]; then
	APP_TAG+="-e s/APPFILE/${localsysfile}/ ";
	echo "generating system.img for booting... ";
	tmpdir=`mktemp -d`;
	mkdir -p "${tmpdir}/boot/extlinux" > /dev/null 2>&1;
	cp -f "${rootfs_dir}/boot/extlinux/extlinux.conf" "${tmpdir}/boot/extlinux" > /dev/null 2>&1;
	cp -f "${kernel_fs}" "${tmpdir}/boot" > /dev/null 2>&1;
	cp -f "${dtbfile}" "${tmpdir}/boot" > /dev/null 2>&1;
	cp -f initrd "${tmpdir}/boot" > /dev/null 2>&1;
	build_fsimg "$localsysfile" "$fillpat" \
		    "$rootfssize" "$rootfs_type" "$tmpdir";
else
	APP_TAG+="-e /system.img/d ";
	APP_TAG+="-e /APPFILE/d ";
fi;

# TBC_TAG:== EBT
#
if [ "${tbcfile}" != "" ]; then
	cp2local tbcfile "${BL_DIR}/${tbcfilename}";
	TBC_TAG+="-e s/TXC/TBC/ ";
	TBC_TAG+="-e s/TBCNAME/cpu-bootloader/ ";
	TBC_TAG+="-e s/TBCTYPE/bootloader/ ";
	TBC_TAG+="-e s/TBCFILE/${tbcfilename}/ ";
else
	TBC_TAG+="-e s/TBCTYPE/data/ ";
	TBC_TAG+="-e /TBCFILE/d ";
fi;

# TBCDTB_TAG:== Bootloader DTB
#
if [ "${tbcdtbfile}" != "" ]; then
	cp2local tbcdtbfile "${BL_DIR}/${tbcdtbfilename}";
	append_bootargs_to_dtb "${tbcdtbfilename}";
	TBCDTB_TAG+="-e s/TBCDTB-NAME/bootloader-dtb/ ";
	TBCDTB_TAG+="-e s/TBCDTB-FILE/${tbcdtbfilename}/ ";
	if [ "${BINSARGS}" != "" ]; then
		BINSARGS+="bootloader_dtb ${tbcdtbfilename}; ";
	fi;
	if [ "${T21BINARGS}" != "" ]; then
		T21BINARGS+="DTB ${tbcdtbfilename}; ";
	fi
else
	TBCDTB_TAG+="-e s/TBCTYPE/data/ ";
	TBCDTB_TAG+="-e /TBCDTB-FILE/d ";
fi;

# EFI_TAG: Minimum FAT32 partition size is 64MiB (== 1 FAT cluster)
#
localefifile=efi.img;
efifs_size=$(( 64 * 1024 * 1024 ));
EFI_TAG+="-e s/EFISIZE/${efifs_size}/ ";
if [ "${bootloadername}" = "uefi.bin" ]; then
	build_fsimg $localefifile "" $efifs_size "FAT32" "";
	EFI_TAG+="-e s/EXI/EFI/ ";
	EFI_TAG+="-e s/EFIFILE/${localefifile}/ ";
else
	EFI_TAG+="-e /EFIFILE/d ";
fi;

# GPT_TAG: tag should created before cfg and actual img should be
#	   created after cfg.
#
localpptfile=ppt.img;
localsptfile=gpt.img;
if [ ! -z "${bootpartsize}" -a ! -z "${emmcsize}" ]; then
	bplmod=$(( ${bootpartlim} % ${devsectsize} ));
	if [ ${bplmod} -ne 0 ]; then
		echo "Error: Boot partition limit is not modulo ${devsectsize}";
		exit 1;
	fi;
	bpsmod=$(( ${bootpartsize} % ${devsectsize} ));
	if [ ${bpsmod} -ne 0 ]; then
		echo "Error: Boot partition size is not modulo ${devsectsize}";
		exit 1;
	fi;
	gptsize=$(( ${bootpartlim} - ${bootpartsize} ));
	if [ ${gptsize} -lt ${devsectsize} ]; then
		echo "Error: No space for primary GPT.";
		exit 1;
	fi;
	GPT_TAG+="-e s/PPTSIZE/${gptsize}/ ";
else
	GPT_TAG+="-e s/PPTSIZE/16896/ ";
fi;

# CBOOTOPTION_TAG:== Cboot option DTB
#
if [ "${cbootoptionfile}" != "" ]; then
	cp2local cbootoptionfile "${BL_DIR}/${cbootoptionfilename}";
	CBOOTOPTION_TAG="-e s/CBOOTOPTION_FILE/${cbootoptionfilename}/ ";
else
	CBOOTOPTION_TAG="-e /CBOOTOPTION_FILE/d ";
fi;

# CFG:
#
if [[ ${cfgfile} =~ \.xml$ ]]; then
	localcfgfile=flash.xml;
else
	localcfgfile=flash.cfg;
fi;
echo -n "copying cfgfile(${cfgfile}) to ${localcfgfile}... ";
if [ "${BINSARGS}" != "" ]; then
	# Close BINSARGS before get used for the first time.
	BINSARGS+="\"";
	BINSCONV+="-e s/\"[[:space:]]*/\"/ ";
	BINSCONV+="-e s/\;[[:space:]]*\"/\"/ ";
	BINSARGS=`echo "${BINSARGS}" | sed ${BINSCONV}`;
fi;
if [ "${T21BINARGS}" != "" ]; then
	# Close T21BINARGS before get used for the first time.
	T21BINARGS+="\"";
	BINSCONV=""
	BINSCONV+="-e s/\"[[:space:]]*/\"/ ";
	BINSCONV+="-e s/\;[[:space:]]*\"/\"/ ";
	T21BINARGS=`echo "${T21BINARGS}" | sed ${BINSCONV}`;
fi;
CFGCONV+="${EBT_TAG} ";
CFGCONV+="${LNX_TAG} ";
CFGCONV+="${SOS_TAG} ";
CFGCONV+="${NCT_TAG} ";
CFGCONV+="${VER_TAG} ";
CFGCONV+="${NVC_TAG} ";
CFGCONV+="${MB2BL_TAG} ";
CFGCONV+="${MPB_TAG} ";
CFGCONV+="${MBP_TAG} ";
CFGCONV+="${MB1_TAG} ";
CFGCONV+="${BPFDTB_TAG} ";
CFGCONV+="${BPF_TAG} ";
CFGCONV+="${SCE_TAG} ";
CFGCONV+="${SPE_TAG} ";
CFGCONV+="${DRAMECC_TAG} ";
CFGCONV+="${BADPAGE_TAG} ";
CFGCONV+="${TOS_TAG} ";
CFGCONV+="${EKS_TAG} ";
CFGCONV+="${FB_TAG}  ";
CFGCONV+="${WB0_TAG} ";
CFGCONV+="${APP_TAG} ";
CFGCONV+="${EFI_TAG} ";
CFGCONV+="${DTB_TAG} ";
CFGCONV+="${TBCDTB_TAG} ";
CFGCONV+="${TBC_TAG} ";
CFGCONV+="${GPT_TAG} ";
CFGCONV+="${CBOOTOPTION_TAG} ";

cat ${cfgfile} | sed ${CFGCONV} > ${localcfgfile}; chkerr;

# GPT:
# mkgpt need to update as per new flash_t186_l4t.xml,
# currently skipping mkgpt as gpt partition is taken care by tegraflash.
if [ ! -z "${bootpartsize}" -a ! -z "${emmcsize}" -a \
    "${tegraid}" != "0x18" -a "${tegraid}" != "0x19" ]; then
	echo "creating gpt(${localpptfile})... ";
	MKGPTOPTS="-c ${localcfgfile} -P ${localpptfile} ";
	MKGPTOPTS+="-t ${emmcsize} -b ${bootpartsize} -s 4KiB ";
	MKGPTOPTS+="-a GPT -v GP1 ";
	MKGPTOPTS+="-V ${MKGPTCMD} ";
	./mkgpt ${MKGPTOPTS};
	chkerr "creating gpt(${localpptfile}) failed.";
fi;
# FLASH:
#
cp2local flasher	"${BL_DIR}/${flashername}";
cp2local flashapp	"${BL_DIR}/${flashappname}";

if [ "${target_partname}" != "" ]; then
	validatePartID target_partid target_partname $target_partname $localcfgfile;
	tmp_updateid="[${target_partname}]";
	need_sign=0;
	signtype="encrypt";
	if [ "${bootauth}" = "PKC" ] || [ "${bootauth}" = "SBKPKC" ]; then
		signtype="signed";
	fi;
	case ${target_partname} in
	BCT) target_partfile="${bctfilename}";
	     FLASHARGS="${BCT} ${target_partfile} --updatebct SDRAM ";
	     ;;
	mb2 | mb2_b) target_partfile="nvtboot.bin";
	     need_sign=1;
	     ;;
	bpmp-fw | bpmp-fw_b)
	     target_partfile="${bpffilename}";
	     need_sign=1;
	     ;;
	bpmp-fw-dtb | bpmp-fw-dtb_b)
	     target_partfile="${bpfdtbfilename}";
	     need_sign=1;
	     ;;
	PPT) target_partfile="${localpptfile}"; ;;
	EBT) target_partfile="${bootloadername}"; need_sign=1; ;;
	cpu-bootloader | cpu-bootloader_b)
	     target_partfile="${tbcfilename}";
	     need_sign=1;
	     ;;
	bootloader-dtb | bootloader-dtb_b)
	     target_partfile="${tbcdtbfilename}";
	     if [ "${write_image_name}" != "" ]; then
	         append_bootargs_to_dtb "${write_image_name}";
	     fi;
	     need_sign=1;
	     ;;
	secure-os | secure-os_b)
	     target_partfile="${tosfilename}";
	     need_sign=1;
	     ;;
	eks) target_partfile="${eksfilename}";
	     need_sign=1;
	     ;;
	LNX) target_partfile="${localbootfile}";
		if [ "${tegraid}" = "0x21" ]; then
			if [ "${read_part_name}" = "" ]; then
				need_sign=1;
			fi;
		else
			pre_cmds="write DTB ${dtbfilename}; ";
		fi;
		;;
	kernel | kernel_b)
	     target_partfile="${localbootfile}";
	     need_sign=1;
	     ;;
	kernel-dtb | kernel-dtb_b) target_partfile="${dtbfilename}";
	     if [ "${write_image_name}" != "" ]; then
	         append_bootargs_to_dtb "${write_image_name}";
	     fi;
	     need_sign=1;
	     ;;
	NCT) target_partfile="${nctfilename}"; ;;
	SOS) target_partfile="${sosfilename}"; ;;
	NVC) target_partfile="${tegrabootname}"; need_sign=1; ;;
	MPB) target_partfile="${mtsprebootname}"; ;;
	MBP) target_partfile="${mtsname}"; ;;
	BPF) target_partfile="${bpffilename}"; ;;
	APP) target_partfile="${localsysfile}"; ;;
	DTB|RP1) target_partfile="${dtbfilename}";
		need_sign=1;
		;;
	EFI) target_partfile="${localefifile}"; ;;
	TOS) target_partfile="${tosfilename}"; ;;
	EKS) target_partfile="${eksfilename}"; ;;
	FB)  target_partfile="${fbfilename}"; ;;
	WB0) target_partfile="${wb0bootname}"; ;;
	GPT) target_partfile="${localsptfile}"; ;;
	rce-fw | rce-fw_b)
	     target_partfile="${camerafwname}";
	     need_sign=1;
	     ;;
	sce-fw | sce-fw_b)
	     target_partfile="${scefilename}";
	     need_sign=1;
	     ;;
	mts-preboot | mts-mce | mts-proper | \
	mts-preboot_b | mts-mce_b | mts-proper_b | \
	adsp-fw | extended-can-fw | \
	adsp-fw_b | extended-can-fw_b | \
	fusebypass)
	     # For partitions that do not have default image, user must provide
	     # the image to be flashed
	     if [ "${read_part_name}" = "" ] && [ "${write_image_name}" = "" ]; then
	         echo -n "*** Error: missing ${target_partname} image. ";
	         echo "Use option --image to specify the image to be flashed.";
	         exit 1;
	     fi;
	     need_sign=1;
	     ;;
	xusb-fw | xusb-fw_b | BMP | BMP_b)
	     if [ "${read_part_name}" = "" ] && [ "${write_image_name}" = "" ]; then
	         echo -n "*** Error: missing ${target_partname} image. ";
	         echo "Use option --image to specify the image to be flashed.";
	         exit 1;
	     fi;
	     ;;
	MB1_BCT | MB1_BCT_b)
		# use the name hard coded by tegraflash.py
		if [ "${read_part_name}" = "" ]; then
			write_image_name="signed/mb1_cold_boot_bct_MB1_sigheader.bct.${signtype}"
		fi;
		need_sign=1;
		;;
	sc7 | sc7_b) target_partfile="${wb0bootname}";
	     need_sign=1;
	     ;;
	spe-fw | spw-fw_b)
	     target_partfile="${spefilename}";
	     need_sign=1;
	     ;;
	CPUBL-CFG)
	     target_partfile="${cbootoptionfilename}";
	     ;;
	*)   echo "*** Update ${tmp_updateid} is not supported. ***";
	     exit 1; ;;
	esac;
	if [ "${read_part_name}" != "" ]; then
		# Read partition
		target_partfile="${read_part_name}";
		echo "*** Reading ${tmp_updateid} and storing to ${target_partfile} ***";
	else
		# Write partition
		if [ "${write_image_name}" != "" ]; then
			# write partition with image provided in command line
			target_partfile="${write_image_name}";
		fi;
		if [ ${no_flash} -eq 1 ]; then
			echo "*** Signing ${target_partfile} ***";
		else
			echo "*** Updating ${tmp_updateid} with ${target_partfile} ***";
		fi;
	fi;
	if [ "${FLASHARGS}" = "" ]; then
		FLASHARGS="--bl ${flashername} ${DTBARGS} ";
		if [ "${keyfile}" != "" -a "${tegraid}" = "0x21" ]; then
			FLASHARGS="--bl ${flashername}.signed ";
			DTBARGS+="--bldtb ${dtbfilename}.signed ";
		fi;
		if [ "${CHIPMAJOR}" != "" ]; then
			FLASHARGS+="--chip \"${tegraid} ${CHIPMAJOR}\" ";
		else
			FLASHARGS+="--chip ${tegraid} ";
		fi;
		FLASHARGS+="--applet ${sosfilename} ";
	fi;
	if [ "${CHIPID}" = "0x19" ]; then
		FLASHARGS+="$BCT ${bctfilename},${bctfile1name} ";
	else
		FLASHARGS+="$BCT ${bctfilename} ";
	fi

	# special handling for T210 due to signwrite command is not supported
	if [ ${need_sign} -eq 1 ]; then
		pf_dir="$(dirname "${target_partfile}")";
		pf_fn="$(basename "${target_partfile}")";
		if [ "${read_part_name}" != "" ]; then
			mkdir -p "${pf_dir}/signed" > /dev/null 2>&1;
		fi;
		if [ "${tegraid}" = "0x21" ]; then
			target_partfile="${pf_dir}/signed/${pf_fn}.${signtype}";
		fi;
	fi

	FLASHARGS+="${BCTARGS}${NV_ARGS} ";
	FLASHARGS+="--cfg  ${localcfgfile} ${BINSARGS} ";
	FLASHARGS+=" --cmd \"";
	FLASHARGS+="${pre_cmds}";
	if [ "${read_part_name}" != "" ]; then
		FLASHARGS+="read ${target_partname} ${target_partfile}\" ";
	else
		if [ ${no_flash} -eq 1 ]; then
			FLASHARGS="--chip ${tegraid} --cmd \"sign ${target_partfile}\" ";
		else
			if [ ${need_sign} -eq 1 ]; then
				# special handling for MB1_BCT and T210
				if [ "${target_partname}" = "MB1_BCT" ] ||
					[ "${target_partname}" = "MB1_BCT_b" ] ||
					[ "${tegraid}" = "0x21" ]; then
					FLASHARGS+="sign; write ";
				else
					FLASHARGS+="signwrite ";
				fi;
			else
				FLASHARGS+="write ";
			fi
			FLASHARGS+="${target_partname} ${target_partfile}; ";
			if [ $reboot_recovery -eq 1 ] ; then
				FLASHARGS+="reboot recovery\" ";
			else
				FLASHARGS+="reboot\" ";
			fi
		fi
	fi
	FLASHARGS+="${SKIPUID} ";
	if [ -n "${usb_instance}" ]; then
		FLASHARGS+="--instance ${usb_instance} ";
	fi;
	# Add keyfile if provided
	if [ "${keyfile}" != "" ]; then
		FLASHARGS+="--key \"${keyfile}\" ";
	fi;
	echo "./${flashappname} ${FLASHARGS}";
	cmd="./${flashappname} ${FLASHARGS}";
	eval ${cmd};
	chkerr "Failed to flash/read ${target_board}.";
	if [ "${read_part_name}" != "" ]; then
		#
		# Save signed image with .signed extension,
		#
		if [ ${need_sign} -eq 1 ]; then
			mv -f "${target_partfile}" "${target_partfile}.signed";
			# remove the sign header
			if [ "${CHIPID}" = "0x21" ]; then
				header_sz=600           # 0x258 bytes
			elif [ "${CHIPID}" = "0x18" ]; then
				header_sz=400           # 0x190 bytes
			elif [ "${CHIPID}" = "0x19" ]; then
				header_sz=4096           # 0x1000 bytes
			fi;
			dd if="${target_partfile}.signed" of="${target_partfile}" \
				bs="${header_sz}" skip=1
		fi;
		echo "*** The ${tmp_updateid} has been read successfully. ***";
		if [ "${target_partname}" = "APP" -a -x mksparse ]; then
			echo -e "\tConverting RAW image to Sparse image... ";
			mv -f ${target_partfile} ${target_partfile}.raw;
			./mksparse -v --fillpattern=0 ${target_partfile}.raw ${target_partfile};
		fi;
	else
		if [ ${no_flash} -eq 1 ]; then
			echo "*** ${target_partfile} has been signed successfully. ***";
		else
			echo "*** The ${tmp_updateid} has been updated successfully. ***";
		fi;
	fi;
	exit 0;
fi;

# Init flash args
FLASHARGS="";

if [ ${bup_blob} -eq 0 ] && [ ${rcm_boot} -eq 0 ]; then
	# both --bup and --rcm-boot are handled outside odmsign
	if [ -f odmsign.func ]; then
		source odmsign.func;
		odmsign_ext;
		if [ $? -ne 0 ]; then
			exit 1;
		fi;
	else
		if [ "${sbk_keyfile}" != "" ]; then
			# SBK is only handled by secure boot package
			echo "Error: missing secure boot package";
			exit 1;
		fi;
	fi;
fi;

if [ -n "${usb_instance}" ]; then
	FLASHARGS+="--instance ${usb_instance} ";
fi;
FLASHARGS+="--bl ${flashername} ${BCT} ${bctfilename}";
if [ "${CHIPID}" = "0x19" ]; then
	FLASHARGS+=",${bctfile1name} ";
fi
FLASHARGS+=" --odmdata ${odmdata} ";
FLASHARGS+="${DTBARGS}${MTSARGS}${SOSARGS}${NCTARGS}${FBARGS}${NV_ARGS} ";
FLASHARGS+="--cfg ${localcfgfile} ";
if [ "${CHIPMAJOR}" != "" ]; then
	FLASHARGS+="--chip \"${tegraid} ${CHIPMAJOR}\" ";
else
	FLASHARGS+="--chip ${tegraid} ";
fi;
FLASHARGS+="${BCTARGS} ";
FLASHARGS+="${BINSARGS} ";
FLASHARGS+="${SKIPUID} ";
FLASHARGS+="${T21BINARGS} ";

# Support PKC signing when flashing
if [ "${keyfile}" != "" ]; then
		FLASHARGS+=" --key \"${keyfile}\" ";
fi;
flashcmd="./${flashappname} ${FLASHARGS}";
echo "${flashcmd}";
flashcmdfile="${BL_DIR}/flashcmd.txt";
echo "saving flash command in ${flashcmdfile}";
echo "${flashcmd}" > "${flashcmdfile}";
# Remove --skipuid flag for running flash command tegraflash.py directly
sed -i 's/--skipuid//g' "${flashcmdfile}"

# For Windows flashing or rcmboot
sata_boot_ext="sb"
rcm_boot_ext="rb"
kernel_dtb_file="kernel_dtb_filename.txt"
if [ ${rcm_boot} -eq 0 ]; then
	flashargfile="${BL_DIR}/flash_parameters.txt";
	cp -f ${localbootfile} ${localbootfile}.${sata_boot_ext};
	chkerr "Failed to copy boot image file ${localbootfile}.";
	cp -f ${localcfgfile} ${localcfgfile}.${sata_boot_ext};
	chkerr "Failed to copy partition layout file ${localcfgfile}.";
	cp -f ${dtbfilename} ${dtbfilename}.${sata_boot_ext};
	chkerr "Failed to copy kernel dtb file ${dtbfilename}.";
else
	flashargfile="${BL_DIR}/rcmboot_parameters.txt";
	cp -f ${localbootfile} ${localbootfile}.${rcm_boot_ext};
	chkerr "Failed to copy boot image file ${localbootfile}.";
	cp -f initrd initrd.${rcm_boot_ext};
	chkerr "Failed to copy initrd image file initrd.";
fi;
echo "${FLASHARGS}" > "${flashargfile}";
# Remove --skipuid flag for running flash command tegraflash.py directly
sed -i 's/--skipuid//g' "${flashargfile}"

# generate batch command for Windows flashing
flash_win_file="${BL_DIR}/flash_win.bat";
flash_win_cmd="python .\\win_tools\\${flashappname}"
echo "saving Windows flash command to ${flash_win_file}";
echo -n "${flash_win_cmd} " > "${flash_win_file}";
cat "${flashargfile}" >> "${flash_win_file}"

# generate bootloader update payload (BUP)
if [ ${bup_blob} -ne 0 ]; then
	bup_gen="${BL_DIR}/l4t_bup_gen.func"
	if [ -f "${bup_gen}" ]; then
		source "${bup_gen}"
		echo "*** Sign and generate BUP... *** ";
		if [ "${BOARDID}" = "" ]; then
			echo "Error: BOARDID is missing. BOARDID can be either set by "\
				"environment variable BOARDID or by reading from on-board "\
				"EEPROM."
			exit 1
		fi
		if [ "${fuselevel}" = "" ]; then
			echo "Error: fuselevel is missing."
			exit 1
		fi;
		if [ "${FAB}" = "" ]; then
			echo "Error: FAB # is missing."
			exit 1
		fi;
		l4t_bup_gen "${flashcmd}" "${spec}" "${fuselevel}" "${target_board}" \
						"${keyfile}" "${CHIPID}"
	else
		echo ""
		echo "Error: Missing ${bup_gen}"
		echo ""
		exit 1
	fi;
	exit 0;
fi;

if [ ${no_flash} -ne 0 ]; then
	echo "${flashcmd}"
	echo "*** no-flash flag enabled. Exiting now... *** ";
	exit 0;
fi;

echo "*** Flashing target device started. ***"
eval "${flashcmd}";
chkerr "Failed flashing ${target_board}.";
echo "*** The target ${target_board} has been flashed successfully. ***"
if [ "${rootdev_type}" = "internal" ]; then
	echo "Reset the board to boot from internal eMMC.";
elif [ "${rootdev_type}" = "network" ]; then
	if [ "${nfsroot}" != "" ]; then
		echo -n "Make target nfsroot(${nfsroot}) exported ";
		echo "on the network and reset the board to boot";
	else
		echo -n "Make the target nfsroot exported on the ";
		echo -n "network, configure your own DHCP server ";
		echo -n "with \"option-root=<nfsroot export path>;\" ";
		echo "properly and reset the board to boot";
	fi;
else
	echo -n "Make the target filesystem available to the device ";
	echo -n "and reset the board to boot from external ";
	echo "${target_rootdev}.";
fi;
echo;
exit 0;

# vi: ts=8 sw=8 noexpandtab
