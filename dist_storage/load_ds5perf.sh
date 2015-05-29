#!/bin/sh
# version 0.13

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

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
fi
if [ x"$STORAGE_USER" = "x" ]; then
  echo "STORAGE_USER does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$DS8_CLIDIR" = "x" ]; then
  echo "DS8_CLIDIR does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$STORAGE_CFG" = "x" ]; then
  echo "STORAGE_CFG does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$PERL" = "x" ]; then
  echo "PERL does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$SAMPLE_RATE" = "x" ]; then
  echo "SAMPLE_RATE does not seem to be set up, correct it in stor2rrd.cfg"
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


# just an workaround for a problem when tmp/*.ds8perf.tmp has zero size (ERROR:Magic number checking ...)
for zero_file in $INPUTDIR/tmp/*ds8perf.tmp
do
  if [ -f "$zero_file" -a ! -s "$zero_file" ]; then
    #ls -l "$zero_file"
    rm "$zero_file"
    echo "removing zero  : $zero_file"
    echo "removing zero  : $zero_file" >> $ERRLOG
  fi
done

date=`date`
SAMPLE_RATE_DEF=$SAMPLE_RATE
for line in `cat $STORAGE_CFG|sed 's/#.*$//'|egrep ":DS5K:"|egrep -v "^#"`
do
  # Only DS5K load ....
  # Name:DS8K:DEVID:HMC1:HMC2:
  STORAGE_NAME=`echo $line | awk 'BEGIN{FS=":"}{print $1}'`
  STORAGE_TYPE=`echo $line | awk 'BEGIN{FS=":"}{print $2}'`
  DS5K_USER=`echo $line | awk 'BEGIN{FS=":"}{print $3}'`
  DS5K_PW=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`

  export STORAGE_NAME STORAGE_TYPE DS5K_USER DS5K_PW 

  SAMPLE_RATE=$SAMPLE_RATE_DEF
  echo "$STORAGE_NAME: $date : starting"

  if [ ! "$SAMPLE_RATE_min"x = "x" -a -f "$INPUTDIR/tmp/$STORAGE_NAME-run" ]; then
    #(( SAMPLE_RATE = SAMPLE_RATE_min * 60 ))
    SAMPLE_RATE=`echo "$SAMPLE_RATE_min*60"|bc`
    # check how offten it should run as per timestamp and skip it if it too early
    time_last_tmp=`$PERL -e '$inp=shift;$st_name=shift;$v = (stat("$inp/tmp/$st_name-run"))[9]; print "$v\n";' $INPUTDIR $STORAGE_NAME`
    time_act=`date "+%s"`
    d=`date`
    #(( time_last = SAMPLE_RATE + time_last - 50 )) # put 50 sec to make sure
    grace_time=50
    time_last=`expr $SAMPLE_RATE + $time_last_tmp - $grace_time`
    echo "$STORAGE_NAME: $d : $time_last -gt $time_act  -- $SAMPLE_RATE -- $INPUTDIR/tmp/$STORAGE_NAME-run"
    if [ $time_last -gt $time_act ]; then
      echo "Skipping now   : $STORAGE_NAME: not process this time due to sample_rate : $SAMPLE_RATE"
      continue
    else
      # go further for the data load
      touch "$INPUTDIR/tmp/$STORAGE_NAME-run"
    fi
  else 
    touch "$INPUTDIR/tmp/$STORAGE_NAME-run"
  fi
  echo "Continue now   : $STORAGE_NAME: sample_rate : $SAMPLE_RATE"
  export SAMPLE_RATE

  if [ ! -f "$DS5_CLIDIR/SMclient" ]; then
    echo "SMclient binnary does not exist here : $DS5_CLIDIR/SMclient"
    echo "If it is installed then configure proper path in etc/stor2rrd.cfg, param DS5_CLIDIR"
    continue
  fi
  
  DATEEXT=`date "+%Y%m%d"`
  DATETIMEEXT=`date "+%Y%m%d-%H%M"`
  ERRLOG_DS5="$ERRLOG-${STORAGE_NAME}"
  OUTLOG="$INPUTDIR/logs/output.log-${STORAGE_NAME}"
  export ERRLOG_DS5 OUTLOG
  export DS5_OUTFILE="$INPUTDIR/data/$STORAGE_NAME/$STORAGE_NAME.perf.$DATETIMEEXT"
  if [ ! -d "$INPUTDIR/data/$STORAGE_NAME" ]; then
    mkdir "$INPUTDIR/data/$STORAGE_NAME"
  fi

  $BINDIR/ds5_stor_load.sh $STORAGE_NAME 2>>$ERRLOG_DS5 1>>$OUTLOG &
  if [ ! $? -eq 0 ]; then
    echo "`date` : An error occured in ds5perf.pl, check $ERRLOG and output of $0" >> $ERRLOG 
    echo "`date` : An error occured in ds5perf.pl, check $ERRLOG and output of $0" 
  fi
done

# wait for all jobs to let see the ouput
for job in `jobs -p`
do
    echo "Waiting for $job"
    wait $job
done
