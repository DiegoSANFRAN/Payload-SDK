#!/usr/bin/env bash
set -euxo pipefail

G=/sys/kernel/config/usb_gadget/psdk

# Stop FunctionFS helpers
pkill -f "/usr/local/bin/startup_bulk /dev/usb-ffs/bulk" 2>/dev/null || true

# Tear down RNDIS bridge/NICs
for nic in usb0 usb1; do ip link set "$nic" nomaster 2>/dev/null || true; done
ip link set pi4br0 down 2>/dev/null || true
ip link del pi4br0 2>/dev/null || true

# Unbind gadget from UDC
[ -e "$G/UDC" ] && echo "" > "$G/UDC" || true

# Remove config symlinks (RNDIS + BULK*)
if [ -d "$G/configs/c.1" ]; then
  find "$G/configs/c.1" -maxdepth 1 -type l -exec rm -f {} + 2>/dev/null || true
  rmdir "$G/configs/c.1/strings/0x409" 2>/dev/null || true
  rmdir "$G/configs/c.1" 2>/dev/null || true
fi

# Unmount all FunctionFS mounts and drop functions
shopt -s nullglob
for d in /dev/usb-ffs/bulk*; do umount -lf "$d" 2>/dev/null || true; done
for f in "$G"/functions/ffs.bulk*; do [ -d "$f" ] && rmdir "$f" 2>/dev/null || true; done
shopt -u nullglob

# Remove RNDIS function & MS OS descriptors
rmdir "$G/functions/rndis.usb0/os_desc/interface.rndis" 2>/dev/null || true
rmdir "$G/functions/rndis.usb0" 2>/dev/null || true
rm -f "$G/os_desc/c.1" 2>/dev/null || true
rmdir "$G/os_desc" 2>/dev/null || true

# Drop strings & the gadget dir
rmdir "$G/strings/0x409" 2>/dev/null || true
rmdir "$G" 2>/dev/null || true

# Cleanup empty /dev/usb-ffs/bulk* dirs
shopt -s nullglob
for d in /dev/usb-ffs/bulk*; do rmdir "$d" 2>/dev/null || true; done
shopt -u nullglob

exit 0
