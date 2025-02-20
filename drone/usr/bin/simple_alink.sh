#!/bin/sh
# simple_alink.sh
# Usage: simple_alink.sh [--verbose]
# --verbose option: if provided as the first argument, enables debug output to stderr.

VERBOSE=0
if [ "$1" = "--verbose" ]; then
    VERBOSE=1
fi

# Debug printing function.
debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "DEBUG: $*" >&2
    fi
}

debug "Verbose mode enabled. Starting command listener with state logic."

# --- Configuration Parameters ---
BITRATE_DIFF_THRESHOLD=2000     # Minimum difference to accept a new bitrate.
TX_PWR_DIFF_THRESHOLD=2         # Minimum difference to accept a new tx power change.
MAX_ACCEPTABLE_BITRATE=12000    # Maximum allowed bitrate.
MIN_ACCEPTABLE_BITRATE=4500     # Minimum allowed bitrate.
MAX_ACCEPTABLE_TX_PWR=9         # Maximum allowed tx power.
MIN_ACCEPTABLE_TX_PWR=2         # Minimum allowed tx power.

# Fallback configuration.
FALLBACK_BITRATE=2800           # Static bitrate to use in fallback.
FALLBACK_TX=10                  # Static tx power to use in fallback.
# Thresholds for triggering fallback based on REC_LOST:
BAD_REC_THRESHOLD=30            # Fallback triggered if REC > BAD_REC_THRESHOLD.
BAD_LOST_THRESHOLD=5            # Fallback triggered if LOST > BAD_LOST_THRESHOLD.
# Recovery threshold parameters:
CURRENT_REC_LOST_RECOVER_REQUIRED=5   # Number of consecutive good REC_LOST messages required to exit fallback.
# Timeout to trigger fallback if no messages are received.
NO_MSG_TIMEOUT=1

# Replace commands with your actual system commands.
UPDATE_BITRATE_COMMAND="set_alink_bitrate.sh"
UPDATE_TX_PWR_COMMAND="set_alink_tx_pwr.sh"

# Read configuration for wireless parameters.
MAX_BW=$(yaml-cli -i /etc/wfb.yaml -g .wireless.max_bw)
if [ "$MAX_BW" -eq 40 ]; then
    MAX_MCS=3
else
    MAX_MCS=5
fi

# Fetch the original GOP size at startup.
ORIGINAL_GOP=$(yaml-cli -i /etc/majestic.yaml -g .video0.gopSize)
if [ -z "$ORIGINAL_GOP" ]; then
    ORIGINAL_GOP=1
fi

# --- Global Counters and State Variables ---
TOTAL_MSG_COUNT=0
MSG_COUNT_SINCE_FALLBACK=0

ENABLED=0
SYSTEM_ACTIVE=0  # Becomes 1 once a valid command is received.

# BITRATE state.
CURRENT_BITRATE=0
PREV_BITRATE=""
BITRATE_DIRECTION="none"
BITRATE_AT_MIN=0
BITRATE_AT_MAX=0

# TX_PWR state.
CURRENT_TX_PWR=0
PREV_TX_PWR=""
TX_PWR_DIRECTION="none"
TX_PWR_AT_MIN=0
TX_PWR_AT_MAX=0

INFO_STATE=""
STATUS_STATE=""

# Fallback state.
FALLBACK_ACTIVE=0
REC_LOST_RECOVER_COUNT=0

# For detecting message timeout.
LAST_MSG_TIME=$(date +%s)

