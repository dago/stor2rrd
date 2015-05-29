#!/bin/ksh
# stderr and stdour redirection is done already when this script is called

#$PERL -w $BINDIR/svcconfig.pl 1>>$OUTLOG_SVC 2>>$ERRLOG_SVC
#if [ ! $? -eq 0 ]; then
#	echo "svc_stor_load.sh: Command svcconfig.pl ends with return code $?" 2>>$ERRLOG_SVC
#	exit 1
#fi

PROC=`ps -ef | egrep 'ds5perf.pl *'$STORAGE_NAME' *$' | grep -v grep | wc -l`
if [ $PROC -lt 2 ]; then
	$PERL -w $BINDIR/ds5perf.pl $STORAGE_NAME  
fi

$PERL -w $BINDIR/data_load.pl $STORAGE_NAME 
if [ ! $? -eq 0 ]; then
	echo "ds5_stor_load.sh: Command data_load.pl ends with return code $?" 2>>$ERRLOG
	exit 1
fi

