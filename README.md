# WFB-NG Provisioning for OpenIPC reference

## Groundstation
chmod +x all .py and .sh files.
### Command examples:
- sudo ./gs_provision.sh wlxc43cb0b7b1a2 flash flash/openipc.ssc338q-nor-fpv.tgz (will send the tar.gz file to the drone, provisioner.sh on drone will enter a code block where you can add flash logic. Right now it will exit and cleanup to avoid headaches).
- sudo ./gs_provision.sh wlxc43cb0b7b1a2 info (Print out some info from drone)
- sudo ./gs_provision.sh wlxc43cb0b7b1a2 version (Prints out a static version from drone)
- sudo ./gs_provision.sh wlxc43cb0b7b1a2 bind bind/docker-ssc338q (Warning! This will copy the files from folder bind/docker-ssc338q to your drone and "provision" it according to bind instructions in bind.sh found on drone)
- sudo ./gs_provision.sh wlxc43cb0b7b1a2 unbind (Will execute "firstboot" to restore the drone)
- sudo ./gs_provision.sh wlxc43cb0b7b1a2 backup backup/ (Will send all files added to /etc/backup_these_files.txt as a tar.gz archive with sha1 checksums to the designated backup folder, with date and time as filename)

## Drone
- Copy files from "drone" to drone /usr/bin folder
- chmod +x the files
- run provision.sh for initiating the provisioner service to listen for provision commands for 30s
- Go and run a provision command on groundstation.
### drone_provisioner exit codes:
- #define EXIT_ERR    1
- #define EXIT_BIND   2
- #define EXIT_UNBIND 3
- #define EXIT_FLASH  4
- #define EXIT_BACKUP 5

# Source
https://github.com/svpcom/wfb-ng/wiki/Drone-auto-provisioning
