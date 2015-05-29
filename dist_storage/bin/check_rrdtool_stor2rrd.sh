#!/bin/ksh
# usage:
# cd /home/stor2rrd/stor2rrd
# ksh ./check_rrdtool_stor2rrd.sh
#  --> then it prints wrong source files on the stderr (screen) ...
#  --> printed files are corrupted, remove them manually
#
# ERROR: fetching cdp from rra at /stor2rrd/bin/stor2rrd.pl line 2329
# ERROR: reading the cookie off /opt/stor2rrd/data/Carolina-9117-MMD-SN1064D47/unxhmcpa001/fairlane_new_test.rrm faild at
# ERROR: short read while reading header rrd->stat_head
#
# You can schedulle it regulary once a day from crontab, it will send an email to $EMAIL addr
# 0 0 * * * cd /home/stor2rrd/stor2rrd; ./bin/check_rrdtool_stor2rrd.sh > /var/tmp/check_rrdtool.out 2>&1


if [ -f etc/.magic ]; then 
  . etc/.magic
  # set that in etc/.magic to avoid overwriting after the upgrade
  #EMAIL="me@me.com"
  #EMAIL_ON=1
  # export 
else
  EMAIL_ON=0
fi

#Run that from /home/stor2rrd/stor2rrd

addr=data
error=0
tmp="/tmp/check_rrdtool.sh-$$"
count=0


for RRDFILE_space in `find $addr -name "*.rr[a-z]" |sed 's/ /===space===/g'`
do
  RRDFILE=`echo "$RRDFILE_space"|sed 's/===space===/ /g'`
  (( count = count + 1 ))
  #echo "$RRDFILE"
  last=`rrdtool last "$RRDFILE"`
  if [ $? -gt 0 ]; then
    (( error = error + 1 ))
    echo "  last:  --> $RRDFILE"| tee -a $tmp
    ls -l $RRDFILE| tee -a $tmp
    continue
  fi
  rrdtool fetch "$RRDFILE" AVERAGE -s $last-60 -e $last-60 >/dev/null
  if [ $? -gt 0 ]; then
    (( error = error + 1 ))
    echo "  fetch: --> $RRDFILE"| tee -a $tmp
    ls -l $RRDFILE| tee -a $tmp
  fi
  # RRDTool error: ERROR: fetching cdp from rra (sometime can be corrupted only old records when "fetch" and "last" are ok
  rr_1st_var=`rrdtool info "$RRDFILE"  |egrep "^ds"|head -1|sed -e 's/ds\[//' -e 's/\].*//'`
  rrdtool graph mygraph.png -a PNG --start 900000000  --end=now  DEF:x="$RRDFILE":$rr_1st_var:AVERAGE PRINT:x:AVERAGE:%2.1lf >/dev/null
  if [ $? -gt 0 ]; then
    (( error = error + 1 ))
    echo "  print: --> $RRDFILE"| tee -a $tmp
    ls -l "$RRDFILE"| tee -a $tmp
    continue
  fi
done

echo "Checked files: $count"| tee -a $tmp


if [ $error -eq 0 ]; then
  echo ""
  echo "No corrupted files have been found"
  echo ""
else
  echo ""
  echo "Printed files are corrupted, remove them manually"
  echo ""
  if [ $EMAIL_ON -eq 1 ]; then
    cat $tmp| mailx -s "LPAR2RRD corrupted files" $EMAIL
  fi
fi

rm -f $tmp

