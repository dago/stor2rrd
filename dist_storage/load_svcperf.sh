#!/bin/sh
# version 0.15

# Parameters:
# Param1 - Storage name

#set -x 

PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/opt/freeware/bin
export PATH

# it is necessary as files need to be readable also for WEB server user
umask 022

# Load STORAGE2RRD configuration
dir=`dirname $0`
CFG="$dir/etc/stor2rrd.cfg"
. $CFG
DEBUG=0

PERL5LIB=$PERL5LIB:$BINDIR
export PERL5LIB

# Load "magic" setup
if [ -f "$dir/etc/.magic" ]; then
  . $dir/etc/.magic
fi

UPGRADE=0
if [ ! -f $dir/tmp/$version ]; then
  UPGRADE=1
fi
export UPGRADE

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
fi
if [ x"$STORAGE_CFG" = "x" ]; then
  echo "STORAGE_CFG does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi

cd $INPUTDIR
# Check if it runs under the right user
install_user=`ls -l etc/stor2rrd.cfg|awk '{print $3}'`
running_user=`id |awk -F\( '{print $2}'|awk -F\) '{print $1}'`
if [ ! "$install_user" = "$running_user" ]; then
  echo "You probably trying to run it under wrong user"
  echo "STOR2RRD files are owned by : $install_user"
  echo "You are : $running_user"
  echo "STOR2RRD should run only under user which owns installed package"
  echo "Do you want to really continue? [n]:"
  read answer
  if [ "$answer"x = "x" -o "$answer" = "n" -o "$anwer" = "N" ]; then
    exit
  fi
fi


# restart of all svcperf.pl processes right after vthe midnight
# To clean up processes in error if it happens
TSTAPM=tmp/swiz.stamp
if [ ! -f "$TSTAPM" ]; then
  touch $TSTAPM
fi

act_day=`date +"%d"`
last_day=`$PERL -e '$file=shift;$t = (stat("$file"))[9]; (my $s,my $m,my $h,my $day) = localtime($t); print "$day";' $TSTAPM`
if [ ! $act_day -eq $last_day -a `ps -ef|grep svcperf.pl|grep "perl "|wc -l` -gt 0 ]; then
  # kill all svcperf.pl and let them restart --> once a day
  drestart=`date`
  echo "$drestart: Restarting svcperf.pl processes : $act_day : $last_day"
  kill `ps -ef|grep svcperf.pl|grep "perl "|awk '{print $2}'|xargs`
  sleep 5
  touch $TSTAPM
fi
# end of restarting




for line in `cat $STORAGE_CFG|sed 's/#.*$//'|egrep ":SWIZ:"|egrep -v "^#"`
do
	# Name:SWIZ:DEVID:HMC1:HMC2:
	STORAGE_NAME=`echo $line | awk 'BEGIN{FS=":"}{print $1}'`
	STORAGE_TYPE=`echo $line | awk 'BEGIN{FS=":"}{print $2}'`
	
	export STORAGE_NAME STORAGE_TYPE

	# SVC/Storwize Storage Family
	SVC_IP=`echo $line | awk 'BEGIN{FS=":"}{print $3}'`
	#SVC_USER=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
	SVC_USER=$STORAGE_USER
	SVC_KEY=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
	SVC_DIR="$INPUTDIR/data/$STORAGE_NAME"
	SVC_INTERVAL=`expr $SAMPLE_RATE / 60`
	export SVC_IP SVC_USER SVC_KEY SVC_DIR SVC_INTERVAL

	if [ "$SVC_IP"x = "x" ]; then
    		echo "Some problem with storage cfg. Storage IP must be set. Check $STORAGE_CFG line: $line"
    		continue
	fi

	if [ ! -d "$SVC_DIR" ]; then
		mkdir "$SVC_DIR"
	fi
	if [ ! -d "$SVC_DIR/tmp" ]; then
		mkdir "$SVC_DIR/tmp"
	fi
	if [ ! -d "$SVC_DIR/iostats" ]; then
		mkdir "$SVC_DIR/iostats"
	fi
	ERRLOG_SVC="$ERRLOG-${STORAGE_NAME}"
	OUTLOG_SVC="$INPUTDIR/logs/output.log-${STORAGE_NAME}"
        export ERRLOG_SVC OUTLOG_SVC
		
	$BINDIR/svc_stor_load.sh 1>>$OUTLOG_SVC 2>>$ERRLOG_SVC &
	if [ ! $? -eq 0 ]; then
		echo "`date` : An error occured in svc_stor_load.sh, check $ERRLOG_SVC and output of $0" >> $ERRLOG_SVC
		echo "`date` : An error occured in svc_stor_load.sh, check $ERRLOG_SVC and output of $0" 
	fi
        # Remove old files
        find $SVC_DIR -name '*svcconf*data' -amin +30 -exec rm {} \;
        find $SVC_DIR -name '*svcconf*out' -atime +1 -exec rm {} \;
        find $SVC_DIR -name '*svcperf*out' -atime +7 -exec rm {} \;
    	find $SVC_DIR -name 'N*_stats_*' -amin +120 -exec rm {} \;
done

# wait for all jobs to let see the ouput
for job in `jobs -p`
do
    echo "Waiting for $job"
    wait $job
done

