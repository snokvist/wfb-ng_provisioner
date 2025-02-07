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

# Check that at least two arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <wlan_mode> <operation> [optional_parameter]"
    exit 1
fi

# Assign arguments
wlan_mode=$1   # First argument: mode for wlan_init.sh
operation=$2   # Second argument: determines which connect.py command to run
optional_param=$3  # Third argument: used only for bind and backup operations (folder path)

# Call wlan_init.sh with the provided mode
#echo "Calling wlan_init.sh with mode: $wlan_mode"
#./wlan_init.sh "$wlan_mode" 100 165 US HT20 bind &
wfb-server --profiles bind_drone --wlans "$wlan_mode"
sleep 3

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

# Run final cleanup script
./final_cleanup.sh
exit 0

