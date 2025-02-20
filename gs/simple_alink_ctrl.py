#!/usr/bin/env python3
import socket
import json
import sys
import time
import threading
import argparse

# --- Global Configuration (defaults) ---
HOST = 'localhost'
PORT = 8103

# Mapping parameters for BITRATE (adjustable):
RS_RSSI_HIGH = -50    # strongest signal (dBm)
RS_RSSI_LOW = -90     # weakest signal (dBm)
BITRATE_HIGH = 14000  # highest bitrate value
BITRATE_LOW = 6000    # lowest bitrate value

# Mapping parameters for TX power:
TX_RSSI_MIN = -90     # lowest RSSI (worst signal)
TX_RSSI_MAX = -40     # highest RSSI (best signal)
TX_PWR_HIGH = 9       # highest TX power (when RSSI is very low)
TX_PWR_LOW = 1        # lowest TX power (when RSSI is high)

# REC_LOST thresholds and sample size
REC_THRESHOLD_FEC = 0  # Default threshold for fec_rec (if > this, trigger)
REC_THRESHOLD_LOST = 0  # Default threshold for lost (if > this, trigger)
REC_LOST_SAMPLE_SIZE = 5  # Number of samples to keep for REC_LOST calculation
rec_lost_samples = []      # Global list for REC_LOST samples

# Global sequence number for all commands sent.
seq_num = 0
seq_lock = threading.Lock()  # For thread-safe sequence increments

# Global variables set via command-line arguments.
VERBOSITY = 0             # 0: silent, 1: commands and acks, 2: full debug info
HEARTBEAT_INTERVAL = 0.5  # seconds (default now 0.5 sec)
UDP_MODE = False          # If True, run in UDP mode

# UDP transmission parameters (only used if UDP_MODE is True)
udp_socket = None
udp_ip = None
udp_port = None

# Global shutdown event.
shutdown_event = threading.Event()

def log(level, msg):
    """
    Print debug messages if the current verbosity level is high enough.
    level 1: Important messages (commands sent, ACK received, errors)
    level 2: Detailed messages (socket connection, packet details, etc.)
    """
    if VERBOSITY >= level:
        sys.stderr.write(msg + "\n")

def safe_send(line):
    """
    Attempt to send a line.
    In UDP mode, send it as a UDP packet to the configured destination.
    Otherwise, write to stdout.
    If an error occurs, log it, set shutdown_event, and return False.
    """
    if UDP_MODE:
        try:
            # Append newline so that receivers (e.g. netcat) see a complete line.
            if not line.endswith("\n"):
                line += "\n"
            udp_socket.sendto(line.encode('utf-8'), (udp_ip, udp_port))
            return True
        except Exception as e:
            log(1, f"[safe_send] UDP send failed: {e} for line: {line}")
            shutdown_event.set()
            return False
    else:
        try:
            print(line)
            sys.stdout.flush()
            return True
        except BrokenPipeError:
            log(1, f"[safe_send] Broken pipe encountered when sending: {line}")
            shutdown_event.set()
            return False

def get_next_seq():
    global seq_num
    with seq_lock:
        seq_num += 1
        return seq_num

def map_rssi_to_bitrate(rssi, rssi_low=RS_RSSI_LOW, rssi_high=RS_RSSI_HIGH,
                        bitrate_low=BITRATE_LOW, bitrate_high=BITRATE_HIGH):
    """
    Map an RSSI value (rssi_avg) to a bitrate using linear interpolation.
    For rssi <= rssi_low, returns bitrate_low.
    For rssi >= rssi_high, returns bitrate_high.
    Otherwise, linearly interpolates between the two.
    """
    if rssi <= rssi_low:
        return bitrate_low
    if rssi >= rssi_high:
        return bitrate_high
    ratio = (rssi - rssi_low) / (rssi_high - rssi_low)
    bitrate = bitrate_low + ratio * (bitrate_high - bitrate_low)
    return int(bitrate)

