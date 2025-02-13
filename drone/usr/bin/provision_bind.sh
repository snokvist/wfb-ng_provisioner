#!/bin/sh

# ----------------------------------------------------------
# Exit code definitions (for readability/reference)
# ----------------------------------------------------------
# #define EXIT_ERR    1   # (Fatal errors)
# #define EXIT_BIND   2   # (File received/bind operation)

# ----------------------------------------------------------
# Cleanup function
# ----------------------------------------------------------
cleanup() {
    echo "[CLEANUP] Stopping wifibroadcast, wfb_rx, wfb_tx, wfb_tun."
    wifibroadcast stop
    killall -q wfb_rx
    killall -q wfb_tx
    killall -q wfb_tun
    sleep 1
    wifibroadcast start
}

# ----------------------------------------------------------
# Trap signals
# ----------------------------------------------------------
# - INT covers Ctrl+C
# - EXIT covers *any* exit (normal or error)
trap cleanup INT EXIT

# ----------------------------------------------------------
# (Optional) Initial cleanup to stop anything already running
# ----------------------------------------------------------
wifibroadcast stop
killall -q wfb_rx
killall -q wfb_tx
killall -q wfb_tun
sleep 1

# ----------------------------------------------------------
# Setup commands
# ----------------------------------------------------------
iw wlan0 set monitor none
iw wlan0 set channel 165 HT20
iw reg set US
sleep 1

echo "- Starting bind process..."

if ! [ -f /etc/bind.key ]
then
    echo "OoLVgEYyFofg9zdhfYPks8/L8fqWaF9Jk8aEnynFPsXNqhSpRCMbVKBFP4fCEOv5DGcbXmUHV5eSykAbFB70ew==" \
        | base64 -d > /etc/bind.key
fi

echo "- Starting wfb_rx, wfb_tx, wfb_tun"
wfb_rx -p 255 -u 5800 -K /etc/bind.key -i 10531917 wlan0 &> /dev/null &
wfb_tx -p 127 -u 5801 -K /etc/bind.key -M 1 -S 0 -L 0 \
    -k 1 -n 2 -i 10531917 wlan0 &> /dev/null &
wfb_tun -a 10.5.99.2/24 &

# Sleep needed for wfb_tun to initialize
sleep 4

# ----------------------------------------------------------
# Run drone_provisioner and capture its exit code
# ----------------------------------------------------------
drone_provisioner --listen-duration 10
EXIT_CODE=$?

echo "drone_provisioner exited with code $EXIT_CODE."

# ----------------------------------------------------------
# Handle exit codes
# ----------------------------------------------------------
case $EXIT_CODE in
    0)
        echo "Listen period ended. Exiting with code 0."
        exit 0
        ;;
    1)
        echo "Fatal errors. Exiting with code 1."
        exit 1
        ;;
    2)
        echo "File received and saved successfully (BIND). Continuing execution..."
        
        cd /tmp/bind || exit 2
        
        # Decompress the .tar.gz
        gunzip bind.tar.gz
        
        # Optional: validate that bind.tar now exists
        if [ ! -f bind.tar ]; then
            echo "ERR: bind.tar not found after gunzip."
            exit 2
        fi
        
        # Show what's in the tar (optional debug)
        # tar -tvf bind.tar
        
        # Extract the tar
        tar x -f bind.tar
        
        # Detect the top-level directory name (assuming exactly one)
        extracted_dir="$(tar -tf bind.tar | head -n1 | cut -d/ -f1)"
        
        # Check that the directory exists
        if [ -n "$extracted_dir" ] && [ -d "$extracted_dir" ]; then
            cd "$extracted_dir" || exit 2
            echo "Changed directory to: $extracted_dir"
        else
            echo "ERR: Could not identify a single top-level directory from bind.tar"
            exit 2
        fi
        
        # Validate checksums
        if ! [ -f checksum.txt ] || ! sha1sum -c checksum.txt
        then
            echo "ERR: Checksum failed."
            exit 2
        fi

        # --------------------------------------------------
        # Copy system files, as needed
        # --------------------------------------------------
        #If overlay folder exists, copy all its files
        if [ -d overlay/ ]; then
            cp -r overlay/* /
            echo "Overlay files copied to root."
        fi

        #In addition, if there are SPECIFIC files exisisting in file system hierarchy
        #they should overwrite the overlay files.
        if [ -f etc/wfb.yaml ]; then
            cp etc/wfb.yaml /etc/wfb.yaml
            echo "Copy success: /etc/wfb.yaml"
        fi

        if [ -d etc/sensors/ ]; then
            cp etc/sensors/* /etc/sensors/
            echo "Copy success: Sensor bins"
        fi

        if [ -f etc/majestic.yaml ]; then
            cp etc/majestic.yaml /etc/majestic.yaml
            /etc/init.d/S95majestic restart
            echo "Copy & restart success: /etc/majestic.yaml"
        fi

        if [ -f lib/modules/4.9.84/sigmastar/sensor_imx335_mipi.ko ]; then
            cp lib/modules/4.9.84/sigmastar/sensor_imx335_mipi.ko \
               /lib/modules/4.9.84/sigmastar/sensor_imx335_mipi.ko
            echo "Copy success (restart required): sensor_imx335_mipi.ko"
        fi
        #Execute arbitrary commands, use with caution.
        #If permanent changes are added with this, submit a PR instead
        if [ -f ./custom_script.sh ]; then
            chmod +x ./custom_script.sh
            ./custom_script.sh
            echo "Copy success and executed: custom_script.sh"
        fi

        # Cleanup
        rm -rf /tmp/bind
        exit 2
        ;;
    *)
        echo "Unexpected error occurred. Exiting with code $EXIT_CODE."
        exit $EXIT_CODE
        ;;
esac

