#!/bin/sh
# simple_alink.sh
# Usage: simple_alink.sh [--verbose]
#
# This script processes tab-delimited commands from STDIN.
# It focuses on HEARTBEAT and BITRATE commands and includes state logic.
#
# HEARTBEAT:
#   - Updates the last heartbeat timestamp.
#   - Resets the fallback flag.
#
# BITRATE:
#   - Updates the last heartbeat timestamp.
#   - Checks if the new bitrate (data2) differs from the last issued
#     bitrate by at least BITRATE_DIFF_THRESHOLD.
#   - If the change is significant, it determines whether the bitrate has
#     increased or decreased, updates state, and calls a system command
#     to update the bitrate.
#
# Additionally, if more than FALLBACK_TIMEOUT seconds elapse without a
# heartbeat (or BITRATE command), a fallback system command is issued.

# --verbose option: if provided as the first argument, enables debug output to stderr.
VERBOSE=0
if [ "$1" = "--verbose" ]; then
    VERBOSE=1
fi

# Debug printing function (prints to stderr in verbose mode)
debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "DEBUG: $*" >&2
    fi
}

debug "Verbose mode enabled. Starting command listener with state logic."

# --- Configuration Parameters ---
FALLBACK_TIMEOUT=1          # Seconds to wait for heartbeat before fallback.
BITRATE_DIFF_THRESHOLD=2000   # Minimum difference to accept a new bitrate.
# Replace the commands below with your actual system commands.
FALLBACK_COMMAND="set_alink_bitrate.sh"  # Command to call on fallback.
UPDATE_BITRATE_COMMAND="set_alink_bitrate.sh"     # Command to update bitrate.

# --- State Variables ---
ENABLED=0
CURRENT_BITRATE=0        # Last received bitrate (from BITRATE command)
PREV_BITRATE=""          # Last BITRATE command that was accepted/issued.
BITRATE_DIRECTION="none" # "initial", "increased", "decreased", or "unchanged"
INFO_STATE=""
STATUS_STATE=""
LAST_HEARTBEAT=$(date +%s)  # Initialize with current epoch seconds.
FALLBACK_ISSUED=0           # To avoid repeatedly issuing fallback.

