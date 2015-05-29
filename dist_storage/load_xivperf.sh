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
DEBUG=1

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

SAMPLE_RATE_ORG=$SAMPLE_RATE
for line in `cat $STORAGE_CFG|sed 's/#.*$//'|egrep ":XIV:"|egrep -v "^#"`
do
	SAMPLE_RATE=$SAMPLE_RATE_ORG
	# Storage name alias:XIV:_xiv_ip_:_password_:
	STORAGE_NAME=`echo $line | awk 'BEGIN{FS=":"}{print $1}'`
	STORAGE_TYPE=`echo $line | awk 'BEGIN{FS=":"}{print $2}'`
	
	export STORAGE_NAME STORAGE_TYPE

	# XiV Storage Family
	XIV_IP=`echo $line | awk 'BEGIN{FS=":"}{print $3}'`
	#XIV_USER=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
	XIV_USER=$STORAGE_USER
	XIV_PASSWD=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
	XIV_DIR="$INPUTDIR/data/$STORAGE_NAME"
	SAMPLE_RATE=`echo $line | awk 'BEGIN{FS=":"}{print $7}'`
        if [ "$SAMPLE_RATE"x = "x" ]; then
	  $SAMPLE_RATE=$SAMPLE_RATE_ORG
        fi
        # sample rate is not used byt xivperf.pl as it reads counters, not delta values, it is used only for timeout purposes

	export XIV_IP XIV_USER XIV_PASSWD XIV_DIR XIV_INTERVAL SAMPLE_RATE

	if [ "$XIV_IP"x = "x" ]; then
    		echo "Some problem with storage cfg. Storage IP must be set. Check $STORAGE_CFG line: $line"
    		continue
	fi

	if [ ! -d "$XIV_DIR" ]; then
		mkdir "$XIV_DIR"
	fi
	if [ ! -d "$XIV_DIR/tmp" ]; then
		mkdir "$XIV_DIR/tmp"
	fi
	ERRLOG_XIV="$ERRLOG-${STORAGE_NAME}"
	OUTLOG_XIV="$INPUTDIR/logs/output.log-${STORAGE_NAME}"
        export ERRLOG_XIV OUTLOG_XIV
		
	$BINDIR/xiv_stor_load.sh 1>>$OUTLOG_XIV 2>>$ERRLOG_XIV &
	if [ ! $? -eq 0 ]; then
		echo "`date` : An error occured in XIV_stor_load.sh, check $ERRLOG_XIV and output of $0" >> $ERRLOG_XIV
		echo "`date` : An error occured in XIV_stor_load.sh, check $ERRLOG_XIV and output of $0" 
	fi
        # Remove old files
        find $XIV_DIR -name '*xivconf*data' -amin +60 -exec rm {} \;
        find $XIV_DIR -name '*xivconf*out' -atime +2 -exec rm {} \;
        find $XIV_DIR -name '*xivperf*out' -atime +30 -exec rm {} \;
done

# wait for all jobs to let see the ouput
for job in `jobs -p`
do
    echo "Waiting for $job"
    wait $job
done

