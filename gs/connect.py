#!/usr/bin/env python3
import socket
import time
import logging
import sys
import os
import argparse
import base64
import hashlib
import tarfile
import io

def compute_sha1(file_path):
    """Compute the SHA1 hash of the given file."""
    hash_obj = hashlib.sha1()
    with open(file_path, 'rb') as f:
        while chunk := f.read(8192):
            hash_obj.update(chunk)
    return hash_obj.hexdigest()

def compute_checksums(directory, checksum_file_path):
    """Compute SHA1 checksums for all files in a directory except checksum.txt."""
    checksum_lines = []
    for root, _, files in os.walk(directory):
        for file in files:
            file_path = os.path.join(root, file)
            if file_path == checksum_file_path:  # Skip checksum.txt itself
                continue
            rel_path = os.path.relpath(file_path, start=directory)
            sha1_hash = compute_sha1(file_path)
            checksum_lines.append(f"{sha1_hash}  {rel_path}")
    return checksum_lines

def create_tar_gz_archive(source_dir, arcname):
    """Create a tar.gz archive of the source directory, ensuring checksum.txt is included."""
    bio = io.BytesIO()
    checksum_file_path = os.path.join(source_dir, "checksum.txt")

    # Compute checksums excluding checksum.txt
    checksum_lines = compute_checksums(source_dir, checksum_file_path)
    
    # Write checksum.txt file
    with open(checksum_file_path, 'w') as f:
        for line in checksum_lines:
            f.write(line + "\n")

    # Create tar.gz archive including checksum.txt
    with tarfile.open(fileobj=bio, mode='w:gz') as tar:
        tar.add(source_dir, arcname=arcname)

    bio.seek(0)
    return bio.read()

def send_rate_limited(sock_file, data, bw_limit, progress=False):
    """Send data using bandwidth limiting."""
    bw_bytes_per_sec = bw_limit / 8.0
    chunk_size = 4096
    total = len(data)
    sent = 0
    start_time = time.time()
    
    while sent < total:
        end = min(sent + chunk_size, total)
        chunk = data[sent:end]
        sock_file.write(chunk)
        sock_file.flush()
        sent += len(chunk)
        elapsed = time.time() - start_time
        expected = sent / bw_bytes_per_sec
        if expected > elapsed:
            time.sleep(expected - elapsed)
        if progress:
            percent = sent / total * 100
            bar_length = 40
            filled_length = int(round(bar_length * sent / total))
            bar = '=' * filled_length + '-' * (bar_length - filled_length)
            sys.stdout.write(f'\rProgress: [{bar}] {percent:6.2f}%')
            sys.stdout.flush()
    
    if progress:
        sys.stdout.write('\n')

def connect_to_server(host, port, max_retries, conn_timeout, op_timeout):
    """Connect to the server with retries."""
    sock = None
    for attempt in range(1, max_retries + 1):
        try:
            logging.debug(f"Attempt {attempt}: Connecting to {host}:{port} ...")
            sock = socket.create_connection((host, port), timeout=conn_timeout)
            logging.debug("Connection established.")
            break
        except Exception as e:
            logging.debug(f"Attempt {attempt} failed: {e}")
            time.sleep(1)
    
    if not sock:
        logging.error("Unable to connect to the server after multiple attempts.")
        sys.exit(1)
    
    sock.settimeout(op_timeout)
    sock_file = sock.makefile('rwb')
    return sock, sock_file

def bind_operation(folder_path, args):
    """Perform the BIND operation with checksum.txt included."""
    host = args.ip
    port = args.port
    max_retries = args.max_retries
    conn_timeout = args.conn_timeout
    op_timeout = args.timeout

    sock, sock_file = connect_to_server(host, port, max_retries, conn_timeout, op_timeout)
    
    try:
        archive_name = os.path.basename(os.path.normpath(folder_path))
        encoded_archive = base64.b64encode(create_tar_gz_archive(folder_path, archive_name)).decode('utf-8')

        bind_message = f"BIND\t{encoded_archive}\n".encode('utf-8')
        send_rate_limited(sock_file, bind_message, args.bw_limit, progress=True)

        response_line = sock_file.readline().decode('utf-8').strip()
        logging.debug(f"Received response after BIND: {response_line}")

    finally:
        sock_file.close()
        sock.close()

def simple_command_operation(command, args):
    """Perform INFO, VERSION, UNBIND operations."""
    sock, sock_file = connect_to_server(args.ip, args.port, args.max_retries, args.conn_timeout, args.timeout)
    
    try:
        sock_file.write(f"{command}\n".encode("utf-8"))
        sock_file.flush()
        response_line = sock_file.readline().decode("utf-8").strip()
        
        if command.upper() == "INFO":
            parts = response_line.split("\t", 1)
            if len(parts) > 1 and parts[0] == "OK":
                try:
                    decoded_msg = base64.b64decode(parts[1]).decode("utf-8")
                    print(decoded_msg)  # Print cleartext output
                except Exception as e:
                    logging.error("Failed to decode INFO response: " + str(e))
                    print(response_line)  # Fallback to raw output
            else:
                print(response_line)  # Print raw response if format is incorrect
        else:
            print(response_line)  # Normal output for other commands

    finally:
        sock_file.close()
        sock.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", nargs="?", help="Path for BIND/FLASH")
    parser.add_argument("--bind", action="store_true", help="Perform BIND operation")
    parser.add_argument("--flash", action="store_true", help="Perform FLASH operation")
    parser.add_argument("--unbind", action="store_true", help="Perform UNBIND operation")
    parser.add_argument("--info", action="store_true", help="Perform INFO operation")
    parser.add_argument("--version", action="store_true", help="Perform VERSION operation")
    parser.add_argument("--ip", "-i", default="10.5.99.2", help="Server IP address")
    parser.add_argument("--port", "-p", type=int, default=5555, help="Server port")
    parser.add_argument("--max-retries", "-r", type=int, default=30, help="Max connection retries")
    parser.add_argument("--timeout", "-t", type=int, default=60, help="Socket timeout after connection")
    parser.add_argument("--conn-timeout", "-c", type=int, default=5, help="Timeout for connection attempt")
    parser.add_argument("--bw-limit", type=int, default=2 * 1024 * 1024, help="Bandwidth limit in bits/sec")

    args = parser.parse_args()

    if args.bind:
        bind_operation(args.folder, args)
    elif args.unbind:
        simple_command_operation("UNBIND", args)
    elif args.info:
        simple_command_operation("INFO", args)
    elif args.version:
        simple_command_operation("VERSION", args)

if __name__ == "__main__":
    main()

