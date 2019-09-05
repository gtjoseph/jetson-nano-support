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

declare -a parts
IFS=,
for p in $PARTITIONS ; do parts+=( $p ) ; done

for part in ${parts[@]} ; do
    r="--reboot-recovery"
    [ $part == ${parts[-1]} -a -z "$NO_REBOOT" ] && r=""
    ${NO_FLASH:+echo} ./flash2.sh $r --no-systemimg -k $part ${POSITIONAL_ARGS[@]} || \
        { echo "An error has occurred" ; exit 1 ; }
done