def map_rssi_to_tx_power(rssi, tx_rssi_min=TX_RSSI_MIN, tx_rssi_max=TX_RSSI_MAX,
                         tx_power_low=TX_PWR_LOW, tx_power_high=TX_PWR_HIGH):
    """
    Map an RSSI value (rssi_avg) to a TX power value.
    When RSSI is low (e.g. -90 dBm), TX power is high.
    When RSSI is high (e.g. -40 dBm), TX power is low.
    Linearly interpolate (inverted) between these limits.
    """
    if rssi <= tx_rssi_min:
        return tx_power_high
    if rssi >= tx_rssi_max:
        return tx_power_low
    ratio = (rssi - tx_rssi_min) / (tx_rssi_max - tx_rssi_min)
    # Invert the ratio so that lower rssi gives higher TX power.
    tx_power = tx_power_high - ratio * (tx_power_high - tx_power_low)
    return int(round(tx_power))

def send_bitrate(bitrate):
    """
    Send a BITRATE command with the computed bitrate.
    Format: BITRATE<TAB>sequence<TAB>bitrate
    """
    seq = get_next_seq()
    command_str = f"BITRATE\t{seq}\t{bitrate}"
    if safe_send(command_str):
        log(1, f"[CMD SENT] {command_str}")

def send_tx_power(tx_power):
    """
    Send a TX_PWR command with the computed TX power.
    Format: TX_PWR<TAB>sequence<TAB>tx_power
    """
    seq = get_next_seq()
    command_str = f"TX_PWR\t{seq}\t{tx_power}"
    if safe_send(command_str):
        log(1, f"[CMD SENT] {command_str}")

def send_rec_lost(fec_val, lost_val):
    """
    Send a REC_LOST command with the given fec_rec and lost values.
    Format: REC_LOST<TAB>sequence<TAB>fec_val<TAB>lost_val
    """
    seq = get_next_seq()
    command_str = f"REC_LOST\t{seq}\t{fec_val}\t{lost_val}"
    if safe_send(command_str):
        log(1, f"[CMD SENT] {command_str}")

def send_heartbeat():
    """
    Send a HEARTBEAT command.
    Format: HEARTBEAT<TAB>sequence<TAB>Heartbeat received
    """
    seq = get_next_seq()
    command_str = f"HEARTBEAT\t{seq}\tHeartbeat received"
    if safe_send(command_str):
        log(1, f"[CMD SENT] {command_str}")

def send_info(info):
    """
    Placeholder for sending an INFO command.
    """
    seq = get_next_seq()
    command_str = f"INFO\t{seq}\t{info}"
    if safe_send(command_str):
        log(1, f"[CMD SENT] {command_str}")

def send_status(status):
    """
    Placeholder for sending a STATUS command.
    """
    seq = get_next_seq()
    command_str = f"STATUS\t{seq}\t{status}"
    if safe_send(command_str):
        log(1, f"[CMD SENT] {command_str}")

def send_command_action(action):
    """
    Placeholder for sending a COMMAND command.
    For example, action can be ENABLE, DISABLE, RESET, etc.
    """
    seq = get_next_seq()
    command_str = f"COMMAND\t{seq}\t{action}"
    if safe_send(command_str):
        log(1, f"[CMD SENT] {command_str}")

def parse_ack_message(line):
    """
    Parse an ack message from STDIN and echo it.
    Expected ack format (tab-delimited):
      ACK:COMMAND_TYPE<TAB>sequence<TAB>message
    """
    parts = line.strip().split('\t')
    if len(parts) < 3:
        log(1, f"[ACK PARSER] Invalid ack format: {line.strip()}")
        return
    command = parts[0]
    seq = parts[1]
    msg = parts[2]
    log(1, f"[ACK RECEIVED] Command: {command}, Seq: {seq}, Msg: {msg}")

