#!/bin/bash

whereami=$PWD
dtb_id=a02
date=$(date -Idate)
flashdir=flash-dtb-update-$date

rm -rf /tmp/$flashdir /tmp/$flashdir.tar.gz
mkdir /tmp/$flashdir

echo 'declare -A partitions=(\' > /tmp/$flashdir/partitions
sed -n -r -e "/EBT|RP1|WB0|LNX|DTB/p" bootloader/signed/partitions >> /tmp/$flashdir/partitions
echo ")" >> /tmp/$flashdir/partitions

source /tmp/$flashdir/partitions
for p in ${partitions[@]} ; do
	eval $p
	echo "Copying $part_file to /tmp/$flashdir/"
	cp bootloader/signed/$part_file /tmp/$flashdir/
done

cp ./flashme.sh /tmp/$flashdir
cp ./FLASHME_README /tmp/$flashdir

cd /tmp/$flashdir/
md5sum * >../hash.md5
mv ../hash.md5 ./
cd ..

tar --owner=0 --group=0 -czvf $flashdir.tar.gz $flashdir/*
