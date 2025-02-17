# WFB-NG Provisioning for OpenIPC reference

## Feature summary
- WFB-NG provisioning implemented using a mix of scripts and a main C program.
  - BIND(yes),UNBIND(yes),BACKUP(yes),INFO(yes),VERSION(yes),FLASH(prepared, not implemented)
  - Python client available for groundstation for testing 
  - Provision on bootup (15s) for a unbinded vtx. Can be turned off in settings.
- Automatic passphrase generation of drone.key on bind (Similar to ELRS passphrase)
- Able to match known wifi profiles to TX-PWR settings, LDPC, STBC (handles 8731bu)
- Able to set a custom name to your VTX, to be used for saving backups and possible other things.
- Prepared for community presets/profiles parsing.
- Automatic bitrate negotiation. decide the bitrate you want to have, and GI,MCS,BW will be automatically selected to fit the channel. Priority order BW>MCS>GI. Capped at 20mbps per default. Fallback if invalid bitrate requested is mcs0 3000bitrate 20mhz long.
- Automatic temperature throttling (scroll down to see limits and actions)
- Simple-alink prototype

## Groundstation
- Setup wfb-ng to use/listen channel 165, until the full openipc-bind is implemented by wfb-ng.
- Run sudo wfb-server --profiles gs gs_bind --wlans wlan1 (This will initiate a tunnel on both the bind and normal gs interface, but you must have latest wfb-ng master branch)
- cd to gs/
- chmod +x *

### Command examples:
By default, connect.py will try connect to 10.5.0.10 port 5555 for provisioning. see --help for full command list.
- connect.py --info
- connect.py --version
- connect.py --bind folder-containing-bind-files-to-send/ (if you have a custom folder structure you want to compress, checksum and send. must be parsable by "provision_listen.sh on drone)
- connect.py --bind backup-folder-to-store-backups/my-backup.tar.gz (direct target a tar.gz generated from --backup)
- connect.py --unbind (will initiate firstboot on drone)
- connect.py --backup backup-folder-to-store-backups/

## Drone
- Setup wfb-ng to use/listen channel 165 for troubleshooting and debug. But it doesnt really matter as long as gs/vtx is on the same channel.
- Copy files from "drone" to drone folder structures. Apply chmod +x on /usr/bin and /etc/init.d/ files.
- set your wifi profile in /etc/wfb.conf. See /etc/wifi_profiles.yaml for valid wifi profiles. This is only used to generate the /etc/vtc_info.yaml
- reboot vtx to generate the /etc/vtx_info.yaml, or run "generate_vtx_info.sh" manually. Check for /etc/vtx_info.yaml
- Run a provision command on groundstation, info or version are good to start with. --backup and --bind can be next step.
![image](https://github.com/user-attachments/assets/1a9d4826-eae6-4a45-9abb-089b07da9fe4)

### Simple alink
- Run on drone wfb_bind_srv_armhf --udp 5557 0.0.0.0 simple_alink.sh --verbose (remember to enable check for temp throttle!!! - Self reminder)
- run on GS: ./wfb_bind_srv --client --udp 5557 10.5.0.10 ./simple_alink_ctrl.py --udp

### VTX info output
````
vtx_id: 556E23F52D0A
vtx_name: OpenIPC
build_option: fpv
soc: ssc338q
wifi:
  wifi_adapter: 8733bu
  wifi_profile: bl-m8731bu4
  bw: [5,10,20,40]
  ldpc: [0]
  stbc: [0]
  tx_power:
    mcs0: [1,5,10,15,20,25,30,35,40,45,50,55,60,63]
    mcs1: [1,5,10,15,20,25,30,35,40,45,50,55,60]
    mcs2: [1,5,10,15,20,25,30,35,40,45,50,55]
    mcs3: [1,5,10,15,20,25,30,35,40,45,50]
    mcs4: [1,5,10,15,20,25,30,35,40,45]
    mcs5: [1,5,10,15,20,25,30,35,40]
    mcs6: [1,5,10,15,20,25,30,35,40]
    mcs7: [1,5,10,15,20,25,30,35]
video:
  sensor: imx335
  bitrate: [4096,6144,8192,10240,12288,14336,16384,18432,20480]
  imu_sensor: BMI270
  modes:
    60fps: [2560x1440,1920x1080,1600x900,1440x810,1280x720]
    90fps: [2208x1248,1920x1080,1440x810,1280x720,1104x624]
    120fps: [1920x1080,1600x900,1440x810,1280x720,960x540]
````
### Temperature throttling
````
#!/bin/sh
# Threshold definitions (degrees Celsius (symbol: °C)):
WARNING1_THRESHOLD=80       # First warning threshold, if below the vtx will reset to original settings
WARNING2_THRESHOLD=90       # Second warning, threshold, written to msposd (warning: VTX will soon throttle), no actions taken yet
THROTTLE_THRESHOLD=100      # Throttle Level 1, written to msposd and TX_PWR set to "10" and FPS set to 30.
THROTTLE2_THRESHOLD=105     # Throttle Level 2, warning written to msposd and a 10second timout starts. After expiration majestic (video streamer) will be killed forcefully.
REBOOT_THRESHOLD=110        # Reboot threshold, warning echo to terminal and 5second countdown to reboot initiated.
````

# Source
https://github.com/svpcom/wfb-ng/wiki/Drone-auto-provisioning
