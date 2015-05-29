#
# used only for DHL accounting purposes
# etc/.magic : KEEP_VIRTUAL=1 --> it has to be setup after initial installation!!!
#

use strict;
use Date::Parse;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);

#$|++; # auto flust --> must be here othervise there is not in sysnc result file (is created after that)
$| = 1;

my $bindir = $ENV{BINDIR};
my $DEBUG = $ENV{DEBUG};
my $errlog = $ENV{ERRLOG};
my $xport = $ENV{EXPORT_TO_CSV};
my $inputdir = $ENV{INPUTDIR};
my $tmpdir = "$inputdir/tmp";
if (defined $ENV{TMPDIR_STOR}) {
  $tmpdir = $ENV{TMPDIR_STOR};
}
my $result_file = "stor2rrd-virtual-result-$$.txt";
my $result_file_full = "/var/tmp/".$result_file;
my $act_time = localtime();

open(OUT, ">> $errlog")  if $DEBUG == 2 ;
print OUT "$QUERY_STRING" if $DEBUG == 2 ;

# print HTML header
print "Content-type: text/html\n\n";
my $time = gmtime();


#`echo "$QUERY_STRING" >> /tmp/ee8`;
 
(my $week, my $month, my $year, my $time_range, my $tier, my @server_list) = split(/&/,$QUERY_STRING);

$week  =~ s/week=//;
$month  =~ s/month=//;
$year  =~ s/year=//;
$time_range  =~ s/time=//;
$tier  =~ s/tier=//;



if ( $time_range =~ m/week/ ) {
  # one week graph
  print "<tr><td><center><h3>Allocated space for $month/$year</center></h3></td></tr>";
  print "<tr><td><img src=\"/stor2rrd-cgi/acc-work.sh?tier=$tier&week=$week&month=$month&year=$year&result=$result_file&weekno=0&print=1&xport=0&smonth=0&emonth=0&@server_list\"></td></tr>";
}
else {
  # one month graph(s)
  my @keep_html = ""; # for CSV links
  my $keep_html_indx = 0;
  my $num_of_weeks = 0;
  my $month_sum_stime = 0;
  my $month_sum_etime = 0;
  for ( my $week_no = 1; $week_no < 7; $week_no++ ) {
    my $stime = find_week($year,$month,$week_no);
    if ($month_sum_stime ==  0 ) {
      $month_sum_stime = $stime;
    }
    if ( $stime > 0 ) {
      #  error ("virtual-cpu-acc-cgi.pl: stime is 0");
      #  err_html ("virtual-cpu-acc-cgi.pl: stime is 0");
      my $etime = $stime + 604800;
      $month_sum_etime = $etime;
      $week=$stime." ".$etime;
      print "<tr><td><img src=\"/stor2rrd-cgi/acc-work.sh?tier=$tier&week=$week&month=$month&year=$year&result=$result_file&weekno=$week_no&print=0&xport=0&smonth=0&emonth=0&@server_list\" style=\"visibility:hidden\"></td></tr>\n";
      $keep_html[$keep_html_indx] = "/stor2rrd-cgi/acc-work.sh?tier=$tier&week=$week&month=$month&year=$year&result=$result_file&weekno=$week_no&print=1&xport=1&smonth=0&emonth=0&@server_list";
      $keep_html_indx++;
      $num_of_weeks++;
    }
  }
  print "</table>\n";
  my $month_string = print_month($month);
  print "<center><h3>$month_string $year</h3></center>\n";
  $keep_html[$keep_html_indx] = "/stor2rrd-cgi/acc-work.sh?tier=$tier&week=$week&month=$month&year=$year&result=$result_file&weekno=0&print=1&xport=1&smonth=$month_sum_stime&emonth=$month_sum_etime&@server_list";
  print_summary ($result_file_full,$num_of_weeks,\@keep_html);

  print "<table border=\"0\">";
  $num_of_weeks = 0;
  for ( my $week_no = 1; $week_no < 7; $week_no++ ) {
    my $stime = find_week($year,$month,$week_no);
    if ( $stime > 0 ) {
      #  error ("virtual-cpu-acc-cgi.pl: stime is 0");
      #  err_html ("virtual-cpu-acc-cgi.pl: stime is 0");
      my $etime = $stime + 604800;
      $week=$stime." ".$etime;
      print "<tr><td><img src=\"/stor2rrd-cgi/acc-work.sh?tier=$tier&week=$week&month=$month&year=$year&result=$result_file&weekno=$week_no&print=1&xport=0&smonth=0&emonth=0&@server_list\"></td>";
      $num_of_weeks++;
    }
  }
}

close(OUT)  if $DEBUG == 2;

if ( -f $result_file_full ) {
  #clean out result file
  unlink ("$result_file_full") || die "Cannot rm $result_file_full : $!";
  # --PH not now due to debugging
}

exit (0);

sub err_html {
  my $text = shift;

  print "<strong> ERROR: $text</strong>\n";
  print "</body></html>";
  exit (1);
}
 
