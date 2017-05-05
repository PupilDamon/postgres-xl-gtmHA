#!/bin/sh
######################################################
# The following variables require manual configuration
pgxl_owner=postgres
local_gtm_ip=192.168.122.179
local_gtm_port=20001
local_gtm_dir=/pgdata/gtm/data
remote_gtm_ip=192.168.122.189
remote_gtm_port=20001
remote_gtm_dir=/pgdata/gtm/data
remote_gtm_ssh_port=22
rec_status_path=/home/postgres/remote_gtm_status.txt
gtm_proxy=y
gtm_proxy_server=(192.168.122.171 192.168.122.172 192.168.122.173)
gtm_proxy_port=(20001 20001 20001)
coord_server=(192.168.122.171 192.168.122.172 192.168.122.173)
coord_port=(15432 15432 15432)
######################################################
######################################################
# The following variables do not require manual configuration
# gtm_mast_status : 0 = ok ; 1 = failure ; 2 = unknown
scp_result=0
echo 1 > $rec_status_path
cur_local_gtm_status=2
cur_remote_gtm_status=2
rec_remote_gtm_status=`cat $rec_status_path`
chk_gtm_proxy_coord=0
success_time=0
failure_time=0
all_off_time=0
keep_time=0
keep_log_file=/tmp/keep_gtm_alive.log
######################################################

# function to write log
function wlog()
{
  now_time=`date +'%Y-%m-%d %H:%M:%S'`
  if [ $1 -eq 1 ] ; then
    echo "" >> $keep_log_file
    echo ${now_time}" "$2 | tee -a ${keep_log_file}
  else
    echo ${now_time}" "$2 | tee -a ${keep_log_file}
  fi
}

# function to scp gtm.control from remote gtm master
scp_gtm_control()
{
nport=`echo ""|port_probe $remote_gtm_ip $remote_gtm_ssh_port 2>/dev/null|grep "connect ok"|wc -l`
if [ $nport -eq 1 ] ; then
  /usr/bin/timeout 2 /usr/bin/scp -rp -P $remote_gtm_ssh_port $remote_gtm_ip:$remote_gtm_dir/gtm.control $local_gtm_dir/ 
#> /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    wlog 1 "scp gtm control error !!!"
    ((scp_result++))
    elif [ $scp_result -ne 0 ] ; then
    wlog 1 "scp gtm control return to normal."
    scp_result=0
  fi
  else
    wlog 1 "the ssh port of gtm master can not connect !!!"
fi
}

# function to test gtm master alive or not
is_gtm_master_ok()
{
nport=`echo ""|port_probe $remote_gtm_ip $remote_gtm_port 2>/dev/null|grep "connect ok"|wc -l`
if [ $nport -eq 1 ];then
   cur_remote_gtm_status=0
 else
   cur_remote_gtm_status=1
fi
}

# function to test gtm slave alive or not
is_gtm_slave_ok()
{
nport=`echo ""|port_probe $local_gtm_ip $local_gtm_port 2>/dev/null|grep "connect ok"|wc -l`
if [ $nport -eq 1 ];then
   cur_local_gtm_status=0
 else
   cur_local_gtm_status=1
fi
}

