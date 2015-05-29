#!/bin/ksh

PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/opt/freeware/bin
export PATH

LANG=C
export LANG

# it is necessary as files need to be readable also for WEB server user
umask 022

# Load STOR2RRD configuration
. `dirname $0`/etc/stor2rrd.cfg

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
fi
TMPDIR_STOR=$INPUTDIR/tmp

# Load "magic" setup
if [ -f `dirname $0`/etc/.magic ]; then
  . `dirname $0`/etc/.magic
fi


# ./load.sh html --> it runs only web creation code
HTML=0
if [ ! "$1"x = "x" -a "$1" = "html" ]; then
  HTML=1
  touch $TMPDIR_STOR/$version-run # force to run html part
fi

prg_name=`basename $0`
if [ $HTML -eq 0 -a -f "$INPUTDIR/tmp/$prg_name.pid" ]; then
  PID=`cat "$INPUTDIR/tmp/$prg_name.pid"|sed 's/ //g'`
  if [ ! "$PID"x = "x" ]; then
    ps -ef|grep "$prg_name"|awk '{print $2}'|egrep "^$PID$" >/dev/null
    if [ $? -eq 0 ]; then
      echo "There is already running another copy of $prg_name, exiting ..."
      d=`date`
      echo "$d: There is already running another copy of $prg_name, exiting ..." >> $ERRLOG
      exit 1
    fi
  fi
  # ok, there is no other copy of $prg_name
  echo "$$" > "$INPUTDIR/tmp/$prg_name.pid"
else
  echo "$$" > "$INPUTDIR/tmp/$prg_name.pid"
fi


HOSTNAME=`uname -n`
export HOSTNAME

ID=`( lsattr -El sys0 -a systemid 2>/dev/null || hostid ) | sed 's/^.*,//' | awk '{print $1}'`
UN=`uname -a`
UNAME=`echo "$UN $ID"`
export UNAME

PERL5LIB=$PERL5LIB:$BINDIR
export PERL5LIB

UPGRADE=0
if [ ! -f $TMPDIR_STOR/$version ]; then
  if [ $DEBUG -eq 1 ]; then 
    echo ""
    echo "Looks like there has been an upgrade to $version, run time wil be longer this time"
    echo ""
  fi
  UPGRADE=1
fi
export UPGRADE  


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


if [ -f $ERRLOG ]; then
  ERR_START=`wc -l $ERRLOG |awk '{print $1}'`
else
  ERR_START=0
fi 

# Checks
if [ ! -f "$RRDTOOL" ]; then
  echo "Set correct path to RRDTOOL binary in stor2rrd.cfg, it does not exist here: $RRDTOOL"
  exit 0
fi 
ok=0
for i in `echo "$PERL5LIB"|sed 's/:/ /g'` 
do
  if [ -f "$i/RRDp.pm" ]; then
    ok=1
  fi
done
if [ $ok -eq 0 ]; then
  echo "Set correct path to RRDp.pm Perl module in stor2rrd.cfg, it does not exist here : $PERL5LIB"
  exit 0
fi
if [ ! -f "$PERL" ]; then
  echo "Set correct path to Perl binary in stor2rrd.cfg, it does not exist here: $PERL"
  exit 0
fi 
if [ x"$RRDHEIGHT" = "x" ]; then
  echo "RRDHEIGHT does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$RRDWIDTH" = "x" ]; then
  echo "RRDWIDTH does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$SAMPLE_RATE" = "x" ]; then
  echo "SAMPLE_RATE does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$STORAGE_CFG" = "x" ]; then
  echo "STORAGE_CFG does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ x"$DEBUG" = "x" ]; then
  echo "DEBUG does not seem to be set up, correct it in stor2rrd.cfg"
  exit 0
fi
if [ ! -d "$WEBDIR" ]; then
  echo "Set correct path to WEBDIR in stor2rrd.cfg, it does not exist here: $WEBDIR"
  exit 0
fi 


#
# Load data from the storage
#

STEP_ORG=$STEP
VOLUME_DATA_MAX_ORG=$VOLUME_DATA_MAX
VOLUME_IO_MAX_ORG=$VOLUME_IO_MAX

