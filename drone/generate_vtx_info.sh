#!/bin/sh
# generate_vtx_info.sh
# This script creates (or conditionally updates) /etc/vtx_info.yaml using the enhanced YAML Configurator.
# It populates vtx_id from ipcinfo, uses a static table for video modes and bitrates,
# adjusts Wi‑Fi settings, and adds an imu_sensor field based on i2cdetect.

CFG_FILE="/etc/vtx_info.yaml"

########################################
# Function: update_value
# Usage: update_value <yaml-key> <new_value>
# Reads the current value at the dot-separated key path; if it differs from <new_value>,
# then sets the value using yaml-cli.
########################################
update_value() {
    key="$1"
    newval="$2"
    oldval="$(yaml-cli -i "$CFG_FILE" -g "$key" 2>/dev/null || echo "")"
    if [ "$oldval" != "$newval" ]; then
        echo "Updating $key from '$oldval' to '$newval'"
        yaml-cli -i "$CFG_FILE" -s "$key" "$newval"
    else
        echo "No change for $key (already '$oldval')"
    fi
}

########################################
# 1. Set vtx_id from ipcinfo -i.
########################################
vtx_id=$(ipcinfo -i 2>/dev/null)
[ -z "$vtx_id" ] && vtx_id="UNKNOWN"

########################################
# 2. Basic system values: soc, sensor, build_option.
########################################
soc=$(fw_printenv soc 2>/dev/null | awk -F= '/soc=/ {print $2}')
[ -z "$soc" ] && soc="ssc338q"

sensor=$(fw_printenv sensor 2>/dev/null | awk -F= '/sensor=/ {print $2}')
[ -z "$sensor" ] && sensor="imx335"

build_option=$(awk -F= '/^BUILD_OPTION=/ {print $2}' /etc/os-release)
[ -z "$build_option" ] && build_option="fpv"

########################################
# 3. Define bitrate list based on soc.
#    For ssc338q: [1024×4,1024×6,…,1024×24]  
#    For ssc30kq: [1024×4,1024×6,…,1024×18]
########################################
if [ "$soc" = "ssc338q" ]; then
    bitrate="[4096,6144,8192,10240,12288,14336,16384,18432,20480,22528,24576]"
elif [ "$soc" = "ssc30kq" ]; then
    bitrate="[4096,6144,8192,10240,12288,14336,16384,18432]"
else
    bitrate="[4096,6144,8192,10240,12288,14336,16384,18432]"
fi

########################################
# 4. Detect Wi‑Fi adapter and define available choices.
########################################
raw_driver="none"
for card in $(lsusb | awk '{print $6}' | sort | uniq); do
    case "$card" in
       "0bda:8812"|"0bda:881a"|"0b05:17d2"|"2357:0101"|"2604:0012")
           raw_driver="rtl8812au"
           break
           ;;
       "0bda:a81a")
           raw_driver="rtl8812eu"
           break
           ;;
       "0bda:f72b"|"0bda:b733")
           raw_driver="rtl8733bu"
           break
           ;;
    esac
done

if [ "$raw_driver" = "rtl8812au" ]; then
    wifi_bw="[5,10,20,40]"
    wifi_ldpc="[0,1]"
    wifi_stbc="[0,1]"
    wifi_mcs="[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]"
    tx_power_mcs0="[1,5,10,15,20,25,30,35,40,45,50,55,60,63]"
    tx_power_mcs1="[1,5,10,15,20,25,30,35,40,45,50,55,60]"
    tx_power_mcs2="[1,5,10,15,20,25,30,35,40,45,50,55]"
    tx_power_mcs3="[1,5,10,15,20,25,30,35,40,45,50]"
    tx_power_mcs4="[1,5,10,15,20,25,30,35,40,45]"
    tx_power_mcs5="[1,5,10,15,20,25,30,35,40]"
    tx_power_mcs6="[1,5,10,15,20,25,30,35,40]"
    tx_power_mcs7="[1,5,10,15,20,25,30,35]"
elif [ "$raw_driver" = "rtl8812eu" ]; then
    wifi_bw="[5,10,20]"
    wifi_ldpc="[0,1]"
    wifi_stbc="[0,1]"
    tx_power_mcs0="[1,5,10,15,20,25,30,35,40,45,50,55,60,63]"
    tx_power_mcs1="[1,5,10,15,20,25,30,35,40,45,50,55,60]"
    tx_power_mcs2="[1,5,10,15,20,25,30,35,40,45,50,55]"
    tx_power_mcs3="[1,5,10,15,20,25,30,35,40,45,50]"
    tx_power_mcs4="[1,5,10,15,20,25,30,35,40,45]"
    tx_power_mcs5="[1,5,10,15,20,25,30,35,40]"
    tx_power_mcs6="[1,5,10,15,20,25,30,35,40]"
    tx_power_mcs7="[1,5,10,15,20,25,30,35]"
elif [ "$raw_driver" = "rtl8733bu" ]; then
    # Extended bw for rtl8733bu
    wifi_bw="[5,10,20,40]"
    wifi_ldpc="[0]"
    wifi_stbc="[0]"
    tx_power_mcs0="[1,5,10,15,20,25,30,35,40,45,50,55,60,63]"
    tx_power_mcs1="[1,5,10,15,20,25,30,35,40,45,50,55,60]"
    tx_power_mcs2="[1,5,10,15,20,25,30,35,40,45,50,55]"
    tx_power_mcs3="[1,5,10,15,20,25,30,35,40,45,50]"
    tx_power_mcs4="[1,5,10,15,20,25,30,35,40,45]"
    tx_power_mcs5="[1,5,10,15,20,25,30,35,40]"
    tx_power_mcs6="[1,5,10,15,20,25,30,35,40]"
    tx_power_mcs7="[1,5,10,15,20,25,30,35]"
