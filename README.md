# WFB-NG Provisioning for OpenIPC reference

## Groundstation
- Setup wfb-ng to use/listen channel 165, until the full openipc-bind is implemented by wfb-ng.
- cd to gs/
- chmod +x *

### Command examples:
By default, connect.py will try connect to 10.5.0.10 port 5555 for provisioning. see --help for full command list.
- connect.py --info
- connect.py --version
- connect.py --bind folder-containing-bind-files-to-send/
- connect.py --unbind (will initiate firstboot on drone)
- connect.py --backup backup-folder-to-store-backups/

## Drone
- Copy files from "drone" to drone folder structures. Apply chmod +x on /usr/bin files.
- run provision.sh for initiating the provisioner service to listen for provision commands on 0.0.0.0 port 5555 for 9999s
- Go and run a provision command on groundstation, info or version are good to start with.
![image](https://github.com/user-attachments/assets/1a9d4826-eae6-4a45-9abb-089b07da9fe4)

### drone_provisioner exit codes:
- #define EXIT_ERR    1
- #define EXIT_BIND   2
- #define EXIT_UNBIND 3
- #define EXIT_FLASH  4
- #define EXIT_BACKUP 5

# Source
https://github.com/svpcom/wfb-ng/wiki/Drone-auto-provisioning
