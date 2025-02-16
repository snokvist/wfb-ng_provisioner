#!/bin/sh
#
# Usage: set_tx_power.sh <value 0-10> [direction]
#
# This script:
#  1. Checks if TX power throttling is enabled.
#  2. Retrieves the current mcs_index from wfb_tx_cmd.
#  3. Uses yaml-cli to get the TX power table for that mcs_index.
#  4. Interpolates the provided value (0–10) to select one of the table entries.
#  5. Checks the wifi adapter type and, if it is "88XXau", prepends a negative sign to the TX power.
#  6. Sets the TX power via iw.
#

# --- Argument Parsing ---
if [ -z "$1" ]; then
    echo "Usage: $0 <value 0-10> [direction]"
    exit 1
fi

TX_INPUT="$1"
# Default direction is "initiated" if not provided.
DIRECTION="${2:-initiated}"

# --- Throttling Check ---
# For now, throttling is set to "disabled". (Update this logic as needed.)
TEMP_THROTTLE="disabled"
if [ "$TEMP_THROTTLE" = "enabled" ]; then
    echo "TX power throttling is enabled. Aborting TX power change."
    exit 0
fi

# --- Get current mcs_index ---
MCS_INDEX=$(wfb_tx_cmd 8000 get_radio | grep '^mcs_index=' | cut -d '=' -f2)
if [ -z "$MCS_INDEX" ]; then
    echo "Error: Unable to retrieve mcs_index."
    exit 1
fi

# --- Retrieve TX power table from YAML ---
# Expected output example:
#   mcs1: [1,5,10,15,20,25,30,35,40,45,50]
TABLE_OUTPUT=$(yaml-cli -i /etc/vtx_info.yaml -g ".wifi.tx_power.mcs${MCS_INDEX}")
# Strip off the "mcsX:" prefix and brackets.
POWER_LIST=$(echo "$TABLE_OUTPUT" | sed -e "s/^mcs${MCS_INDEX}:[[:space:]]*//" -e 's/[][]//g')

# --- Parse list into individual values ---
OLD_IFS="$IFS"
IFS=,
set -- $POWER_LIST
IFS="$OLD_IFS"
NUM_VALUES=$#
# For instance, mcs1 might yield NUM_VALUES=11.

# --- Interpolate to select TX power ---
# The provided TX_INPUT (0–10) is mapped to an index in the table.
DESIRED_INDEX=$(awk -v input="$TX_INPUT" -v num="$NUM_VALUES" 'BEGIN {
    ratio = input / 10.0;
    index = int(ratio * (num - 1) + 0.5);
    print index
}')
# Convert from 0-indexed to shell’s 1-indexed positional parameters.
ARRAY_INDEX=$((DESIRED_INDEX + 1))

# Retrieve the selected TX power value.
eval "MCS_TX_PWR=\${$ARRAY_INDEX}"
if [ -z "$MCS_TX_PWR" ]; then
    echo "Error: Could not determine TX power from table."
    exit 1
fi

# --- Check wifi adapter type ---
WIFI_ADAPTER=$(yaml-cli -i /etc/vtx_info.yaml -g .wifi.wifi_adapter)
if [ "$WIFI_ADAPTER" = "bl-r8812af1" ]; then
    # Prepend a negative sign if not already present.
    case "$MCS_TX_PWR" in
        -*)
            # Already negative.
            ;;
        *)
            MCS_TX_PWR="-${MCS_TX_PWR}"
            ;;
    esac
fi

# --- Set the TX power ---
echo "Setting TX power to $MCS_TX_PWR (mcs${MCS_INDEX}, adapter: $WIFI_ADAPTER)"
iw wlan0 set txpower fixed "$MCS_TX_PWR"

exit 0
