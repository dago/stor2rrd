#!/bin/ksh
# only SWIZ script
# stderr and stdour rediretcion already in calling script

$PERL -w $BINDIR/svcconfig.pl 
RET=$?
if [ ! $RET -eq 0 ]; then
	echo "svc_stor_load.sh: Command svcconfig.pl ends with return code $RET" 2>>$ERRLOG_SVC
	exit 1
fi

PROC=`ps -ef | egrep 'svcperf.pl *'$STORAGE_NAME' *$' | grep -v grep | wc -l`
if [ $PROC -eq 0 ]; then
	$PERL -w $BINDIR/svcperf.pl $STORAGE_NAME 1>>$OUTLOG_SVC 2>>$ERRLOG_SVC &
fi

$PERL -w $BINDIR/data_load.pl $STORAGE_NAME 
RET=$?
if [ ! $RET -eq 0 ]; then
	echo "svc_stor_load.sh: Command data_load.pl ends with return code $RET" 2>>$ERRLOG_SVC
	exit 1
fi

