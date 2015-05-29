#!/bin/sh
#
#
# Output redirection to logs/test-healthcheck.log

# Load STOR2RRD environment
CGID=`dirname $0`
if [ "$CGID" = "." ]; then
  CGID=`pwd`
fi
INPUTDIR_NEW=`dirname $CGID`
. $INPUTDIR_NEW/etc/stor2rrd.cfg
INPUTDIR=$INPUTDIR_NEW
export INPUTDIR

LOGDIR="$INPUTDIR/logs"
export LOGDIR

BINDIR="$INPUTDIR/bin"
export BINDIR

umask 000
ERRLOG="/var/tmp/stor2rrd-realt-error.log"
export ERRLOG

rm -f $LOGDIR/stor-test-healthcheck.log

exec $BINDIR/stor-test-healthcheck.sh 2>>$ERRLOG | tee $LOGDIR/stor-test-healthcheck.log
