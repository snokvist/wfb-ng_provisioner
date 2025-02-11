# WFB-NG Provisioning for OpenIPC reference

## Groundstation
cd to gs/
chmod +x *

### Command examples:
By default, connect.py will try connect to 10.5.0.10 port 5555 for provisioning. see --help for full command list.
- connect.py --info
- connect.py --version
- connect.py --bind folder-containing-bind-files-to-send/
- connect.py --unbind (will initiate firstboot on drone)
- connect.py --backup backup-folder-to-store-backups/

## Drone
- Copy files from "drone" to drone folder structures. Apply chmod +x on /usr/bin files.
- run provision.sh for initiating the provisioner service to listen for provision commands for 9999s
- Go and run a provision command on groundstation.

### drone_provisioner exit codes:
- #define EXIT_ERR    1
- #define EXIT_BIND   2
- #define EXIT_UNBIND 3
- #define EXIT_FLASH  4
- #define EXIT_BACKUP 5

# Source
https://github.com/svpcom/wfb-ng/wiki/Drone-auto-provisioning