if [ $HTML -eq 0 ]; then # avoid that if "./load.sh html" is issued
 for line in `cat $STORAGE_CFG|egrep -v "#"`
 do
  # set it to original values
  VOLUME_DATA_MAX=$VOLUME_DATA_MAX_ORG
  VOLUME_IO_MAX=$VOLUME_IO_MAX_ORG
  STEP=$STEP_ORG

  # Name:DS8K:DEVID:HMC1:HMC2:
  export STORAGE=`echo $line | awk 'BEGIN{FS=":"}{print $1}'`
  export STORAGE_NAME=$STORAGE  # compadability for load_ds...
  export STORAGE_TYPE=`echo $line | awk 'BEGIN{FS=":"}{print $2}'`
  if [ "$STORAGE_TYPE" = "SWIZ" ]; then
    VOLUME_DATA_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $5}'`
    VOLUME_IO_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $6}'`
    SAMPLE_RATE_min=`echo $line | awk 'BEGIN{FS=":"}{print $7}'`
  fi  
  if [ "$STORAGE_TYPE" = "XIV" ]; then
    VOLUME_DATA_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $5}'`
    VOLUME_IO_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $6}'`
    SAMPLE_RATE_min=`echo $line | awk 'BEGIN{FS=":"}{print $7}'`
  fi  
  if [ "$STORAGE_TYPE" = "DS8K" ]; then
    # DS8K
    export DS8_DEVID=`echo $line | awk 'BEGIN{FS=":"}{print $3}'`
    VOLUME_DATA_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $6}'`
    VOLUME_IO_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $7}'`
    SAMPLE_RATE_min=`echo $line | awk 'BEGIN{FS=":"}{print $8}'`
    if [ "$DS8_DEVID"x = "x" ]; then
      echo "Some problem with storage cfg, check $STORAGE_CFG line: $line"
      continue
    fi
  fi
  if [ "$STORAGE_TYPE" = "DS5K" ]; then
    VOLUME_DATA_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $5}'`
    VOLUME_IO_MAX_tmp=`echo $line | awk 'BEGIN{FS=":"}{print $6}'`
    SAMPLE_RATE_min=`echo $line | awk 'BEGIN{FS=":"}{print $7}'`
  fi  

  if [ ! "$VOLUME_DATA_MAX_tmp"x = "x" ]; then
    VOLUME_DATA_MAX=$VOLUME_DATA_MAX_tmp
  fi
  if [ ! "$VOLUME_IO_MAX_tmp"x = "x" ]; then
    VOLUME_IO_MAX=$VOLUME_IO_MAX_tmp
  fi

  if [ ! "$SAMPLE_RATE_min"x = "x" ]; then
    # set specific sample rate if it is defined in storage-list.cfg
    (( STEP = SAMPLE_RATE_min * 60 ))
  fi
  export STEP VOLUME_IO_MAX VOLUME_DATA_MAX

  if [ "$STORAGE_TYPE" = "DS8K" -o "$STORAGE_TYPE" = "SWIZ" -o "$STORAGE_TYPE" = "XIV" -o "$STORAGE_TYPE" = "DS5K" ]; then
    DATE=`date`
    echo "start time stor: $DATE"

    #
    # main storage loop
    #
    $PERL -w $BINDIR/storage.pl 2>>$ERRLOG 

    ret=$?
    if [ ! $ret -eq 0 ]; then
      DATE=`date`
      echo "$DATE: an error in $PERL -w $BINDIR/storage.pl: $ret" >> $ERRLOG
    fi
  else
    echo "Unsupported storage type: $STORAGE_TYPE ($line)"
  fi
 done
fi

#
#
# Install/Update web frontend
#

DATE=`date`
echo "start time html: $DATE"
$BINDIR/install-st.sh 
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-st.sh, return code: $ret" >> $ERRLOG
fi
DATE=`date`
echo "end time       : $DATE"

#
# Error handling
# 

if [ -f $ERRLOG ]; then
  ERR_END=`wc -l $ERRLOG |awk '{print $1}'`
else
  ERR_END=0
fi
ERR_TOT=`expr $ERR_END - $ERR_START`
if [ $ERR_TOT -gt 0 ]; then
  echo "An error occured, check $ERRLOG and output of load.sh"
  echo ""
  echo "$ tail -$ERR_TOT $ERRLOG"
  echo ""
  tail -$ERR_TOT $ERRLOG
  #date >> $ERRLOG
fi

if [ -d "$INPUTDIR/logs" ]; then
  if [ -f "$INPUTDIR/load.out" ]; then
    cp -p "$INPUTDIR/load.out" "$INPUTDIR/logs"
  fi
fi
date
exit 0
