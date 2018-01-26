#!/bin/bash

set -x

STRESS_WOWLAN_DIR=/home/admin/stress_wowlan
exec &> >(tee -a "$STRESS_WOWLAN_DIR/data/wowlan_stress.log")

STRESS_WOWLAN_CONF=/home/admin/stress_wowlan/config
STRESS_WOWLAN_RUNTIME=/home/admin/stress_wowlan/runtime
STRESS_WOWLAN_PASS_FILE=/home/admin/stress_wowlan/pass
STRESS_WOWLAN_FAIL_FILE=/home/admin/stress_wowlan/fail

. $STRESS_WOWLAN_CONF
if [ -f $STRESS_WOWLAN_RUNTIME ];then
    . $STRESS_WOWLAN_RUNTIME
fi

build_ssh_env() {
    if [ ! -f /home/admin/.ssh/id_rsa ]; then
        ssh-keygen -b 2048 -t rsa -f /home/admin/.ssh/id_rsa -q -N ""
        chown admin:admin /home/admin/.ssh/*
    fi
    ssh-copy-id -i /home/admin/.ssh/id_rsa.pub $WOWLAN_SERVER_USR@$WOWLAN_SERVER_IP || true
}

wait_nm_started(){
    until /snap/bin/network-manager.nmcli d; do
        echo "wait nm started"
        sleep 10
    done
}

connect_wifi_ap() {
    echo "Connect wifi AP"
    # delete old connection
    wait_nm_started
    CONT=$(/snap/bin/network-manager.nmcli c | grep Canonical-2.4GHz-g | cut -d ' ' -f 3)
    if [ ! -z $CONT ]; then
        /snap/bin/network-manager.nmcli c del $CONT
    fi

    # create a new connection
    /snap/bin/network-manager.nmcli d wifi connect $WIFI_AP password $WIFI_PASSWD

    sleep 5
    # try to ping out
    #ping -I wlan0 -c 3 10.101.46.1
    #if [ $? -ne 0 ]; then
    #    /snap/bin/network-manager.nmcli d > $STRESS_WOWLAN_FAIL_FILE
    #    /snap/bin/network-manager.nmcli c >> $STRESS_WOWLAN_FAIL_FILE
    #    echo "Wifi ping out error" >> $STRESS_WOWLAN_FAIL_FILE
    #fi

}

check_wifi_funtions() {
    error=
    # s3
    if [ $LAST_S3_ITERATION -lt $STRESS_S3_ITERATIONS ]; then
        sleep $STRESS_S3_UP_DELAY
    # s4
    elif [ $LAST_S4_ITERATION -lt $STRESS_S4_ITERATIONS ]; then
        sleep $STRESS_S4_UP_DELAY
    # s5
    elif [ $LAST_S5_ITERATION -lt $STRESS_S5_ITERATIONS ]; then
        sleep $STRESS_S5_UP_DELAY
    fi
    
    wait_nm_started
    /snap/bin/network-manager.nmcli d status | grep wlan0 | grep connected
    if [ $? -ne 0 ]; then
        echo "Wifi lost connection" >> $STRESS_WOWLAN_FAIL_FILE
        error=true
    fi
    # try to ping out
    #ping -I wlan0 -c 3 10.101.46.1
    #if [ $? -ne 0 ]; then
    #    /snap/bin/network-manager.nmcli d > $STRESS_WOWLAN_FAIL_FILE
    #    /snap/bin/network-manager.nmcli c >> $STRESS_WOWLAN_FAIL_FILE
    #    echo "Wifi ping out error" >> $STRESS_WOWLAN_FAIL_FILE
    #    error=true
    #fi

	echo "Test BT"
    # try bluetooth
    /snap/bin/hciconfig hci0
    if [ $? -ne 0 ]; then
        echo "bluetooth not found" >> $STRESS_WOWLAN_FAIL_FILE
        error=true
    fi

	if [ "$error" = true ];then
      echo "Wifi/BT failed... "
      
      # s3
      if [ $LAST_S3_ITERATION -lt $STRESS_S3_ITERATIONS ]; then
          echo "when in S3..." >> $STRESS_WOWLAN_FAIL_FILE
      # s4
      elif [ $LAST_S4_ITERATION -lt $STRESS_S4_ITERATIONS ]; then
          echo "when in S4..." >> $STRESS_WOWLAN_FAIL_FILE
      # s5
      elif [ $LAST_S5_ITERATION -lt $STRESS_S5_ITERATIONS ]; then
          echo "when in S5..." >> $STRESS_WOWLAN_FAIL_FILE
      fi

      echo "see the log: $STRESS_WOWLAN_FAIL_FILE"
      exit
    fi
}

remote_wowlan_enable() {
    # s3
    if [ $LAST_S3_ITERATION -lt $STRESS_S3_ITERATIONS ]; then
        DELAY=$ISSUE_WOWLAN_S3_WAIT_DELAY
    # s4
    elif [ $LAST_S4_ITERATION -lt $STRESS_S4_ITERATIONS ]; then
        DELAY=$ISSUE_WOWLAN_S4_WAIT_DELAY
    # s5
    elif [ $LAST_S5_ITERATION -lt $STRESS_S5_ITERATIONS ]; then
        DELAY=$ISSUE_WOWLAN_S5_WAIT_DELAY
    fi

    MAC=$(cat /sys/class/net/wlan0/address)
    ssh -i /home/admin/.ssh/id_rsa $WOWLAN_SERVER_USR@$WOWLAN_SERVER_IP "
echo 'echo 'sleep $DELAY';sleep $DELAY;echo 'issue wowlan to $MAC'; wakeonlan $MAC; sleep 2; echo 'issue wowlan to $MAC'; wakeonlan $MAC; sleep 2; echo 'issue wowlan to $MAC'; wakeonlan $MAC' > /tmp/test.sh; nohup bash /tmp/test.sh > /tmp/test.out 2>/tmp/test.err < /dev/null &"

    if [ $? -ne 0 ]; then
        echo "ssh to server error. wifi failed?" >> $STRESS_WOWLAN_FAIL_FILE
        exit
    fi
}

go_to_power_mode() {
    # s3
    if [ $LAST_S3_ITERATION -lt $STRESS_S3_ITERATIONS ]; then
        sleep $STRESS_S3_WAIT_DELAY
    # s4
    elif [ $LAST_S4_ITERATION -lt $STRESS_S4_ITERATIONS ]; then
        sleep $STRESS_S4_WAIT_DELAY
    # s5
    elif [ $LAST_S5_ITERATION -lt $STRESS_S5_ITERATIONS ]; then
        sleep $STRESS_S5_WAIT_DELAY
    fi
    #remote_wowlan_enable
    sudo iw phy $(cat /sys/class/net/wlan0/phy80211/name) wowlan enable magic-packet
    if [ $1 == 'poweroff' ]; then
        sudo poweroff || true
    else
	    sudo systemctl $1 || true
    fi
}

if [ "$1" == "restart" ] && [ -f $STRESS_WOWLAN_RUNTIME ]; then
    rm $STRESS_WOWLAN_RUNTIME
    LAST_S3_ITERATION=
    LAST_S4_ITERATION=
    LAST_S5_ITERATION=
    if [ -f $STRESS_WOWLAN_PASS_FILE ];then
        rm $STRESS_WOWLAN_PASS_FILE
    fi
    if [ -f $STRESS_WOWLAN_FAIL_FILE ];then
        rm $STRESS_WOWLAN_FAIL_FILE
    fi
fi

# main loop
while [ 1 ]; do
    #First cycle
    if [ ! -n "$LAST_S3_ITERATION" -a ! -n "$LAST_S4_ITERATION" -a ! -n "$LAST_S5_ITERATION" ]; then
        LAST_S3_ITERATION=0
        LAST_S4_ITERATION=0
        LAST_S5_ITERATION=0
	    #build_ssh_env
        connect_wifi_ap
    else #other cycles
        echo "WOWLAN stress cycle:"
        echo "S3: $LAST_S3_ITERATION/$STRESS_S3_ITERATIONS"
        echo "S4: $LAST_S4_ITERATION/$STRESS_S4_ITERATIONS"
        echo "S5: $LAST_S5_ITERATION/$STRESS_S5_ITERATIONS"
        check_wifi_funtions
    fi

    # s3
    if [ $LAST_S3_ITERATION -lt $STRESS_S3_ITERATIONS ]; then
        LAST_S3_ITERATION=$((LAST_S3_ITERATION + 1))
        sudo echo "LAST_S3_ITERATION=$LAST_S3_ITERATION" > $STRESS_WOWLAN_RUNTIME
        sudo echo "LAST_S4_ITERATION=$LAST_S4_ITERATION" >> $STRESS_WOWLAN_RUNTIME
        sudo echo "LAST_S5_ITERATION=$LAST_S5_ITERATION" >> $STRESS_WOWLAN_RUNTIME
        go_to_power_mode suspend
    # s4
    elif [ $LAST_S4_ITERATION -lt $STRESS_S4_ITERATIONS ]; then
        LAST_S4_ITERATION=$((LAST_S4_ITERATION + 1))
        sudo echo "LAST_S3_ITERATION=$LAST_S3_ITERATION" > $STRESS_WOWLAN_RUNTIME
        sudo echo "LAST_S4_ITERATION=$LAST_S4_ITERATION" >> $STRESS_WOWLAN_RUNTIME
        sudo echo "LAST_S5_ITERATION=$LAST_S5_ITERATION" >> $STRESS_WOWLAN_RUNTIME
        go_to_power_mode hibernate
    # s5
    elif [ $LAST_S5_ITERATION -lt $STRESS_S5_ITERATIONS ]; then
        LAST_S5_ITERATION=$((LAST_S5_ITERATION + 1))
        sudo echo "LAST_S3_ITERATION=$LAST_S3_ITERATION" > $STRESS_WOWLAN_RUNTIME
        sudo echo "LAST_S4_ITERATION=$LAST_S4_ITERATION" >> $STRESS_WOWLAN_RUNTIME
        sudo echo "LAST_S5_ITERATION=$LAST_S5_ITERATION" >> $STRESS_WOWLAN_RUNTIME
        go_to_power_mode poweroff
    fi

    if [ $LAST_S3_ITERATION -ge $STRESS_S3_ITERATIONS ] && [ $LAST_S4_ITERATION -ge $STRESS_S4_ITERATIONS ] && [ $LAST_S5_ITERATION -ge $STRESS_S5_ITERATIONS ]; then
        echo "WOWLAN stress test done! Pass!" > $STRESS_WOWLAN_PASS_FILE
        exit
    fi
done