def ack_listener():
    """
    Continuously read ack messages from STDIN and process them.
    In bidirectional mode, exit on EOF.
    In UDP mode, ignore EOF (i.e. do not shut down).
    """
    log(2, "[ACK LISTENER] Started.")
    while not shutdown_event.is_set():
        line = sys.stdin.readline()
        if not line:
            if UDP_MODE:
                log(2, "[ACK LISTENER] EOF on STDIN, but in UDP mode. Ignoring.")
                time.sleep(1)
                continue
            else:
                log(2, "[ACK LISTENER] EOF reached on STDIN. Exiting ack listener.")
                shutdown_event.set()
                break
        parse_ack_message(line)

def socket_listener():
    """
    Connect to the JSON stream on port 8103 and process incoming JSON messages.
    If the connection is lost, reconnect every 3 seconds.
    """
    global rssi_history, rec_lost_samples
    while not shutdown_event.is_set():
        try:
            log(2, f"[SOCKET] Connecting to JSON stream at {HOST}:{PORT}...")
            sock = socket.create_connection((HOST, PORT))
        except Exception as e:
            log(2, f"[SOCKET] Failed to connect: {e}. Retrying in 3 seconds...")
            time.sleep(3)
            continue

        log(2, "[SOCKET] Connected. Listening for JSON messages...")
        try:
            stream = sock.makefile('r')
            for line in stream:
                if shutdown_event.is_set():
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError as e:
                    log(2, f"[SOCKET] JSON decode error: {e}")
                    continue

                # Skip the one-time "settings" message.
                if data.get("type") == "settings":
                    log(2, "[SOCKET] Received settings message.")
                    continue

                # Process rx messages.
                if data.get("type") == "rx":
                    msg_id = data.get("id", "")
                    if msg_id == "video rx":
                        # --- Process "packets" for REC_LOST ---
                        packets = data.get("packets", {})
                        if packets:
                            fec_rec = packets.get("fec_rec")
                            lost = packets.get("lost")
                            if (isinstance(fec_rec, list) and len(fec_rec) > 0 and
                                isinstance(lost, list) and len(lost) > 0):
                                new_fec = fec_rec[0]
                                new_lost = lost[0]
                                # Append new sample; maintain sliding window.
                                rec_lost_samples.append((new_fec, new_lost))
                                if len(rec_lost_samples) > REC_LOST_SAMPLE_SIZE:
                                    rec_lost_samples.pop(0)
                                # Select sample with highest combined value.
                                max_sample = max(rec_lost_samples, key=lambda s: s[0] + s[1])
                                # Check thresholds: if both are 0, always send; otherwise, only send if either exceeds threshold.
                                if REC_THRESHOLD_FEC == 0 and REC_THRESHOLD_LOST == 0:
                                    send_rec_lost(max_sample[0], max_sample[1])
                                else:
                                    if max_sample[0] > REC_THRESHOLD_FEC or max_sample[1] > REC_THRESHOLD_LOST:
                                        send_rec_lost(max_sample[0], max_sample[1])
                        else:
                            log(2, "[SOCKET] No 'packets' data available for REC_LOST.")

                        # --- Process "rx_ant_stats" to get best RSSI ---
                        ant_stats = data.get("rx_ant_stats", [])
                        if not ant_stats:
                            log(2, "[SOCKET] No rx_ant_stats available.")
                            continue

                        best_ant = max(ant_stats, key=lambda ant: ant.get("rssi_avg", -1000))
                        best_rssi = best_ant.get("rssi_avg", -1000)
                        log(2, f"[SOCKET] Best antenna stats: {best_ant}")

                        # --- Update moving average for RSSI ---
                        # (Append new best_rssi; remove oldest if window exceeded)
                        rssi_history.append(best_rssi)
                        if len(rssi_history) > 5:
                            rssi_history.pop(0)
                        avg_rssi = round(sum(rssi_history) / len(rssi_history))
                        log(2, f"[SOCKET] Updated RSSI moving average: {avg_rssi} (history: {rssi_history})")

                        # --- Compute commands using moving average ---
                        target_bitrate = map_rssi_to_bitrate(avg_rssi)
                        target_tx_power = map_rssi_to_tx_power(avg_rssi)
                        log(2, f"[SOCKET] Using avg RSSI: {avg_rssi} dBm, computed BITRATE: {target_bitrate}, computed TX_PWR: {target_tx_power}")

                        # --- Send BITRATE and TX_PWR commands ---
                        send_bitrate(target_bitrate)
                        send_tx_power(target_tx_power)
                    else:
                        log(2, f"[SOCKET] Received rx message with id '{msg_id}'. Placeholder processing...")
                else:
                    log(2, f"[SOCKET] Received message of type '{data.get('type')}'. Placeholder processing...")
        except Exception as e:
            log(2, f"[SOCKET] Exception while reading JSON stream: {e}. Reconnecting in 3 seconds...")
        finally:
            try:
                sock.close()
            except Exception:
                pass
            time.sleep(3)

