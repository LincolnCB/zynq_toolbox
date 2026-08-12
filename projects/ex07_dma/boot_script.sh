#!/bin/sh
# Runs once at boot (installed to /etc/init.d by the boot-script recipe; see
# scripts/petalinux/boot_script.sh).
#
# Relax the u-dma-buf interfaces so the mcdma-loopback demo runs without root.
# This rootfs has no udev, and u-dma-buf creates its /dev node root-owned 0600 and
# its sysfs cache-sync controls root-owned 0664 -- neither has a mode knob (unlike
# pl-reg, which sets misc.mode = 0666 itself). A boot-time chmod is the udev-free
# way to hand them to a non-root user; a chmod on a sysfs attribute persists for
# the device's lifetime. The MCDMA register window is already non-root via pl-reg
# (/dev/mcdma).

# The buffer node itself (the mmap target).
chmod 0666 /dev/udmabuf* 2>/dev/null || true

# The sysfs controls the program writes: sync_for_device / sync_for_cpu drive the
# single-flush coherency path, and the offset/size/direction/mode attrs may be set
# alongside them. Without these, mmap succeeds but the first sync fails EACCES.
for f in sync_for_device sync_for_cpu sync_offset sync_size sync_direction sync_mode; do
  chmod 0666 /sys/class/u-dma-buf/*/"$f" 2>/dev/null || true
done
