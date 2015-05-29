#!/bin/ksh
#
# CGI-BIN testing script, healthcheck
#
# Output redirection to logs/test-healthcheck.log

# Load STOR2RRD environment and stor2rrd.cfg
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

APACHE_ERROR_LOG=`find /var -name error_log 2>/dev/null`

APACHE_ACCESS_LOG=`find /var -name access_log 2>/dev/null`

WEBDIR=`cat $INPUTDIR/etc/stor2rrd.cfg | grep WEBDIR= | cut -c 10-`

umask 000
ERRLOG="/var/tmp/stor2rrd-realt-error.log"
export ERRLOG

echo "Content-type: text/html"
echo ""
echo "<HTML>"
echo "<body><h2>It is working!</h2>"
echo "<b>You should see STOR2RRD environment here:</b><pre>"
set|egrep -i "HMC|DOCUMENT_ROOT|HEA|COD|HWINFO|LPM|PERL|PICTURE|RRD|stor2rrd|BINDIR|EXPORT_TO_CSV|LDR_CNTRL|MANAGED_SYSTEMS|MAX_ENT|SAMPLE_RATE|SYS_CHANGE|TOPTEN|DEBUG|version="|egrep -v "^_="
echo "</pre><br><br><b>Here is the OS environment:</b><pre>"
set|egrep -iv "HMC|DOCUMENT_ROOT|HEA|COD|HWINFO|LPM|PERL|PICTURE|RRD|stor2rrd|BINDIR|EXPORT_TO_CSV|LDR_CNTRL|MANAGED_SYSTEMS|MAX_ENT|SAMPLE_RATE|SYS_CHANGE|TOPTEN|DEBUG|version="|egrep -v "^_="

echo "</pre><br><br><b>Here is stor2rrd.cfg:</b><pre>"
cat "$INPUTDIR/etc/stor2rrd.cfg"
# stor2rrd.cfg preview

echo "</pre><br><br><b>Here is logs dir:</b><pre>"
ls -ltrL "$INPUTDIR/logs"
# logs preview

echo "</pre><br><br><b>Here is stor2rrd-realt-error.log:</b><pre>"
egrep "ERROR:" $ERRLOG | grep -v GPRINT | tail -5
TEST_LOG=`egrep "ERROR:" $ERRLOG | grep -v GPRINT | tail -5 | wc -l`
if [ "$TEST_LOG" = "0" ]; then
  echo "stor2rrd-realt-error.log is OK"
fi
# /var/tmp/stor2rrd-realt-error.log preview

echo "</pre><br><br><b>Here is error.log:</b><pre>"
egrep "ERROR:" $INPUTDIR/logs/error.log | grep -v GPRINT | tail -5
TEST_LOG=`egrep "ERROR:" $INPUTDIR/logs/error.log | grep -v GPRINT | tail -5 | wc -l`
if [ "$TEST_LOG" = "0" ]; then
  echo "error.log is OK"
fi
# error.log preview

echo "</pre><br><br><b>Here is error-cgi.log:</b><pre>"
egrep "ERROR:" "$INPUTDIR/logs/error-cgi.log" | grep -v GPRINT | tail -5
TEST_LOG=`egrep "ERROR:" "$INPUTDIR/logs/error-cgi.log" | grep -v GPRINT | tail -5 | wc -l`
if [ "$TEST_LOG" = "0" ]; then
  echo "error-cgi.log is OK"
fi
# error-cgi.log

echo "</pre><br><br><b>Here is apache error.log:</b><pre>"
egrep "lpar2rrd|stor2rrd" $APACHE_ERROR_LOG | tail -5
TEST_LOG=`egrep "lpar2rrd|stor2rrd" $APACHE_ERROR_LOG | tail -5 | wc -l`
if [ "$TEST_LOG" = "0" ]; then
  echo "apache error.log is OK"
fi

# apache error_log

echo "</pre><br><br><b>Here is apache access log:</b><pre>"
egrep "lpar2rrd|stor2rrd" $APACHE_ACCESS_LOG | tail -5
TEST_LOG=`egrep "lpar2rrd|stor2rrd" $APACHE_ACCESS_LOG | tail -5 | wc -l`
if [ "$TEST_LOG" = "0" ]; then
  echo "apache access log is OK"
fi
# apache access_log

echo "</pre><br><br><b>Errors in apache access log:</b><pre>"
egrep "\" 4[0-9][0-9]" $APACHE_ACCESS_LOG | tail -5
TEST_LOG=`egrep "\" 4[0-9][0-9]" $APACHE_ACCESS_LOG | tail -5 | wc -l`
if [ "$TEST_LOG" = "0" ]; then
  echo "apache access log is OK"
fi
#apache access_log errors

echo "</pre><br><br><b>genjson test:</b><pre>"
$PERL $BINDIR/genjson.pl

echo "</pre><br><br><b>Here is bin dir:</b><pre>"
ls -l $BINDIR

echo "</pre><br><br><b>Stor2rrd version:</b><pre>"
ls -l $TMPDIR/[0-9].*

echo "</pre><br><br><b>Users:</b><pre>"
install_user=`ls -l $BINDIR/storage.pl|awk '{print $3}'`
running_user=`id |awk -F\( '{print $2}'|awk -F\) '{print $1}'`
echo "install user: $install_user"
echo "running user: $running_user"

echo "</pre><br><br><b>Files not owned by install user: $install_user</b><pre>"

echo "INPUTDIR:"
find $INPUTDIR \! -user $install_user -exec ls -ld {} \;

echo "WEBDIR:"
find $WEBDIR \! -user $install_user -exec ls -ld {} \;

echo "</pre></body></html>"