# --- Main Loop ---
while true; do
    current_time=$(date +%s)
    if IFS=$'\t' read -t 1 -r command data1 data2 data3; then
        # Update timestamp and counters.
        LAST_MSG_TIME=$(date +%s)
        TOTAL_MSG_COUNT=$(( TOTAL_MSG_COUNT + 1 ))
        if [ "$FALLBACK_ACTIVE" -eq 1 ]; then
            MSG_COUNT_SINCE_FALLBACK=$(( MSG_COUNT_SINCE_FALLBACK + 1 ))
        fi

        debug "Received command: '$command', data1: '$data1', data2: '$data2', data3: '$data3'"
        case "$command" in
            HEARTBEAT)
                if [ "$SYSTEM_ACTIVE" -eq 0 ]; then
                    SYSTEM_ACTIVE=1
                    debug "First valid command received: system activated."
                fi
                debug "HEARTBEAT processed."
                echo "ACK:HEARTBEAT	$data1	Heartbeat received"
                ;;
            BITRATE)
                # In fallback, ignore BITRATE commands.
                if [ "$FALLBACK_ACTIVE" -eq 1 ]; then
                    debug "In fallback mode: BITRATE command ignored."
                    echo "ACK:BITRATE	$data1	Bitrate command ignored (fallback active)"
                    continue
                fi
                if [ "$SYSTEM_ACTIVE" -eq 0 ]; then
                    SYSTEM_ACTIVE=1
                    debug "First valid command received: system activated."
                fi
                new_bitrate="$data2"
                if [ "$new_bitrate" -ge "$MAX_ACCEPTABLE_BITRATE" ]; then
                    debug "New bitrate $new_bitrate exceeds max limit $MAX_ACCEPTABLE_BITRATE, using max."
                    new_bitrate="$MAX_ACCEPTABLE_BITRATE"
                    if [ "$BITRATE_AT_MAX" -eq 0 ]; then
                        BITRATE_AT_MAX=1; BITRATE_AT_MIN=0; accept=1; BITRATE_DIRECTION="increased"
                    else
                        accept=0
                        debug "Already at max bitrate; ignoring update."
                    fi
                elif [ "$new_bitrate" -le "$MIN_ACCEPTABLE_BITRATE" ]; then
                    debug "New bitrate $new_bitrate below min limit $MIN_ACCEPTABLE_BITRATE, using min."
                    new_bitrate="$MIN_ACCEPTABLE_BITRATE"
                    if [ "$BITRATE_AT_MIN" -eq 0 ]; then
                        BITRATE_AT_MIN=1; BITRATE_AT_MAX=0; accept=1; BITRATE_DIRECTION="decreased"
                    else
                        accept=0
                        debug "Already at min bitrate; ignoring update."
                    fi
                else
                    BITRATE_AT_MIN=0; BITRATE_AT_MAX=0
                    if [ -z "$PREV_BITRATE" ]; then
                        accept=1; BITRATE_DIRECTION="initial"
                    else
                        diff=$(( new_bitrate - PREV_BITRATE ))
                        [ $diff -lt 0 ] && diff=$(( -diff ))
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
                fi

                if [ "$accept" -eq 1 ]; then
                    PREV_BITRATE="$new_bitrate"
                    debug "BITRATE accepted. New bitrate: $new_bitrate, Direction: $BITRATE_DIRECTION."
                    $UPDATE_BITRATE_COMMAND "$new_bitrate" $MAX_MCS --max_bw $MAX_BW --direction "$BITRATE_DIRECTION"
                    echo "ACK:BITRATE	$data1	Bitrate updated to $new_bitrate ($BITRATE_DIRECTION)"
                    debug "System command issued to update bitrate to $new_bitrate."
                else
                    debug "BITRATE change not significant or already at extreme; command ignored."
                    echo "ACK:BITRATE	$data1	Bitrate change ignored; not significant"
                fi
                ;;
            TX_PWR)
                # In fallback, ignore TX_PWR commands.
                if [ "$FALLBACK_ACTIVE" -eq 1 ]; then
                    debug "In fallback mode: TX_PWR command ignored."
                    echo "ACK:TX_PWR	$data1	Tx power command ignored (fallback active)"
                    continue
                fi
                if [ "$SYSTEM_ACTIVE" -eq 0 ]; then
                    SYSTEM_ACTIVE=1
                    debug "First valid command received: system activated."
                fi
                new_tx="$data2"
                if [ "$new_tx" -ge "$MAX_ACCEPTABLE_TX_PWR" ]; then
                    debug "New TX_PWR $new_tx exceeds max limit $MAX_ACCEPTABLE_TX_PWR, using max."
                    new_tx="$MAX_ACCEPTABLE_TX_PWR"
                    if [ "$TX_PWR_AT_MAX" -eq 0 ]; then
                        TX_PWR_AT_MAX=1; TX_PWR_AT_MIN=0; accept_tx=1; TX_PWR_DIRECTION="increased"
                    else
                        accept_tx=0
                        debug "Already at max TX_PWR; ignoring update."
                    fi
                elif [ "$new_tx" -le "$MIN_ACCEPTABLE_TX_PWR" ]; then
                    debug "New TX_PWR $new_tx below min limit $MIN_ACCEPTABLE_TX_PWR, using min."
                    new_tx="$MIN_ACCEPTABLE_TX_PWR"
                    if [ "$TX_PWR_AT_MIN" -eq 0 ]; then
                        TX_PWR_AT_MIN=1; TX_PWR_AT_MAX=0; accept_tx=1; TX_PWR_DIRECTION="decreased"
                    else
                        accept_tx=0
                        debug "Already at min TX_PWR; ignoring update."
                    fi
                else
                    TX_PWR_AT_MIN=0; TX_PWR_AT_MAX=0
                    if [ -z "$PREV_TX_PWR" ]; then
                        accept_tx=1; TX_PWR_DIRECTION="initial"
                    else
                        diff_tx=$(( new_tx - PREV_TX_PWR ))
                        [ $diff_tx -lt 0 ] && diff_tx=$(( -diff_tx ))
                        if [ "$diff_tx" -ge "$TX_PWR_DIFF_THRESHOLD" ]; then
                            accept_tx=1
                            if [ "$new_tx" -gt "$PREV_TX_PWR" ]; then
                                TX_PWR_DIRECTION="increased"
                            elif [ "$new_tx" -lt "$PREV_TX_PWR" ]; then
                                TX_PWR_DIRECTION="decreased"
                            else
                                TX_PWR_DIRECTION="unchanged"
                            fi
                        else
                            accept_tx=0
                        fi
                    fi
                fi

                if [ "$accept_tx" -eq 1 ]; then
                    PREV_TX_PWR="$new_tx"
                    debug "TX_PWR accepted. New tx power: $new_tx, Direction: $TX_PWR_DIRECTION."
                    $UPDATE_TX_PWR_COMMAND "$new_tx" --direction "$TX_PWR_DIRECTION"
                    echo "ACK:TX_PWR	$data1	Tx power updated to $new_tx ($TX_PWR_DIRECTION)"
                    debug "System command issued to update tx power to $new_tx."
                else
                    debug "TX_PWR change not significant or already at extreme; command ignored."
                    echo "ACK:TX_PWR	$data1	Tx power change ignored; not significant"
                fi
                ;;
            REC_LOST)
                # Process REC_LOST messages for fallback/recovery.
                # data2 = REC, data3 = LOST.
                rec_val="$data2"
                lost_val="$data3"

                if [ "$FALLBACK_ACTIVE" -eq 0 ]; then
                    # Not in fallback: trigger fallback if REC or LOST are too high.
                    if [ "$rec_val" -gt "$BAD_REC_THRESHOLD" ] || [ "$lost_val" -gt "$BAD_LOST_THRESHOLD" ]; then
                        debug "REC_LOST indicates bad link (REC=$rec_val, LOST=$lost_val). Entering fallback mode."
                        FALLBACK_ACTIVE=1
                        MSG_COUNT_SINCE_FALLBACK=0
                        REC_LOST_RECOVER_COUNT=0
                        $UPDATE_BITRATE_COMMAND "$FALLBACK_BITRATE" $MAX_MCS --max_bw $MAX_BW --direction "decreased"
                        $UPDATE_TX_PWR_COMMAND "$FALLBACK_TX" --direction "increased"
                        # Update state variables so that fallback values become the baseline.
                        PREV_BITRATE="$FALLBACK_BITRATE"
                        PREV_TX_PWR="$FALLBACK_TX"
                        curl localhost/api/v1/set?video0.gopSize=0.25
                        echo "ACK:REC_LOST	$data1	Fallback activated due to bad link (REC=$rec_val, LOST=$lost_val)"
                        continue
                    fi
                else
                    # Already in fallback.
                    # Use REC_LOST messages with REC < 20 and LOST < 5 as good recovery signals.
                    if [ "$rec_val" -lt 20 ] && [ "$lost_val" -lt 5 ]; then
                        REC_LOST_RECOVER_COUNT=$(( REC_LOST_RECOVER_COUNT + 1 ))
                        debug "In fallback: Good REC_LOST received (REC=$rec_val, LOST=$lost_val). Recovery count = $REC_LOST_RECOVER_COUNT (required: $CURRENT_REC_LOST_RECOVER_REQUIRED)."
                        if [ "$REC_LOST_RECOVER_COUNT" -ge "$CURRENT_REC_LOST_RECOVER_REQUIRED" ]; then
                            debug "Recovery criteria met: Exiting fallback mode."
                            FALLBACK_ACTIVE=0
                            REC_LOST_RECOVER_COUNT=0
                            # Reset recovery threshold to 5 on successful recovery.
                            CURRENT_REC_LOST_RECOVER_REQUIRED=5
                            MSG_COUNT_SINCE_FALLBACK=0
                            # Reset BITRATE/TX_PWR state flags so new changes will be accepted.
                            BITRATE_AT_MAX=0; BITRATE_AT_MIN=0
                            TX_PWR_AT_MAX=0; TX_PWR_AT_MIN=0
                            curl localhost/api/v1/set?video0.gopSize=$ORIGINAL_GOP
                            echo "ACK:REC_LOST	$data1	Recovery successful, fallback exited."
                            continue
                        fi
                    else
                        REC_LOST_RECOVER_COUNT=0
                        debug "In fallback: REC_LOST values not acceptable (REC=$rec_val, LOST=$lost_val); recovery counter reset."
                    fi
                    echo "ACK:REC_LOST	$data1	REC=$rec_val, LOST=$lost_val (fallback active)"
                    continue
                fi
                debug "REC_LOST message received: REC=$rec_val, LOST=$lost_val"
                echo "ACK:REC_LOST	$data1	REC=$rec_val, LOST=$lost_val"
                ;;
            INFO)
                INFO_STATE="$data2"
                debug "INFO command processed. INFO_STATE set to '$INFO_STATE'."
                echo "ACK:INFO	$data1	Info updated to: $INFO_STATE"
                ;;
            STATUS)
                STATUS_STATE="$data2"
                debug "STATUS command processed. STATUS_STATE set to '$STATUS_STATE'."
                echo "ACK:STATUS	$data1	Status updated to: $STATUS_STATE"
                ;;
            COMMAND)
                case "$data2" in
                    ENABLE)
                        SYSTEM_ACTIVE=1
                        debug "COMMAND ENABLE processed. System activated."
                        echo "ACK:COMMAND	$data1	Enabled"
                        ;;
                    DISABLE)
                        SYSTEM_ACTIVE=0
                        CURRENT_BITRATE=0; PREV_BITRATE=""; BITRATE_DIRECTION="none"
                        BITRATE_AT_MIN=0; BITRATE_AT_MAX=0
                        CURRENT_TX_PWR=0; PREV_TX_PWR=""; TX_PWR_DIRECTION="none"
                        TX_PWR_AT_MIN=0; TX_PWR_AT_MAX=0
                        INFO_STATE=""; STATUS_STATE=""
                        debug "COMMAND DISABLE processed. System deactivated and states reset."
                        set_alink_bitrate.sh 8000 5 --max_bw 20
                        set_alink_tx_pwr.sh 5
                        echo "ACK:COMMAND	$data1	Disabled"
                        ;;
                    RESET)
                        CURRENT_BITRATE=0; PREV_BITRATE=""; BITRATE_DIRECTION="none"
                        BITRATE_AT_MIN=0; BITRATE_AT_MAX=0
                        CURRENT_TX_PWR=0; PREV_TX_PWR=""; TX_PWR_DIRECTION="none"
                        TX_PWR_AT_MIN=0; TX_PWR_AT_MAX=0
                        INFO_STATE=""; STATUS_STATE=""
                        debug "COMMAND RESET processed. All states reset."
                        echo "ACK:COMMAND	$data1	States reset"
                        ;;
                    *)
                        debug "Unknown COMMAND action: '$data2'."
                        echo "ACK:COMMAND	$data1	Unknown command action: $data2"
                        ;;
                esac
                ;;
            *)
                debug "Unknown command received: '$command'."
                echo "ERROR	$data1	Unknown command: $command"
                ;;
        esac
    else
        # read timed out – no message received.
        current_time=$(date +%s)
        if [ $(( current_time - LAST_MSG_TIME )) -ge "$NO_MSG_TIMEOUT" ]; then
            if [ "$FALLBACK_ACTIVE" -eq 0 ]; then
                debug "No messages received for $NO_MSG_TIMEOUT seconds. Triggering fallback."
                FALLBACK_ACTIVE=1
                MSG_COUNT_SINCE_FALLBACK=0
                REC_LOST_RECOVER_COUNT=0
                $UPDATE_BITRATE_COMMAND "$FALLBACK_BITRATE" $MAX_MCS --max_bw $MAX_BW --direction "decreased"
                $UPDATE_TX_PWR_COMMAND "$FALLBACK_TX" --direction "increased"
                # Update state variables on timeout fallback as well.
                PREV_BITRATE="$FALLBACK_BITRATE"
                PREV_TX_PWR="$FALLBACK_TX"
                curl localhost/api/v1/set?video0.gopSize=0.25
                echo "ACK:TIMEOUT	-	Fallback activated due to timeout (no messages for $NO_MSG_TIMEOUT seconds)"
                LAST_MSG_TIME=$(date +%s)
            fi
        fi
    fi
done
