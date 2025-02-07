#!/bin/bash
# Usage:
#   ./script.sh <wlan_mode> <operation> [optional_parameter]
#
# Examples:
#   ./script.sh bind_mode bind /path/to/bind_data_folder
#   ./script.sh flash_mode flash
#   ./script.sh info_mode info
#   ./script.sh version_mode version
#   ./script.sh unbind_mode unbind
#   ./script.sh backup_mode backup /path/to/backup_folder

# --- BEGIN TRAP-BASED CLEANUP ---
# Define a cleanup function that will be called on EXIT (and optionally SIGINT, SIGTERM if desired).
cleanup() {
    echo "Cleaning up background processes..."
    # If WFB_PID is set and the process is still running, gracefully kill it
    if [[ -n "$WFB_PID" ]] && ps -p "$WFB_PID" &>/dev/null; then
        echo "Stopping wfb-server (PID: $WFB_PID)..."
        kill -TERM "$WFB_PID"   # Send SIGTERM for graceful shutdown
        wait "$WFB_PID"         # Wait until wfb-server actually stops
    fi
}
# Trap exit (and optionally signals) and call cleanup
trap cleanup EXIT
# --- END TRAP-BASED CLEANUP ---

# Check that at least two arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <wlan_mode> <operation> [optional_parameter]"
    exit 1
fi

# Assign arguments
wlan_mode=$1         # First argument: mode for wlan_init.sh
operation=$2         # Second argument: determines which connect.py command to run
optional_param=$3    # Third argument: used only for bind and backup operations (folder path)

# Start wfb-server in the background and store its PID
# Adjust --profiles, --wlans, or any other arguments as needed
echo "Starting wfb-server..."
wfb-server --profiles bind_drone --wlans "$wlan_mode" &
WFB_PID=$!
sleep 3  # Give wfb-server some time to come up

# Execute the corresponding connect.py command based on the operation
case "$operation" in
    bind)
        # Require a bind data folder as an extra parameter
        if [ -z "$optional_param" ]; then
            echo "Usage for bind: $0 <wlan_mode> bind <bind_data_folder>"
            exit 1
        fi
        echo "Executing connect.py with --bind $optional_param"
        ./connect.py --bind "$optional_param"
        ;;
    flash)
        echo "Executing connect.py with --flash flash/openipc.ssc338q-nor-fpv.tgz"
        ./connect.py --flash flash/openipc.ssc338q-nor-fpv.tgz
        ;;
    info)
        echo "Executing connect.py with --info"
        ./connect.py --info
        ;;
    version)
        echo "Executing connect.py with --version"
        ./connect.py --version
        ;;
    unbind)
        echo "Executing connect.py with --unbind"
        ./connect.py --unbind
        ;;
    backup)
        # Require a backup folder path as an extra parameter
        if [ -z "$optional_param" ]; then
            echo "Usage for backup: $0 <wlan_mode> backup <backup_folder>"
            exit 1
        fi
        echo "Executing connect.py with --backup $optional_param"
        ./connect.py --backup "$optional_param"
        ;;
    *)
        echo "Invalid operation: $operation. Valid operations are: bind, flash, info, version, unbind, or backup."
        exit 1
        ;;
esac

# If you have any other cleanup steps (e.g. final_cleanup.sh), you can do them now:
# ./final_cleanup.sh

# By default the script exits here, triggering the cleanup trap function.
exit 0
