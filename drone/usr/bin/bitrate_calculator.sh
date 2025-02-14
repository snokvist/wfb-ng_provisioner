#!/bin/sh
#
# bitrate_calculator.sh
#
# This script supports two modes:
#
# 1. Normal (default) mode:
#    Usage:
#       bitrate_calculator.sh <target_bitrate_in_kbps> [fec_ratio] [max_mcs (0-7)] [--cap <cap>]
#
#    If fec_ratio is not provided, it defaults to "8/12".
#    The script searches (in fixed order: 20 MHz long, 20 MHz short, then 40 MHz long, 40 MHz short)
#    for the lowest MCS (0..max_mcs, default max_mcs=7) whose computed forward rate is ≥ target.
#    The computed rate is given by:
#
#         final = ( base_rate * 3 * fec_n + (4*fec_k)/2 ) / (4*fec_k)
#
#    where base_rate (in kbps) is looked up from hardcoded tables.
#    The computed rate is capped at a maximum value (default cap is 20000 kbps,
#    overrideable via --cap).
#
#    Output is a single line in the format:
#         <mcs>:<bw>:<gi>:<fec>
#
# 2. Backwards mode:
#    Usage:
#       bitrate_calculator.sh --backwards <bw (20|40)> <mcs (0-7)> <guard (long|short)> <fec ratio (x/y)> [--cap <cap>]
#
#    It computes (and outputs) the forward rate (capped) for the given parameters.
#

# -------------------------
# Parse optional global arguments
# -------------------------
# Default cap is 20000 kbps.
CAP=20000
backwards_mode=0
other_args=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --cap)
            shift
            if [ "$#" -eq 0 ]; then
                echo "Error: --cap requires a value"
                exit 1
            fi
            CAP="$1"
            shift
            ;;
        --backwards)
            backwards_mode=1
            shift
            ;;
        *)
            other_args="$other_args $1"
            shift
            ;;
    esac
done

set -- $other_args

# -------------------------
# Function: compute_final
# -------------------------
# Given:
#   bw    : Bandwidth (20 or 40)
#   gi    : Guard interval ("long" or "short")
#   mcs   : MCS index (0-7)
#   fec_n : FEC numerator
#   fec_k : FEC denominator
#
# Looks up the base_rate (in kbps) from hardcoded tables:
#
# 20 MHz:
#   Long GI:  6500, 13000, 19500, 26000, 39000, 52000, 58500, 65000
#   Short GI: 7200, 14400, 21700, 28900, 43300, 57800, 65000, 72200
#
# 40 MHz:
#   Long GI:  13500, 27000, 40500, 54000, 81000, 108000, 121500, 135000
#   Short GI: 15000, 30000, 45000, 60000, 90000, 120000, 135000, 150000
#
# Then computes:
#
#    final = ( base_rate * 3 * fec_n + (4*fec_k)/2 ) / (4*fec_k)
#
# If final > CAP, it is set to CAP.
compute_final() {
    bw="$1"
    gi="$2"
    mcs="$3"
    fec_n="$4"
    fec_k="$5"

    if [ "$bw" -eq 20 ]; then
        if [ "$gi" = "long" ]; then
            case "$mcs" in
                0) base=6500 ;;
                1) base=13000 ;;
                2) base=19500 ;;
                3) base=26000 ;;
                4) base=39000 ;;
                5) base=52000 ;;
                6) base=58500 ;;
                7) base=65000 ;;
            esac
        else
            case "$mcs" in
                0) base=7200 ;;
                1) base=14400 ;;
                2) base=21700 ;;
                3) base=28900 ;;
                4) base=43300 ;;
                5) base=57800 ;;
                6) base=65000 ;;
                7) base=72200 ;;
            esac
        fi
    elif [ "$bw" -eq 40 ]; then
        if [ "$gi" = "long" ]; then
            case "$mcs" in
                0) base=13500 ;;
                1) base=27000 ;;
                2) base=40500 ;;
                3) base=54000 ;;
                4) base=81000 ;;
                5) base=108000 ;;
                6) base=121500 ;;
                7) base=135000 ;;
            esac
        else
            case "$mcs" in
                0) base=15000 ;;
                1) base=30000 ;;
                2) base=45000 ;;
                3) base=60000 ;;
                4) base=90000 ;;
                5) base=120000 ;;
                6) base=135000 ;;
                7) base=150000 ;;
            esac
        fi
    else
        echo "Error: unsupported bandwidth $bw" >&2
        exit 1
    fi

    denom=$(( 4 * fec_k ))
    half_denom=$(( denom / 2 ))
    num=$(( base * 3 * fec_n ))
    final=$(( (num + half_denom) / denom ))
    if [ "$final" -gt "$CAP" ]; then
         final="$CAP"
    fi
    echo "$final"
}

