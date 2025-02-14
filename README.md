# WFB-NG Provisioning for OpenIPC reference

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
- Setup wfb-ng to use/listen channel 165, until the full openipc-bind is implemented by wfb-ng.
- Copy files from "drone" to drone folder structures. Apply chmod +x on /usr/bin and /etc/init.d/ files.
- set your wifi profile with for example "fw_setenv wifi_profile bl-r8812af1". See /etc/wifi_profiles.yaml for valid wifi profiles. This is only used to generate the /etc/vtc_info.yaml
- set your vtx name with "fw_setenv vtx_name My_Cool_VTX". This is only used to generate the /etc/vtc_info.yaml but is used for example when naming your backup.
- reboot vtx to generate the /etc/vtx_info.yaml, or run "generate_vtx_info.sh" manually. Check for /etc/vtx_info.yaml
- run provision.sh for initiating the provisioner service to listen for provision commands on 0.0.0.0 port 5555 for 9999s (or if service already running due to init scripts, you need to kill it first)
- Go and run a provision command on groundstation, info or version are good to start with. --backup and --bind can be next step.
![image](https://github.com/user-attachments/assets/1a9d4826-eae6-4a45-9abb-089b07da9fe4)

### drone_provisioner exit codes:
- #define EXIT_OK     0
- #define EXIT_ERR    1
- #define EXIT_BIND   2
- #define EXIT_UNBIND 3
- #define EXIT_FLASH  4
- #define EXIT_BACKUP 5

# Source
https://github.com/svpcom/wfb-ng/wiki/Drone-auto-provisioning
