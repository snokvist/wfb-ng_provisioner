#!/bin/sh
#
# Script: generate_backup.sh
# Purpose: Read a list of file paths, generate SHA1 checksums, copy them to /tmp/backup/,
#          then create a backup tar.gz (with checksum.txt at the tar root).
#
# Usage: ./generate_backup.sh file_list.txt
#

# Bail out on any unhandled error
# (Uncomment `set -e` if you want to exit immediately on any command failure.)
# set -e

# 1. Check input arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <file_with_list_of_paths>"
  exit 1
fi

FILE_LIST="$1"
BACKUP_STAGING_DIR="/tmp/backup/staging"   # Where we'll copy all files
CHECKSUM_FILE="$BACKUP_STAGING_DIR/checksum.txt"
FINAL_BACKUP_DIR="/tmp/backup"
TAR_FILE="$FINAL_BACKUP_DIR/backup.tar"
TAR_GZ_FILE="$FINAL_BACKUP_DIR/backup.tar.gz"

# 2. Validate the file containing the list of paths
if [ ! -f "$FILE_LIST" ]; then
  echo "Error: The file '$FILE_LIST' does not exist or is not accessible."
  exit 1
fi

# 3. Prepare a clean staging directory
rm -rf "$BACKUP_STAGING_DIR" 2>/dev/null
mkdir -p "$BACKUP_STAGING_DIR" || {
  echo "Error: Could not create staging directory '$BACKUP_STAGING_DIR'."
  exit 1
}

# 4. Create/empty the checksum file
> "$CHECKSUM_FILE" || {
  echo "Error: Cannot write to checksum file '$CHECKSUM_FILE'."
  exit 1
}

# 5. Read each line, check existence, copy it, generate sha1sum
while IFS= read -r filepath; do
  # Skip empty lines
  [ -z "$filepath" ] && continue
  
  # Ensure the file actually exists
  if [ ! -f "$filepath" ]; then
    echo "Error: File '$filepath' does not exist."
    exit 1
  fi
  
  # Generate a checksum and append to checksum.txt
  # We handle error separately in case sha1sum isn't available or fails
  sha1sum_output=$(sha1sum "$filepath" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: Failed to calculate SHA1 for '$filepath'."
    exit 1
  fi
  echo "$sha1sum_output" >> "$CHECKSUM_FILE"
  
  # Copy the file to the staging directory, preserving relative path (minus leading slash)
  # Example: if filepath = "/etc/drone.key", then REL_PATH="etc/drone.key"
  REL_PATH="$(echo "$filepath" | sed 's|^/||')"
  
  # Make sure the subdirectory structure exists
  mkdir -p "$BACKUP_STAGING_DIR/$(dirname "$REL_PATH")" || {
    echo "Error: Could not create subdirectory for '$REL_PATH' in staging."
    exit 1
  }
  
  # Copy the file
  cp "$filepath" "$BACKUP_STAGING_DIR/$REL_PATH" || {
    echo "Error: Could not copy '$filepath' to staging area."
    exit 1
  }
  
done < "$FILE_LIST"

# 6. Create the tar from the staging directory
#    -C changes the directory to staging
#    We include everything (.) under staging so that the archived structure looks like:
#       etc/...    (for any file originally in /etc)
#       ...
#       checksum.txt (root of the tar)
#
mkdir -p "$FINAL_BACKUP_DIR" || {
  echo "Error: Could not create final backup directory '$FINAL_BACKUP_DIR'."
  exit 1
}

tar -C "$BACKUP_STAGING_DIR" -cvf "$TAR_FILE" . || {
  echo "Error: Failed to create tar file from staging directory."
  exit 1
}

# 7. Compress to backup.tar.gz (overwriting if it exists)
gzip -f "$TAR_FILE" || {
  echo "Error: Failed to compress tar file."
  exit 1
}

echo "Backup archive successfully created at: $TAR_GZ_FILE"
exit 0

