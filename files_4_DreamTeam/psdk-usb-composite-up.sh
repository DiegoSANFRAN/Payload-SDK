#!/usr/bin/env bash
set -euxo pipefail

G=/sys/kernel/config/usb_gadget/psdk
BULK_NODES=3

preflight_reset() {
  # Unbind if bound (ignore errors)
  [[ -e "$G/UDC" ]] && echo "" > "$G/UDC" || true

  # Detach MS OS descriptors (important before removing RNDIS)
  [[ -L "$G/os_desc/c.1" ]] && rm -f "$G/os_desc/c.1" || true
  [[ -e "$G/os_desc/use" ]] && echo 0 > "$G/os_desc/use" || true

  # Remove config symlinks (ffs.*, rndis.usb0) so functions can be rmdir'ed
  [[ -d "$G/configs" ]] && find "$G/configs" -type l -exec rm -f {} + || true

  # Unmount FunctionFS and drop ffs.* functions
  for n in 1 2 3; do
    MP="/dev/usb-ffs/bulk$n"
    mountpoint -q "$MP" && umount -lf "$MP" || true
    [[ -d "$G/functions/ffs.bulk$n" ]] && rmdir "$G/functions/ffs.bulk$n" || true
  done

  # RNDIS function removal in the only order kernel accepts
  [[ -d "$G/functions/rndis.usb0/os_desc/interface.rndis" ]] && rmdir "$G/functions/rndis.usb0/os_desc/interface.rndis" || true
  [[ -d "$G/functions/rndis.usb0/os_desc" ]]              && rmdir "$G/functions/rndis.usb0/os_desc" || true
  [[ -d "$G/functions/rndis.usb0" ]]                       && rmdir "$G/functions/rndis.usb0" || true

  # Remove empty containers
  [[ -d "$G/functions" ]]                  && rmdir "$G/functions" || true
  [[ -d "$G/configs/c.1/strings/0x409" ]]  && rmdir "$G/configs/c.1/strings/0x409" || true
  [[ -d "$G/configs/c.1" ]]                && rmdir "$G/configs/c.1" || true
  [[ -d "$G/os_desc" ]]                    && rmdir "$G/os_desc" || true
  [[ -d "$G/strings/0x409" ]]              && rmdir "$G/strings/0x409" || true

  # Finally remove the gadget dir
  [[ -d "$G" ]] && rmdir "$G" || true

  # Cleanup empty /dev/usb-ffs/bulk* dirs
  shopt -s nullglob
  for d in /dev/usb-ffs/bulk*; do rmdir "$d" 2>/dev/null || true; done
  shopt -u nullglob
}

# --- Kernel bits we need ---
modprobe libcomposite
modprobe usb_f_fs
modprobe usb_f_rndis
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

# If a stale/busy gadget is hanging around, clear it first
preflight_reset

mkdir -p "$G"

# --- Device identity (DJI VID/PID) ---
echo 0x2CA3 > "$G/idVendor"      # DJI
echo 0xF001 > "$G/idProduct"     # Composite (RNDIS + BULK)
# (Optional cosmetics)
mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409"
echo "DJI-PSDK"                 > "$G/strings/0x409/manufacturer"
echo "DJI-PSDK Pi (Composite)"  > "$G/strings/0x409/product"
echo "00000001"                 > "$G/strings/0x409/serialnumber"
echo "RNDIS+BULK"               > "$G/configs/c.1/strings/0x409/configuration"
echo 250                        > "$G/configs/c.1/MaxPower"
echo 0x80                       > "$G/configs/c.1/bmAttributes"  # bus-powered

# --- RNDIS (must be first in the config for Windows, harmless elsewhere) ---
mkdir -p "$G/functions/rndis.usb0" "$G/os_desc" "$G/functions/rndis.usb0/os_desc/interface.rndis"
echo 1       > "$G/os_desc/use"
echo 0xcd    > "$G/os_desc/b_vendor_code"
echo MSFT100 > "$G/os_desc/qw_sign"
echo RNDIS   > "$G/functions/rndis.usb0/os_desc/interface.rndis/compatible_id"
echo 5162001 > "$G/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id"
ln -snf "$G/configs/c.1"               "$G/os_desc/c.1"
ln -snf "$G/functions/rndis.usb0"      "$G/configs/c.1/rndis.usb0"

# --- BULK via FunctionFS (3 nodes) ---
mkdir -p /dev/usb-ffs
for n in $(seq 1 $BULK_NODES); do
  mkdir -p "$G/functions/ffs.bulk$n"
  mkdir -p "/dev/usb-ffs/bulk$n"
  # uid/gid give non-root processes access to ep files; mode 0777 just in case.
  mountpoint -q "/dev/usb-ffs/bulk$n" || mount -t functionfs -o mode=0777,uid=2000,gid=2000 "bulk$n" "/dev/usb-ffs/bulk$n"
  ln -snf "$G/functions/ffs.bulk$n" "$G/configs/c.1/ffs.bulk$n"
done

# --- Start helpers BEFORE binding (one per FunctionFS mount) ---
pkill -f "/usr/local/bin/startup_bulk /dev/usb-ffs/bulk" 2>/dev/null || true
for n in $(seq 1 $BULK_NODES); do
  nohup /usr/local/bin/startup_bulk "/dev/usb-ffs/bulk$n" >"/run/psdk-bulk$n.log" 2>&1 &
done

# --- Wait for each FunctionFS control endpoint (ep0) to appear ---
for i in $(seq 1 50); do
  ok=1
  for n in $(seq 1 $BULK_NODES); do
    [ -e "/dev/usb-ffs/bulk$n/ep0" ] || ok=0
  done
  [ $ok -eq 1 ] && break
  sleep 0.1
done

# --- Bind gadget to the UDC ---
UDC="$(ls /sys/class/udc | head -n1)"
[ -n "$UDC" ] && echo "$UDC" > "$G/UDC"

# --- Bring up RNDIS NIC + bridge (like DJI’s post) ---
# We put the IP on the bridge, not directly on usb0.
udevadm settle -t 5 || true
ip link set usb0 up 2>/dev/null || true
ip addr flush dev usb0 2>/dev/null || true

# Create/refresh bridge at 192.168.55.1/24
ip link add pi4br0 type bridge 2>/dev/null || true
ip addr flush dev pi4br0 2>/dev/null || true
ip addr add 192.168.55.1/24 dev pi4br0 2>/dev/null || true
ip link set pi4br0 up 2>/dev/null || true

# Enslave the RNDIS NIC into the bridge (try usb0 then usb1 as a fallback)
for i in $(seq 1 20); do
  if ip link set usb0 master pi4br0 2>/dev/null; then break; fi
  if ip link set usb1 master pi4br0 2>/dev/null; then break; fi
  sleep 0.2
done

exit 0