# error handling
sub error
{
  my $text = shift;

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

sub isdigit
{
  my $digit = shift;
  my $text = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  if (length($digit_work) == 0) {
    # is a number
    return 1;
  }
  return 0;
}

sub find_week {
  my $year = shift;
  my $month = shift;
  my $week_no = shift;
  my $month_next = $month;
  my $year_next = $year;

  my $stime = str2time("$month/1/$year");
  my $etime = $stime;

  if ( $month < 12 ) {
    $month_next++;
  }
  else {
    $month_next = 1;
    $year_next++;
  }
  my $utime_end = str2time("$month_next/1/$year_next");


  my $weekNumber = "";
  my $weekday = strftime("%u", localtime($stime));
  while ( $weekday != 1 ) {
    # find first Monday
    $stime -= 86400;
    $weekday = strftime("%u", localtime($stime));
  }

  my $act_time = time();

  my $number_weeks = 1;
  while ( $stime < $utime_end ) {
    # list all weeks
    if ( $number_weeks ==  $week_no ) {
      return $stime;
    }
    $stime = $stime + 604800;
    $number_weeks++;
  }

  return 0;
}

sub print_summary {
  my ($result_file_full, $num_of_weeks, $keep_html_tmp) = @_;
  my @keep_html = @{$keep_html_tmp};
  my $num_of_weeks_act = 0;
  my $MAX_WAIT_TIME = 180;
  my $indx = 0;


  while ( $indx < $MAX_WAIT_TIME ) {
    # wait until all processes (weeks) write down total result into $result_file_full
    sleep (1);
    $num_of_weeks_act = 0;
    $indx++;
    if ( ! -f $result_file_full ) {
      next;    
    }

    open(FHR, "< $result_file_full") || error ("Can't open $result_file_full : $!");
    my @res_all = <FHR>;
    close (FHR);
    foreach my $line (@res_all) {
      $num_of_weeks_act++;
    }
    if ( $num_of_weeks == $num_of_weeks_act ) {
      last; # all graphs wrote down total ... conrtinue
    }
  }

  
  if ( $indx == $MAX_WAIT_TIME ) {
    my $result_all = "<br>";
    my $result_all_text = "";
    if ( -f $result_file_full ) {
      open(FHR, "< $result_file_full") || die "$act_time: Can't open $result_file_full : $!";
      my @res_all = <FHR>;
      close (FHR);
      foreach my $line (@res_all) {
        $result_all .= $line."<br>";
        $result_all_text .= $line;
      }
    }
    error ("acc-cgi.pl: $result_file_full does not exist or timed out ($MAX_WAIT_TIME) or too less row : $num_of_weeks : $num_of_weeks_act : $result_all_text");
    err_html ("acc-cgi.pl: $result_file_full does not exist or timed out ($MAX_WAIT_TIME) or too less row : $num_of_weeks : $num_of_weeks_act : $result_all");
  }
  else {
    if ( ! -f $result_file_full ) {
      error ("acc-cgi.pl: $result_file_full does not exist");
      err_html ("acc-cgi.pl: $result_file_full does not exist");
      return 1;
    }

    open(FHR, "< $result_file_full") || die "$act_time: Can't open $result_file_full : $!";
    my @res_all = <FHR>;
    close (FHR);
    @res_all = sort { lc $a cmp lc $b } @res_all;
  
    print "\n<center><table border=\"1\"><tr><th>week no</th><th>Days in a week</th><th>Avrg allocation</th><th>CSV</th></tr>";
    my $week_tot = 0;
    my $days_tot = 0;
    my $keep_html_indx = 0;
    my $virtual_tot = 0;
    foreach my $line (@res_all) {
      chomp ($line);
      (my $wekkno, my $days, my $virtual) = split (/:/,$line);
      print "<tr><td align=\"center\">$wekkno</td><td align=\"center\">$days</td><td align=\"center\">$virtual</td><td><a href=\"$keep_html[$keep_html_indx]\">data</a></tr>\n";
      $week_tot++;
      $keep_html_indx++;
      $days_tot += $days;
      $virtual_tot += $days * $virtual;
    }
    if ( $days_tot == 0 || $virtual_tot == 0 ) {
      $virtual_tot = 0;
    }
    else {
      $virtual_tot = sprintf("%.1f", $virtual_tot/$days_tot);
    }
    print "<tr><td align=\"center\"><b>Total</b></td><td align=\"center\"><b>$days_tot</b></td><td align=\"center\"><b>$virtual_tot</b></td><td><a href=\"$keep_html[$keep_html_indx]\">data</a></tr>\n";
    print "</table></center><br>";
  }

  if ( -f $result_file_full ) {
    unlink ("$result_file_full") || die "Cannot rm $result_file_full : $!";
  }

  return 1;
}

sub print_month {
  my $month_number = shift;
  my $month = "";

  if ( $month_number == 1 ) {
    $month = "January";
  }
  if ( $month_number == 2 ) {
    $month = "February";
  }
  if ( $month_number == 3 ) {
    $month = "March";
  }
  if ( $month_number == 4 ) {
    $month = "April";
  }
  if ( $month_number == 5 ) {
    $month = "May";
  }
  if ( $month_number == 6 ) {
    $month = "June";
  }
  if ( $month_number == 7 ) {
    $month = "July";
  }
  if ( $month_number == 8 ) {
    $month = "August";
  }
  if ( $month_number == 9 ) {
    $month = "September";
  }
  if ( $month_number == 10 ) {
    $month = "October";
  }
  if ( $month_number == 11 ) {
    $month = "November";
  }
  if ( $month_number == 12 ) {
    $month = "December";
  }

  return $month;
}
