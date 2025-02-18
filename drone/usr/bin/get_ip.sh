#!/bin/sh
# Default IP prefix.
prefix="10.5.0"

# If a custom prefix is provided, use it.
if [ "$1" = "--prefix" ]; then
    prefix="$2"
    shift 2
fi

# Check if the hexadecimal string was provided; if not, exit with an error.
if [ -z "$1" ]; then
    echo "Error: No hexadecimal string provided." >&2
    echo "Usage: $0 [--prefix PREFIX] HEXSTRING" >&2
    exit 1
fi

input_str="$1"

# Compute the SHA1 hash of the input.
# sha1sum output is like: d41d294d6787a4d13b529dca0e44f0b2801f8122  -
hash=$(printf "%s" "$input_str" | sha1sum | cut -d ' ' -f1)

# Take the first 8 characters of the hash.
subhash=$(echo "$hash" | cut -c1-8)

# Convert the 8-digit hexadecimal to a decimal number.
num=$((0x$subhash))

# Reduce the number modulo 244 (because 254 - 11 + 1 = 244) and add 11.
final=$(( (num % 244) + 11 ))

# Output the complete IP address.
echo "$prefix.$final"
