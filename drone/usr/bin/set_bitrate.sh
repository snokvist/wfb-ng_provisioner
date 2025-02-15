#!/bin/sh
#
# set_bitrate.sh
#
# Usage:
#    set_bitrate.sh <target_bitrate_in_kbps> [max_mcs] [--cap <cap_value>]
#
# This script reads FEC settings from /etc/wfb.yaml and allowed bandwidths
# from /etc/vtx_info.yaml, then calls bitrate_calculator.sh (with the given
# target, FEC ratio, and max_mcs) to compute the best settings (MCS, BW, GI).
#
# The FEC ratio is constructed by swapping the YAML values so that a file with:
#
#   broadcast:
#     fec_n: 12
#     fec_k: 8
#
# produces a ratio "8/12" as expected by bitrate_calculator.sh.
#
# The output from bitrate_calculator.sh is expected in the format:
#      <mcs>:<bw>:<gi>:<fec>
#
# Then the script updates the YAML configuration files and sets the radio
# settings in the running session using wfb_tx_cmd.
#
# Note: If the maximum allowed bandwidth is 40, then the wireless mode is always
# set to "HT40+" (even if the candidate BW from the calculator is 20).
#

# --- Parse arguments ---
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <target_bitrate_in_kbps> [max_mcs] [--cap <cap_value>]"
    exit 1
fi

TARGET="$1"
shift

# Default max_mcs is 5.
max_mcs=5
if [ "$#" -gt 0 ]; then
    case "$1" in
        --*) ;;  # if next arg starts with --
        *) max_mcs="$1"; shift;;
    esac
fi

# Default cap is 20000 kbps unless overridden.
CAP=20000
while [ "$#" -gt 0 ]; do
    case "$1" in
        --cap)
            shift
            if [ -z "$1" ]; then
                echo "Error: --cap requires a value."
                exit 1
            fi
            CAP="$1"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# --- Read FEC settings from /etc/wfb.yaml ---
# Example YAML:
#   broadcast:
#     fec_n: 12
#     fec_k: 8
fec_n=$(yaml-cli -i /etc/wfb.yaml -g .broadcast.fec_n)
fec_k=$(yaml-cli -i /etc/wfb.yaml -g .broadcast.fec_k)
if [ -z "$fec_n" ] || [ -z "$fec_k" ]; then
    echo "Error: Could not read FEC settings from /etc/wfb.yaml."
    exit 1
fi
# IMPORTANT: Swap the order so that a YAML with fec_n:12 and fec_k:8 produces "8/12".
fec_ratio="${fec_k}/${fec_n}"

# --- Read allowed bandwidths from /etc/vtx_info.yaml ---
# Expected format: [5,10,20,40]
bw_array=$(yaml-cli -i /etc/vtx_info.yaml -g .wifi.bw)
max_bw_allowed=$(echo "$bw_array" | sed 's/[][]//g' | awk -F, '{print $NF}' | tr -d ' ')
if [ -z "$max_bw_allowed" ]; then
    echo "Error: Could not read allowed bandwidths from /etc/vtx_info.yaml."
    exit 1
fi
# Our bitrate_calculator.sh supports 20 and 40 MHz.
if [ "$max_bw_allowed" -ge 40 ]; then
    ALLOWED_BW="40"
else
    ALLOWED_BW="20"
fi

# --- Call bitrate_calculator.sh ---
RESULT=$(bitrate_calculator.sh "$TARGET" "$fec_ratio" "$max_mcs" --cap "$CAP")
if [ $? -ne 0 ]; then
    echo "Error: bitrate_calculator.sh failed."
    exit 1
fi

# RESULT is expected in the format: <mcs>:<bw>:<gi>:<fec>
candidate_mcs=$(echo "$RESULT" | cut -d: -f1)
candidate_bw=$(echo "$RESULT" | cut -d: -f2)
candidate_gi=$(echo "$RESULT" | cut -d: -f3)
candidate_fec=$(echo "$RESULT" | cut -d: -f4)

# --- Adjust candidate if its bandwidth exceeds allowed maximum ---
if [ "$candidate_bw" -gt "$max_bw_allowed" ]; then
    echo "Warning: Candidate BW ${candidate_bw} MHz exceeds allowed maximum (${max_bw_allowed} MHz)."
    candidate_bw="$max_bw_allowed"
fi

echo "Setting new configuration:"
echo "   Target bitrate: ${TARGET} kbps"
echo "   Selected settings: MCS=${candidate_mcs}, BW=${candidate_bw} MHz, GI=${candidate_gi}, FEC=${candidate_fec}"
echo "   Bitrate cap: ${CAP} kbps"
echo "   Allowed max BW: ${max_bw_allowed} MHz"

# --- Update YAML configuration ---
# Update /etc/wfb.yaml:
yaml-cli -i /etc/wfb.yaml -s .broadcast.wfb_index "$candidate_mcs"
yaml-cli -i /etc/wfb.yaml -s .broadcast.fec_k "$fec_k"
yaml-cli -i /etc/wfb.yaml -s .broadcast.fec_n "$fec_n"

# Determine wireless mode:
# If the maximum allowed BW is 40, then always use "HT40+"
if [ "$max_bw_allowed" -eq 40 ]; then
    mode="HT40+"
else
    mode="HT${candidate_bw}"
fi
yaml-cli -i /etc/wfb.yaml -s .wireless.mode "$mode"

# Update /etc/majestic.yaml: set .video0.bitrate to TARGET
yaml-cli -i /etc/majestic.yaml -s .video0.bitrate "$TARGET"

# --- Inform the running instance via curl ---
curl -s "http://localhost/api/v1/set?video0.bitrate=${TARGET}" > /dev/null

# --- Set radio settings in the running session ---
# Set FEC using the original YAML values (order unchanged)
#wfb_tx_cmd 8000 set_fec -k "$fec_k" -n "$fec_n"
# Set radio settings (bandwidth, guard, mcs) using the candidate values
#wfb_tx_cmd 8000 set_radio -B "$candidate_bw" -G "$candidate_gi" -M "$candidate_mcs"



wifibroadcast stop
wifibroadcast start

echo "Settings applied successfully."