def heartbeat_sender(interval):
    """
    Periodically send HEARTBEAT messages every 'interval' seconds.
    """
    log(2, f"[HEARTBEAT] Started with interval {interval} seconds.")
    while not shutdown_event.is_set():
        send_heartbeat()
        time.sleep(interval)

def main():
    global VERBOSITY, HEARTBEAT_INTERVAL, UDP_MODE, udp_socket, udp_ip, udp_port
    global rec_lost_samples, rssi_history

    # Initialize the moving average lists.
    rssi_history = []
    rec_lost_samples = []

    parser = argparse.ArgumentParser(
        description="JSON Stream Client with periodic HEARTBEAT messages and REC_LOST detection")
    parser.add_argument("--heartbeat", type=float, default=0.5,
                        help="Heartbeat interval in seconds (default: 0.5)")
    parser.add_argument("--verbose", type=int, default=0,
                        help="Set verbosity level (0: silent, 1: commands and acks, 2: full debug)")
    parser.add_argument("--udp", action="store_true",
                        help="Run in UDP mode (transmit commands via UDP instead of stdout)")
    parser.add_argument("--udp_ip", type=str, default="10.5.0.10",
                        help="Destination IP for UDP transmissions (default: 10.5.0.10)")
    parser.add_argument("--udp_port", type=int, default=5557,
                        help="Destination port for UDP transmissions (default: 5557)")
    args = parser.parse_args()

    VERBOSITY = args.verbose
    HEARTBEAT_INTERVAL = args.heartbeat
    UDP_MODE = args.udp

    if UDP_MODE:
        udp_ip = args.udp_ip
        udp_port = args.udp_port
        try:
            udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            log(1, f"[MAIN] Running in UDP mode: transmitting to {udp_ip}:{udp_port}.")
        except Exception as e:
            log(1, f"[MAIN] Failed to create UDP socket: {e}")
            shutdown_event.set()

    # Start the ack listener thread only if not in UDP mode.
    if not UDP_MODE:
        ack_thread = threading.Thread(target=ack_listener, daemon=True)
        ack_thread.start()
    else:
        log(1, "[MAIN] UDP mode active: ignoring STDIN (ACK listener not started).")

    # Start the JSON socket listener thread.
    socket_thread = threading.Thread(target=socket_listener, daemon=True)
    socket_thread.start()

    # Start the heartbeat sender thread.
    heartbeat_thread = threading.Thread(target=heartbeat_sender, args=(HEARTBEAT_INTERVAL,), daemon=True)
    heartbeat_thread.start()

    # Main thread waits until shutdown is signaled.
    try:
        while not shutdown_event.is_set():
            time.sleep(1)
    except KeyboardInterrupt:
        log(1, "[MAIN] Terminated by user (KeyboardInterrupt).")
        shutdown_event.set()

    log(1, "[MAIN] Shutdown event set. Exiting gracefully.")
    sys.exit(0)

if __name__ == '__main__':
    main()
