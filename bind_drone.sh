#!/bin/sh
	wifibroadcast stop        
	killall -q wfb_rx
	killall -q wfb_tx
                                                                              
        iw wlan0 set monitor none                                                                        
        iw wlan0 set channel 165 HT20                                                                    
        iw reg set US                                                                                         
                                                                                                              
	echo "- Starting bind process"
	
	if ! [ -f /etc/bind.key ]
	then
		# Default bind key
		echo "OoLVgEYyFofg9zdhfYPks8/L8fqWaF9Jk8aEnynFPsXNqhSpRCMbVKBFP4fCEOv5DGcbXmUHV5eSykAbFB70ew==" | base64 -d > /etc/bind.key
	fi
	
	echo "- Starting wfb_tun"
	wfb_rx -p 255 -u 5800 -K /etc/bind.key -i 10531917 wlan0 &> /dev/null &
	wfb_tx -p 127 -u 5801 -K /etc/bind.key -M 1 -S 0 -L 0 \
		-k 1 -n 2 -i 10531917 wlan0 &> /dev/null &
	wfb_tun -a 10.5.99.2/24 &
	
	#Sleep needed for wfb_tun to initialize, dont remove it!
	sleep 4
	 
	drone_bind --debug --listen-duration 30
	EXIT_CODE=$?

	echo "drone_bind exited with code $EXIT_CODE"

	# Handle exit codes
	case $EXIT_CODE in
    	0)
		echo "Listen period ended. Exiting."
        ;;
    	1)
        	echo "Fatal errors."
        	exit 1
        ;;
    	2)
        	echo "File received and saved successfully. Continuing execution..."
        	                                                                                                                                                        
        	cd /tmp/bind                                                                                                                                                               
        	gunzip bind.tar.gz
		tar x -f bind.tar
		cd bind
        	if ! [ -f checksum.txt ] || ! sha1sum -c checksum.txt                                                                                                 
            	then                                                                                                                                                                        
                	echo $'ERR\tChecksum failed'
                	exit 0                                                                                                                                                 
            	fi                                                                                                                                                                          
                                                                                                                                                                                        
        	#copy system files to their locations
		if [ -f etc/wfb.yaml ]
		then
			cp etc/wfb.yaml /etc/wfb.yaml
			echo "Copy success: /etc/wfb.yaml"
		fi

                if [ -f etc/sensors/ ]                                                                                                                                                  
                then                                                                                                                                                                    
                        cp etc/sensors/* /etc/sensors/                                                                                                                                  
                        echo "Copy success: Sensor bins"                                                                                                                                
                fi 

		if [ -f etc/majestic.yaml ]
                then                                                            
                        cp etc/majestic.yaml /etc/majestic.yaml
			/etc/init.d/S95majestic restart                                         
                        echo "Copy & restart success: /etc/majestic.yaml"                      
                fi
                
		if [ -f lib/modules/4.9.84/sigmastar/sensor_imx335_mipi.ko ]                                     
                then                                                            
                        cp lib/modules/4.9.84/sigmastar/sensor_imx335_mipi.ko /lib/modules/4.9.84/sigmastar/sensor_imx335_mipi.ko                 
                        echo "Copy success (restart required): lib/modules/4.9.84/sigmastar/sensor_imx335_mipi.ko"       
                fi

		if [ -f ./custom_script.sh ]                                                                          
                then                                                                                                                                  
                        chmod +x ./custom_script.sh
			./custom_script.sh
			echo "Copy success and execute: custom_script.sh"                                    
                fi


		#cleanup
		rm -rf /tmp/bind
                                                                                                                             
        ;;
    	3)
        	echo "UNBIND command recieved: Executing firstboot."
        	firstboot
		exit 3
        ;;
        3)                                                                                                   
                echo "FLASH command recieved: Exiting."                                                     
                #Insert FLASH code here
		exit 4                                                                                      
        ;;
    	*)
        	echo "Unexpected error occurred. Exiting with code $EXIT_CODE."
        	#exit $EXIT_CODE
        ;;
	esac	


echo "Exiting drone_bind"

exit 0
