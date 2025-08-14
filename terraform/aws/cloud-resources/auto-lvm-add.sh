#!/bin/bash
# Usage: auto-lvm-add.sh /dev/nvmeXn1
set -e

DEV=$1
VG_NAME="data-vg"
LV_NAME="data-lv"
MOUNT_POINT="/mnt/data"


# Wait for device to be ready
udevadm settle --exit-if-exists=$DEV

# Check if already a PV
if ! pvs | grep -q "$DEV"; then
  pvcreate $DEV
fi

# Create or extend VG
if ! vgs | grep -q "$VG_NAME"; then
  vgcreate $VG_NAME $DEV
else
  # Only extend if PV not already in VG
  if ! vgdisplay $VG_NAME | grep -q "$DEV"; then
    vgextend $VG_NAME $DEV
  fi
fi

# Create LV if not present
if ! lvs | grep -q "$LV_NAME"; then
  lvcreate -l 100%FREE -n $LV_NAME $VG_NAME
  mkfs.ext4 /dev/$VG_NAME/$LV_NAME
else
  # Only extend if there is free space
  FREE_EXT=$(vgdisplay $VG_NAME | awk '/Free  PE/ {print $3}')
  if [ "$FREE_EXT" != "0" ]; then
    lvextend -l +100%FREE /dev/$VG_NAME/$LV_NAME
    resize2fs /dev/$VG_NAME/$LV_NAME
  fi
fi

# Always ensure mount point exists
mkdir -p $MOUNT_POINT

# Ensure fstab entry exists (idempotent)
if ! grep -q "/dev/$VG_NAME/$LV_NAME" /etc/fstab; then
  echo "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

