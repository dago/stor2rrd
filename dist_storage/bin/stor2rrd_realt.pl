
#open(OUT, ">> $errlog")  if $DEBUG == 2 ;

use strict;
use Date::Parse;

my $DEBUG = $ENV{DEBUG};
my $errlog = $ENV{ERRLOG};
my $xport = $ENV{EXPORT_TO_CSV};
my $webdir = $ENV{WEBDIR};

open(OUT, ">> $errlog")  if $DEBUG == 2 ;

# print HTML header
my $time = gmtime();
print "Content-type: text/html\n";
print "Expires: $time\n\n";
print "<HTML><HEAD>
<META HTTP-EQUIV=\"pragma\" CONTENT=\"no-cache\">
<META HTTP-EQUIV=\"Expires\" CONTENT=\"NOW\">
<META HTTP-EQUIV=\"last modified\" CONTENT=\"NOW\">
<STYLE TYPE=\"text/css\">
<!--
.header, .header TD, .header TH
{
background-color:#D3D2F3;
}
-->
</STYLE>
<style>
<!--
a {text-decoration: none}
-->
</style>
<SCRIPT TYPE=\"text/javascript\">
<!--
function popup(mylink, windowname)
{
if (! window.focus)return true;
var href;
if (typeof(mylink) == 'string')
   href=mylink;
else
   href=mylink.href;
window.open(href, windowname, 'resizable=yes,width=1329,height=670,scrollbars=yes');
return false;
}
//-->
</SCRIPT>
</HEAD>
<BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\" >";
my $time = gmtime();


# get QUERY_STRING
use Env qw(QUERY_STRING);
$QUERY_STRING .= ":.";
print OUT "-- $QUERY_STRING\n" if $DEBUG == 2 ;

( my $host,my $type, my $name, my $item, my $st_type) = split(/&/,$QUERY_STRING);

# no URL decode here, as it goes immediately into URL again

$host =~ s/host=//;
$type =~ s/type=//;
$name =~ s/name=//;
$item =~ s/item=//;
$st_type =~ s/storage=//;


##print "<center><b>$name</b>";
print "&nbsp;&nbsp;<font size=-1><A HREF=\"/stor2rrd-cgi/stor2rrd-realt.sh?host=$host&type=$type&name=$name&item=sum&storage=$st_type&none=none\">Refresh</A></font>\n";

print "<table align=\"center\" summary=\"Graphs\">\n";

print "<tr><td valign=\"top\"><a href=\"/stor2rrd-cgi/detail-graph.sh?host=$host&type=$type&name=$name&item=$item&time=d&detail=1&none=none\" onClick=\"return popup(this, \'detail\')\"><img border=\"0\" src=\"/stor2rrd-cgi/detail-graph.sh?host=$host&type=$type&name=$name&item=$item&time=d&detail=2&none=none\"></a></td>";
print "</tr>\n";
print "</table>";
print "<br><font size=-1>STOR2RRD refreshs graphs usualy once an hour<br>";
print "Refresh link can display data which is meanwhile loaded from the storage (every 5 minutes)<br>\n";
if ( $type =~ m/VOLUME/ ) {
  print "For volume stats might happen then a data sudden peak of any volume is displayed as part of \"rest of vols total\"<br>";
  print "This is always resolved during next schedulled STOR2RRD run</font>";
}

exit (0);
