#
# used only for DHL accounting purposes
# etc/.magic : ACCOUTING=1 
#

#use strict;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);
use Date::Parse;

my $DEBUG = $ENV{DEBUG};
my $inputdir = $ENV{INPUTDIR};
my $rrdtool = $ENV{RRDTOOL};
#my $refer = $ENV{HTTP_REFERER};
my $errlog = $ENV{ERRLOG};
#use Env qw(QUERY_STRING);

# only for development debuging purposes
my $acc_dev = 0;
if (defined $ENV{ACCOUTING_DEBUG}) {
  $acc_dev = $ENV{ACCOUTING_DEBUG};
}

open(OUT, ">> $errlog")  if $DEBUG == 2 ;


print_html();

close (OUT) if $DEBUG == 2;
exit (0);

sub print_lpar {

  # count just number of storages at first
  $size = 0;
  foreach my $storage (<$inputdir/data/*>) {
    chomp($storage);
    if ( ! -d $storage ) {
      next;
    }
    $size++;
  }

  print "<SELECT NAME=SERVERS MULTIPLE SIZE=$size style=\"font-family:Courier New\">\n";

  my $first = 1;
  foreach my $storage_all (<$inputdir/data/*>) {
    chomp($storage_all);
    if ( ! -d $storage_all ) {
      next;
    }
    my $storage = basename($storage_all);

    if ( $storage !~ m/svc/ && $acc_dev == 0 ) {
      next; # include only SVC
    }

    if ( $first == 1 ) {
      print "<OPTION VALUE=\"$storage\"  SELECTED >$storage</OPTION>\n";
      $first++;
    }
    else {
      print "<OPTION VALUE=\"$storage\">$storage</OPTION>\n";
    }
  }


  return 0;
}



sub print_html {

my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my $date = strftime "%d-%m-%Y", localtime(time() - 86400);
(my $day, my $month, my $year) = split (/-/,$date);
$month--;

# print HTML header
print "Content-type: text/html\n\n";

print "<CENTER>
  <h3>Accounting based on allocated space in weekly average</h3>
  <FORM METHOD=\"GET\" ACTION=\"/stor2rrd-cgi/acc-wrapper.sh\">
  <TABLE BORDER=0 CELLSPACING=5 SUMMARY=\"Accounting\"> <TR> <TD>
  <SELECT NAME=\"week\">\n";

 print_week();
 print "</SELECT></td><td>";

 print "<SELECT NAME=\"month\">\n";
 my $j = 1;
 for (my $i=0; $i < 12; $i++, $j++) {
   if ( $i == $month ) {
     print "<OPTION VALUE=\"$j\" SELECTED >$abbr[$i]\n";
   } else {
     print "<OPTION VALUE=\"$j\" >$abbr[$i]\n";
   }
 }
 print "</SELECT> </td><td>\n";

 print "<SELECT NAME=\"year\">\n";
 for (my $i=2013; $i < $year; $i++) {
   print "<OPTION VALUE=\"$i\" >$i\n";
 }
 print "<OPTION VALUE=\"$year\" SELECTED > $year";
 print "</SELECT></td></tr></table>\n";
 print " <TABLE BORDER=0 CELLSPACING=5 SUMMARY=\"Accounting\">\n";
 #print "<tr><td>&nbsp;&nbsp;&nbsp;weekly/monthly report&nbsp;&nbsp;&nbsp;</td><td>&nbsp;&nbsp;&nbsp;Tier&nbsp;&nbsp;&nbsp;</td><td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td></tr>\n";
 print "<tr><td ><input type=\"radio\" name=\"time\" value=\"week\">Week\n";
 print "    <td ><input type=\"radio\" name=\"tier\" value=\"1\" checked>Premium</td>\n";
 #print "    <td ><input type=\"radio\" name=\"step\" value=\"3600\" checked>1 hour</td></tr>\n";
 print "<tr><td ><input type=\"radio\" name=\"time\" value=\"month\" checked>Month</td>\n";
 print "    <td ><input type=\"radio\" name=\"tier\" value=\"2\">Standard</td>\n";
 #print "    <td ><input type=\"radio\" name=\"step\" value=\"300\">5 min</td></tr>\n";


 print "<tr><td colspan=\"3\" align=\"center\"><B>List of servers</b></td></tr>\n";
 print "<tr><td colspan=\"3\" align=\"center\">";

 print_lpar();

 print "
        </SELECT>
          <BR><BR>
          <INPUT TYPE=\"SUBMIT\" style=\"font-weight: bold\" NAME=\"Report\" VALUE=\"Generate Report\" ALT=\"Generate Report\">
       </FORM>
       </TD>
      </TR>
      <tr><td colspan=\"3\"  align=\"left\"><br><font size=-1>You can select more rows (servers) via holding Ctrl/Shift.<br></td></tr>
   </TABLE>
</center>
</font>
</BODY> </HTML>
"
}

sub print_week {

  my $year = strftime "%Y", localtime(time());
  my $stime = str2time("1/1/4year");
  my $etime = $stime;
  $year++;
  my $utime_end = str2time("1/1/$year");
  my $weekNumber = "";
  my $weekday = strftime("%u", localtime($stime));
  while ( $weekday != 1 ) {
    # find first Monday
    $stime -= 86400;
    $weekday = strftime("%u", localtime($stime));
  }

  my $act_time = time();
  
  
  while ( $stime < $utime_end ) {
    # list all weeks
    (my $sec,my $min,my $hour,my $sday,my $smonth,my $year,my $wday,my $yday,my $isdst) = localtime($stime);
    $etime = $stime + 604800;
    (my $sec,my $min,my $hour,my $eday,my $emonth,my $year,my $wday,my $yday,my $isdst) = localtime($etime);
    $smonth += 1;
    $emonth += 1;
    $weekNumber = strftime("%U", localtime($etime));
    # --> it start with Monday as first day (%U starts with Sunday, %V starts with Monday)
    #print "$weekNumber : $sday/$smonth - $eday/$emonth\n";
    $sday = sprintf("%02.0f",$sday);
    $eday = sprintf("%02.0f",$eday);
    $smon = sprintf("%02.0f",$smon);
    $emon = sprintf("%02.0f",$emon);
    if ( $act_time > $stime && $act_time < $etime ) {
      print "<OPTION VALUE=\"$stime $etime\" SELECTED >$weekNumber : $sday/$smonth - $eday/$emonth\n";
    }
    else {
      print "<OPTION VALUE=\"$stime $etime\" >$weekNumber : $sday/$smonth - $eday/$emonth\n";
    }
    $stime = $etime;
  }
}

sub basename {
  my $full = shift;
  my $out = "";

  # basename without direct function
  my @base = split(/\//,$full);
  foreach my $m (@base) {
    $out = $m;
  }

  return $out;
}

