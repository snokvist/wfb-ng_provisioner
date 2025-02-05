#!/bin/bash
# Usage:
#   ./script.sh <wlan_mode> <operation> [optional_parameter]
#
# Examples:
#   ./script.sh bind_mode bind /path/to/bind_data_folder
#   ./script.sh flash_mode flash
#   ./script.sh info_mode info

# Check that at least two arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <wlan_mode> <operation> [optional_parameter]"
    exit 1
fi

# Assign arguments
wlan_mode=$1   # First argument: mode for wlan_init.sh
operation=$2   # Second argument: determines which connect.py command to run
optional_param=$3  # Third argument: used only for bind operation (bind data folder)

# Call wlan_init.sh with the provided mode
echo "Calling wlan_init.sh with mode: $wlan_mode"
./wlan_init.sh "$wlan_mode" 100 165 US HT20 bind &
sleep 3

# Execute the corresponding connect.py command based on the operation
case "$operation" in
    bind)
         # Expect a bind data folder as an extra parameter
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
    *)
         echo "Invalid operation: $operation. Valid operations are: bind, flash, or info."
         exit 1
         ;;
esac

# Run final cleanup script
./final_cleanup.sh
exit 0
