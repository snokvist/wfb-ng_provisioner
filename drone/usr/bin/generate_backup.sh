#!/bin/sh
#
# Script: generate_backup.sh
# Purpose: Back up files and/or directories (recursively) as listed in a file or a single directory.
#          If the backup source includes /overlay/root, then any subfolder named "root" under it
#          is removed from the staging area (and its files are excluded from checksums).
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

# --- Determine Input Mode ---

found_overlay_root=0

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

# --- Directories and File Names ---

BACKUP_STAGING_DIR="/tmp/backup/staging"
FINAL_BACKUP_DIR="/tmp/backup"
TAR_FILE="$FINAL_BACKUP_DIR/backup.tar"
TAR_GZ_FILE="$FINAL_BACKUP_DIR/backup.tar.gz"
CHECKSUM_FILE="$BACKUP_STAGING_DIR/checksum.txt"

# --- Prepare Staging Area ---

rm -rf "$BACKUP_STAGING_DIR" 2>/dev/null
mkdir -p "$BACKUP_STAGING_DIR" || { echo "Error: Could not create staging directory '$BACKUP_STAGING_DIR'."; exit 1; }
# Initialize the checksum file.
> "$CHECKSUM_FILE" || { echo "Error: Cannot write to checksum file '$CHECKSUM_FILE'."; exit 1; }

# --- Function: process_path ---
# Processes a given absolute path (file or directory) by:
#   - Computing SHA1 checksums for files.
#   - Copying files (or directories) into the staging area, preserving relative paths.
process_path() {
    filepath="$1"
    # Skip empty lines.
    [ -z "$filepath" ] && return

    # Remove any trailing slash (unless the path is just "/")
    if [ "$filepath" != "/" ]; then
      filepath=$(echo "$filepath" | sed 's:/*$::')
    fi

    # Check if this path is exactly /overlay/root.
    if [ "$filepath" = "/overlay/root" ]; then
        found_overlay_root=1
    fi

    if [ -f "$filepath" ]; then
        # It's a file.
        sha1sum_output=$(sha1sum "$filepath" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Failed to calculate SHA1 for '$filepath'."
            exit 1
        fi
        echo "$sha1sum_output" >> "$CHECKSUM_FILE"

        # Remove leading slash for relative path.
        REL_PATH=$(echo "$filepath" | sed 's|^/||')
        DEST_DIR="$BACKUP_STAGING_DIR/$(dirname "$REL_PATH")"
        mkdir -p "$DEST_DIR" || { echo "Error: Could not create subdirectory for '$REL_PATH' in staging."; exit 1; }
        cp "$filepath" "$DEST_DIR" || { echo "Error: Could not copy '$filepath' to staging area."; exit 1; }
    elif [ -d "$filepath" ]; then
        # It's a directory.
        # Compute checksums for all files recursively.
        # (If this directory is /overlay/root, we'll remove its "root" subfolder later.)
        for file_in_dir in $(find "$filepath" -type f); do
            sha1sum "$file_in_dir" >> "$CHECKSUM_FILE" || { echo "Error: Failed to calculate SHA1 for '$file_in_dir'."; exit 1; }
        done

        # Determine the relative path (strip leading slash).
        REL_PATH=$(echo "$filepath" | sed 's|^/||')
        # Copy the directory (with all contents) into the staging area.
        DEST_PARENT="$BACKUP_STAGING_DIR/$(dirname "$REL_PATH")"
        mkdir -p "$DEST_PARENT" || { echo "Error: Could not create parent directory '$DEST_PARENT'."; exit 1; }
        cp -r "$filepath" "$DEST_PARENT" || { echo "Error: Could not copy directory '$filepath' to staging area."; exit 1; }
    else
        echo "Error: File or directory '$filepath' does not exist."
        exit 1
    fi
}

# --- Process Input ---

if [ "$mode" = "list" ]; then
    while IFS= read -r line; do
        process_path "$line"
    done < "$list_file"
elif [ "$mode" = "single" ]; then
    process_path "$single_path"
fi

# --- Remove Unwanted Subfolder for /overlay/root Backup ---

# If /overlay/root was used for backup, then in the staging area the relative path is "overlay/root".
# If a subdirectory "root" exists under that, remove it.
if [ $found_overlay_root -eq 1 ]; then
    unwanted_dir="$BACKUP_STAGING_DIR/overlay/root/root"
    if [ -d "$unwanted_dir" ]; then
        rm -rf "$unwanted_dir" || { echo "Error: Could not remove unwanted folder '$unwanted_dir' from staging area."; exit 1; }
    fi

    # Re-generate the checksum file so that it reflects only the files that remain in staging.
    # Remove the old checksum file first.
    > "$CHECKSUM_FILE"
    # Compute checksums for all files in the staging area, excluding the checksum file itself.
    find "$BACKUP_STAGING_DIR" -type f | grep -v "$(basename "$CHECKSUM_FILE")" | while read file; do
        sha1sum "$file" >> "$CHECKSUM_FILE" || { echo "Error: Failed to generate checksum for '$file'."; exit 1; }
    done
fi

# --- Create Tar Archive and Compress ---

mkdir -p "$FINAL_BACKUP_DIR" || { echo "Error: Could not create final backup directory '$FINAL_BACKUP_DIR'."; exit 1; }

# Create the tar archive from the staging directory.
tar -C "$BACKUP_STAGING_DIR" -cvf "$TAR_FILE" . || { echo "Error: Failed to create tar file from staging directory."; exit 1; }

# Compress the tar archive.
gzip -f "$TAR_FILE" || { echo "Error: Failed to compress tar file."; exit 1; }

echo "Backup archive successfully created at: $TAR_GZ_FILE"
exit 0
