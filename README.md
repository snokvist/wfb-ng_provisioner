# WFB-NG Provisioning for OpenIPC reference

## Groundstation
chmod +x all .py and .sh files.
### Command examples:
- sudo ./gs_bind.sh wlxc43cb0b7b1a2 flash flash/openipc.ssc338q-nor-fpv.tgz
- sudo ./gs_bind.sh wlxc43cb0b7b1a2 info
- sudo ./gs_bind.sh wlxc43cb0b7b1a2 version
- sudo ./gs_bind.sh wlxc43cb0b7b1a2 bind bind/docker-ssc338q (Warning! This will copy the files from folder bind/docker-ssc338q to your drone and "provision" it according to bind instructions in bind.sh found on drone)
- udo ./gs_bind.sh wlxc43cb0b7b1a2 unbind (Will prinout that firstboot should run (but it will not run to save you some headaches restoring everything, check bind.sh)

## Drone
- Copy files from "drone" to drone /usr/bin folder
- chmod +x the files
- run bind.sh for initiating the provisioner service to listen for provision commands for 30s
- Go and run a provision command on groundstation.
