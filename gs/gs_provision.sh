#!/bin/bash
# Usage:
#   sudo ./script.sh <wlan_id> <operation> [optional_parameter]
#
# <wlan_id> is a required argument (e.g., "bind_mode", "flash_mode", "info_mode" etc.)
# <operation> must be one of: bind, flash, info, version, unbind, backup
# [optional_parameter] may be required for certain operations (e.g. bind folder, backup folder)
#
# Examples:
#   sudo ./script.sh bind_mode bind /path/to/bind_data_folder
#   sudo ./script.sh flash_mode flash
#   sudo ./script.sh info_mode info
#   sudo ./script.sh version_mode version
#   sudo ./script.sh unbind_mode unbind
#   sudo ./script.sh backup_mode backup /path/to/backup_folder

########################################
# Usage/Help
########################################
usage() {
    echo "Usage:"
    echo "  $0 <wlan_id> <operation> [optional_parameter]"
    echo
    echo "Positional arguments:"
    echo "  <wlan_id>        Required. For example: bind_mode, flash_mode, etc."
    echo "  <operation>      One of: bind, flash, info, version, unbind, backup"
    echo "  [optional_param] Required for 'bind' or 'backup', specifying a folder path."
    echo
    echo "Examples:"
    echo "  sudo $0 bind_mode bind /path/to/bind_data_folder"
    echo "  sudo $0 flash_mode flash"
    echo "  sudo $0 info_mode info"
    echo "  sudo $0 version_mode version"
    echo "  sudo $0 unbind_mode unbind"
    echo "  sudo $0 backup_mode backup /path/to/backup_folder"
    exit 1
}

########################################
# Check for root privileges
########################################
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run with root privileges (try: sudo $0 ...)"
    exit 1
fi

########################################
# Trap-based cleanup
########################################
cleanup() {
    echo "Cleaning up background processes..."
    # If WFB_PID is set and the process is still running, gracefully kill it
    if [[ -n "$WFB_PID" ]] && ps -p "$WFB_PID" &>/dev/null; then
        echo "Stopping wfb-server (PID: $WFB_PID)..."
        kill -TERM "$WFB_PID"   # Send SIGTERM for graceful shutdown
        wait "$WFB_PID"         # Wait until wfb-server actually stops
    fi
}
trap cleanup EXIT

########################################
# Argument checks
########################################
if [[ $# -lt 2 ]]; then
    echo "Error: Not enough arguments provided."
    usage
fi

# Assign arguments
wlan_id="$1"         # First argument: used to pass to wfb-server
operation="$2"       # Second argument: determines which connect.py command to run
optional_param="$3"  # Third argument: used for bind or backup (folder path)

########################################
# stop background wfb-ng services
########################################
systemctl stop wfb-cluster-node
systemctl stop wfb-cluster-manager
systemctl stop wifibroadcast@gs

########################################
# Start wfb-server bind_drone in the background
########################################
echo "Starting wfb-server drone_bind with wlan_id: $wlan_id"
wfb-server --profiles bind_drone --wlans "$wlan_id" &
WFB_PID=$!
sleep 3  # Give wfb-server some time to come up

########################################
# Perform operation using connect.py
########################################
case "$operation" in
    bind)
        # Require a bind data folder as an extra parameter
        if [[ -z "$optional_param" ]]; then
            echo "Error: For 'bind', an additional folder path is required."
            usage
        fi
        echo "Executing connect.py --bind $optional_param"
        ./connect.py --bind "$optional_param"
        ;;
    flash)
        echo "Executing connect.py --flash flash/openipc.ssc338q-nor-fpv.tgz"
        ./connect.py --flash flash/openipc.ssc338q-nor-fpv.tgz
        ;;
    info)
        echo "Executing connect.py --info"
        ./connect.py --info
        ;;
    version)
        echo "Executing connect.py --version"
        ./connect.py --version
        ;;
    unbind)
        echo "Executing connect.py --unbind"
        ./connect.py --unbind
        ;;
    backup)
        # Require a backup folder path as an extra parameter
        if [[ -z "$optional_param" ]]; then
            echo "Error: For 'backup', an additional folder path is required."
            usage
        fi
        echo "Executing connect.py --backup $optional_param"
        ./connect.py --backup "$optional_param"
        ;;
    *)
        echo "Error: Invalid operation '$operation'."
        usage
        ;;
esac

# Any other cleanup or final steps can go here:
# ./final_cleanup.sh

exit 0
