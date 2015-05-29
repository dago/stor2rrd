#!/bin/ksh
# version 0.2
#
# so stdout redirection, it is already done in the calling script

$PERL -w $BINDIR/xivperf.pl $STORAGE_NAME 
RET=$?
if [ ! $RET -eq 0 ]; then
	echo "xiv_stor_load.sh: Command xivperf.pl ends with return code $RET" 2>>$ERRLOG_XIV
	exit 1
fi

$PERL -w $BINDIR/data_load.pl $STORAGE_NAME 
RET=$?
if [ ! $RET -eq 0 ]; then
	echo "xiv_stor_load.sh: Command data_load.pl ends with return code $RET" 2>>$ERRLOG_XIV
	exit 1
fi

