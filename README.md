# jetson-nano-support

## SPI

The spi directory contains dtb and u-boot binaries for the DevKit
with part number p3448-0000-p3449-0000-a02 as well as the patch files
used to create them.  Together they enable both spi1 and spi2, or just spi1,
on the 40-pin expansion connector and create /dev nodes for spidev0.0, spidev0.1
and for spidev1.0 and spidev1.1 if spi2 is enabled.

To use these files without modification you'll still need to download
and unpack the 32.2.1 version of Linux for Tegra found at
https://developer.nvidia.com/embedded/linux-tegra.
You'll also need to download this repository of course.

You do NOT need to install the root filesystem under rootfs for
this procedure.  It's not needed.

The following instructions assume that both the resulting
Linux_for_Tegra and jetson-nano-support directories are installed in
`/usr/src/nano` but you can install them anywhere on the host Linux computer.

### Setup

** NOTE: You should test this procedure on a freshly prepared SD card before
trying it on a card that has already had its root filesystem customized.  Once
you're comfortable with the results, you should be able to flash a customized
card without disturbing the root filesystem.

Make sure your Jetson Nano Development Kit boots and is fully
functional before proceeding.  If it's not, continuing will only
make things more confusing.

### Copy the binary files

If you want to modify the device tree before flashing, skip down to the Customization
section to create new u-boot.bin and tegra210-p3448-0000-p3449-0000-a02.dtb
files instead of copying the ones provides in this repo.

Otherwise:

For both spi1 and spi2:
```
$ cd /usr/src/nano
$ cp jetson-nano-support/spi/u-boot-spi1-spi2.bin Linux_for_Tegra/bootloader/t210ref/p3450-porg/u-boot.bin
$ cp jetson-nano-support/spi/tegra210-p3448-0000-p3449-0000-a02-spi1-spi2.dtb Linux_for_Tegra/kernel/dtb/tegra210-p3448-0000-p3449-0000-a02.dtb
```

Or to enable only spi1 leaving the spi2 pins avaialble for GPIO:
```
$ cd /usr/src/nano
$ cp jetson-nano-support/spi/u-boot-spi1-only.bin Linux_for_Tegra/bootloader/t210ref/p3450-porg/u-boot.bin
$ cp jetson-nano-support/spi/tegra210-p3448-0000-p3449-0000-a02-spi1-only.dtb Linux_for_Tegra/kernel/dtb/tegra210-p3448-0000-p3449-0000-a02.dtb
```

### Copy updated flash scripts
```
$ cp jetson-nano-support/flash/flash2.sh Linux_for_Tegra/
$ cp jetson-nano-support/flash/flash-partitions.sh Linux_for_Tegra/
```
`flash2.sh` is a copy of `Linux_for_Tegra/flash.sh` that has an added
option to not coldboot after flashing a partition.  Since you have to flash
3 partitions, this just saves time and the hassle of having to keep placing
the device in recovery mode between flashes.
`flash-partitions.sh` is just a quick script to allow flashing multiple
partitions at the same time.

### Prepare the device for flashing

* Shut down the device and remove power.
* Place a jumper on pins 3 and 4 of the front panel header.
* Connect a cable from the MicroUSB connector to your host Linux computer.
* It is highly recommended to connect the device's serial port to the host computer as well.  If you do, open your favorite terminal emulator to watch the boot and flash progress.
* In a terminal on the host computer, run `sudo dmesg -wePL` to confirm that the device registers to USB once powered on.
* Apply power.

The device should now be in recovery mode.  The only indication of
this will be messages in the dmesg window on the host...
```
new high-speed USB device number 114 using xhci_hcd
New USB device found, idVendor=0955, idProduct=7f21, bcdDevice= 1.02
New USB device strings: Mfr=1, Product=2, SerialNumber=0
Product: APX
Manufacturer: NVIDIA Corp.
```

The device is now ready for flashing.


### Flash the partitions

There are 4 partitions that have to be flashed.
* EBT is the cboot bootloader.
* LNX is technically the Linux kernel but on these boards, it's really the u-boot bootloader.
* DTB is the device tree blob that the actual Linux kernel will use.
* RP1 is another copy of the device tree blob.

To flash all 4 at the same time...
```
$ cd /usr/src/nano/Linux_for_Tegra
$ ./flash-partitions.sh --partitions=EBT,RP1,LNX,DTB jetson-nano-qspi-sd mmcblk0p1
```
This will flash a partition, reboot to recovery, then flash the next partition, etc.
After the last partition, the board will coldboot.  If you have the serial console
connected, you'll see the rebooting/flashing progress and finally you should
see the u-boot menu and then the kernel load process.

