#!/usr/bin/perl

### Modules
use strict;
use warnings;
use Time::Local;

### Options
my $storage_name;
my $storage_type;
my $sample_rate;
my $out_perf_file;
my $DS5_CLIDIR;
my $SMcli;
my $inputdir;
my @storage_items;
my @logicalDrives;
my $cmd_performanceStats;
my $cmd_logicalDrives;
my $user_name;
my $user_pw;
my $version;
my $tmp_file;

if ( defined $ENV{STORAGE_NAME} ) {
  $storage_name = $ENV{STORAGE_NAME};
}
else {
  error( "ds5perf.pl: DS5k storage name alias is required! $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
my $tmp_dir    = "/home/lpar2rrd/stor2rrd/tmp/";
my $output_dir = "/home/lpar2rrd/stor2rrd/data/$storage_name/";
if   ( defined $ENV{SAMPLE_RATE} ) { $sample_rate = $ENV{SAMPLE_RATE} }
if   ( defined $ENV{DS5_CLIDIR} )  { $DS5_CLIDIR  = $ENV{DS5_CLIDIR}, $SMcli = "$DS5_CLIDIR/SMcli"; }
else                               { $SMcli       = "SMcli"; }
if ( defined $ENV{DS5K_USER} ) { $user_name = $ENV{DS5K_USER} }
if ( defined $ENV{DS5K_PW} )   { $user_pw   = $ENV{DS5K_PW} }
if ( defined $ENV{INPUTDIR} )  { $inputdir  = $ENV{INPUTDIR}; $output_dir = "$inputdir/data/$storage_name/"; $tmp_dir = "$inputdir/tmp/"; }
if ( defined $ENV{TMPDIR} )    { $tmp_dir   = $ENV{TMPDIR} }
my $timeout = $sample_rate * 3;    #alarm timeout

### SMcli commands
my $cmd_performanceStats_to_errorlog;
my $cmd_logicalDrives_to_errorlog;
eval {
  # Set alarm
  my $act_time = localtime();
  local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
  alarm($timeout);

  # CMDs
  if ( $user_name && $user_pw ) {
    $cmd_performanceStats             = `$SMcli -n $storage_name -e -R $user_name -p $user_pw -c "set session performanceMonitorInterval=$sample_rate performanceMonitorIterations=1 ; show allLogicalDrives performanceStats;" 2>/dev/null`;
    $cmd_logicalDrives                = `$SMcli -n $storage_name -e -R $user_name -p $user_pw -c "show logicalDrives;" 2>/dev/null`;
    $cmd_performanceStats_to_errorlog = "$SMcli -n $storage_name -e -R $user_name -p <XXXXX> -c \"set session performanceMonitorInterval=$sample_rate performanceMonitorIterations=1 ; show allLogicalDrives performanceStats;\" 2>/dev/null";
    $cmd_logicalDrives_to_errorlog    = "$SMcli -n $storage_name -e -R $user_name -p <XXXXX> -c \"show logicalDrives;\" 2>/dev/null";
  }
  else {
    $cmd_performanceStats             = `$SMcli -n $storage_name -e -c "set session performanceMonitorInterval=$sample_rate performanceMonitorIterations=1 ; show allLogicalDrives performanceStats;" 2>/dev/null`;
    $cmd_logicalDrives                = `$SMcli -n $storage_name -e -c "show logicalDrives;" 2>/dev/null`;
    $cmd_performanceStats_to_errorlog = "$SMcli -n $storage_name -e -c \"set session performanceMonitorInterval=$sample_rate performanceMonitorIterations=1 ; show allLogicalDrives performanceStats;\" 2>/dev/null";
    $cmd_logicalDrives_to_errorlog    = "$SMcli -n $storage_name -e -c \"show logicalDrives;\" 2>/dev/null";
  }

  @storage_items = split( "\n", $cmd_performanceStats );
  @logicalDrives = split( "\n", $cmd_logicalDrives );

  # end of alarm
  alarm(0);
};

if ($@) {
  if ( $@ =~ /died in SIG ALRM/ ) {
    my $act_time = localtime();
    error("command timed out after : $timeout seconds");
    exit(0);
  }
}

if ( "@storage_items" !~ /SMcli completed successfully/ ) {
  $cmd_performanceStats =~ s/\n//g;
  $cmd_performanceStats = substr $cmd_performanceStats, -512;
  if ( "@storage_items" =~ /error code 12/ ) {
    error("SMcli command failed: $cmd_performanceStats_to_errorlog");
    error( "$cmd_performanceStats : $!" . __FILE__ . ":" . __LINE__ );
    error("Most probably permission issue, STOR2RRD cannot run SMcli command. Problem description and fix: http://www.stor2rrd.com/install.htm#SMclierror");
    exit;
  }
  else {
    error("SMcli command failed: $cmd_performanceStats_to_errorlog");
    error( "$cmd_performanceStats : $!" . __FILE__ . ":" . __LINE__ );
    exit;
  }
}
if ( "@logicalDrives" !~ /SMcli completed successfully/ ) {
  $cmd_logicalDrives =~ s/\n//g;
  $cmd_logicalDrives = substr $cmd_logicalDrives, -512;
  if ( "@logicalDrives" =~ /error code 12/ ) {
    error("SMcli command failed: $cmd_logicalDrives_to_errorlog");
    error( "$cmd_logicalDrives : $!" . __FILE__ . ":" . __LINE__ );
    error("Most probably permission issue, STOR2RRD cannot run SMcli command. Problem description and fix: http://www.stor2rrd.com/install.htm#SMclierror");
    exit;
  }
  else {
    error("SMcli command failed: $cmd_logicalDrives_to_errorlog");
    error( "$cmd_logicalDrives : $!" . __FILE__ . ":" . __LINE__ );
    exit;
  }
}
if ( "@storage_items" =~ /\"Objects\"/ ) {
  $storage_type = "new";
  $version      = "v2";
}
if ( "@storage_items" =~ /\"Storage Subsystems/ ) {
  $storage_type = "old";
  $version      = "v1";
}

### Search ID, POOL name, Controller, Capacity
my @logicalDrives_lines = grep {/Logical Drive name:|Logical Drive ID:|Associated disk pool:|Associated array:|Current owner:|Capacity:/} @logicalDrives;
my @volume_id;
my @pools;
my $volume_name = "";
my $volume_id   = "";
my $volume_pool = "";
my $controller  = "";
my $capacity    = "";
foreach my $line (@logicalDrives_lines) {
  chomp $line;
  if ( $line =~ "Logical Drive name:" ) {
    $line =~ s/Logical Drive name://g;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    $volume_name = $line;
  }
  if ( $line =~ "Logical Drive ID:" ) {
    $line =~ s/Logical Drive ID://g;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    $line =~ s/://g;
    $volume_id = $line;
  }
  if ( $line =~ "Capacity:" ) {
    $line =~ s/Capacity://g;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    $line =~ s/,//g;
    $capacity = $line;
  }
  if ( $line =~ "Associated disk pool:" || $line =~ "Associated array:" ) {
    $line =~ s/Associated disk pool://g;
    $line =~ s/Associated array://g;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    $volume_pool = $line;
    push( @pools, "$volume_pool\n" );
  }
  if ( $line =~ "Current owner:" ) {
    $line =~ s/Current owner://g;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    $controller = $line;
    push( @volume_id, "$volume_name,$volume_id,$volume_pool,$controller,$capacity\n" );
  }
}

### search start date/time and interval
my ($time_line) = grep {/Performance Monitor Statistics/} @storage_items;
$time_line =~ s/\"//g;
my ( undef, $time, $interval ) = split( " - ", $time_line );
$time =~ s/Date\/Time://g;
$time =~ s/^\s+//g;
$time =~ s/\s+$//g;
$interval =~ s/Polling interval in seconds://g;
$interval =~ s/^\s+//g;
$interval =~ s/\s+$//g;
my ( $date,  $time_s, $part_of_the_day ) = split( " ", $time );
my ( $month, $day,    $year )            = split( "/", $date );
my ( $hour,  $min,    $sec )             = split( ":", $time_s );
my $year_s = $year + 2000;
my $hour_s = $hour;

if ( $part_of_the_day =~ /PM/ && $hour !~ /12/ ) {
  $hour_s = $hour + 12;
}
if ( $part_of_the_day =~ /AM/ && $hour =~ /12/ ) {
  $hour_s = $hour - 12;
}
my $s_timestamp = timelocal( $sec, $min, $hour_s, $day, $month - 1, $year_s );
my $s_date = sprintf( "%4d:%02d:%02d",  $year_s, $month, $day );
my $s_time = sprintf( "%02d:%02d:%02d", $hour_s, $min,   $sec );
my $e_timestamp = $s_timestamp + $interval;
my ( $sec_e, $min_e, $hour_e, $day_e, $month_e, $year_e, $wday_e, $yday_e, $isdst_e ) = localtime($e_timestamp);
my $e_date = sprintf( "%4d:%02d:%02d",  $year_e + 1900, $month_e + 1, $day_e );
my $e_time = sprintf( "%02d:%02d:%02d", $hour_e,        $min_e,       $sec_e );
my $start_time          = "$s_date" . "T" . "$s_time";
my $end_time            = $e_date . "T" . $e_time;
my $time_to_output_name = sprintf( "%4d%02d%02d_%02d%02d", $year_s, $month, $day, $hour_s, $min );

### output file
$out_perf_file = $output_dir . $storage_name . "_ds5perf_" . $time_to_output_name . ".out.tmp";
open( PERFOUT, ">$out_perf_file" ) || die "Couldn't open file $out_perf_file";

### header
print PERFOUT "\nVolume Level Statistics\n";
print PERFOUT "  Interval Start:   $start_time\n";
print PERFOUT "  Interval End:     $end_time\n";
print PERFOUT "  Interval Length:  $interval seconds\n";
print PERFOUT "---------------------\n";
print PERFOUT "Volume ID,Time,Interval (s),Volume Name,Pool Name,Controler,Total IOs,Total IO Rate (IO/s),Total Data Rate (KB/s),Read Hits,Write Hits,Cache read %,SSD Read Cache Hit %,IO Latency,Cache hits,Capacity (MB)\n";

### data parse
if ( $storage_type =~ /new/ ) {
  foreach my $line (@storage_items) {
    chomp $line;
    $line =~ s/\"//g;
    if ( $line =~ /^Logical Drive/ ) {
      $line =~ s/^Logical Drive //g;
      my ( $volume_name, $total_IOs, $read_pct, $read_hits, $write_hits, $ssd_cache_hit_pct, $curr_MBsec, undef, $curr_IOsec, undef, undef, $avg_IOsec, undef, $avg_MBsec, undef, undef, undef, $IO_latency ) = split( ",", $line );
      my $avg_KBsec = $avg_MBsec * 1024;
      my ($id_line) = grep {/$volume_name/} @volume_id;
      chomp $id_line;
      my ( undef, $id, $pool, $vol_controller, $cap ) = split( ",", $id_line );
      my $capacity;
      my ( $cap_num, $cap_size ) = split( " ", $cap );
      if ( $cap_size =~ /MB/ ) { $capacity = $cap_num; }
      if ( $cap_size =~ /GB/ ) { $capacity = $cap_num * 1024; }
      if ( $cap_size =~ /TB/ ) { $capacity = $cap_num * 1024 * 1024; }
      if ( $cap_size =~ /PB/ ) { $capacity = $cap_num * 1024 * 1024 * 1024; }
      $vol_controller =~ s/Controller in slot//g;
      $vol_controller =~ s/^\s+//g;
      $vol_controller =~ s/\s+$//g;
      $volume_name =~ s/:/===colon===/g;
      $volume_name =~ s/\s/===space===/g;
      $pool =~ s/:/===colon===/g;
      $pool =~ s/\s/===space===/g;
      print PERFOUT "$id,$start_time,$interval,$volume_name,$pool,$vol_controller,$total_IOs,$avg_IOsec,$avg_KBsec,$read_hits,$write_hits,$read_pct,$ssd_cache_hit_pct,$IO_latency,,$capacity\n";
    }
  }
}

if ( $storage_type =~ /old/ ) {
  foreach my $line (@storage_items) {
    chomp $line;
    $line =~ s/\"//g;
    if ( $line =~ /^Logical Drive/ ) {
      $line =~ s/^Logical Drive //g;
      my ( $volume_name, $total_IOs, $read_pct, $cache_hit_pct, $curr_KBsec, $max_KBsec, $curr_IOsec, $max_IOsec ) = split( ",", $line );
      my ($id_line) = grep {/$volume_name/} @volume_id;
      chomp $id_line;
      my ( undef, $id, $pool, $vol_controller, $cap ) = split( ",", $id_line );
      my $capacity;
      my ( $cap_num, $cap_size ) = split( " ", $cap );
      if ( $cap_size =~ /MB/ ) { $capacity = $cap_num; }
      if ( $cap_size =~ /GB/ ) { $capacity = $cap_num * 1024; }
      if ( $cap_size =~ /TB/ ) { $capacity = $cap_num * 1024 * 1024; }
      if ( $cap_size =~ /PB/ ) { $capacity = $cap_num * 1024 * 1024 * 1024; }
      $vol_controller =~ s/Controller in slot//g;
      $vol_controller =~ s/^\s+//g;
      $vol_controller =~ s/\s+$//g;
      $volume_name =~ s/:/===colon===/g;
      $volume_name =~ s/\s/===space===/g;
      $pool =~ s/:/===colon===/g;
      $pool =~ s/\s/===space===/g;
      print PERFOUT "$id,$start_time,$interval,$volume_name,$pool,$vol_controller,$total_IOs,$curr_IOsec,$curr_KBsec,,,$cache_hit_pct,,,$read_pct,$capacity\n";
    }
  }
}

close(PERFOUT);

### CONFIGURATION

# conditions for creating a configuration file
my $config_html            = $output_dir . "config.html";
my $time_for_configuration = "";
my $act_time               = time();
my $time_diff              = 0;
$tmp_file = $tmp_dir . $storage_name . "conf_time";
if ( !-e $tmp_file ) {
  open( CONFTIME, ">$tmp_file" ) || die "Couldn't open file $tmp_file";
  print CONFTIME "$act_time";
  close(CONFTIME);
  $time_for_configuration = "OK";
}
else {
  open( CONFTIME, "<$tmp_file" ) || die "Couldn't open file $tmp_file";
  my @conf_array = <CONFTIME>;
  close(CONFTIME);
  $time_diff = $act_time - $conf_array[0];
}

if ( $time_diff > 3600 ) { $time_for_configuration = "OK"; }
if ( !-e $config_html )  { $time_for_configuration = "OK"; }

# creating configuration file
if ( $time_for_configuration =~ /OK/ ) {
  open( CONFTIME, ">$tmp_file" ) || die "Couldn't open file $tmp_file";
  print CONFTIME "$act_time";
  close(CONFTIME);

  my $out_conf_file;
  $out_conf_file = $output_dir . $storage_name . "_ds5conf_" . $time_to_output_name . ".out.tmp";
  open( CONFOUT, ">$out_conf_file" ) || die "Couldn't open file $out_conf_file";

  # Configuration data main header
  print CONFOUT "Configuration Data\n";
  print CONFOUT "------------------\n";
  print CONFOUT "DS5K type : $version\n";

  # SMcli command
  my $cmd_summary;
  my $cmd_summary_to_errorlog;
  my @show_summary;

  if ( $storage_type =~ /new/ ) {
    eval {
      # Set alarm
      my $act_time = localtime();
      local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
      alarm($timeout);

      # CMDs
      if ( $user_name && $user_pw ) {
        $cmd_summary             = `$SMcli -n $storage_name -e -R $user_name -p $user_pw -c "show storagesubsystem summary;" 2>/dev/null`;
        $cmd_summary_to_errorlog = "$SMcli -n $storage_name -e -R $user_name -p <XXXXX> -c \"show storagesubsystem summary;\" 2>/dev/null";
      }
      else {
        $cmd_summary             = `$SMcli -n $storage_name -e -c "show storagesubsystem summary;" 2>/dev/null`;
        $cmd_summary_to_errorlog = "$SMcli -n $storage_name -e -c \"show storagesubsystem summary;\" 2>/dev/null";
      }
      @show_summary = split( "\n", $cmd_summary );

      # end of alarm
      alarm(0);
    };
    if ($@) {
      if ( $@ =~ /died in SIG ALRM/ ) {
        my $act_time = localtime();
        error("command timed out after : $timeout seconds");
        exit(0);
      }
    }
    if ( "@show_summary" !~ /SMcli completed successfully/ ) {
      $cmd_summary =~ s/\n//g;
      $cmd_summary = substr $cmd_summary, -512;
      if ( "@show_summary" =~ /error code 12/ ) {
        error("SMcli command failed: $cmd_summary_to_errorlog");
        error( "$cmd_summary : $!" . __FILE__ . ":" . __LINE__ );
        error("Most probably permission issue, STOR2RRD cannot run SMcli command. Problem description and fix: http://www.stor2rrd.com/install.htm#SMclierror");
        exit;
      }
      else {
        error("SMcli command failed: $cmd_summary_to_errorlog");
        error( "$cmd_summary : $!" . __FILE__ . ":" . __LINE__ );
        exit;
      }
    }
    my $package_version = "";
    foreach my $line (@show_summary) {
      chomp $line;
      $line =~ s/^\s+//g;
      if ( $line =~ "^Chassis Serial Number:" ) {
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        my ( $title, $variable ) = split( ":", $line );
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
        $variable =~ s/^\s+//g;
        $variable =~ s/\s+$//g;
        print CONFOUT "$title: $variable\n";
      }
      if ( $line =~ "^Current Package Version:" ) {
        if   ( $package_version =~ "Current Package Version:" ) { next; }
        else                                                    { $package_version = $line; }
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        my ( $title, $variable ) = split( ":", $line );
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
        $variable =~ s/^\s+//g;
        $variable =~ s/\s+$//g;
        print CONFOUT "$title: $variable\n";
      }
      if ( $line =~ "^SMW Version:" ) {
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        my ( $title, $variable ) = split( ":", $line );
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
        $variable =~ s/^\s+//g;
        $variable =~ s/\s+$//g;
        print CONFOUT "$title: $variable\n";
      }
    }
  }
  if ( $storage_type =~ /old/ ) {
    eval {
      # Set alarm
      my $act_time = localtime();
      local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
      alarm($timeout);

      # CMDs
      if ( $user_name && $user_pw ) {
        $cmd_summary             = `$SMcli -n $storage_name -e -R $user_name -p $user_pw -c "show storagesubsystem summary;" 2>/dev/null`;
        $cmd_summary_to_errorlog = "$SMcli -n $storage_name -e -R $user_name -p <XXXXX> -c \"show storagesubsystem summary;\" 2>/dev/null";
      }
      else {
        $cmd_summary             = `$SMcli -n $storage_name -e -c "show storagesubsystem summary;" 2>/dev/null`;
        $cmd_summary_to_errorlog = "$SMcli -n $storage_name -e -c \"show storagesubsystem summary;\" 2>/dev/null";
      }
      @show_summary = split( "\n", $cmd_summary );

      # end of alarm
      alarm(0);
    };
    if ($@) {
      if ( $@ =~ /died in SIG ALRM/ ) {
        my $act_time = localtime();
        error("command timed out after : $timeout seconds");
        exit(0);
      }
    }
    if ( "@show_summary" !~ /SMcli completed successfully/ ) {
      $cmd_summary =~ s/\n//g;
      $cmd_summary = substr $cmd_summary, -512;
      if ( "@show_summary" =~ /error code 12/ ) {
        error("SMcli command failed: $cmd_summary_to_errorlog");
        error( "$cmd_summary : $!" . __FILE__ . ":" . __LINE__ );
        error("Most probably permission issue, STOR2RRD cannot run SMcli command. Problem description and fix: http://www.stor2rrd.com/install.htm#SMclierror");
        exit;
      }
      else {
        error("SMcli command failed: $cmd_summary_to_errorlog");
        error( "$cmd_summary : $!" . __FILE__ . ":" . __LINE__ );
        exit;
      }
    }
    my $firmware_vers = "";
    foreach my $line (@show_summary) {
      chomp $line;
      $line =~ s/^\s+//g;
      if ( $line =~ "^Firmware version:" ) {
        if   ( $firmware_vers =~ "Firmware version:" ) { next; }
        else                                           { $firmware_vers = $line; }
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        my ( $title, $variable ) = split( ":", $line );
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
        $variable =~ s/^\s+//g;
        $variable =~ s/\s+$//g;
        print CONFOUT "$title: $variable\n";
      }
      if ( $line =~ "^SMW version:" ) {
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        my ( $title, $variable ) = split( ":", $line );
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
        $variable =~ s/^\s+//g;
        $variable =~ s/\s+$//g;
        print CONFOUT "$title: $variable\n";
      }
      if ( $line =~ "^Feature pack:" ) {
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        my ( $title, $variable ) = split( ":", $line );
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
        $variable =~ s/^\s+//g;
        $variable =~ s/\s+$//g;
        print CONFOUT "$title: $variable\n";
      }
      if ( $line =~ "^Feature pack submodel ID:" ) {
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        my ( $title, $variable ) = split( ":", $line );
        $title =~ s/^\s+//g;
        $title =~ s/\s+$//g;
        $variable =~ s/^\s+//g;
        $variable =~ s/\s+$//g;
        print CONFOUT "$title: $variable\n";
      }
    }
  }

  # Volume part
  my @volume_cfg_lines   = grep {/Logical Drive name:|Capacity:|Logical Drive ID:|Associated disk pool:|Associated array:|Accessible By:|Interface type:|Drive interface type:/} @logicalDrives;
  my $volume_name_cfg    = "";
  my $volume_id_cfg      = "";
  my $volume_pool_cfg    = "";
  my $volume_capacity    = "";
  my $vol_interface_type = "";
  my @vol_hosts;

  print CONFOUT "\nVolume Level Configuration\n";
  print CONFOUT "--------------------------\n";
  print CONFOUT "volume_id,id,name,,,,pool_id,pool_name,capacity (MB),,,,,,vdisk_UID,,,,,,interface_type\n";

  #print @config_lines;
  foreach my $line (@volume_cfg_lines) {
    chomp $line;
    if ( $line =~ "Logical Drive name:" ) {
      $line =~ s/Logical Drive name://g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      $volume_name = $line;
    }
    if ( $line =~ "Logical Drive ID:" ) {
      $line =~ s/Logical Drive ID://g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      $line =~ s/://g;
      $volume_id = $line;
    }
    if ( $line =~ "Associated disk pool:" || $line =~ "Associated array:" ) {
      $line =~ s/Associated disk pool://g;
      $line =~ s/Associated array://g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      $volume_pool = $line;
    }
    if ( $line =~ "Capacity:" ) {
      $line =~ s/Capacity://g;
      $line =~ s/,//g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      $volume_capacity = $line;
    }
    if ( $line =~ "Interface type:" || $line =~ "Drive interface type:" ) {
      $line =~ s/Interface type://g;
      $line =~ s/Drive interface type://g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      $vol_interface_type = $line;
      my $capacity;
      my ( $cap_num, $cap_size ) = split( " ", $volume_capacity );
      if ( $cap_size =~ /MB/ ) { $capacity = $cap_num; }
      if ( $cap_size =~ /GB/ ) { $capacity = $cap_num * 1024; }
      if ( $cap_size =~ /TB/ ) { $capacity = $cap_num * 1024 * 1024; }
      if ( $cap_size =~ /PB/ ) { $capacity = $cap_num * 1024 * 1024 * 1024; }
      $volume_name =~ s/:/===colon===/g;
      $volume_name =~ s/\s/===space===/g;
      $volume_pool =~ s/:/===colon===/g;
      $volume_pool =~ s/\s/===space===/g;
      print CONFOUT "$volume_id,,$volume_name,,,,,$volume_pool,$capacity,,,,,,,,,,,,$vol_interface_type\n";
    }
    if ( $line =~ "Accessible By:" ) {
      $line =~ s/Accessible By://g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      push( @vol_hosts, "$volume_name,$line,$volume_id\n" );
    }
  }

  # Host part
  # SMcli command
  my $cmd_hostTopology;
  my $cmd_hostTopology_to_errorlog;
  my @hostTopology;
  eval {
    # Set alarm
    my $act_time = localtime();
    local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
    alarm($timeout);

    # CMDs
    if ( $user_name && $user_pw ) {
      $cmd_hostTopology             = `$SMcli -n $storage_name -e -R $user_name -p $user_pw -c "show hostTopology;" 2>/dev/null`;
      $cmd_hostTopology_to_errorlog = "$SMcli -n $storage_name -e -R $user_name -p <XXXXX> -c \"show hostTopology;\" 2>/dev/null";
    }
    else {
      $cmd_hostTopology             = `$SMcli -n $storage_name -e -c "show hostTopology;" 2>/dev/null`;
      $cmd_hostTopology_to_errorlog = "$SMcli -n $storage_name -e -c \"show hostTopology;\" 2>/dev/null";
    }
    @hostTopology = split( "\n", $cmd_hostTopology );

    # end of alarm
    alarm(0);
  };
  if ($@) {
    if ( $@ =~ /died in SIG ALRM/ ) {
      my $act_time = localtime();
      error("command timed out after : $timeout seconds");
      exit(0);
    }
  }
  if ( "@hostTopology" !~ /SMcli completed successfully/ ) {
    $cmd_hostTopology =~ s/\n//g;
    $cmd_hostTopology = substr $cmd_hostTopology, -512;
    if ( "@hostTopology" =~ /error code 12/ ) {
      error("SMcli command failed: $cmd_hostTopology_to_errorlog");
      error( "$cmd_hostTopology : $!" . __FILE__ . ":" . __LINE__ );
      error("Most probably permission issue, STOR2RRD cannot run SMcli command. Problem description and fix: http://www.stor2rrd.com/install.htm#SMclierror");
      exit;
    }
    else {
      error("SMcli command failed: $cmd_hostTopology_to_errorlog");
      error( "$cmd_hostTopology : $!" . __FILE__ . ":" . __LINE__ );
      exit;
    }
  }

  print CONFOUT "\nHost Level Configuration\n";
  print CONFOUT "--------------------------\n";
  print CONFOUT "host_id,id,name,port_count,Type,volume_count,WWPN,Volume IDs,Volume Names\n";

  my $host_group = "";
  my $host_name  = "";
  foreach my $line (@hostTopology) {
    chomp $line;
    if ( $line =~ /Host Group:/ ) {
      $line =~ s/Host Group://g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      $host_group = "$line";
    }
    if ( $line =~ /^         Host:/ ) {
      $host_group = "===UNKNOWN===XORUX===";
    }
    if ( $line =~ /Host:/ ) {
      $line =~ s/Host://g;
      $line =~ s/^\s+//g;
      $line =~ s/\s+$//g;
      $host_name = "$line";

      #print "HOST: $host_name GROUP: $host_group\n";
      my @vol_lines = grep {/$host_name,|$host_group,/} @vol_hosts;
      $host_name =~ s/:/===colon===/g;
      $host_name =~ s/\s/===space===/g;
      print CONFOUT ",,$host_name,,,,,";
      foreach my $line_i (@vol_lines) {
        chomp $line_i;
        my ( undef, undef, $vol_id ) = split( ",", $line_i );
        print CONFOUT "$vol_id ";
      }
      print CONFOUT ",";
      foreach my $line_l (@vol_lines) {
        chomp $line_l;
        my ( $vol_name, undef ) = split( ",", $line_l );
        $vol_name =~ s/:/===colon===/g;
        $vol_name =~ s/\s/===space===/g;
        print CONFOUT "$vol_name ";
      }
      print CONFOUT "\n";
    }
  }

  # Pool part
  print CONFOUT "\nPool Level Configuration\n";
  print CONFOUT "------------------------\n";
  print CONFOUT "name,id,status,mdisk_count,vdisk_count,capacity (GB),extent_size,free_capacity (GB),virtual_capacity,used_capacity (GB),real_capacity,overallocation,warning,easy_tier,easy_tier_status,compression_active,compression_virtual_capacity,compression_compressed_capacity,compression_uncompressed_capacity\n";

  my $last_pool = "";
  @pools = sort @pools;
  foreach (@pools) {
    chomp $_;
    my $pool = $_;
    if ( $pool eq $last_pool ) {next}
    $last_pool = $pool;

    # SMcli command
    my $cmd_show_array;
    my $cmd_show_array_to_errorlog;
    my @show_array;
    my $capacity      = "";
    my $used_capacity = "";
    my $free_capacity = "";

    if ( $storage_type =~ /new/ ) {
      eval {
        # Set alarm
        my $act_time = localtime();
        local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
        alarm($timeout);

        # CMDs
        if ( $user_name && $user_pw ) {
          $cmd_show_array             = `$SMcli -n $storage_name -e -R $user_name -p $user_pw -c "show diskPool [$pool] ;" 2>/dev/null`;
          $cmd_show_array_to_errorlog = "$SMcli -n $storage_name -e -R $user_name -p <XXXXX> -c \"show diskPool [$pool] ;\" 2>/dev/null";
        }
        else {
          $cmd_show_array             = `$SMcli -n $storage_name -e -c "show diskPool [$pool] ;" 2>/dev/null`;
          $cmd_show_array_to_errorlog = "$SMcli -n $storage_name -e -c \"show diskPool [$pool] ;\" 2>/dev/null";
        }
        @show_array = split( "\n", $cmd_show_array );

        # end of alarm
        alarm(0);
      };
      if ($@) {
        if ( $@ =~ /died in SIG ALRM/ ) {
          my $act_time = localtime();
          error("command timed out after : $timeout seconds");
          exit(0);
        }
      }
      if ( "@show_array" !~ /SMcli completed successfully/ ) {
        $cmd_show_array =~ s/\n//g;
        $cmd_show_array = substr $cmd_show_array, -512;
        if ( "@show_array" =~ /error code 12/ ) {
          error("SMcli command failed: $cmd_show_array_to_errorlog");
          error( "$cmd_show_array : $!" . __FILE__ . ":" . __LINE__ );
          error("Most probably permission issue, STOR2RRD cannot run SMcli command. Problem description and fix: http://www.stor2rrd.com/install.htm#SMclierror");
          exit;
        }
        else {
          error("SMcli command failed: $cmd_show_array_to_errorlog");
          error( "$cmd_show_array : $!" . __FILE__ . ":" . __LINE__ );
          exit;
        }
      }
      foreach my $line_k (@show_array) {
        chomp $line_k;
        if ( $line_k =~ "Usable capacity:" ) {
          $line_k =~ s/Usable capacity://g;
          $line_k =~ s/,//g;
          $line_k =~ s/^\s+//g;
          $line_k =~ s/\s+$//g;
          my ( $cap_num, $cap_size ) = split( " ", $line_k );
          if ( $cap_size =~ /^B/ ) { $capacity = $cap_num / 1024 / 1024 / 1024; }
          if ( $cap_size =~ /kB/ ) { $capacity = $cap_num / 1024 / 1024; }
          if ( $cap_size =~ /MB/ ) { $capacity = $cap_num / 1024; }
          if ( $cap_size =~ /GB/ ) { $capacity = $cap_num; }
          if ( $cap_size =~ /TB/ ) { $capacity = $cap_num * 1024; }
          if ( $cap_size =~ /PB/ ) { $capacity = $cap_num * 1024 * 1024; }
        }
        if ( $line_k =~ "Used capacity:" ) {
          $line_k =~ s/Used capacity://g;
          $line_k =~ s/,//g;
          $line_k =~ s/^\s+//g;
          $line_k =~ s/\s+$//g;
          my ( $cap_num, $cap_size ) = split( " ", $line_k );
          if ( $cap_size =~ /^B/ ) { $used_capacity = $cap_num / 1024 / 1024 / 1024; }
          if ( $cap_size =~ /kB/ ) { $used_capacity = $cap_num / 1024 / 1024; }
          if ( $cap_size =~ /MB/ ) { $used_capacity = $cap_num / 1024; }
          if ( $cap_size =~ /GB/ ) { $used_capacity = $cap_num; }
          if ( $cap_size =~ /TB/ ) { $used_capacity = $cap_num * 1024; }
          if ( $cap_size =~ /PB/ ) { $used_capacity = $cap_num * 1024 * 1024; }
        }
        if ( $line_k =~ "Free Capacity:" ) {
          $line_k =~ s/Free Capacity://g;
          $line_k =~ s/,//g;
          $line_k =~ s/^\s+//g;
          $line_k =~ s/\s+$//g;
          my ( undef, $cap_num, $cap_size ) = split( " ", $line_k );
          if ( $cap_size =~ /^B/ ) { $free_capacity = $cap_num / 1024 / 1024 / 1024; }
          if ( $cap_size =~ /kB/ ) { $free_capacity = $cap_num / 1024 / 1024; }
          if ( $cap_size =~ /MB/ ) { $free_capacity = $cap_num / 1024; }
          if ( $cap_size =~ /GB/ ) { $free_capacity = $cap_num; }
          if ( $cap_size =~ /TB/ ) { $free_capacity = $cap_num * 1024; }
          if ( $cap_size =~ /PB/ ) { $free_capacity = $cap_num * 1024 * 1024; }
        }
      }
      $pool =~ s/:/===colon===/g;
      $pool =~ s/\s/===space===/g;
      print CONFOUT "$pool,,,,,$capacity,,$free_capacity,,$used_capacity,,,,,,,,,\n";
    }
    if ( $storage_type =~ /old/ ) {
      eval {
        # Set alarm
        my $act_time = localtime();
        local $SIG{ALRM} = sub { die "$act_time: died in SIG ALRM"; };
        alarm($timeout);

        # CMDs
        if ( $user_name && $user_pw ) {
          $cmd_show_array             = `$SMcli -n $storage_name -e -R $user_name -p $user_pw -c "show array [$pool] ;" 2>/dev/null`;
          $cmd_show_array_to_errorlog = "$SMcli -n $storage_name -e -R $user_name -p <XXXXX> -c \"show array [$pool] ;\" 2>/dev/null";
        }
        else {
          $cmd_show_array             = `$SMcli -n $storage_name -e -c "show array [$pool] ;" 2>/dev/null`;
          $cmd_show_array_to_errorlog = "$SMcli -n $storage_name -e -c \"show array [$pool] ;\" 2>/dev/null";
        }
        @show_array = split( "\n", $cmd_show_array );

        # end of alarm
        alarm(0);
      };
      if ($@) {
        if ( $@ =~ /died in SIG ALRM/ ) {
          my $act_time = localtime();
          error("command timed out after : $timeout seconds");
          exit(0);
        }
      }
      if ( "@show_array" !~ /SMcli completed successfully/ ) {
        $cmd_show_array =~ s/\n//g;
        $cmd_show_array = substr $cmd_show_array, -512;
        if ( "@show_array" =~ /error code 12/ ) {
          error("SMcli command failed: $cmd_show_array_to_errorlog");
          error( "$cmd_show_array : $!" . __FILE__ . ":" . __LINE__ );
          error("Most probably permission issue, STOR2RRD cannot run SMcli command. Problem description and fix: http://www.stor2rrd.com/install.htm#SMclierror");
          exit;
        }
        else {
          error("SMcli command failed: $cmd_show_array_to_errorlog");
          error( "$cmd_show_array : $!" . __FILE__ . ":" . __LINE__ );
          exit;
        }
      }
      foreach my $line_k (@show_array) {
        chomp $line_k;
        $line_k =~ s/^\s+//g;
        if ( $line_k =~ "^Capacity:" ) {
          $line_k =~ s/Capacity://g;
          $line_k =~ s/,//g;
          $line_k =~ s/^\s+//g;
          $line_k =~ s/\s+$//g;
          my ( $cap_num, $cap_size ) = split( " ", $line_k );
          if ( $cap_size =~ /^B/ ) { $capacity = $cap_num / 1024 / 1024 / 1024; }
          if ( $cap_size =~ /kB/ ) { $capacity = $cap_num / 1024 / 1024; }
          if ( $cap_size =~ /MB/ ) { $capacity = $cap_num / 1024; }
          if ( $cap_size =~ /GB/ ) { $capacity = $cap_num; }
          if ( $cap_size =~ /TB/ ) { $capacity = $cap_num * 1024; }
          if ( $cap_size =~ /PB/ ) { $capacity = $cap_num * 1024 * 1024; }
        }
        if ( $line_k =~ "^Free Capacity:" ) {
          $line_k =~ s/Free Capacity://g;
          $line_k =~ s/,//g;
          $line_k =~ s/^\s+//g;
          $line_k =~ s/\s+$//g;
          my ( $cap_num, $cap_size ) = split( " ", $line_k );
          if ( $cap_size =~ /^B/ ) { $free_capacity = $cap_num / 1024 / 1024 / 1024; }
          if ( $cap_size =~ /kB/ ) { $free_capacity = $cap_num / 1024 / 1024; }
          if ( $cap_size =~ /MB/ ) { $free_capacity = $cap_num / 1024; }
          if ( $cap_size =~ /GB/ ) { $free_capacity = $cap_num; }
          if ( $cap_size =~ /TB/ ) { $free_capacity = $cap_num * 1024; }
          if ( $cap_size =~ /PB/ ) { $free_capacity = $cap_num * 1024 * 1024; }
        }
      }
      $pool =~ s/:/===colon===/g;
      $pool =~ s/\s/===space===/g;
      print CONFOUT "$pool,,,,,$capacity,,$free_capacity,,$used_capacity,,,,,,,,,\n";
    }
  }
  close(CONFOUT);
}

### ERROR HANDLING
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);
  print STDERR "$act_time: $text : $!\n";
  return 1;
}
