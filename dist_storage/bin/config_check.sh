#!/bin/ksh
# version 0.13

# Parameters:
# Param1 - Storage name

#set -x

PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/opt/freeware/bin
export PATH

# it is necessary as files need to be readable also for WEB server user
umask 022

if [ ! -d "etc" ]; then
  if [ -d "../etc" ]; then
    cd ..
  else
    echo "Problem with actual directory, assure you are in LPAR2RRD home"
    echo "Then run : sh ./bin/config_check.sh"
    exit
  fi
fi

LHOME=`pwd|sed -e 's/bin//' -e 's/\/\//\//' -e 's/\/$//'` # it must be here
pwd=`pwd`


# Load STOR2RRD configuration
CFG="$pwd/etc/stor2rrd.cfg"
. $CFG
DEBUG=0

PERL5LIB=$PERL5LIB:$BINDIR
export PERL5LIB

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

count=0
date=`date`
SAMPLE_RATE_DEF=$SAMPLE_RATE
for line in `cat $STORAGE_CFG|sed 's/#.*$//'|egrep ":DS8K:"|egrep -v "^#"`
do
  # Only DS8K load ....
  # Name:DS8K:DEVID:HMC1:HMC2:
  STORAGE_NAME=`echo $line | awk 'BEGIN{FS=":"}{print $1}'`
  STORAGE_TYPE=`echo $line | awk 'BEGIN{FS=":"}{print $2}'`
  DS8_DEVID=`echo $line | awk 'BEGIN{FS=":"}{print $3}'`
  DS8_HMC1=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
  DS8_HMC2=`echo $line | awk 'BEGIN{FS=":"}{print $5}'`
  SAMPLE_RATE_min=`echo $line | awk 'BEGIN{FS=":"}{print $8}'`

  SAMPLE_RATE=$SAMPLE_RATE_DEF

  if [ "$DS8_HMC2"x = "x" ]; then
    echo "$STORAGE_NAME: Some problem with storage cfg, check $STORAGE_CFG line: $line"
    continue
  fi

  echo "========================="
  echo "STORAGE: $STORAGE_NAME: $STORAGE_TYPE "
  echo "========================="

  if [ ! -f "$DS8_CLIDIR/dscli" ]; then
    echo "DSCLI binnary does not exist here : $DS8_CLIDIR/dscli"
    echo "If it is installed then configure proper path in etc/stor2rrd.cfg, param DS8_CLIDIR"
    continue
  fi
  if [ "$DS8_HMC2"x = "x" ]; then
    echo "  $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -user $STORAGE_USER whoami"
    $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -user $STORAGE_USER whoami
    echo "  $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -user $STORAGE_USER ver -l"
    $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -user $STORAGE_USER ver -l
  else
    echo "  $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -hmc2 $DS8_HMC2 -user $STORAGE_USER whoami"
    $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -hmc2 $DS8_HMC2 -user $STORAGE_USER whoami
    echo "  $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -hmc2 $DS8_HMC2 -user $STORAGE_USER ver -l"
    $DS8_CLIDIR/dscli -hmc1 $DS8_HMC1 -hmc2 $DS8_HMC2 -user $STORAGE_USER ver -l
  fi
  echo ""
  (( count = count + 1 ))
done
if [ $count -gt 0 ]; then
  echo ""
  echo "$STORAGE_USER user on all IBM DS8K must belong to \"monitor\" role at least"
  echo ""
fi

count=0
for line in `cat $STORAGE_CFG|sed 's/#.*$//'|egrep ":SWIZ:"|egrep -v "^#"`
do
        # Name:SWIZ:DEVID:HMC1:HMC2:
        STORAGE_NAME=`echo $line | awk 'BEGIN{FS=":"}{print $1}'`
        STORAGE_TYPE=`echo $line | awk 'BEGIN{FS=":"}{print $2}'`

        # SVC/Storwize Storage Family
        SVC_IP=`echo $line | awk 'BEGIN{FS=":"}{print $3}'`
        #SVC_USER=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
        SVC_USER=$STORAGE_USER
        SVC_KEY=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
        SVC_DIR="$INPUTDIR/data/$STORAGE_NAME"
        SVC_INTERVAL=`expr $SAMPLE_RATE / 60`

        if [ "$SVC_IP"x = "x" ]; then
                echo "$STORAGE_NAME: Some problem with storage cfg. Storage IP must be set. Check $STORAGE_CFG line: $line"
                continue
        fi

        echo "========================="
        echo "STORAGE: $STORAGE_NAME: $STORAGE_TYPE"
        echo "========================="

        if [ "$SVC_KEY"x = "x" ]; then
          echo "  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no $STORAGE_USER@$SVC_IP  \"lscurrentuser\""
          ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no $STORAGE_USER@$SVC_IP  "lscurrentuser"
        else
          echo "  ssh -o ConnectTimeout=15 -i $SVC_KEY  $STORAGE_USER@$SVC_IP  \"lscurrentuser\""
          ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no -i $SVC_KEY  $STORAGE_USER@$SVC_IP  "lscurrentuser"
        fi
        echo ""
        (( count = count + 1 ))
