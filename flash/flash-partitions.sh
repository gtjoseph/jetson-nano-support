#!/bin/bash

declare -i OPTION_COUNT=0
declare -a POSITIONAL_ARGS
for a in $* ; do
	OPTION_COUNT+=1
	case "$a" in
		--*=*)
			[[ $a =~ --([^=]+)=(.*) ]]
			l=${BASH_REMATCH[1]//-/_}
			r=${BASH_REMATCH[2]}
			eval ${l^^}=\"$r\"
			;;
		--*)
			[[ $a =~ --(.+) ]]
			l=${BASH_REMATCH[1]//-/_}
			eval ${l^^}=1
			;;
		*)
			POSITIONAL_ARGS+=($a)
			;;
	esac
done

whoami=$(whoami)

if [ "$whoami" != "root" ] ; then
	echo "You must be root to flash."
	exit 1
fi

if [ -z "$PARTITIONS" -o ${#POSITIONAL_ARGS[@]} -ne 2 ] ; then
	cat <<EOF
Usage: sudo ./flash-partitions.sh --partitions=<part1>[,<part2> ... ] <target_board> <rootdev>
Where,
	partX: DTB,LNX, etc
	target board: Valid target board name. I.E. jetson-nano-qspi-sd
	rootdev: Proper root device.  I.E.  mmcblk0p1
		(flash.sh requires <rootdev> even if the rootfs isn't being flashed)
EOF
	exit 1
fi

LDK_DIR=$(dirname $(readlink -f $0))
target=${POSITIONAL_ARGS[0]}
source ${LDK_DIR}/${target}.conf
flashconf=${LDK_DIR}/bootloader/t210ref/cfg/$EMMC_CFG

declare -a parts
IFS=,
for p in $PARTITIONS ; do
	lookfor=$p
	[ $p == "DTB" ] && lookfor=DXB
	grep -q "partition name=\"$lookfor\"" $flashconf || { echo "Partition $p is not valid" ; exit 1 ; }
	parts+=( $p )
done

for part in ${parts[@]} ; do
    r="--reboot-recovery"
    [ $part == ${parts[-1]} -a -z "$NO_REBOOT" ] && r=""
	echo "*"
	echo "* Flashing partition ${part}"
    ${NO_FLASH:+echo} ./flash2.sh $r --no-systemimg -k $part ${POSITIONAL_ARGS[@]} || \
        { echo "An error has occurred" ; exit 1 ; }
	echo "* Completed flashing partition ${part}"
	[ "x$r" == "x" ] && echo "* Rebooting"
	echo "*"
done