# function to check gtm proxy alive or not
is_gtm_proxy_coord_ok()
{
wlog 1 'Start to Check Gtm_Proxy or Coordinator Alive'
if [ $gtm_proxy == "y" ] ; then
  arr=0
  chk_gtm_proxy_coord=0
  while [ $arr -lt ${#gtm_proxy_server[@]} ]
  do
    nport=`echo ""|port_probe ${gtm_proxy_server[$arr]} ${gtm_proxy_port[$arr]} 2>/dev/null|grep "connect ok"|wc -l`
    if [ $nport -eq 1 ] ; then
      wlog 2 "gtm proxy server "${gtm_proxy_server[$arr]}" alive"
      ((chk_gtm_proxy_coord++))
    fi
    ((arr++))
  done
 else
   arr=0
   chk_gtm_proxy_coord=0
   while [ $arr -lt ${#coord_server[@]} ]
   do
     nport=`echo ""|port_probe ${coord_server[$arr]} ${coord_port[$arr]} 2>/dev/null|grep "connect ok"|wc -l`
     if [ $nport -eq 1 ] ; then
      wlog 2 "coordinator server "${coord_server[$arr]}" alive"
       ((chk_gtm_proxy_coord++))
     fi
     ((arr++))
   done
fi
}

# function to update gtm slave gtm.control
update_gtm_control()
{
wlog 1 "Start to update local gtm.control"
wlog 2 "old gtm.control :"
cat $local_gtm_dir/gtm.control >> $keep_log_file
ori_xid=`cat $local_gtm_dir/gtm.control | grep next_xid | tail -n 1 | sed 's/ //g' | awk -F ':' '{print $2}'`
ori_xmin=`cat $local_gtm_dir/gtm.control | grep global_xmin | tail -n 1 | sed 's/ //g' | awk -F ':' '{print $2}'`
((new_xid=$ori_xid+2000))
((new_xmin=$ori_xmin+2000))
sed -i '/next_xid/d' $local_gtm_dir/gtm.control
echo "next_xid: $new_xid" >> $local_gtm_dir/gtm.control
sleep 0.5
sed -i '/global_xmin/d' $local_gtm_dir/gtm.control
echo "global_xmin: $new_xmin" >> $local_gtm_dir/gtm.control
wlog 2 "new gtm.control :"
cat $local_gtm_dir/gtm.control >> $keep_log_file
}

# function to kill -9 gtm proxy force
kill_9_gtm_proxy()
{
if [ $gtm_proxy == "y" ] ; then
  arr=0
  while [ $arr -lt ${#gtm_proxy_server[@]} ]
  do
    wlog 2 "kill -9 gtm proxy server "${gtm_proxy_server[$arr]}"..."
    ssh $pgxl_owner@${gtm_proxy_server[$arr]} 'ps -ef | grep -v "grep" | grep gtm_proxy | awk '{print $2}' | xargs kill -9' &
    sleep 0.5
    ((arr++))
  done
fi
}

# function to keep gtm master alive
keep_gtm_master_alive()
{
  rec_remote_gtm_status=`cat $rec_status_path`
  is_gtm_master_ok;
#  echo "cur_remote_gtm_status "$cur_remote_gtm_status >> $keep_log_file
#  echo "rec_remote_gtm_status "$rec_remote_gtm_status >> $keep_log_file
  if [ $cur_remote_gtm_status -eq 0 ] && [ $rec_remote_gtm_status -eq 1 ] ; then
    ((success_time++))
#    echo "success_time "$success_time
       if [ $success_time -eq 3 ] ; then
         success_time=0
         wlog 2 "rec_remote_gtm_status is "$rec_remote_gtm_status" and cur_remote_gtm_status is "$cur_remote_gtm_status" more then 3 times"
	 echo 0 > $rec_status_path
         wlog 2 "rec_remote_gtm_status changed to 0"
       fi
  fi
  if [ $cur_remote_gtm_status -eq 0 ] && [ $failure_time -ne 0 ] ; then
    ((success_time++))
#    echo "success_time "$success_time
       if [ $success_time -eq 3 ] ; then
         success_time=0
         wlog 2 "gtm master have failed "$failure_time" times"
         failure_time=0
         wlog 2 "but then succeeded more than 3 times"
         wlog 2 "rec_remote_gtm_status is "$rec_remote_gtm_status" and cur_remote_gtm_status is "$cur_remote_gtm_status" more then 3 times"
         echo 0 > $rec_status_path
         wlog 2 "rec_remote_gtm_status changed to 0"
       fi
  fi
  if [ $cur_remote_gtm_status -eq 1 ] && [ $rec_remote_gtm_status -eq 0 ] ; then
    ((failure_time++))
#    echo "failure_time "$failure_time >> $keep_log_file
#echo 5 >> $keep_log_file
    wlog 2 "Warning : monitoring gtm master failed "$failure_time" times !"
      if [ $failure_time -eq 3 ] ; then
        wlog 2 "Warning : monitoring gtm master failed "$failure_time" times !"
        failure_time=0
        wlog 2 "rec_remote_gtm_status is "$rec_remote_gtm_status" and cur_remote_gtm_status is "$cur_remote_gtm_status" more then 3 times"
        wlog 1 "gtm master failed 3 times !!!"
        is_gtm_proxy_coord_ok;
#	echo "chk_gtm_proxy_coord"$chk_gtm_proxy_coord
        if [ $chk_gtm_proxy_coord -ne 0 ] ; then
          update_gtm_control;
          wlog 1 "Start to failover gtm"
          pgxc_ctl failover gtm >> $keep_log_file
          if [ $? -eq 0 ] ; then
            echo 1 > $rec_status_path
       wlog 2 "rec_remote_gtm_status changed to 1"
	    sleep 0.5
	    if [ $gtm_proxy == "y" ] ; then
          wlog 2 "Start to reconnect gtm_proxy all"
	      pgxc_ctl reconnect gtm_proxy all >> $keep_log_file
              sleep 0.5
          wlog 2 "Start to stop gtm_proxy all"
              pgxc_ctl stop gtm_proxy all >> $keep_log_file
              sleep 0.5
              kill_9_gtm_proxy
              sleep 0.5
          wlog 2 "Start to start gtm_proxy all"
              pgxc_ctl start gtm_proxy all >> $keep_log_file
          wlog 1 "failover gtm done."
          echo "" >> $keep_log_file
	    fi
          fi
        fi
      fi
  fi
}

# function to check is all gtm off
is_all_gtm_off()
{
rec_remote_gtm_status=`cat $rec_status_path`
if [ $rec_remote_gtm_status -eq 0 ] ; then
  is_gtm_master_ok;
  if [ $cur_remote_gtm_status -eq 1 ] ; then
    ((all_off_time++))
    if [ $all_off_time  -eq 3 ] ; then
      echo 1 > $rec_status_path
      all_off_time=0
      wlog 2 "rec_remote_gtm_status is "$rec_remote_gtm_status" and cur_remote_gtm_status is "$cur_remote_gtm_status" more then 3 times"
      wlog 2 "rec_remote_gtm_status changed to 1"
      wlog 1 "gtm master and gtm slave is all off."
      echo "" >> $keep_log_file
    fi
  fi
fi
}

# main
# keep this script 1 seconds to run once
wlog 1 "Start to run keep_gtm_alive.sh"
for ((m=1;m>0;m=1))
do
  gtm_role=`cat $local_gtm_dir/gtm.conf | grep startup | tail -n 1 | sed 's/ //g' | awk -F '=' '{print $2}' | cut -c 1-7`
  if [ $gtm_role == "STANDBY" ] ; then
    is_gtm_slave_ok;
    if [ $cur_local_gtm_status -eq 0 ] ; then
      scp_gtm_control;
      ((keep_time++))
#      echo "keep_time="$keep_time >> $keep_log_file
      if [ $keep_time -eq 3 ] ; then
        keep_gtm_master_alive;
        keep_time=0
      fi
    else
      is_all_gtm_off;
    fi
  fi
sleep 1
done
