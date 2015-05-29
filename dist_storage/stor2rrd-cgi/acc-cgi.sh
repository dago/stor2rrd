#!/bin/sh

# Load LPAR2RRD environment
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

umask 000
ERRLOG="/var/tmp/stor2rrd-realt-error.log"
export ERRLOG

TMPDIR_STOR="$INPUTDIR/tmp"
export TMPDIR_STOR

# workaround for fonconfig (.fonts.conf) on AIX and RRDTool 1.3+
export HOME=$TMPDIR_STOR/home

# Load "magic" setup
if [ -f $INPUTDIR/etc/.magic ]; then
  . $INPUTDIR/etc/.magic
fi

exec $PERL $BINDIR/acc-cgi.pl 2>>$ERRLOG

