# postgres-xl-gtmHA
shell run in backgroup to keep gtm master of postgres-xl alive

run on gtm master and gtm slave
# echo "su - postgres -c /home/postgres/keep_gtm_alive.sh &" >> /etc/rc.local
# chmod +x /etc/rc.d/rc.local
# init 6

after the machine reboot, the script will run in backgroup to keep gtm master of postgres-xl alive if the gtm slave is ok.
