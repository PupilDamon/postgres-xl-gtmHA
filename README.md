# postgres-xl-gtmHA
shell run in backgroup to keep gtm master of postgres-xl alive </br>

run on gtm master and gtm slave </br>
    # echo "su - postgres -c /home/postgres/keep_gtm_alive.sh &" >> /etc/rc.local</br> 
    # chmod +x /etc/rc.d/rc.local</br>
    # init 6</br>

after the machine reboot, the script will run in backgroup to keep gtm master of postgres-xl alive if the gtm slave is ok.