# -------------------------
# Mode Selection
# -------------------------
if [ "$backwards_mode" -eq 1 ]; then
    # Backwards mode: Expect exactly 4 arguments: bw, mcs, guard, fec.
    if [ "$#" -ne 4 ]; then
         echo "Usage: $0 --backwards <bw (20|40)> <mcs (0-7)> <guard (long|short)> <fec ratio (x/y)> [--cap <cap>]"
         exit 1
    fi

    bw="$1"
    mcs="$2"
    guard="$3"
    fec="$4"

    # Validate inputs.
    if [ "$bw" -ne 20 ] && [ "$bw" -ne 40 ]; then
         echo "Error: bandwidth must be 20 or 40."
         exit 1
    fi

    case "$mcs" in
         [0-7]) ;;
         *) echo "Error: mcs must be between 0 and 7." ; exit 1 ;;
    esac

    if [ "$guard" != "long" ] && [ "$guard" != "short" ]; then
         echo "Error: guard must be 'long' or 'short'."
         exit 1
    fi

    fec_n=$(echo "$fec" | cut -d'/' -f1)
    fec_k=$(echo "$fec" | cut -d'/' -f2)
    if [ -z "$fec_n" ] || [ -z "$fec_k" ]; then
         echo "Error: fec ratio must be in the form x/y."
         exit 1
    fi

    final=$(compute_final "$bw" "$guard" "$mcs" "$fec_n" "$fec_k")
    echo "$final"
    exit 0
fi

# -------------------------
# Normal Mode (Forward Search)
# -------------------------
# New usage:
#    bitrate_calculator.sh <target_bitrate_in_kbps> [fec_ratio] [max_mcs (0-7)] [--cap <cap>]
#
# If fec_ratio is not provided, default is "8/12". If max_mcs is not provided, default is 7.
if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <target_bitrate_in_kbps> [fec_ratio] [max_mcs (0-7)] [--cap <cap>]"
    exit 1
fi

target="$1"
shift

# Validate target.
case "$target" in
    ''|*[!0-9]*)
         echo "Error: target must be a positive integer." >&2
         exit 1
         ;;
esac

# If the next argument contains a slash, treat it as the fec ratio.
if [ "$#" -ge 1 ]; then
    case "$1" in
        */*) fec="$1"; shift;;
         *) fec="8/12" ;;
    esac
else
    fec="8/12"
fi

fec_n=$(echo "$fec" | cut -d'/' -f1)
fec_k=$(echo "$fec" | cut -d'/' -f2)
if [ -z "$fec_n" ] || [ -z "$fec_k" ]; then
    echo "Error: fec ratio must be in the form x/y." >&2
    exit 1
fi

# Next, if any, treat next argument as max_mcs.
if [ "$#" -ge 1 ]; then
    max_mcs="$1"
    shift
    case "$max_mcs" in
         [0-7]) ;;
         *) echo "Error: max_mcs must be between 0 and 7." >&2; exit 1 ;;
    esac
else
    max_mcs=7
fi

# Fixed search order: 20 MHz long, then 20 MHz short, then 40 MHz long, then 40 MHz short.
candidate_found=0
for bw in 20 40; do
    for gi in long short; do
        for mcs in $(seq 0 $max_mcs); do
            final=$(compute_final "$bw" "$gi" "$mcs" "$fec_n" "$fec_k")
            if [ "$final" -ge "$target" ]; then
                candidate_mcs="$mcs"
                candidate_bw="$bw"
                candidate_gi="$gi"
                candidate_fec="$fec"
                candidate_found=1
                break 3
            fi
        done
    done
done

if [ "$candidate_found" -eq 1 ]; then
    echo "${candidate_mcs}:${candidate_bw}:${candidate_gi}:${candidate_fec}"
else
    echo "No combination found." >&2
    exit 1
fi
