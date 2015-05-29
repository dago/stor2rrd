#!/bin/sh
# 
# Load STOR2RRD environment
CGID=`dirname $0`
if [ "$CGID" = "." ]; then
  CGID=`pwd`
fi
INPUTDIR_NEW=`dirname $CGID`
. $INPUTDIR_NEW/etc/stor2rrd.cfg
INPUTDIR=$INPUTDIR_NEW
export INPUTDIR 

BINDIR="$INPUTDIR/bin"
export BINDIR

TMPDIR="$INPUTDIR/tmp"
export TMPDIR

umask 000
ERRLOG="/var/tmp/stor2rrd-realt-error.log"
export ERRLOG

#echo "$QUERY_STRING" >> /tmp/qrstpr


echo "Content-type: text/html"
echo ""
echo "<html><body><p>"
echo "<iframe src='/stor2rrd-cgi/acc-cgi.sh?$QUERY_STRING' style='position: absolute; width: 99%; height: 90%; border: 0'>"
echo "</iframe>"
echo "</body></html>"
