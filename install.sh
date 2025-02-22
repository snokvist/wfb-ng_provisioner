#!/bin/sh


echo "chmmod +x on relevant files ..."
chmod +x drone/usr/bin*
chmod +x drone/etc/init.d/*

echo "Starting scp ..."
SSHPASS="12345" sshpass -e  scp -O -v -r /etc/gs.key root@192.168.1.232:/etc/drone.key 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e  scp -O -v -r drone/* root@192.168.1.232:/ 2>&1 | grep -v debug1


echo "Scp completed ... rebooting ... wait for reconnect... "
SSHPASS="12345" sshpass -e ssh -t root@192.168.1.232 'reboot' 2>&1 | grep -v debug1
sleep 8
echo "Reconnecting ..."
SSHPASS="12345" sshpass -e ssh root@192.168.1.232