else
    wifi_bw="[20]"
    wifi_ldpc="[0]"
    wifi_stbc="[0]"
    wifi_mcs=""
    tx_power_mcs0="[1,5,10,15,20,25,30]"
    tx_power_mcs1="[1,5,10,15,20,25,30]"
    tx_power_mcs2="[1,5,10,15,20,25,30]"
    tx_power_mcs3="[1,5,10,15,20,25,30]"
    tx_power_mcs4="[1,5,10,15,20,25,30]"
    tx_power_mcs5="[1,5,10,15,20,25,30]"
    tx_power_mcs6="[1,5,10,15,20,25,30]"
    tx_power_mcs7="[1,5,10,15,20,25,30]"
fi

########################################
# 5. Define static video modes mapping based on sensor type.
#    Each mode's list now always includes a "1920x1080" entry;
#    if an entry close to 1920x is present, it is replaced by "1920x1080".
########################################
if [ "$sensor" = "imx415" ]; then
  video_modes="{30fps: [3840x2160,2880x1620,1920x1080,1440x810,1280x720], 60fps: [2720x1528,1920x1080,1440x810,1360x764,1280x720], 90fps: [1920x1080,1600x900,1440x810,1280x720,960x540], 120fps: [1920x1080,1440x810,1280x720,1104x612,736x408]}"
elif [ "$sensor" = "imx335" ]; then
  video_modes="{60fps: [2560x1440,1920x1080,1600x900,1440x810,1280x720], 90fps: [2208x1248,1920x1080,1440x810,1280x720,1104x624], 120fps: [1920x1080,1600x900,1440x810,1280x720,960x540]}"
else
  video_modes="{}"
fi

########################################
# 6. Determine the IMU sensor.
########################################
imu_output=$(i2cdetect -y -r 1 2>/dev/null)
if echo "$imu_output" | grep -q "68"; then
    imu_sensor="BMI270"
else
    imu_sensor="none"
fi

########################################
# 7. Create or update the YAML configuration.
########################################
if [ ! -f "$CFG_FILE" ]; then
    cat <<EOF > "$CFG_FILE"
vtx_info:
  vtx_id: $vtx_id
  build_option: $build_option
  soc: $soc
  wifi:
    wifi_adapter: $raw_driver
    bw: $wifi_bw
    ldpc: $wifi_ldpc
    stbc: $wifi_stbc
EOF
    if [ "$raw_driver" = "rtl8812au" ]; then
       echo "    mcs: $wifi_mcs" >> "$CFG_FILE"
    fi
    cat <<EOF >> "$CFG_FILE"
    tx_power:
      mcs0: $tx_power_mcs0
      mcs1: $tx_power_mcs1
      mcs2: $tx_power_mcs2
      mcs3: $tx_power_mcs3
      mcs4: $tx_power_mcs4
      mcs5: $tx_power_mcs5
      mcs6: $tx_power_mcs6
      mcs7: $tx_power_mcs7
  video:
    sensor: $sensor
    bitrate: $bitrate
    imu_sensor: $imu_sensor
    modes: $video_modes
EOF
    echo "Created $CFG_FILE with default/auto-detected values."
else
    echo "$CFG_FILE found. Conditionally updating values..."
    update_value .vtx_info.vtx_id "$vtx_id"
    update_value .vtx_info.build_option "$build_option"
    update_value .vtx_info.soc "$soc"

    update_value .vtx_info.wifi.wifi_adapter "$raw_driver"
    update_value .vtx_info.wifi.bw "$wifi_bw"
    update_value .vtx_info.wifi.ldpc "$wifi_ldpc"
    update_value .vtx_info.wifi.stbc "$wifi_stbc"
    if [ "$raw_driver" = "rtl8812au" ]; then
        update_value .vtx_info.wifi.mcs "$wifi_mcs"
    fi
    update_value .vtx_info.wifi.tx_power.mcs0 "$tx_power_mcs0"
    update_value .vtx_info.wifi.tx_power.mcs1 "$tx_power_mcs1"
    update_value .vtx_info.wifi.tx_power.mcs2 "$tx_power_mcs2"
    update_value .vtx_info.wifi.tx_power.mcs3 "$tx_power_mcs3"
    update_value .vtx_info.wifi.tx_power.mcs4 "$tx_power_mcs4"
    update_value .vtx_info.wifi.tx_power.mcs5 "$tx_power_mcs5"
    update_value .vtx_info.wifi.tx_power.mcs6 "$tx_power_mcs6"
    update_value .vtx_info.wifi.tx_power.mcs7 "$tx_power_mcs7"

    update_value .vtx_info.video.sensor "$sensor"
    update_value .vtx_info.video.bitrate "$bitrate"
    update_value .vtx_info.video.imu_sensor "$imu_sensor"
    update_value .vtx_info.video.modes "$video_modes"

    echo "Done updating $CFG_FILE with conditional checks."
fi
