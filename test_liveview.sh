#!/bin/bash
# Simple liveview test script
# This will run the SDK and automatically select liveview options

echo "=== DJI PSDK Liveview Test ==="
echo "This script will:"
echo "1. Start the SDK application"
echo "2. Select camera stream view (option 'c')"
echo "3. Choose normal RGB display (option '0')"
echo "4. Select FPV camera (option '0')"
echo ""
echo "The liveview should start. Press 'q' to quit when ready."
echo ""
read -p "Press Enter to continue..."

cd /home/rsp/work/Payload-SDK/build/bin

# Create input sequence for automated selection
{
    echo "c"      # Camera stream view sample
    sleep 1
    echo "0"      # Normal RGB image display
    sleep 1
    echo "0"      # FPV Camera
    sleep 5       # Wait 5 seconds to see if liveview starts
    echo "q"      # Quit
} | sudo ./dji_sdk_demo_on_rpi_cxx
