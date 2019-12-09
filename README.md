# jetson-nano-support

### SPI

The spi directory contains dtb and u-boot binaries for the DevKit
with part number p3448-0000-p3449-0000-a02 as well as the patch files
used to create them.  Together they enable spi1 on the 40-pin connector and
create a device node for /dev/spidev0.0.

Unlike earlier install methods, you can install the binaries
_on a running Nano_ without the need for any other downloads, compiling, etc.  

The [latest release](https://github.com/gtjoseph/jetson-nano-support/releases/latest)
contains a tarball which, when extracted
and run on the Nano, will update the appropriate partitions.

Extract the tarball then change to the directory created.
Run `sudo ./flashme.sh /dev/mmcblk0` (assuming /dev/mmcblk0 contains the system partitions)
Reboot and you should have the spidev0.0 device.

**NOTE:** This program doesn't touch any other partitions or files so it's safe to run
on an existing customized filesystem. The program will also make sure that the needed
partitions are already on the device before it writes anything.

You can also run this program on any other computer to update an SDCard
that's not currently in a Nano.  The above note still applies.


### Customization

The patches that created the DTB and u-boot binaries are included here.  You'll
need to follow the instructions in the Nvidia documentation for customizing
the DTBs and u-boot.

If you want to create your own flash package you can use the scripts in the
[flash](flash) directory.

* Use the Nvidia documentation to create your DTB and u-boot images.  
  Follow the instructions to copy the DTBs to your Linux_for_Tegra/kernel/dtb
  directory, and your u-boot.bin file to Linux_for_Tegra/bootloader/t210ref/p3450-porg/
  directory.

* From your Linux_for_Tegra directory, run `sudo ./create-signed-partitions.sh -r 200`
  where "200" is the board rev id for the "a02" boards.  Adjust as necessary.
  This command will apply the DTBs to the appropriate partition blobs and sign
  the partition blobs.  They'll be located in bootloader/signed directory.

* From your Linux_for_Tegra directory, run `./create-flash-package.sh`.
  You don't need to be root for this command.  When it's done (it'll be very quick)
  you should have a /tmp/flash-dtb-update-<date>.tar.gz file that you can copy
  to any Nano and execute as above.
