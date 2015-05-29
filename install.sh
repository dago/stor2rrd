#!/bin/sh
#
# STOR2RRD install script wrapper
# usage : ./install.sh
#
#
LOG="/var/tmp/stor2rrd-install.log-$$"

./scripts/$0 $1 2>&1| tee $LOG

PRODUCT_HOME=`cat "$HOME/.stor2rrd_home"`
if [ -f "$HOME/.stor2rrd_home" -a -d "$PRODUCT_HOME" ]; then
  mv $LOG $PRODUCT_HOME/logs 2>/dev/null
fi
