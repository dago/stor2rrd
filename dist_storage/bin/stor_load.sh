#!/bin/ksh
# only DS8K script!!!!
# stderr is redirected in above calling of that script ...

echo "$PERL -w $BINDIR/ds8perf.pl $STORAGE_NAME "
$PERL -w $BINDIR/ds8perf.pl $STORAGE_NAME 
$PERL -w $BINDIR/data_load.pl $STORAGE_NAME 