# --- Main Loop ---
# We use a read timeout (-t 1) so that even if no input is received we can check for heartbeat timeout.
while true; do
	now=$(date +%s)
	elapsed=$(( now - LAST_HEARTBEAT ))
	if [ "$elapsed" -gt "$FALLBACK_TIMEOUT" ] && [ "$FALLBACK_ISSUED" -eq 0 ]; then
	    debug "No heartbeat received for ${elapsed}s. Issuing fallback command."
	    FALLBACK_BITRATE=3000
	    BITRATE_DIRECTION="decreased"
	    CURRENT_BITRATE="$FALLBACK_BITRATE"
	    PREV_BITRATE="$FALLBACK_BITRATE"
	    # Issue the fallback command with proper arguments.
	    $FALLBACK_COMMAND "$FALLBACK_BITRATE" 5 --max_bw 20 --direction "$BITRATE_DIRECTION"
	    debug "Fallback command issued: setting bitrate to $FALLBACK_BITRATE, direction: $BITRATE_DIRECTION"
	    FALLBACK_ISSUED=1
	fi

    # Attempt to read a command (fields separated by tabs). Timeout after 1 second.
    if IFS=$'\t' read -t 1 -r command data1 data2; then
        debug "Received command: '$command', data1: '$data1', data2: '$data2'"
        case "$command" in
            HEARTBEAT)
                # On heartbeat, update the timestamp and clear the fallback flag.
                LAST_HEARTBEAT=$(date +%s)
                FALLBACK_ISSUED=0
                debug "HEARTBEAT processed. LAST_HEARTBEAT updated to $LAST_HEARTBEAT."
                echo "ACK:HEARTBEAT\t$data1\tHeartbeat received"
                ;;
            BITRATE)
                # Update heartbeat timestamp (activity) and clear fallback flag.
                LAST_HEARTBEAT=$(date +%s)
                FALLBACK_ISSUED=0
                new_bitrate="$data2"
                CURRENT_BITRATE="$new_bitrate"
                accept=0

                if [ -z "$PREV_BITRATE" ]; then
                    # First bitrate received is always accepted.
                    accept=1
                    BITRATE_DIRECTION="initial"
                else
                    # Calculate absolute difference between new and previous bitrate.
                    diff=$(( new_bitrate - PREV_BITRATE ))
                    if [ $diff -lt 0 ]; then
                        diff=$(( -diff ))
                    fi
                    if [ "$diff" -ge "$BITRATE_DIFF_THRESHOLD" ]; then
                        accept=1
                        if [ "$new_bitrate" -gt "$PREV_BITRATE" ]; then
                            BITRATE_DIRECTION="increased"
                        elif [ "$new_bitrate" -lt "$PREV_BITRATE" ]; then
                            BITRATE_DIRECTION="decreased"
                        else
                            BITRATE_DIRECTION="unchanged"
                        fi
                    else
                        accept=0
                    fi
                fi

                if [ "$accept" -eq 1 ]; then
                    PREV_BITRATE="$new_bitrate"
                    debug "BITRATE accepted. New bitrate: $new_bitrate, Direction: $BITRATE_DIRECTION."
                    # Call the system command to update the bitrate.
                    #$UPDATE_BITRATE_COMMAND "$new_bitrate"
                    $UPDATE_BITRATE_COMMAND "$new_bitrate" 5 --max_bw 20 --direction "$BITRATE_DIRECTION"
                    echo "ACK:BITRATE\t$data1\tBitrate updated to $new_bitrate ($BITRATE_DIRECTION)"
                    debug "System command issued to update bitrate to $new_bitrate."
                else
                    debug "BITRATE change not significant (difference < $BITRATE_DIFF_THRESHOLD). Command ignored."
                    echo "ACK:BITRATE\t$data1\tBitrate change ignored; not significant"
                fi
                ;;
            INFO)
                INFO_STATE="$data2"
                debug "INFO command processed. INFO_STATE set to '$INFO_STATE'."
                echo "ACK:INFO\t$data1\tInfo updated to: $INFO_STATE"
                ;;
            STATUS)
                STATUS_STATE="$data2"
                debug "STATUS command processed. STATUS_STATE set to '$STATUS_STATE'."
                echo "ACK:STATUS\t$data1\tStatus updated to: $STATUS_STATE"
                ;;
            COMMAND)
                # Handle additional COMMAND subcommands as needed.
                case "$data2" in
                    ENABLE)
                        ENABLED=1
                        debug "COMMAND ENABLE processed. ENABLED set to 1."
                        echo "ACK:COMMAND\t$data1\tEnabled"
                        ;;
                    DISABLE)
                        ENABLED=0
                        debug "COMMAND DISABLE processed. ENABLED set to 0."
                        echo "ACK:COMMAND\t$data1\tDisabled"
                        ;;
                    RESET)
                        ENABLED=0
                        CURRENT_BITRATE=0
                        PREV_BITRATE=""
                        BITRATE_DIRECTION="none"
                        INFO_STATE=""
                        STATUS_STATE=""
                        LAST_HEARTBEAT=$(date +%s)
                        FALLBACK_ISSUED=0
                        debug "COMMAND RESET processed. All states reset."
                        echo "ACK:COMMAND\t$data1\tStates reset"
                        ;;
                    *)
                        debug "Unknown COMMAND action: '$data2'."
                        echo "ACK:COMMAND\t$data1\tUnknown command action: $data2"
                        ;;
                esac
                ;;
            *)
                debug "Unknown command received: '$command'."
                echo "ERROR\t$data1\tUnknown command: $command"
                ;;
        esac
    fi
done