If you didn't unpack the root filesystem to Linux_for_Tegra/rootfs, you may see
harmless messages like
`sed: can't read /usr/src/nano/Linux_for_Tegra/rootfs/etc/nv_boot_control.conf: Not a directory`
They can be safely ignored.`

### Confirm

On the device...
```
# ls -al /dev/spi*
crw------- 1 root root 153, 0 Sep  4 16:03 spidev0.0
crw------- 1 root root 153, 1 Sep  4 16:03 spidev0.1
```
and if spi2 was enabled...
```
crw------- 1 root root 153, 2 Sep  4 16:03 spidev1.0
crw------- 1 root root 153, 3 Sep  4 16:03 spidev1.1
```

### Customization

In order to customize the device tree, you'll need the sources.  Fortunately,
there's a script for that:
```
$ cd /usr/src/nano/Linux_for_Tegra
$ ./source_sync.sh -t tegra-l4t-r32.2.1
```
This will take a few minutes to complete.  While it's downloading, make sure you
have the proper toolchain installed as described here:
https://docs.nvidia.com/jetson/archives/l4t-archived/l4t-322/index.html#page/Tegra%2520Linux%2520Driver%2520Package%2520Development%2520Guide%2Fxavier_toolchain.html%23

*The following instructions assume you have the CROSS_COMPILE environment variable
set to `$TOOLCHAIN_PATH/aarch64-linux-gnu-` where `$TOOLCHAIN_PATH` is wherever
you've installed the toolchain.*

#### U-Boot

If you're just changing the slave SPI devices and not altering how the
pins are assigned or initialized, you don't need to make any changes to
u-boot.  Simply use the u-boot.bin provided in this repo.

##### Patch and modify

```
$ cd /usr/src/nano/Linux_for_Tegra/sources/u-boot
$ patch -p1 < /usr/src/nano/jetson-nano-support/spi/uboot-spi1-spi2.patch
patching file board/nvidia/p3450-porg/pinmux-config-p3450-porg.h
```
Use the `spi1-only` patch file if you only want spi1.
Adjust board/nvidia/p3450-porg/pinmux-config-p3450-porg.h as needed.  

##### Build and copy
```
$ make p3450-porg_defconfig
### You may see some -wformat-overflow warnings.  These can be ignored.
```
If you have a version of the device tree compiler (dtc) installed on
your host system that's newer than the one provided by Linux_for_Tegra (1.4.0),
the following `make` command may produce lots of warnings when the device tree
blobs are created.  Although they seem to be harmless, we can force `make` to
use the compiler provided by Linux_for_Tegra:
```
$ make DTC=/usr/src/nano/Linux_for_Tegra/kernel/dtc
```
Assuming the build was successful, copy the u-boot binary to the install location:
```
$ cp u-boot.bin /usr/src/nano/Linux_for_Tegra/bootloader/t210ref/p3450-porg/
```

#### Kernel Device Tree

##### Patch and modify

```
$ cd /usr/src/nano/Linux_for_Tegra/sources/hardware/nvidia/platform/t210/porg
$ patch -p1 < /usr/src/nano/jetson-nano-support/spi/kernel-dtb-spi1-spi2.patch
patching file kernel-dts/porg-platforms/tegra210-porg-gpio-p3448-0000-a02.dtsi
patching file kernel-dts/porg-platforms/tegra210-porg-pinmux-p3448-0000-a02.dtsi
patching file kernel-dts/tegra210-porg-p3448-common.dtsi
```
Use the `spi1-only` patch file if you only want spi1.

If you need to alter the slave devices assigned to the SPI controllers, those
definitions are in `kernel-dts/tegra210-porg-p3448-common.dtsi` starting at around
line 204.  If you need to modify the pin assignments or initialization parameters,
you'll probably need to modify all 3 patched files.

##### Build and copy
Building is actually done from the kernel sources.  The Makefile automatically
pulls in the sources from Linux_for_Tegra/sources/hardware/nvidia/platform/t210/porg.
```
$ cd /usr/src/nano/Linux_for_Tegra/sources/kernel/kernel-4.9
$ make ARCH=arm64 tegra_defconfig
$ make ARCH=arm64 dtbs
```
Assuming the build was successful, copy the dtb to the install location:
```
$ cp arch/arm64/boot/dts/tegra210-p3448-0000-p3449-0000-a02.dtb /usr/src/nano/Linux_for_Tegra/kernel/dtb/
```
Return to the *Flash the partitions* section above.