done
if [ $count -gt 0 ]; then
  echo ""
  echo "$STORAGE_USER user on all IBM SVC/Storwize must belong to \"admin\" or \"Administrator\" UserRole"
  echo ""
fi


count=0
for line in `cat $STORAGE_CFG|sed 's/#.*$//'|egrep ":XIV:"|egrep -v "^#"`
do
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
        XIV_INTERVAL=$SAMPLE_RATE
        export XIV_IP XIV_USER XIV_PASSWD XIV_DIR XIV_INTERVAL

        if [ "$XIV_IP"x = "x" ]; then
                echo "Some problem with storage cfg. Storage IP must be set. Check $STORAGE_CFG line: $line"
                continue
        fi

        ERRLOG_XIV="$ERRLOG-${STORAGE_NAME}"
        OUTLOG_XIV="$INPUTDIR/logs/${STORAGE_NAME}.output_xiv.log"
        export ERRLOG_XIV OUTLOG_XIV

        WBEMCLI="/usr/bin/wbemcli"
        if [ ! -f $WBEMCLI ]; then
          WBEMCLI="/opt/freeware/bin/wbemcli"
          if [ ! -f $WBEMCLI ]; then
            WBEMCLI="/usr/local/bin/wbemcli"
            if [ ! -f $WBEMCLI ]; then
              echo "XIV Error: could not found wbemcli binnary, searched /usr/bin/wbemcli, /opt/freeware/bin/wbemcli, /usr/local/bin/wbemcli"
              break
            fi
          fi
        fi
       
        echo "========================="
        echo "STORAGE: $STORAGE_NAME: $STORAGE_TYPE"
        echo "========================="

        echo "  $WBEMCLI -noverify -nl ei https://$XIV_USER:$XIV_PASSWD@$XIV_IP:5989/root/ibm:IBMTSDS_StorageSystem"
	$WBEMCLI -noverify -nl ei https://$XIV_USER:$XIV_PASSWD@$XIV_IP:5989/root/ibm:IBMTSDS_StorageSystem
        echo ""          
        (( count = count + 1 ))
done
if [ $count -gt 0 ]; then
  echo ""
  echo "$STORAGE_USER user on all IBM XIV category \"readonly\""
  echo ""
fi



for line in `cat $STORAGE_CFG|sed 's/#.*$//'|egrep ":DS5K:"|egrep -v "^#"`
do
        # Storage name alias:XIV:_xiv_ip_:_password_:
        STORAGE_NAME=`echo $line | awk 'BEGIN{FS=":"}{print $1}'`
        STORAGE_TYPE=`echo $line | awk 'BEGIN{FS=":"}{print $2}'`
        DS5K_USER=`echo $line | awk 'BEGIN{FS=":"}{print $3}'`
        DS5K_PW=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`

        export STORAGE_NAME STORAGE_TYPE

        DS5_PASSWD=`echo $line | awk 'BEGIN{FS=":"}{print $4}'`
        DS5_DIR="$INPUTDIR/data/$STORAGE_NAME"
        DS5_INTERVAL=$SAMPLE_RATE
        export DS5_IP DS5_USER DS5_PASSWD DS5_DIR DS5_INTERVAL

        ERRLOG_DS5="$ERRLOG-${STORAGE_NAME}"
        OUTLOG_DS5="$INPUTDIR/logs/${STORAGE_NAME}.output_ds5.log"
        export ERRLOG_DS5 OUTLOG_DS5

        if [ ! -f $DS5_CLIDIR/SMcli ]; then
          echo "DS5K Error: could not found SMcli binnary : $DS5_CLIDIR/SMcli, Install SMcli or update DS5_CLIDIR in etc/stor2rrd.cfg"
          break
        fi
       
        echo "========================="
        echo "STORAGE: $STORAGE_NAME: $STORAGE_TYPE"
        echo "========================="

        if [ "$DS5K_PW"x = "x" ]; then
          # no user/pw is set
          echo "  $DS5_CLIDIR/SMcli -n $STORAGE_NAME -e -c \"show storageSubsystem summary;\""
	  if [ `$DS5_CLIDIR/SMcli -n $STORAGE_NAME -e -c "show storageSubsystem summary;"| grep "SMcli completed successfully"|wc -l` -gt 0 ]; then
            echo "  connection ok"          
          else 
            echo "  connection failed!!"          
          fi
        else
          # no user/pw is set
          echo "  $DS5_CLIDIR/SMcli -n $STORAGE_NAME -R $DS5K_USER -p $DS5K_PW -e -c \"show storageSubsystem summary;\""
	  if [ `$DS5_CLIDIR/SMcli -n $STORAGE_NAME -R $DS5K_USER -p $DS5K_PW -e -c "show storageSubsystem summary;"| grep "SMcli completed successfully"|wc -l` -gt 0 ]; then
            echo "  connection ok"          
          else 
            echo "  connection failed!!"          
          fi
        fi
        echo ""          
done
echo ""
#echo "$STORAGE_USER user on all IBM XIV category \"\""
echo ""



