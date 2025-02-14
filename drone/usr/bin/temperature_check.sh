#!/bin/sh
# Threshold definitions:
WARNING1_THRESHOLD=80       # First warning threshold
WARNING2_THRESHOLD=90       # Second warning: add "VTX will soon thermal throttle..."
THROTTLE_THRESHOLD=100      # Throttle action threshold: adjust TX power and set FPS
REBOOT_THRESHOLD=110       # Reboot threshold

while true; do
    # --- Get VTX Temperature ---
    # Example output: "39.00"
    vtx_temp=$(ipcinfo --temp)
    # Extract integer part for comparison (e.g. 39)
    vtx_int=$(echo "$vtx_temp" | cut -d. -f1)
    
    # --- Get Adapter Temperature ---
    # Determine the WiFi adapter type
    wifi_adapter=$(yaml-cli -i /etc/vtx_info.yaml -g .wifi.wifi_adapter)
    
    # Initialize adapter_temp (default to 0 if unavailable)
    adapter_temp=0
    if [ "$wifi_adapter" = "8733bu" ]; then
        # The thermal state file might contain:
        # "rf_path: 0, thermal_value: 37, offset: 45, temperature: 20"
        adapter_temp=$(grep -o 'temperature: [0-9]*' /proc/net/rtl8733bu/wlan0/thermal_state | awk '{print $2}')
    elif [ "$wifi_adapter" = "88XXau" ]; then
        # Placeholder for extraction for 88XXau:
        echo "Adapter 88XXau temperature extraction not implemented yet."
        adapter_temp=0
    elif [ "$wifi_adapter" = "8812eu" ]; then
        # Placeholder for extraction for 8812eu:
        #cat /proc/net/rtl88x2eu/<wlan0>/thermal_state 
        echo "Adapter 8812eu temperature extraction not implemented yet."
        adapter_temp=0
    else
        echo "Unknown adapter type: $wifi_adapter"
    fi

    echo "VTX temperature: ${vtx_temp}°C, Adapter temperature: ${adapter_temp}°C"

    # Ensure adapter_temp is a number (set to 0 if empty)
    if [ -z "$adapter_temp" ]; then
        adapter_temp=0
    fi

    # --- Determine the Highest Temperature ---
    # If either sensor is high, we take action.
    max_temp=$vtx_int
    if [ "$adapter_temp" -gt "$max_temp" ]; then
        max_temp=$adapter_temp
    fi

    # --- Check Thresholds and Take Actions ---
    if [ "$max_temp" -ge "$REBOOT_THRESHOLD" ]; then
        echo "VTX will reboot due to thermal state..."
	echo "Rebooting in 5seconds...VTX Temp:&T WifiTemp: &W &L33 &F24 CPU: &C Bitrate: &B" > /tmp/msposd.msg
	sleep 5
        reboot
    elif [ "$max_temp" -ge "$THROTTLE_THRESHOLD" ]; then
        # For adapter type 88XXau, use a negative value in the txpower command.
        if [ "$wifi_adapter" = "88XXau" ]; then
            txpower_value="-500"
        else
            txpower_value="500"
        fi
        iw dev wlan0 set txpower fixed $txpower_value
        echo setfps 0 30 > /proc/mi_modules/mi_sensor/mi_sensor0
        echo "Throttling VTX. Reboot imminent, return to home..VTX Temp:&T WifiTemp: &W &L23 &F34 CPU: &C Bitrate: &B" > /tmp/msposd.msg
    elif [ "$max_temp" -ge "$WARNING2_THRESHOLD" ]; then
        echo "Warning: High temperature detected. VTX will soon thermal throttle...VTX Temp:&T WifiTemp: &W &L33 &F24 CPU: &C Bitrate: &B" > /tmp/msposd.msg
    elif [ "$max_temp" -ge "$WARNING1_THRESHOLD" ]; then
        echo "Warning: High temperature detected. VTX Temp:&T WifiTemp: &W &L33 &F44 CPU: &C Bitrate: &B" > /tmp/msposd.msg
    fi

    # Check again every 5 seconds
    sleep 5
done
