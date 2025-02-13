#!/bin/sh
#
# Script: generate_backup.sh
# Purpose: Read one or more file/directory paths (from a file list or a single argument),
#          generate SHA1 checksums on all files (recursively for directories),
#          stage them preserving directory structure, and create a compressed tar archive.
#
# Usage:
#   ./generate_backup.sh file_list.txt
#     - Reads absolute paths (files or directories) from file_list.txt.
#
#   ./generate_backup.sh /some/directory
#     - Backs up the specified directory recursively.
#
#   ./generate_backup.sh
#     - Defaults to backing up /overlay/root.
#

# Determine mode and input source.
if [ $# -lt 1 ]; then
    mode="single"
    single_path="/overlay/root"
elif [ -f "$1" ]; then
    mode="list"
    list_file="$1"
elif [ -d "$1" ]; then
    mode="single"
    single_path="$1"
else
    echo "Error: Provided argument is neither a file list nor a directory."
    exit 1
fi

# Set directories and file names.
BACKUP_STAGING_DIR="/tmp/backup/staging"
FINAL_BACKUP_DIR="/tmp/backup"
TAR_FILE="$FINAL_BACKUP_DIR/backup.tar"
TAR_GZ_FILE="$FINAL_BACKUP_DIR/backup.tar.gz"
CHECKSUM_FILE="$BACKUP_STAGING_DIR/checksum.txt"

# Prepare staging area.
rm -rf "$BACKUP_STAGING_DIR" 2>/dev/null
mkdir -p "$BACKUP_STAGING_DIR" || { echo "Error: Could not create staging directory '$BACKUP_STAGING_DIR'."; exit 1; }
# Create (or empty) checksum file.
> "$CHECKSUM_FILE" || { echo "Error: Cannot write to checksum file '$CHECKSUM_FILE'."; exit 1; }

# Function: process_path
# Given an absolute path (to a file or directory), do:
#  - For a file: compute its SHA1, append to checksum.txt, then copy it to the staging area.
#  - For a directory: recursively compute SHA1 for every file (inside that directory)
#    and copy the entire directory preserving its relative structure.
process_path() {
    filepath="$1"
    # Skip empty lines.
    [ -z "$filepath" ] && return

    # Remove any trailing slash (except if the path is just "/")
    if [ "$filepath" != "/" ]; then
      filepath=$(echo "$filepath" | sed 's:/*$::')
    fi

    if [ -f "$filepath" ]; then
        # It's a file.
        sha1sum_output=$(sha1sum "$filepath" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Failed to calculate SHA1 for '$filepath'."
            exit 1
        fi
        echo "$sha1sum_output" >> "$CHECKSUM_FILE"

        # Remove leading slash for relative path in the archive.
        REL_PATH=$(echo "$filepath" | sed 's|^/||')
        DEST_DIR="$BACKUP_STAGING_DIR/$(dirname "$REL_PATH")"
        mkdir -p "$DEST_DIR" || { echo "Error: Could not create subdirectory for '$REL_PATH' in staging."; exit 1; }
        cp "$filepath" "$DEST_DIR" || { echo "Error: Could not copy '$filepath' to staging area."; exit 1; }
    elif [ -d "$filepath" ]; then
        # It's a directory.
        # Compute checksums for all files recursively.
        for file_in_dir in $(find "$filepath" -type f); do
            sha1sum "$file_in_dir" >> "$CHECKSUM_FILE" || { echo "Error: Failed to calculate SHA1 for '$file_in_dir'."; exit 1; }
        done

        # Determine relative path and copy directory.
        REL_PATH=$(echo "$filepath" | sed 's|^/||')
        # Copy the directory into its parent in the staging area.
        DEST_PARENT="$BACKUP_STAGING_DIR/$(dirname "$REL_PATH")"
        mkdir -p "$DEST_PARENT" || { echo "Error: Could not create parent directory '$DEST_PARENT'."; exit 1; }
        cp -r "$filepath" "$DEST_PARENT" || { echo "Error: Could not copy directory '$filepath' to staging area."; exit 1; }
    else
        echo "Error: File or directory '$filepath' does not exist."
        exit 1
    fi
}

# Process input based on mode.
if [ "$mode" = "list" ]; then
    while IFS= read -r line; do
        process_path "$line"
    done < "$list_file"
elif [ "$mode" = "single" ]; then
    process_path "$single_path"
fi

# Ensure final backup directory exists.
mkdir -p "$FINAL_BACKUP_DIR" || { echo "Error: Could not create final backup directory '$FINAL_BACKUP_DIR'."; exit 1; }

# Create the tar archive from the staging directory.
# The archive will contain the relative paths (e.g. etc/drone.key, overlay/root/...)
tar -C "$BACKUP_STAGING_DIR" -cvf "$TAR_FILE" . || { echo "Error: Failed to create tar file from staging directory."; exit 1; }

# Compress the tar file.
gzip -f "$TAR_FILE" || { echo "Error: Failed to compress tar file."; exit 1; }

echo "Backup archive successfully created at: $TAR_GZ_FILE"
exit 0
