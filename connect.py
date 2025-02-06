#!/usr/bin/env python3
import socket
import time
import logging
import sys
import os
import argparse
import base64

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

def flash_operation(archive_file, args):
    """Perform the FLASH operation."""
    if not os.path.isfile(archive_file):
        logging.error(f"Provided archive file '{archive_file}' does not exist or is not a file.")
        sys.exit(1)
    
    try:
        with open(archive_file, 'rb') as f:
            file_data = f.read()
    except Exception as e:
        logging.error(f"Failed to read file '{archive_file}': {e}")
        sys.exit(1)
    
    encoded_archive = base64.b64encode(file_data).decode('utf-8')
    logging.debug(f"FLASH operation: Read and base64-encoded file '{archive_file}' "
                  f"({len(file_data)} bytes, {len(encoded_archive)} characters).")
    
    host = args.ip
    port = args.port
    max_retries = args.max_retries
    conn_timeout = args.conn_timeout
    op_timeout = args.timeout

    sock, sock_file = connect_to_server(host, port, max_retries, conn_timeout, op_timeout)

    try:
        logging.debug("Sending FLASH command to peer...")
        flash_message = f"FLASH\t{encoded_archive}\n".encode('utf-8')
        send_rate_limited(sock_file, flash_message, args.bw_limit, progress=True)
        
        response_line = sock_file.readline().decode('utf-8').strip()
        logging.debug(f"Received response after FLASH: {response_line}")

        if not response_line.startswith("OK"):
            logging.error(f"FLASH failed: {response_line}")
            sys.exit(1)

        logging.info("FLASH operation completed successfully.")

    finally:
        sock_file.close()
        sock.close()
        logging.debug("Connection closed.")

def info_operation(args):
    """Perform the INFO operation and decode the base64 response."""
    sock, sock_file = connect_to_server(args.ip, args.port, args.max_retries, args.conn_timeout, args.timeout)

    try:
        logging.debug("Sending INFO command to peer...")
        sock_file.write(b"INFO\n")
        sock_file.flush()

        response_line = sock_file.readline().decode('utf-8').strip()
        logging.debug(f"Received raw INFO response: {response_line}")

        parts = response_line.split('\t', 1)
        if parts[0] != "OK":
            logging.error(f"INFO command failed: {response_line}")
            sys.exit(1)

        if len(parts) < 2:
            logging.error("INFO response missing expected base64 data.")
            sys.exit(1)

        encoded_data = parts[1]

        try:
            decoded_data = base64.b64decode(encoded_data).decode('utf-8')
            print(decoded_data)
        except Exception as e:
            logging.error(f"Failed to decode INFO response: {e}")
            print(response_line)  # Fall back to raw output if decoding fails

    finally:
        sock_file.close()
        sock.close()

def simple_command_operation(command, args):
    """Perform VERSION, UNBIND operations."""
    sock, sock_file = connect_to_server(args.ip, args.port, args.max_retries, args.conn_timeout, args.timeout)
    
    try:
        sock_file.write(f"{command}\n".encode('utf-8'))
        sock_file.flush()
        response_line = sock_file.readline().decode('utf-8').strip()
        print(response_line)
    
    finally:
        sock_file.close()
        sock.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", nargs="?", help="Path for BIND/FLASH/BACKUP")
    parser.add_argument("--bind", action="store_true")
    parser.add_argument("--flash", action="store_true")
    parser.add_argument("--unbind", action="store_true")
    parser.add_argument("--info", action="store_true")
    parser.add_argument("--version", action="store_true")
    parser.add_argument("--backup", action="store_true")
    parser.add_argument("--ip", "-i", default="10.5.99.2")
    parser.add_argument("--port", "-p", type=int, default=5555)
    parser.add_argument("--max-retries", "-r", type=int, default=30)
    parser.add_argument("--timeout", "-t", type=int, default=60)
    parser.add_argument("--conn-timeout", "-c", type=int, default=5)
    parser.add_argument("--bw-limit", type=int, default=2 * 1024 * 1024)

    args = parser.parse_args()

    if args.flash:
        if not args.folder:
            logging.error("FLASH operation requires a file argument.")
            sys.exit(1)
        flash_operation(args.folder, args)
    elif args.info:
        info_operation(args)
    elif args.unbind:
        simple_command_operation("UNBIND", args)
    elif args.version:
        simple_command_operation("VERSION", args)

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.DEBUG,
        format='[%(asctime)s] %(levelname)s: %(message)s',
        datefmt='%H:%M:%S'
    )

    try:
        main()
    except KeyboardInterrupt:
        logging.info("Ctrl+C pressed. Exiting gracefully.")
        sys.exit(130)  # Exit code for Ctrl+C

