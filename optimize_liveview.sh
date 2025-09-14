#!/bin/bash
# Additional optimization script for liveview-only mode
# Run this before starting your DJI SDK application

echo "=== DJI PSDK Liveview Optimization ==="

# Set CPU governor to performance for better USB throughput
echo "Setting CPU governor to performance..."
sudo cpufreq-set -g performance 2>/dev/null || echo "cpufreq-set not available"

# Increase USB buffer sizes
echo "Optimizing USB buffer sizes..."
echo 16384 | sudo tee /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null || true

# Set IO scheduler to deadline for better real-time performance
echo "Setting IO scheduler..."
for disk in /sys/block/sd*/queue/scheduler; do
    if [ -f "$disk" ]; then
        echo deadline | sudo tee "$disk" 2>/dev/null || true
    fi
done

# Kill any competing USB processes (be careful with this)
echo "Checking for competing processes..."
sudo pkill -f "usb" 2>/dev/null || true

echo "Optimization complete. Start your DJI SDK application now."
