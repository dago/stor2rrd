
use strict;
use Date::Parse;
use RRDp;
use POSIX qw(strftime);



my $DEBUG = $ENV{DEBUG};
my $errlog = $ENV{ERRLOG};

#$DEBUG=2;
open(OUT, ">> $errlog")  if $DEBUG == 2 ;

# get QUERY_STRING
use Env qw(QUERY_STRING);
$QUERY_STRING .= ":.";
#print OUT "-- $QUERY_STRING\n" if $DEBUG == 2 ;

my $STEP = $ENV{SAMPLE_RATE};
my $pic_col = $ENV{PICTURE_COLOR};
my $basedir = $ENV{INPUTDIR};
my $rrdtool = $ENV{RRDTOOL};
my $bindir = $ENV{BINDIR};
my $tmp_dir = "$basedir/tmp";
if (defined $ENV{TMPDIR_STOR}) {
  $tmp_dir = $ENV{TMPDIR_STOR};
}
my $width = 400;
my $height = 150;
my $width_trend = $width * 2;
my $detail_multipication = 3; # detail pop up will be 3 times bigger
my $wrkdir = "$basedir/data";
my $act_time = localtime();
my $font_def_normal =  "--font=DEFAULT:7:";
my $font_tit_normal =  "--font=TITLE:9:";
my $font_def_dashbo =  "--font=DEFAULT:6:";
my $font_tit_dashbo =  "--font=TITLE:7:";
my $font_def_popup  =  "--font=DEFAULT:10:";
my $font_tit_popup  =  "--font=TITLE:13:";
my $font_def_hist   =  "--font=DEFAULT:8:";
my $font_tit_hist   =  "--font=TITLE:10:";
my $font_def =  $font_def_normal;
my $font_tit =  $font_tit_normal;
my $png_end_heading = "\n";        # this or graphv dimensions

my $delimiter = "XORUX"; # this is for rrdtool print lines for clickable legend
my @table_out = "";

my $rrd_legend = "table"; #   "table" or "both" or "orig"
if ( -f "$tmp_dir/xorux_test_orig.txt" ) {
	  $rrd_legend = "orig";
}
if ( -f "$tmp_dir/xorux_test_both.txt" ) {
	  $rrd_legend = "both";
}
if ( -f "$tmp_dir/xorux_test_table.txt" ) {
	  $rrd_legend = "table";
}
if (! defined $ENV{HTTP_USER_AGENT}) {
	  $rrd_legend = "orig";
}
else {
  if ( defined $ENV{DEMO} && ($ENV{DEMO} == 1)) {
  }
  else {
    if ($ENV{HTTP_USER_AGENT} =~ /MSIE 8.0/) {
      $rrd_legend = "orig";
    }
  }
}


### graph or graphv
my $graph_cmd = "graph";
if ( -f "$tmp_dir/graphv" ) {
   $graph_cmd = "graphv";       # if exists - call this function
}

#`echo "query string ,$QUERY_STRING,"  >> /tmp/xd-g-c-query`;
#print STDERR "query string ,$QUERY_STRING,\n";

(my $host,my $type,my $name,my $item,my $time,my $detail,
 my $start_unix,my $end_unix, my $height_new, my $width_new) = split(/&/,$QUERY_STRING);


if ( ! defined($host) || ! defined($type) || ! defined($name) ) {
  error ("Not defined host/type/name, exiting: $QUERY_STRING ".__FILE__.":".__LINE__) && exit (1);
}
$host =~ s/host=//;
$host =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/eg;
$host =~ s/\+/ /g;
$host =~ s/%23/\#/g;
$type =~ s/type=//;
$item =~ s/item=//;
$name =~ s/name=//;
$name =~ tr/+/ /;
$name =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/eg;
$name =~ s/\+/ /g;
$name =~ s/%23/\#/g;
$time =~ s/time=//;
$detail =~ s/detail=//;

if ( $host  eq ''|| $type  eq ''|| $name eq '' ) {
  error ("Not defined host/type/name, exiting: $QUERY_STRING ".__FILE__.":".__LINE__) && exit (1);
}
#print STDERR " $QUERY_STRING : $name\n";

if ( $time !~ m/^d$/ && $width_new eq '' ) {
  select(undef, undef, undef, 0.15);
}

# following is from historical reporting
$height_new =~ s/\+//;
$height_new =~ s/height=//;
$width_new =~ s/\+//;
$width_new =~ s/width=//;

# parameters called only from historical reports, normally they are NULL
# and from zoom
if ( ! $start_unix eq '' ) {
  $start_unix =~ s/sunix=//;
}
if ( ! $end_unix eq '' ) {
  $end_unix =~ s/eunix=//;
  $end_unix =~ s/:\.,//; # some garbage could appear there
  $end_unix =~ s/:\.//;
}
if ( ! $height_new eq '' && $detail == 0 ) {
  $height_new  =~ s/height=//;
  if ( isdigit($height_new) > 0 ) {
    $height = $height_new; #replace HEIGHT by passed one
  }
}
if ( ! $width_new eq '' && $detail == 0 ) {
  $width_new =~ s/width=//;
  if ( isdigit($width_new) > 0 ) {
    $width = $width_new; #replace WIDTH by passed one
  }
}


my $heading_png = "";

# only for CGI-BIN purposes
if ( $item =~ m/xport/ ) {
  # export to CSV, not implemented yet
  # It should be here to do not influence normal report when XML is not in Perl
  require "$bindir/xml.pl";
  # use XML::Simple; --> it has to be in separete file
  print "Content-type: application/octet-stream\n";
}
else {
  if ( $type =~ m/VOLUME/ && $name =~ m/^top$/ ) {
    # Volume Top tablesuff
    #print "Content-type: text/html\n";

    print "Content-type: image/png\n";
    print "Cache-Control: max-age=60, must-revalidate\n\n"; # workaround for caching on Chrome
  }
  else {
    # normal picture stuff
    $heading_png = "Content-type: image/png\nCache-Control: max-age=60, must-revalidate\n";
    # print "Content-type: image/png\nCache-Control: max-age=60, must-revalidate\n"; # workaround for caching on Chrome
  }
}

my $no_legend = "--interlaced";  # just nope string , it is deprecated anyway
if ( isdigit($detail) == 0 ) {
  $detail = 0;
}
if ( $detail == 2 ) {
  # dashboard size
  if (defined $ENV{DASHB_RRDHEIGHT}) {
    $height = $ENV{DASHB_RRDHEIGHT};
  }
  else {
    $height = 50;
  }
  if (defined $ENV{DASHB_RRDWIDTH}) {
    $width  = $ENV{DASHB_RRDWIDTH};
  }
  else {
    $width = 120;
  }
  $font_def =  $font_def_dashbo;
  $font_tit =  $font_tit_dashbo;
  $no_legend = "--no-legend";
}
if ( $detail == 1 ) {
  $font_def =  $font_def_popup;
  $font_tit =  $font_tit_popup;
}

my $disable_rrdtool_tag = "--interlaced";  #just nope string, it is deprecated anyway
my $rrd_ver = $RRDp::VERSION;
if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
  $disable_rrdtool_tag = "--disable-rrdtool-tag";
}


if ( ! $height_new eq '' ) {
  $height=$height_new;
}
if ( ! $width_new eq '' ) {
  $width=$width_new;
}

  # keep here green - yellow - red - blue ...
  my @color=("#FF0000", "#0000FF", "#FFFF00", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080",
"#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887",
"#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E",
"#F6358A", "#151B54", "#6D7B8D", "#FDEEF4", "#FF0080", "#F88017", "#2554C7", "#FFF8C6", "#D4A017", "#306EFF",
"#151B8D", "#9E7BFF", "#EAC117", "#E0FFFF", "#15317E", "#6C2DC7", "#FBB917", "#FCDFFF", "#15317E", "#254117",
"#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC", "#C0C0C0");
  my $color_max = 53;


if ( $detail == 1 ) {
  $width = $width * $detail_multipication;
  $width_trend = $width_trend * $detail_multipication;
  $height = $height * $detail_multipication;
}

my @name_list = "";
if ( $detail == 3 ) { # real time Refresh
  $width = $width * 2;
  $width_trend = $width_trend * 2;
  $height = $height * 2;
  #@name_list = split(/;/,$line); # for aggregated sums ... --> it has to be finished
}

my $name_out = "/var/tmp/stor2rrd-$$.png";

# start RRD via a pipe
RRDp::start "$rrdtool";

my $st_type = "";
if ( -f "$wrkdir/$host/SWIZ" ) {
  $st_type = "SWIZ";
}
if ( -f "$wrkdir/$host/XIV" ) {
  $st_type = "XIV";
}
if ( -f "$wrkdir/$host/DS8K" ) {
  $st_type = "DS8K";
}
if ( -f "$wrkdir/$host/DS5K" ) {
  $st_type = "DS5K";
}
if ( $st_type eq '' ) {
  error ("Not defined storage type, exiting ".__FILE__.":".__LINE__) && exit (1);
}

# mdisk name translation table, must be global one
my @mdisk_trans = "";
if ( $type =~ m/RANK/ && $st_type =~ m/SWIZ/ ) {
  if ( -f "$wrkdir/$host/mdisk.cfg" ) {
    open(FHR, "< $wrkdir/$host/mdisk.cfg") || error ("Can't open $wrkdir/$host/mdisk.cfg : $! ".__FILE__.":".__LINE__) && exit (1);
    @mdisk_trans = <FHR>;
    close(FHR);
  }
  else {
    my $act_time = localtime();
    print STDERR "$act_time: File does not exist (no mdisk translation to names): $wrkdir/$host/mdisk.cfg\n"; # no error() 
  }
}

my $return = 1;

if ($item =~ m/^sum$/ ) {
  # only for big summ graphs --> it uses already created rddtool cmd line in tmp dir
  # print STDERR  "$host,$type,$name,$item,$time,$name_out,$detail\n";

  if ($rrd_legend eq "table" && $detail < 1) {
	if (( $name =~ m/^sum_data$/ ) ||
        ( $name =~ m/^sum_io$/ )   ||
        ( $name =~ m/^sum_capacity$/ ) ||
        ( $name =~ m/^tier0$/ )    ||
        ( $name =~ m/^tier1$/ )    ||
        ( $name =~ m/^tier2$/ )    ||
        ( $name =~ m/^io_rate-subsys$/ )    ||
        ( $name =~ m/^data_rate-subsys$/ )  ||
        ( $name =~ m/^read_io-subsys$/ )    ||
        ( $name =~ m/^write_io-subsys$/ )   ||
        ( $name =~ m/^read-subsys$/ )    ||
        ( $name =~ m/^write-subsys$/ )   ||
        ( $name =~ m/^used$/ )   ||
        ( $name =~ m/^sys$/ ) 
	   ) {  
	 } # nothing
	 else {  
       $no_legend = "--no-legend";
     }
  } 

  $return = create_graph_summ ($host,$type,$name,$item,$time,$name_out,$detail,$start_unix,$end_unix,$st_type);
}
else {
  # normal detail processing, not summed parts
  $no_legend = "--interlaced";
  if ($type =~ m/VOLUME/ ) {
    if ( $name =~ m/^top$/ ) {
      # print Top table, no graphs
      $return = volumes_top ($host,$type,$name,$item,$time,$st_type);
    }
    else {
      $return = create_graph_volume ($host,$type,$name,$item,$time,$name_out,$detail,$start_unix,$end_unix,$st_type,$STEP);
    }
  }
  else {
    if ($type =~ m/POOL/ && $item !~ m/^sum_capacity$/ ) {
      $return = create_graph_pool ($host,$type,$name,$item,$time,$name_out,$detail,$start_unix,$end_unix,$wrkdir,$act_time,$STEP,$st_type);
    }
    else {
      if ($type =~ m/HOST/ ) {
        $return = draw_graph_host_volume ($host,$type,$name,$item,$time,$name_out,$detail,$start_unix,$end_unix,$wrkdir,$act_time,$STEP);
      }
      else {
        $return = create_graph ($host,$type,$name,$item,$time,$name_out,$detail,$start_unix,$end_unix,$wrkdir,$act_time);
      }
    }
  }
}

if ( $return == 1 ) {
  print_png($name_out);
}

# close RRD pipe
RRDp::end;

close(OUT)  if $DEBUG == 2;

sub create_graph
{
  my $host = shift;     
  my $type = shift;     
  my $name = shift;     
  my $item = shift;     
  my $time = shift;     
  my $name_out = shift;     
  my $detail = shift;
  my $start_unix = shift;
  my $end_unix = shift;
  my $wrkdir = shift;
  my $act_time = shift;
  #`echo "create-graph : $host,$type,$name,$item,$time,$name_out,$detail,$start_unix,$end_unix,$wrkdir,$act_time," >> /tmp/xdgc-graph-start`;

  my $name_full = $name;
  $name =~ s/-P.*//;  # vyhozeni pool informace z rank rrd

  my $name_text = $name; 
  my $type_text = $type; 
  if ( $item =~ m/^sum_capacity$/ ) {
    # POOL name translation --> from ID
    open(FHR, "< $wrkdir/$host/pool.cfg") || error("Can't open $wrkdir/$host/pool.cfg : $! ".__FILE__.":".__LINE__) && return 0;
    my @lines_translate = <FHR>;
    close(FHR);
    foreach my $linep (@lines_translate) {
      chomp($linep);
      (my $id, my $name_pool) = split (/:/,$linep);
      if ( $name =~ m/^$id$/ ) {
        $name_text = $name_pool;
        last;
      }
    }
  }

  if ( $st_type =~ m/SWIZ/ && $type =~ m/RANK/ ) {
    # translate id into names only for MDISKS
    foreach my $line (@mdisk_trans) {
      chomp($line);
      (my $id, my $name_mdisk) = split (/:/,$line);
      if ( $id =~ m/^$name$/ ) {
        $name_text = $name_mdisk;
        $type_text = "MDISK";
        last;
      }
    }
  }

  #print OUT "$host:$type:$item:$name:$time:$name_out\n";

  my $value_short = "";
  my $value_long = "";
  my $val = 1;
  my $suffix = "rrd"; #standard suffix

  if ( $item =~ m/^data_rate$/ ){ $value_short= "MB"; $value_long = "Data throughput in MBytes"; $val=1024;}
  if ( $item =~ m/^io_rate$/ )  { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^data$/ )     { $value_short= "MB"; $value_long = "Data throughput in MBytes"; $val=1024;}
  if ( $item =~ m/^io$/ )       { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp$/ )     { $value_short= "msec"; $value_long = "Response time in msec"; $val=100;}
  if ( $item =~ m/^resp_t$/ )   { $value_short= "msec"; $value_long = "Response time in msec"; $val=100;}
  if ( $item =~ m/^read$/ )     { $value_short= "MB"; $value_long = "Read in MBytes"; $val=1024;}
  if ( $item =~ m/^write$/ )    { $value_short= "MB"; $value_long = "Write in MBytes"; $val=1024;}
  if ( $item =~ m/^read_io$/ )  { $value_short= "IOPS"; $value_long = "Read in IO per second";}
  if ( $item =~ m/^resp_t_r$/ ) { $value_short= "msec"; $value_long = "Read response time in msec"; }
  if ( $item =~ m/^resp_t_w$/ ) { $value_short= "msec"; $value_long = "Write response time in msec";}
  if ( $item =~ m/^write_io$/ ) { $value_short= "IOPS"; $value_long = "Write in IO per second"; }
  if ( $item =~ m/^sys$/ )      { $value_short= "CPU util"; $value_long = "CPU utilization in %"; }
  if ( $item =~ m/^compress$/ ) { $value_short= "CPU util"; $value_long = "CPU utilization in %"; }
  if ( $item =~ m/^pprc_data_r$/){ $suffix="rrp";$value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^pprc_data_w$/){ $suffix="rrp";$value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^pprc_rio$/ )  { $suffix="rrp";$value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^pprc_wio$/ )  { $suffix="rrp";$value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^pprc_rt_r$/ ) { $suffix="rrp";$value_short= "ms"; $value_long = "mili seconds";}
  if ( $item =~ m/^pprc_rt_w$/ ) { $suffix="rrp";$value_short= "ms"; $value_long = "mili seconds";}

  my $rrd = "$basedir/data/$host/$type/$name.$suffix";
  if ( $type =~ m/RANK/ ) {
    # original name with POOL info "-PXY"
    $name =~ s/^mdisk//;
    $rrd = "$basedir/data/$host/$type/$name_full.$suffix";
    if ( ! -f $rrd ) {
      # sometimes RANK might go here without pool info 
      my $time_newest = 0;
      foreach my $file (<$basedir/data/$host/$type/$name-P*.$suffix>) {
        my $file_time = (stat("$file"))[9]; 
        if ( $file_time > $time_newest) {
          $rrd = $file;
          $time_newest = $file_time;
          $name_text = $name;
        }
      }
    }
  }

  if ( ! -f $rrd ) {
    # try alias
    my $alias = alias ($type,$host,$name);
    if ( $alias eq '' ) {
      error ("Could not find $type ID for $host:$type:$name in neither in etc/alias.cfg ".__FILE__.":".__LINE__);
      return 0;
    }
    $rrd = "$basedir/data/$host/$type/$alias.$suffix";
    if ( $type =~ m/RANK/ ) {
      # original name with POOL info "-PXY"
      # there can be more rank files in different pools (historical reasons) --> use always the latest one
      $rrd = "$basedir/data/$host/$type/$name_full.$suffix";
      my $time_newest = 0;
      foreach my $file (<$basedir/data/$host/$type/$alias-P*.$suffix>) {
        my $file_time = (stat("$file"))[9]; 
        if ( $file_time > $time_newest) {
          $rrd = $file;
          $time_newest = $file_time;
          $name_text = $name;
        }
      }
    }
  }
  if ( ! -f $rrd ) {
    error ("Could not find $type ID for $host:$type:$name in neither in etc/alias.cfg ".__FILE__.":".__LINE__);
    return 0;
  }


  if ( $item =~ m/^sum_capacity$/) { $value_short= "TB"; $value_long = "TBytes"; $rrd = "$basedir/data/$host/$type/$name-cap.rrd";}

  if ( $detail == 1 ) {
    $font_def =  $font_def_popup;
    $font_tit =  $font_tit_popup;
  }

  my $name_space = sprintf ("%-10s","$name_text");

  my $comment = sprintf ("%-25s","$item [$value_short]");

  my $xgrid_all = xgrid_set($time,$detail);
  my $text = text_set($time);
  my $last = " last";
  my $header = "$type : $name : $item$last $text";
  if ( $detail == 2 ) {
    $header = "$name : $item $text";
  }

  my $start_time = "now-1$time";
  my $end_time = "now-1$time+1$time";
  if ( ! $start_unix eq '' && ! $end_unix eq '' ) {
    if ( isdigit($start_unix) > 0 && isdigit($end_unix) > 0 ) {
      # Historical report detected
      $start_time = $start_unix;
      $end_time = $end_unix;
      #$xgrid ="COMMENT: "; # just a trick to place there something otherwise rrdtool complains
      my $start_human = strftime "%H:%M:%S %d.%m.%Y",localtime($start_unix);
      my $end_human = strftime "%H:%M:%S %d.%m.%Y",localtime($end_unix);
      $header = "$type_text : $name_text : $item : $start_human - $end_human";
      $text = "";
      $xgrid_all= "--alt-y-grid";
      $font_def = $font_def_hist;  
      $font_tit = $font_tit_hist;  
    }
  }

  my $vertical_label="--vertical-label=$value_long";
  if ( $detail == 2 ) {
    $vertical_label="--interlaced";
    $no_legend = "--no-legend";
  }


  my $answ = "";
  my $item1 .= "";
  my $item2 .= "";
  if ( $item =~ m/^io$/ || $item =~ m/^data$/ ) {
    if ( $item =~ m/^io$/ ) {
      $item1 .= "read_".$item;
      $item2 .= "write_".$item;
    }
    if ( $item =~ m/^data$/ ) {
      $item1 .= "read";
      $item2 .= "write";
    }
    RRDp::cmd qq($graph_cmd "$name_out"
          "--title" "$header"
          "--start" "$start_time"
          "--end" "$end_time"
          "--imgformat" "PNG"
          "--slope-mode"
          "--width=$width"
          "--height=$height"
          "--step=$STEP"
          "--lower-limit=0"
          "--color=BACK#$pic_col"
          "--color=SHADEA#$pic_col"
          "--color=SHADEB#$pic_col"
          "--color=CANVAS#$pic_col"
          "$vertical_label"
          "--alt-autoscale-max"
          "--interlaced"
          "--upper-limit=0.2"
          "--units-exponent=1.00"
          "$no_legend"
          "$disable_rrdtool_tag"
          "$font_def"
          "$font_tit"
          "$xgrid_all"
          "DEF:value1="$rrd":$item1:AVERAGE"
          "DEF:value2="$rrd":$item2:AVERAGE"
          "CDEF:valmb1=value1,$val,/"
          "CDEF:valmb2=value2,$val,/"
          "CDEF:tot=valmb2,valmb1,+"
          "COMMENT:$comment Avg        Max\\n"
          "LINE1:valmb1#00FF00:read  $name_space "
          "GPRINT:valmb1:AVERAGE:%8.1lf"
          "GPRINT:valmb1:MAX:%8.1lf"
          "COMMENT:\\n"
          "LINE1:valmb2#4444FF:write $name_space "
          "GPRINT:valmb2:AVERAGE:%8.1lf"
          "GPRINT:valmb2:MAX:%8.1lf"
          "COMMENT:\\n"
          "COMMENT:Total              "
          "GPRINT:tot:AVERAGE:%8.1lf"
          "GPRINT:tot:MAX:%8.1lf"
          "COMMENT:\\n"
          "HRULE:0#000000");
    $answ = RRDp::read;
    if ( $$answ =~ "ERROR" ) {
       error ("$host:$type Graph rrdtool error : $$answ");
       if ( $answ =~ "is not an RRD file" ) {
	      (my $err,  my $file, my $txt) = split(/'/,$answ);
          error ("It need to be removed due to corruption: $file");
       }
       else {
	      error ( "Graph rrdtool error : $answ");
       }
    }
    $png_end_heading = ret_graph_param($answ);
  }
  else {
    if ( $item =~ m/^resp$/ ) {
      $item1 .= "resp_t_r";
      $item2 .= "resp_t_w";
      RRDp::cmd qq($graph_cmd "$name_out"
          "--title" "$header"
          "--start" "$start_time"
          "--end" "$end_time"
          "--imgformat" "PNG"
          "--slope-mode"
          "--width=$width"
          "--height=$height"
          "--step=$STEP"
          "--lower-limit=0"
          "--color=BACK#$pic_col"
          "--color=SHADEA#$pic_col"
          "--color=SHADEB#$pic_col"
          "--color=CANVAS#$pic_col"
          "$vertical_label"
          "--alt-autoscale-max"
          "--interlaced"
          "--upper-limit=0.2"
          "--units-exponent=1.00"
          "$no_legend"
          "$disable_rrdtool_tag"
          "$font_def"
          "$font_tit"
          "$xgrid_all"
          "DEF:val1=$rrd:$item1:AVERAGE"
          "DEF:val2=$rrd:$item2:AVERAGE"
          "COMMENT:$comment Avg        Max\\n"
          "LINE1:val1#00FF00:read  $name_space "
          "GPRINT:val1:AVERAGE:%8.1lf"
          "GPRINT:val1:MAX:%8.1lf"
          "COMMENT:\\n"
          "LINE1:val2#4444FF:write $name_space "
          "GPRINT:val2:AVERAGE:%8.1lf"
          "GPRINT:val2:MAX:%8.1lf"
          "COMMENT:\\n"
          "HRULE:0#000000");
      $answ = RRDp::read;
      $png_end_heading = ret_graph_param($answ);
    }
    else {
      if ( $item =~ m/^sum_capacity$/ ) {
        RRDp::cmd qq($graph_cmd "$name_out"
          "--title" "$header"
          "--start" "$start_time"
          "--end" "$end_time"
          "--imgformat" "PNG"
          "--slope-mode"
          "--width=$width"
          "--height=$height"
          "--step=$STEP"
          "--lower-limit=0"
          "--color=BACK#$pic_col"
          "--color=SHADEA#$pic_col"
          "--color=SHADEB#$pic_col"
          "--color=CANVAS#$pic_col"
          "$vertical_label"
          "--alt-autoscale-max"
          "--interlaced"
          "--upper-limit=0.2"
          "--units-exponent=1.00"
          "$no_legend"
          "$disable_rrdtool_tag"
          "$font_def"
          "$font_tit"
          "$xgrid_all"
          "DEF:total="$rrd":total:AVERAGE"
          "DEF:free="$rrd":free:AVERAGE"
          "CDEF:used=total,free,-"
          "COMMENT:$comment Avg        Max\\n"
          "AREA:used#FF3333:Used               "
          "GPRINT:used:AVERAGE:%7.2lf"
          "GPRINT:used:MAX:%7.2lf"
          "COMMENT:\\n"
          "STACK:free#33FF33:Free               "
          "GPRINT:free:AVERAGE:%7.2lf"
          "GPRINT:free:MAX:%7.2lf"
          "COMMENT:\\n"
          "HRULE:0#000000");
        $answ = RRDp::read;
        $png_end_heading = ret_graph_param($answ); 
      }
      else {
        RRDp::cmd qq($graph_cmd "$name_out"
          "--title" "$header"
          "--start" "$start_time"
          "--end" "$end_time"
          "--imgformat" "PNG"
          "--slope-mode"
          "--width=$width"
          "--height=$height"
          "--step=$STEP"
          "--lower-limit=0"
          "--color=BACK#$pic_col"
          "--color=SHADEA#$pic_col"
          "--color=SHADEB#$pic_col"
          "--color=CANVAS#$pic_col"
          "$vertical_label"
          "--alt-autoscale-max"
          "--interlaced"
          "--upper-limit=0.2"
          "--units-exponent=1.00"
          "$no_legend"
          "$disable_rrdtool_tag"
          "$font_def"
          "$font_tit"
          "$xgrid_all"
          "DEF:value="$rrd":$item:AVERAGE"
          "CDEF:valmb=value,$val,/"
          "COMMENT:$comment Avg        Max\\n"
          "LINE1:valmb#4444FF:$name_space       "
          "GPRINT:valmb:AVERAGE:%8.1lf"
          "GPRINT:valmb:MAX:%8.1lf"
          "COMMENT:\\n"
          "HRULE:0#000000");
       $answ = RRDp::read;
       $png_end_heading = ret_graph_param($answ);
      }
    }
  }


  return (1);
}


# Print the png out
sub print_png {
   my $name_out = shift;

   if ( ! -f "$name_out" ) {
     error ("Graph rrdtool error : print_png : file does not exist : $name_out ".__FILE__.":".__LINE__) && return 0;
   }

   if ( defined $ENV{DEMO} && ($ENV{DEMO} == 1)) {
	 my $name_out_8 = "$name_out".".png";
	 `convert $name_out -colors 256 PNG8:$name_out_8;`;
	 ` mv $name_out_8 $name_out`;
	 # print STDERR "convert in use for $name_out\n";
   }

#  if ( $type =~ m/VOLUME/ && $name =~ m/^top$/ ) {

   if (@table_out > 1 && $detail < 1 && ($rrd_legend ne "orig") ) {
     $heading_png =~ s/image\/png/application\/json/;
     print "$heading_png";
     print "$png_end_heading"; # for graphv possibility
     #print STDERR "\$heading_png ,$heading_png,";
     #print STDERR "\$png_end_heading ,$png_end_heading,";
     my $picture = do {
  	   local $/ = undef;
	   open my $fh, "<", $name_out || error("Cannot open  $name_out: $!".__FILE__.":".__LINE__) && return 0;
	   <$fh>;
     };
     my $encoded_pict = encode_base64($picture, "");
     $encoded_pict = "data:image/png;base64,$encoded_pict";

     my $table_one_string = "@table_out";
     my $encoded_table_out = encode_base64($table_one_string, "");

     my $lll = length $encoded_pict;
     my $llx = length $encoded_table_out;
     #print STDERR "length encoded pict is $lll\n";
     #print STDERR "length encoded table is $llx\n";

     print "{\"img\":\"$encoded_pict\", \"table\": \"$encoded_table_out\"}";

   }
   else {
     print "$heading_png";
     print "$png_end_heading"; # for graphv possibility
     #print STDERR "no table $heading_png ,$heading_png,";
     #print STDERR "no table $png_end_heading ,$png_end_heading,";

     open(PNG, "< $name_out") || error("Cannot open  $name_out: $!".__FILE__.":".__LINE__) && return 0;
     binmode(PNG);
     while (read(PNG,$b,4096)) {
        print "$b";
     }
     close (PNG);
   }
   unlink ("$name_out");

   return 1;
}



sub create_graph_volume
{
  my $host = shift;     
  my $type = shift;     
  my $lpar = shift;     
  my $item = shift;     
  my $time = shift;     
  my $name_out = shift;     
  my $detail = shift;
  my $start_unix = shift;
  my $end_unix = shift;
  my $st_type = shift;     
  my $step = shift; # for volumes must be step corect due to DS8K and read/write stored in GAUGE instead oif ABSOLUTE
  # print STDERR "create-graph-volume : $host,$type,$lpar,$item,$time,$name_out,$detail,$start_unix,$end_unix,$st_type,$step\n";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $act_time = localtime();
  my $act_time_u = time();
  my $req_time = 0;
  my $xgrid = "";
  my $suffix = "rrd";
  my $value_short = "";
  my $value_long = "";
  my $val = 1;

  if ( $item =~ m/^data_rate$/ )     { $value_short= "MB"; $value_long = "Data throughput in MBytes"; $val=1024;}
  if ( $item =~ m/^read$/ )          { $value_short= "MB"; $value_long = "Data throughput in MBytes"; $val=1024;}
  if ( $item =~ m/^write$/ )         { $value_short= "MB"; $value_long = "Data throughput in MBytes"; $val=1024;}
  if ( $item =~ m/^io_rate$/ )       { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp_t$/ )        { $value_short= "msec"; $value_long = "Response time in msec"; $val=1}
  if ( $item =~ m/^resp_t_w$/ )      { $value_short= "msec"; $value_long = "Response time in msec"; $val=1;}
  if ( $item =~ m/^resp_t_r$/ )      { $value_short= "msec"; $value_long = "Response time in msec"; $val=1;}
  if ( $item =~ m/^read_io$/ )       { $value_short= "IOPS"; $value_long = "Read in IO per second";}
  if ( $item =~ m/^write_io$/ )      { $value_short= "IOPS"; $value_long = "Write in IO per second";}
  if ( $item =~ m/^r_cache_hit$/ )   { $value_short= "%"; $value_long = "percent"; $val=1; }
  if ( $item =~ m/^w_cache_hit$/ )   { $value_short= "%"; $value_long = "percent"; $val=1; }
  if ( $item =~ m/^r_cache_usage$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val=1024; }
  if ( $item =~ m/^w_cache_usage$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val=1024; }
  if ( $item =~ m/^read_b$/ )        { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write_b$/ )       { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read_io_b$/ )     { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io_b$/ )    { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp_t_r_b$/ )    { $value_short= "ms"; $value_long = "mili seconds"; }
  if ( $item =~ m/^resp_t_w_b$/ )    { $value_short= "ms"; $value_long = "mili seconds"; }

  if ( $st_type =~ m/^DS8K$/ && $type =~ /VOLUME/ ) {
    if ( $item =~ m/^resp_t_r$/ || $item =~ m/^resp_t_w$/ || $item =~ m/^r_cache_usage$/ || $item =~ m/^r_cache_hit$/ ||
         $item =~ m/^w_cache_hit$/ || $item =~ m/^w_cache_usage$/ || $item =~ m/^read_io$/ || $item =~ m/^write_io$/  ||
         $item =~ m/^read_io_b$/ || $item =~ m/^write_io_b$/ || $item =~ m/^read_b$/ || $item =~ m/^write_b$/ ||
         $item =~ m/^resp_t_r_b$/ || $item =~ m/^resp_t_w_b$/ ) {
      # those are stored in .rrc files
      $suffix = "rrc";
    }
  }

  if ( $st_type =~ m/^SWIZ$/ && $type =~ /VOLUME/ ) {
    if ( $item =~ m/^r_cache_usage$/ || $item =~ m/^r_cache_hit$/ || $item =~ m/^w_cache_hit$/ || $item =~ m/^w_cache_usage$/  ||
         $item =~ m/^total_usage$/ || $item =~ m/^res1$/ || $item =~ m/^res2$/  ) {
      # those are stored in .rrc files
      $suffix = "rrc";
    }
  }


  if ( $st_type =~ m/^DS8K$/ && $type =~ /VOLUME/ ) {
    if ( $item =~ m/^read$/ || $item =~ m/^write$/ ) {
      # data is stored in wrong RRDTool type (GAUGE instead of ABSOLUTE)
      # this do data conversion
      $val = $step; # do not use $val=1024
    }
  }

  my $comment=$item," [".$value_short."]";
  $comment =~ s/r_cache_//g;
  $comment =~ s/w_cache_//g;
  $comment = sprintf ("%-38s","$comment");


  my $xgrid_all = xgrid_set($time,$detail);
  my $text = text_set($time);
  my $header = "$type : $name : $item last $text";
  if ( $detail == 2 ) {
    $header = "$name : $item $text";
  }

  my $start_time = "now-1$time";
  my $end_time = "now-1$time+1$time";
  if ( ! $start_unix eq '' && ! $end_unix eq '' ) {
    if ( isdigit($start_unix) > 0 && isdigit($end_unix) > 0 ) {
      # Historical report detected
      $start_time = $start_unix;
      $end_time = $end_unix;
      #$xgrid ="COMMENT: "; # just a trick to place there something otherwise rrdtool complains
      my $start_human = strftime "%H:%M:%S %d.%m.%Y",localtime($start_unix);
      my $end_human = strftime "%H:%M:%S %d.%m.%Y",localtime($end_unix);
      $header = "$type : $name : $item : $start_human - $end_human";
      $text = "";
      $xgrid_all= "--alt-y-grid";
      $font_def = $font_def_hist;  
      $font_tit = $font_tit_hist;  
      $req_time = $start_unix;
    }
  }


  my $i = 0;
  my $j = 0;
  my $cmd = "";

  my $vertical_label="--vertical-label=\\\"$value_long\\\"";
  if ( $detail == 2 ) {
    $vertical_label="--interlaced";
    $no_legend = "--no-legend";
  }

  #if ($rrd_legend eq "table" && $detail < 1) {
  #  $no_legend = "--no-legend";
  #}

  $cmd .= "$graph_cmd \\\"$name_out\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start \\\"$start_time\\\"";
  $cmd .= " --end \\\"$end_time\\\"";
  $cmd .= " --imgformat PNG";
  $cmd .= " --slope-mode";
  $cmd .= " --width=$width";
  $cmd .= " --height=$height";
  $cmd .= " --step=$step";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $vertical_label";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " $no_legend";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " $xgrid_all";
  $cmd .= " $font_def";
  $cmd .= " $font_tit";
  $cmd .= " COMMENT:\\\"Volume $comment  Avg         Max\\l\\\"";

  my $legend_heading = "Volume $delimiter $comment $delimiter Avg $delimiter Max ";

  my $gtype="AREA";
  if ( $item =~ m/resp_t/ || $item =~ m/cache_hit/ ) {
    $gtype="LINE1";
  }
  if ( $st_type !~ m/^DS8K$/ ) {
    # only DS8K must be stacked due to multivolumes
    $gtype="LINE1";
  }

  my $col_indx = 1; # on purpose to start with the blue one
  my $line_indx = 0; # place enter evry 3rd line

  # read volume cfg files with grouped volumes 
  # translation volume names to ID(s)
  open(FHR, "< $basedir/data/$host/VOLUME/volumes.cfg") || error ("file does not exists : $basedir/data/$host/VOLUME/volumes.cfg ".__FILE__.":".__LINE__) && return 0;
  my @files = <FHR>;
  my @files_org = @files;
  close (FHR);

  my $vols = "";
  my $vol_found = 0;
  foreach my $volg (@files) {
    chomp($volg);
    $vols = $volg;
    $volg =~ s/ : .*//;
    if ( $volg =~ m/^$lpar$/ ) {
      $vol_found++;
      last;
    }
  }
  if ( $vol_found == 0 ) {
    my $alias = alias ($type,$host,$lpar);
    if ( $alias eq '' ) {
        error ("Could not find volume ID for $host:$lpar in $basedir/data/$host/VOLUME/volumes.cfg neither any alias in etc/alias.cfg ".__FILE__.":".__LINE__);
        return 0;
    }

    # search volume ID again after realiasing
    foreach my $volg (@files_org) {
      chomp($volg);
      $vols = $volg;
      $volg =~ s/ : .*//;
      if ( $volg =~ m/^$alias$/ ) {
        $vol_found++;
        last;
      }
    }
  }
  if ( $vol_found == 0 ) {
    error ("Could not find volume ID for $host:$lpar in $basedir/data/$host/VOLUME/volumes.cfg neither any alias in etc/alias.cfg ".__FILE__.":".__LINE__);
    return 0;
  }

  $vols =~ s/^.* : //; # it contains a list of volumes ID(s)
    
  my @vol_array = split(';', $vols);

  #print OUT "009 vols:$vols\n";
  foreach my $lpar_file (@vol_array) {
    $lpar_file =~ s/^0x//;
    $lpar_file =~ s/ //;

    if ( $lpar_file eq '' ) {
      next;
    }

    #print OUT "019 $basedir/data/$host/$type/$lpar_file.rrd  $lpar\n";
    # go every each volume for particular group

    my $file = "$basedir/data/$host/$type/$lpar_file.$suffix";
    if ( $st_type =~ m/XIV/ || $st_type =~ m/DS5K/ ) {
      # XIV volumes contain pool_id in their names: 00273763-P102932.rrd
      foreach my $file_xiv (<$wrkdir/$host/$type/$lpar_file-P*\.$suffix>) {
        $file = $file_xiv;
        last;
      }
    }

    if ( ! -f "$file" ) {
       error ("Could not find volume file: $file ".__FILE__.":".__LINE__);
       next;
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = (stat("$file"))[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }
    #print OUT "020 $basedir/data/$host/$type/$lpar_file.rrd  $lpar\n";
    my $lpar_space = $lpar;

    # add spaces to volume name to have 15 chars total (for formating graph legend)
    $lpar_space =~ s/\&\&1/\//g;
    if ( $st_type =~ m/^DS8K/ || $st_type =~ m/^SWIZ$/ ) {
      $lpar_space = sprintf ("%-38s","$lpar_space [$lpar_file]");
    }
    else {
      # DS5k has very long IDs and does not use multivolumes at all
      $lpar_space = sprintf ("%-38s","$lpar_space");
    }

    #print OUT "020 $basedir/data/$host/$type/$lpar_file.rrd  $lpar\n";
    # bulid RRDTool cmd
    $cmd .= " DEF:value${i}=\\\"$file\\\":$item:AVERAGE";
    $cmd .= " CDEF:valmb${i}=value${i},$val,/";
    $cmd .= " $gtype:valmb${i}$color[$col_indx]:\\\"$lpar_space\\\"";
    $cmd .= " PRINT:valmb${i}:AVERAGE:\\\"%8.1lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color[$col_indx]\\\"";
    $cmd .= " PRINT:valmb${i}:MAX:\\\" %8.1lf $delimiter\\\"";
    $col_indx++;
    if ( $col_indx > $color_max ) {
      $col_indx = 0;
    }

    $cmd .= " GPRINT:valmb${i}:AVERAGE:\\\"%8.1lf \\\"";
    $cmd .= " GPRINT:valmb${i}:MAX:\\\" %8.1lf \\\"";
    # --> it does not work ideally with newer RRDTOOL (1.2.30 --> it needs to be separated by cariage return here)
    if ( $item !~ m/resp_t/ && $item !~ m/cache_hit/ ) {
      if ( $st_type =~ m/^DS8K$/ ) {
        # only DS8K must be stacked due to multivolumes
        $gtype="STACK";
      }
    }
    $i++;
    $cmd .= " COMMENT:\\\"\\l\\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error ("$host : Multi graph rrdtool error : $$ret  ".__FILE__.":".__LINE__);
    return 0;
  }
  $png_end_heading = ret_graph_param($ret);
  return 1;
}

# error handling
sub error
{
  my $text = shift;
  my $act_time = localtime();
  my $basedir = $ENV{INPUTDIR};

  #print "ERROR          : $text : $!\n";
  #print STDERR "$act_time: $text : $!\n";
  print STDERR "$act_time: $host:$type:$name:$item:$detail: $text \n";


  print "\n"; # print missing enter to finish header HTTP

  # print error picture to check error-cgi.log or web error log
  open(PNG, "< $basedir/html/error.png") || error ("Cannot open  $basedir/html/error.png: $! ".__FILE__.":".__LINE__) && return 0;
  binmode(PNG);
  while (read(PNG,$b,4096)) {
    print "$b";
  }
  close (PNG);
}

sub create_graph_summ
{
  my $host = shift;     
  my $type = shift;     
  my $name = shift;     
  my $item = shift;     
  my $time = shift;     
  my $name_out = shift;     
  my $detail = shift;
  my $start_unix = shift;
  my $end_unix = shift;
  my $st_type = shift;
  my $text = "";
  my $updated = ""; #sending to clickable legend

  #print STDERR "create-graph-summ : $host,$type,$name,$item,$time,$name_out,$detail,$start_unix,$end_unix,$st_type\n";


  my $xgrid = xgrid_set($time,$detail);

  if ( $time !~ m/d/ ) {
    # slow down all graphs except of the daily one to let create the daily one as the first
    select(undef, undef, undef, 0.2);
  }

  my $tmp_file="$tmp_dir/$host/$type-$name-$time.cmd";

  my $rank_vol = "RANK";
  if ( $st_type =~ m/XIV/ || $st_type =~ m/DS5K/ ) {
    $rank_vol = "VOLUME";
  }

  #if ( $type =~ m/^POOL$/ || $type =~ m/^RANK$/ ) { 
  #  # For pools has to be changed pwd
  #  my $dir= "$basedir/data/$host/$rank_vol/";
  #  chdir $dir;
  #}

  #if ( $type =~ m/^POOL$/ || $st_type =~ m/^XIV$/ || $st_type =~ m/DS5K/ ) { 
  #  # For pools has to be changed pwd
  #  my $dir= "$basedir/data/$host/VOLUME/";
  #  chdir $dir;
  #}

  my $header = "";
  my $start_time = "now-1$time";
  my $end_time = "now-1$time+1$time";
  if ( ! $start_unix eq '' && ! $end_unix eq '' ) {
    if ( isdigit($start_unix) > 0 && isdigit($end_unix) > 0 ) {
      $start_time = $start_unix;
      $end_time = $end_unix;
      my $start_human = strftime "%H:%M:%S %d.%m.%Y",localtime($start_unix);
      my $end_human = strftime "%H:%M:%S %d.%m.%Y",localtime($end_unix);
      $header = "$start_human - $end_human";
      $text = "";
      $xgrid="--alt-y-grid";
      $font_def =  "--font=DEFAULT:10:";
      $font_tit =  "--font=TITLE:13:";
    }
  }

 # replace graph size and total value
  open(FH, "< $tmp_file") || error ("sum detail: $host:$type:$item:$time: Can't open $tmp_file ".__FILE__.":".__LINE__) && return 0;
  my @lines = <FH>;
  close (FH);

  my $title;
  if ($header != "") {
    (undef, $title) = split("--",$lines[0]);
    $title =~ s/last .*/$header\"/;
    $lines[0] =~ s/--title.*--start/--$title --start/; 
  }  

  my $lines_no = 0;
  my $cmd = "";

  foreach my $line (@lines) {

    if ( $line !~ m/DEF:/ ) {
      next; # some problem, probably no DEF input files
    }
    $lines_no = 1;

    # get last update of the first RRDTool file
    my ( $trash, $source_rrd) = split (/ DEF:/,$line);
    $source_rrd =~ s/:.*//g;
    $source_rrd =~ s/^.*=//g;
    my $last_update = rrd_last_update($source_rrd,$type,"$basedir/data/$host/$rank_vol/");
    if ( $last_update eq '' ) {
      $line =~ s/ COMMENT:\"Updated.* HRULE:/ HRULE:/;
    }
    else {
      $updated = "Updated $last_update";
      $last_update =~ s/:/\\:/g;
      my $test_res = $line =~ s/ COMMENT:\"Updated.* HRULE:/ COMMENT:\"Updated $last_update\" HRULE:/;
      if (!$test_res) { $updated = "" }; #no subs -> no Updated
    }

    $line =~ s/graph .* --title/$graph_cmd \"$name_out\" --title/;
    $line =~ s/--start now.*--imgformat/--start $start_time --end $end_time $no_legend --imgformat /;
    if ( $detail == 1 ) {
      $line =~ s/ --step=3600/ --step=$STEP /;
      $line =~ s/ --step=86400/ --step=$STEP /;
      $line =~ s/ --font=DEFAULT:[0-9]:/ /;
      $line =~ s/ --font=TITLE:[0-9]:/ /;
      #$line =~ s/Total                                                .*\\l\"/Total                                                $total\\l\"/;
      $line =~ s/ --width=400/ --width=$width $font_def_popup /;
      $line =~ s/ --height=150/ --height=$height $font_tit_popup /;
      $line =~ s/ --x-grid=.* --alt-y-grid/ $xgrid --alt-y-grid/;
      $line =~ s/ $delimiter +$st_type//g;
      $line =~ s/$delimiter//g;
    }
    if ( $detail == 2 ) {
      $line =~ s/ --font=DEFAULT:[0-9]:/ /;
      $line =~ s/ --font=TITLE:[0-9]:/ /;
      $line =~ s/ --width=400/ --width=$width $font_def_dashbo  /;
      $line =~ s/ --height=150/ --height=$height $font_tit_dashbo $no_legend /;
      $line =~ s/ : last / : /;
      $line =~ s/ last / /;
      $line =~ s/ aggregated / agg /;
      $line =~ s/ 4 weeks/ month/;
      $line =~ s/ --x-grid=.* --alt-y-grid/ $xgrid --alt-y-grid/;
      $line =~ s/ --vertical-label=.* --units-exponent/ --units-exponent /;
      $line =~ s/--title "POOL /--title "/;
      $line =~ s/--title "RANK /--title "/;
      $line =~ s/--title "PORT /--title "/;
      $line =~ s/--title "HOST /--title "/;
      $line =~ s/--title "MDISK /--title "/;
      $line =~ s/--title "DRIVE /--title "/;
      $line =~ s/--title "VOLUME /--title "/;
      $line =~ s/--title "CPU-NODE /--title "/;
      $line =~ s/ $delimiter +$st_type//g;
      $line =~ s/$delimiter//g;
    }
    #print STDERR "$line";
    $cmd = $line;
  }

  if ( $lines_no == 0 ) {
    error ("cmd file dos not contain data source files: $tmp_file ".__FILE__.":".__LINE__);
    return 0;
  }

  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error ("sum detail: Multi graph rrdtool error : $$ret  ".__FILE__.":".__LINE__);
    return 0;
  }
  $png_end_heading = ret_graph_param($ret, $updated);
  return 1;
}


  
sub create_graph_pool
{
  my $host = shift;     
  my $type = shift;     
  my $lpar = shift;     
  my $item = shift;     
  my $time = shift;     
  my $name_out = shift;     
  my $detail = shift;
  my $start_unix = shift;
  my $end_unix = shift;
  my $wrkdir = shift;
  my $act_time = shift;
  my $step = shift;
  my $st_type = shift;
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $act_time = localtime();
  my $act_time_u = time();
  my $req_time = 0;
  my $itemm = "";

  #print STDERR "$host,$type,$lpar,$item\n";

  my $value_short = "";
  my $value_long = "";
  my $val = 1;

  if ( $item =~ m/^data_rate$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read$/ )      { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read_b$/ )    { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write$/ )     { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write_b$/ )   { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^io_rate$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^read_io$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^read_io_b$/ ) { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io$/ )  { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io_b$/ ){ $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp_t$/ )    { $value_short= "ms"; $value_long = "mili seconds"; $val=1;}
  if ( $item =~ m/^resp_t_r$/ )  { $value_short= "ms"; $value_long = "mili seconds"; $val=1;}
  if ( $item =~ m/^resp_t_r_b$/ ){ $value_short= "ms"; $value_long = "mili seconds"; $val=1;}
  if ( $item =~ m/^resp_t_w$/ )  { $value_short= "ms"; $value_long = "mili seconds"; $val=1;}
  if ( $item =~ m/^resp_t_w_b$/ ){ $value_short= "ms"; $value_long = "mili seconds"; $val=1;}
  if ( $item =~ m/^tier0$/ )     { $value_short= "TB"; $value_long = "TBytes"; }
  if ( $item =~ m/^tier1$/ )     { $value_short= "TB"; $value_long = "TBytes"; }
  if ( $item =~ m/^tier2$/ )     { $value_short= "TB"; $value_long = "TBytes"; }
  if ( $item =~ m/^used$/ )      { $value_short= "TB"; $value_long = "TBytes"; }

  my $name_text = $name;

  if ( $st_type =~ m/^DS5K$/ || $st_type =~ m/^DS8K$/ ) {
     if ( $item =~ m/^read$/ || $item =~ m/^write$/ ) {
       $val = 1;
     }
  } 

  # POOL name translation --> from ID
  open(FHR, "< $wrkdir/$host/pool.cfg") || error ("Can't open $wrkdir/$host/pool.cfg : $! ".__FILE__.":".__LINE__) && return 0;
  my @lines_translate = <FHR>;
  close(FHR);
  my $pool_found = 0;
  foreach my $linep (@lines_translate) {
    chomp($linep);
    (my $id, my $name_pool) = split (/:/,$linep);
    #print STDERR "001 $id : $name : $name_pool : $lpar\n";
    if ( $name =~ m/^$id$/ ) {
      $name_text = $name_pool;
      $lpar = $id;
      $pool_found++;
      last;
    }
    if ( $name =~ m/^$name_pool$/ ) {
      $name_text = $name_pool;
      $lpar = $id;
      $pool_found++;
      last;
    }
  }
  if ( $pool_found == 0 ) {
    my $alias = alias ($type,$host,$lpar);
    if ( $alias eq '' ) {
        error ("Could not find pool ID for $host:$lpar in $basedir/data/$host/pool.cfg neither any alias in etc/alias.cfg ".__FILE__.":".__LINE__);
        return 0;
    }
    foreach my $linep (@lines_translate) {
      chomp($linep);
      (my $id, my $name_pool) = split (/:/,$linep);
      if ( $alias =~ m/^$id$/ ) {
        $name_text = $lpar;
        $name = $alias;
        $lpar = $id;
        $pool_found++;
        last;
      }
    }
  }
  if ( $pool_found == 0 ) {
    error ("Could not find pool ID for $host:$lpar in $basedir/data/$host/pool.cfg neither any alias in etc/alias.cfg ".__FILE__.":".__LINE__);
    return 0;
  }
  #print STDERR "002 name:$name name_text:$name_text lpar:$lpar\n";

  my $name_space = $name_text;
  $name_space = sprintf ("%-38s","$name_space");

  my $comment=$item," [".$value_short."]";
  $comment = sprintf ("%-10s","$comment");

  if ( $time =~ m/d/ ) { 
    $req_time = $act_time_u - 86400;
  }
  if ( $time =~ m/w/ ) { 
    $req_time = $act_time_u - 604800;
  }
  if ( $time =~ m/m/ ) { 
    $req_time = $act_time_u - 2764800;
  }
  if ( $time =~ m/y/ ) { 
    $req_time = $act_time_u - 31536000;
  }


  my $xgrid_all = xgrid_set($time,$detail);
  my $text = text_set($time);
  my $header = "$type : $name_text : $item last $text";
  if ( $detail == 2 ) {
    $header = "$name_text : $item $text";
  }

  my $start_time = "now-1$time";
  my $end_time = "now-1$time+1$time";
  if ( ! $start_unix eq '' && ! $end_unix eq '' ) {
    if ( isdigit($start_unix) > 0 && isdigit($end_unix) > 0 ) {
      # Historical report detected
      $start_time = $start_unix;
      $end_time = $end_unix;
      my $start_human = strftime "%H:%M:%S %d.%m.%Y",localtime($start_unix);
      my $end_human = strftime "%H:%M:%S %d.%m.%Y",localtime($end_unix);
      $header = "$type : $name_text : $item : $start_human - $end_human";
      $text = "";
      $xgrid_all= "--alt-y-grid";
      $font_def =  $font_def_hist;
      $font_tit =  $font_tit_hist;
    }
  }

  my $i = 0;
  my $j = 0;
  my $cmd = "";

  my $vertical_label="--vertical-label=\\\"$value_long\\\"";
  if ( $detail == 2 ) {
    $vertical_label="--interlaced";
    $no_legend = "--no-legend";
    # $vertical_label="COMMENT: "; --> no, no, some versions does not like comment wityhout anything
  }

  $cmd .= "$graph_cmd \\\"$name_out\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start \\\"$start_time\\\"";
  $cmd .= " --end \\\"$end_time\\\"";
  $cmd .= " --imgformat PNG";
  $cmd .= " --slope-mode";
  $cmd .= " --width=$width";
  $cmd .= " --height=$height";
  $cmd .= " --step=$step";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $vertical_label";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " $no_legend";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " $xgrid_all";
  $cmd .= " $font_def";
  $cmd .= " $font_tit";
  $cmd .= " COMMENT:\\\"Pool   $comment                               Avg        Max\\l\\\"";


  my $gtype="LINE";
  my $col_indx = 0;
  my $line_indx = 0; # place enter evry 3rd line
  my $nothing_to_sum = 0;

  my $rank_vol = "RANK";
  if ( $st_type =~ m/XIV/ || $st_type =~ m/DS5K/ ) {
    $rank_vol = "VOLUME";
  }

  my $file_list = "$rank_vol/*-P$lpar\.rrd";
  if ( $item =~ m/tier/ ) {
    # due to tier capacity files : POOL/0-cap.rrd
    $file_list = "POOL/$lpar-cap\.rrd";
    $gtype="AREA";
  }

  if ( $st_type =~ m/^DS8K$/ || $st_type =~ m/^SWIZ/ ) {
    if ( $item =~ m/^io_rate$/ || $item =~ m/^data_rate$/ || $item =~ m/^read_io$/ || $item =~ m/^write_io$/ || $item =~ m/^read$/ || $item =~ m/^write$/ || $item =~ m/^resp_t_r$/ || $item =~ m/^resp_t_w$/ ) {
      # Front-end data are stored in POOL dir (based on Volume data) like POOL/0.rrd
      $file_list = "POOL/$lpar\.rrd";
    }
    else {
      # delete _b suffix, front-end data is in POOL dir and back-end in RANK, no any suffix is there
      $item =~ s/_b$//;
    }
  }

  my $time_first = find_real_data_start_pool("$basedir/data/$host/$rank_vol",$lpar);

  # following loop is copied from storage.pl : draw_graph_sum ()
  foreach my $line (<$basedir/data/$host/$file_list>) {
    chomp($line);
    # avoid old lpars which do not exist in the period
    # No no here, here it is detail which should always work, it do not save anything here ...
    #my $rrd_upd_time = (stat("$line"))[9];
    #if ( $rrd_upd_time < $req_time ) {
    #  next;
    #}
	
    $nothing_to_sum=0;

    my @link_l = split(/\//,$line);
    my $lpar = "";
    foreach my $m (@link_l) {
      $lpar = $m;
    }
    $lpar =~ s/\.rrd$//;
    $lpar =~ s/-P.*//; # filter pool info
    $lpar =~ s/PORT-//;
    $lpar =~ s/RANK-//;
    $lpar =~ s/VOLUME-//;
    $lpar =~ s/0x//;
    $lpar =~ s/-cap//;

    my $lpar_space = $lpar;

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $lpar_space = sprintf ("%-8s","$lpar_space");

    # bulid RRDTool cmd
    $itemm = $item."m";

    if ( $item =~ m/sum_io/ || $item =~ m/^io_rate$/ ) {
      if ( $st_type =~ m/^DS5K$/ ) {
        $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":io_rate:AVERAGE";
        $cmd .= " CDEF:$item${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,UNKN,$item${i}_r_u,IF,IF";
        $cmd .= " CDEF:$itemm${i}_r=$item${i}_r,$val,/"; # convert into MB if necessary, normaly is there 1
      }
      else {
        $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":read_io:AVERAGE";
        $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":write_io:AVERAGE";
        # when UNKNOWN then place 0 --> there can be some old RANK datafiles without actual data then --> NaN in the GUI
        #$cmd .= " CDEF:$item${i}_r=$item${i}_r_u,UN,0,$item${i}_r_u,IF";
        #$cmd .= " CDEF:$item${i}_w=$item${i}_w_u,UN,0,$item${i}_w_u,IF";
        $cmd .= " CDEF:$item${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,UNKN,$item${i}_r_u,IF,IF";
        $cmd .= " CDEF:$item${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,UNKN,$item${i}_w_u,IF,IF";
        $cmd .= " CDEF:$itemm${i}_r=$item${i}_r,$val,/"; # convert into MB if necessary, normaly is there 1
        $cmd .= " CDEF:$itemm${i}_w=$item${i}_w,$val,/"; # convert into MB if necessary, normaly is there 1
      }
    }
    if ( $item =~ m/sum_data/ || $item =~ m/^data_rate$/ ) {
      if ( $st_type =~ m/^DS5K$/ ) {
        $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":data_rate:AVERAGE";
        $cmd .= " CDEF:$item${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,UNKN,$item${i}_r_u,IF,IF";
        $cmd .= " CDEF:$itemm${i}_r=$item${i}_r,$val,/"; # convert into MB if necessary, normaly is there 1
      }
      else {
        $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":read:AVERAGE";
        $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":write:AVERAGE";
        # when UNKNOWN then place 0 --> there can be some old RANK datafiles without actual data then --> NaN in the GUI
        #$cmd .= " CDEF:$item${i}_r=$item${i}_r_u,UN,0,$item${i}_r_u,IF";
        #$cmd .= " CDEF:$item${i}_w=$item${i}_w_u,UN,0,$item${i}_w_u,IF";
        $cmd .= " CDEF:$item${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,UNKN,$item${i}_r_u,IF,IF";
        $cmd .= " CDEF:$item${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,UNKN,$item${i}_w_u,IF,IF";
        $cmd .= " CDEF:$itemm${i}_r=$item${i}_r,$val,/"; # convert into MB if necessary, normaly is there 1
        $cmd .= " CDEF:$itemm${i}_w=$item${i}_w,$val,/"; # convert into MB if necessary, normaly is there 1
      }
    }
    if ( $item !~ m/tier/ && $item !~ m/sum_cap/ && $item !~ m/sum_data/ && $item !~ m/sum_io/ && $item !~ m/^io_rate$/ && $item !~ m/^data_rate$/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":$item:AVERAGE";
      # when UNKNOWN then place 0 --> there can be some old RANK datafiles without actual data then --> NaN in the GUI
      #$cmd .= " CDEF:$item${i}_r=$item${i}_r_u,UN,0,$item${i}_r_u,IF";
      $cmd .= " CDEF:$item${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,UNKN,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_r=$item${i}_r,$val,/"; # convert into MB if necessary, normaly is there 1
    }
    if ( $item =~ m/tier0/ ) {
      $cmd .= " DEF:$item${i}_c_u=\\\"$line\\\":tier0cap:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":tier0free:AVERAGE";
      $cmd .= " CDEF:$item${i}_c=TIME,$time_first,LT,$item${i}_c_u,$item${i}_c_u,UN,UNKN,$item${i}_c_u,IF,IF";
      $cmd .= " CDEF:$item${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,UNKN,$item${i}_w_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_c=$item${i}_c,$val,/"; # convert into MB if necessary, normaly is there 1
      $cmd .= " CDEF:$itemm${i}_w=$item${i}_w,$val,/"; # convert into MB if necessary, normaly is there 1
      $cmd .= " CDEF:$itemm${i}_r=$item${i}_c,$item${i}_w,-";
    }
    if ( $item =~ m/tier1/ ) {
      $cmd .= " DEF:$item${i}_c_u=\\\"$line\\\":tier1cap:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":tier1free:AVERAGE";
      $cmd .= " CDEF:$item${i}_c=TIME,$time_first,LT,$item${i}_c_u,$item${i}_c_u,UN,UNKN,$item${i}_c_u,IF,IF";
      $cmd .= " CDEF:$item${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,UNKN,$item${i}_w_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_c=$item${i}_c,$val,/"; # convert into MB if necessary, normaly is there 1
      $cmd .= " CDEF:$itemm${i}_w=$item${i}_w,$val,/"; # convert into MB if necessary, normaly is there 1
      $cmd .= " CDEF:$itemm${i}_r=$item${i}_c,$item${i}_w,-";
    }
    if ( $item =~ m/tier2/ ) {
      $cmd .= " DEF:$item${i}_c_u=\\\"$line\\\":tier2cap:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":tier2free:AVERAGE";
      $cmd .= " CDEF:$item${i}_c=TIME,$time_first,LT,$item${i}_c_u,$item${i}_c_u,UN,UNKN,$item${i}_c_u,IF,IF";
      $cmd .= " CDEF:$item${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,UNKN,$item${i}_w_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_c=$item${i}_c,$val,/"; # convert into MB if necessary, normaly is there 1
      $cmd .= " CDEF:$itemm${i}_w=$item${i}_w,$val,/"; # convert into MB if necessary, normaly is there 1
      $cmd .= " CDEF:$itemm${i}_r=$item${i}_c,$item${i}_w,-";
    }
    $i++;
  }
  if ( $nothing_to_sum == 1) {
    # there is nothing to sum at the moment
    return 0;
  }

  my $zero = 0;
  if ( $item =~ m/tier/ || $item =~ m/sum_data/ || $item =~ m/sum_io/ || $item =~ m/^data_rate$/ || $item =~ m/^io_rate$/ ) {
    #
    # read
    #

    # Load all items into the $cmd
    my $index_actual = 1; # must be 1 here, othervise reuslt is 2x more
    $cmd .= " CDEF:rsum${i}=$itemm${zero}_r,0,+";
    for (; $index_actual < $i; $index_actual++) {
      $cmd .= ",$itemm${index_actual}_r,+";
    }
    my $text = "read";
    if ( $st_type =~ m/^DS5K$/ ) {
      $text = "Total"
    }
    my $item_col = "#4444FF";
    my $value = "%8.1lf";
    if ( $item =~ m/tier/ ) {
      $text = "Used";
      $item_col = "#FF3333";
      $value = "  %6.2lf";
    }
    my $name_space = sprintf ("%-38s","$text");
    $cmd .= " $gtype:rsum${i}$item_col:\\\"$name_space \\\"";
    $cmd .= " GPRINT:rsum${i}:AVERAGE:\\\"$value \\\"";
    $cmd .= " GPRINT:rsum${i}:MAX:\\\"$value \\l\\\"";
  
    #
    # write
    #
  
    if ( $st_type !~ m/^DS5K$/ ) {
      $index_actual = 1; # must be 1 here, othervise reuslt is 2x more
      $cmd .= " CDEF:wsum${i}=$itemm${zero}_w,0,+";
      for (; $index_actual < $i; $index_actual++) {
        $cmd .= ",$itemm${index_actual}_w,+";
      }
      my $item_col = "#00FF00";
      my $text = "write";
      my $value = "%8.1lf";
      if ( $item =~ m/tier/ ) {
        $text = "Free ";
        $gtype="STACK";
        $item_col = "#33FF33";
        $value = "  %6.2lf";
      }
      # print legend

      my $name_space = sprintf ("%-38s","$text");
      $cmd .= " $gtype:wsum${i}$item_col:\\\"$name_space \\\"";
      $cmd .= " GPRINT:wsum${i}:AVERAGE:\\\"$value \\\"";
      $cmd .= " GPRINT:wsum${i}:MAX:\\\"$value \\l\\\"";
    }
  }
  else {
    # usual stuff , 1 item
    # even this must be summed!! --> there is no dedicated stuff for pools, all is taken from RANK/MDISKs
    # must be summed except response time 

    # Load all items into the $cmd
    my $index_actual = 1; # must be 1 here, othervise reuslt is 2x the first item
    $cmd .= " CDEF:rsum${i}=$itemm${zero}_r,0,+";
    for (; $index_actual < $i; $index_actual++) {
      $cmd .= ",$itemm${index_actual}_r,+";
    }

    if ( $item =~ m/^resp/ ) {
      if ( $index_actual == 0 ) {
        error ("No pool data found : $host,$type,$lpar,$item ".__FILE__.":".__LINE__);
        return 0;
      }
      $cmd .= ",$index_actual,/";
    }
    
    my $name_space = sprintf ("%-38s","$item");
    $cmd .= " $gtype:rsum${i}#4444FF:\\\"$name_space \\\"";
    $cmd .= " GPRINT:rsum${i}:AVERAGE:\\\"%8.1lf \\\"";
    $cmd .= " GPRINT:rsum${i}:MAX:\\\"%8.1lf \\l\\\"";
  }
  
  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error ("POOL: Multi graph rrdtool error : $$ret  ".__FILE__.":".__LINE__);
    return 0;
  }
  $png_end_heading = ret_graph_param($ret);
  return 1;
}

sub rrd_last_update
{
  my $rrd_file = shift;
  my $type = shift;
  my $full_path = shift;
  my $last_time = "";

  $rrd_file =~ s/^"//;
  $rrd_file =~ s/"$//;

  # must be full path, relative path somehow does not work (perhaps rrdtool is already started in some dira which cannot be changed)
  my $rrd_file_full = $full_path.$rrd_file;
  
  if ( ! -f $rrd_file_full ) {
    if ( ! -f $rrd_file ) {
      # some problem, ignore it and do not display last update
      # error ("$rrd_file does not exist : cannot obtain the last update time ".__FILE__.":".__LINE__);
      # --> do not call error()!!!
      return "";
    }
    $rrd_file_full = $rrd_file;
  }

  RRDp::cmd qq(last $rrd_file_full);
  my $last_tt = RRDp::read;
  $last_time=localtime($$last_tt);
  #$last_time =~ s/:/\:/g;

  return $last_time;
}

sub isdigit
{
  my $digit = shift;
  my $text = shift;

  if ( $digit eq '' ) {
    return 0;
  }
  if ( $digit eq 'U' ) {
    return 1;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  if (length($digit_work) == 0) {
    # is a number
    return 1;
  }

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  return 0;
}


sub xgrid_set
{
  my $type = shift;
  my $detail = shift;
  my $xgrid = "--x-grid=";


  if ( $type =~ m/d/ ) {
    if ( $detail == 0 ) {
      $xgrid .= "MINUTE:60:HOUR:2:HOUR:4:0:%H";
    }
    if ( $detail == 1 ) {
      $xgrid .= "MINUTE:60:HOUR:1:HOUR:1:0:%H";
    }
    if ( $detail == 2 ) {
      # dashboard
      #$xgrid .= "MINUTE:60:HOUR:1:HOUR:1:0:%H";
      $xgrid .= "HOUR:6:DAY:1:HOUR:6:0:%H";
    }
  }
  if ( $type =~ m/w/ ) {
    if ( $detail == 0 ) {
      $xgrid .= "HOUR:8:DAY:1:DAY:1:0:%a";
    }
    if ( $detail == 1 ) {
      $xgrid .= "HOUR:12:HOUR:6:HOUR:12:0:%a-%H";
    }
    if ( $detail == 2 ) {
      # dashboard
      $xgrid .= "DAY:1:DAY:7:DAY:1:0:%d";
    }
  }
  if ( $type =~ m/m/ ) {
    if ( $detail == 0 ) {
      $xgrid .= "DAY:1:DAY:2:DAY:2:0:%d";
    }
    if ( $detail == 1 ) {
      $xgrid .= "HOUR:12:DAY:1:DAY:1:0:%d";
    }
    if ( $detail == 2 ) {
      # dashboard
      $xgrid .= "DAY:7:MONTH:1:DAY:7:0:%d";
    }
  }
  if ( $type =~ m/y/ ) {
    if ( $detail == 0 ) {
      $xgrid .= "MONTH:1:MONTH:1:MONTH:1:0:%b";
    }
    if ( $detail == 1 ) {
      $xgrid .= "MONTH:1:MONTH:1:MONTH:1:0:%b";
    }
    if ( $detail == 2 ) {
      # dashboard
      $xgrid .= "MONTH:4:MONTH:12:MONTH:4:0:%b";
    }
  }

  return $xgrid;
}

sub text_set
{
  my $type = shift;
  my $text = "day";

  $text="day";
  if ( $type =~ m/w/ ) {
    $text="week";
  }
  if ( $type =~ m/m/ ) {
    $text="month";
  }
  if ( $type =~ m/y/ ) {
    $text="year";
  }
  return $text;
}

# search through aliases
sub alias 
{
  my $type = shift;
  my $host = shift;
  my $lpar = shift;

  #print STDERR "001 $host:$host: - :$lpar\n";
  my $afile="$basedir/etc/alias.cfg";
  if ( -f $afile ) {
    open(FHA, "< $afile") || error ("File cannot be opened for read, wrong user rights?? : $afile ".__FILE__.":".__LINE__) && return "";
    my @alines = <FHA>;
    close (FHA);
    # VOLUME:DS05:AAA11:OracleVolume --> example
    foreach my $aline (@alines) {
       chomp ($aline);
       $aline =~ s/ *$//; # zrusit mezery za koncem aliasy kdyby tam nejake omylem byly
       if ( $aline =~ m/^$type:$host:.*:$lpar$/ ) {
         # alias has been found
         ( my $t1, my $t2, my $alias) = split(/:/,$aline);
         return "$alias";
       }
    }
  }

  return "";
}

sub ret_graph_param
{
# for graphv returns
#  "X-RRDGraph-Properties: $graph_left:$graph_top:$graph_width:$graph_height:$graph_start:$graph_end\n\n"
#  for graph returns
#  "\n"
# if exist print lines containing $delimiter -> prepares @table_out for clickable legend
# if defined second parameter > Updated time for LAN SAN1 SAN2 SEA & others for clickable legend

  my $answ = shift;
  my $updated = shift;

  if (! defined $updated) { # line Updated
    $updated = "";
  }

  my $graphv_line = ""; # end of HTML heading
  my $test_item = "graph_";
  my @rrd_result;
  if ($answ =~ /0x/) {
     @rrd_result = split('\n',$$answ)
  }
  else {
     @rrd_result = split('\n',$answ)
  }
    # print STDERR "\@rrd_result @rrd_result\n";

  for (@rrd_result) {s/\"//g};   # filtr
  for (@rrd_result) {s/print\[.*\] =//g};  #  remove 1st part of print line in newer rrd versions

  my @rrd_print = grep { /$delimiter/ } @rrd_result; #print lines for legend

  #  print STDERR "\nrrdprint @rrd_print";

  my @matches = grep { /^$test_item/ } @rrd_result;
  my $param_num = @matches;

  if ($param_num > 0 && $param_num != 6) {
    print STDERR "cmd graphv did not give 6 graph_ params, gave $param_num ".__FILE__.":".__LINE__."\n";
    # return $graphv_line;   # let it go on, 5 params is maybe enough so lets try
  }
  if ($param_num > 0) {
    $graphv_line = "X-RRDGraph-Properties: ";
    for (my $i = 0; $i < $param_num; $i++) {
      (undef, my $dimension) = split("=",$matches[$i]);
      $dimension *= 1;
      $graphv_line .= $dimension;
      if ($i != 5) {
        $graphv_line .= ":";
      }
    }
    $graphv_line .= "\n\n";
  }
  else {
    $graphv_line .= "\n";
  }

  # print STDERR "\$graphv_line $graphv_line\n";
 
#now prepare HTML table for clickable legend for pool, shared pool, hmctotals lpar

  if (@rrd_print < 1 ) {
    return "$graphv_line";
  }
  my $item_ret = "";
    # print STDERR join "\n", @rrd_print;
    # print STDERR "\n\$rrd_print[0] $rrd_print[0]\n";
  (undef, undef, my $item1_ret, my $item2_ret, undef) = split("$delimiter",$rrd_print[0]);
    # print STDERR "\$item1_ret $item1_ret \$item2_ret $item2_ret\n";

   # return "$graphv_line";
   # print STDERR "\$graphv_line $graphv_line\n";

  if (defined $item1_ret && $item1_ret ne "") {

# necessary to filter some none html legend pict
    if ($item1_ret =~ /Volume/ && $item2_ret !~ /sum/) { return "$graphv_line"; }
	if ($item1_ret =~ /HOST/) { return "$graphv_line"; } 
    if ($no_legend ne "--no-legend") { return "$graphv_line"; }

    my $line1 = "<table class=\"tablesorter tablegend\">
    <thead>
      <tr>
        <th>&nbsp;</th>
        <th class=\"sortable header toleft\">$item1_ret $item2_ret</th>
        <th class=\"sortable header\">Avg&nbsp;&nbsp;&nbsp;&nbsp;</th>
        <th class=\"sortable header\">Max&nbsp;&nbsp;&nbsp;&nbsp;</th>
      </tr>
    </thead>
    <tbody>";
    my $line2 = "    <tr>
        <td class=\"legsq\">xorux_lpar_color</td>
        <td class=\"clickabletd\">xorux_lpar_name</td>
        <td>xorux_lpar_avg</td>
        <td>xorux_lpar_max</td>
      </tr>";

    my $line4 = "</tbody><tfoot>";
	my @comments = grep { /XOR_COM/ } @rrd_result;
    while (my $print_line=shift(@comments)) {
      (undef, $print_line) = split("XOR_COM",$print_line);
	  $line4 .= "<tr><td colspan=\"7\" class=\"toleft\">$print_line</td></tr>";
	}
    if ($updated =~ "Updated") {
      $line4 .= "<tr><td colspan=\"7\" class=\"tdupdated toleft\">$updated</td></tr>";
    }
    $line4 .= "</table>\n";

    push  @table_out, $line1;
    while (my $print_line=shift(@rrd_print)) {
      my $line2_act = $line2;
      (my $average, my $lpar_space, undef, undef, undef, undef, my $color, my $rrd_file_all, my $st_type) = split(" $delimiter ",$print_line);
      $print_line = shift(@rrd_print);
      (my $max, undef) = split("$delimiter",$print_line);
      if (! defined $rrd_file_all) {    #if not in 1st line > try second
         (undef, $rrd_file_all,$st_type ) = split("$delimiter",$print_line);
      }
      $st_type  =~ s/ //g; # space might appear in RAN/MDISK somehow
      my @pathx = split ("/",$rrd_file_all);

      my $lpar_name_url = @pathx[@pathx - 1];
      my $hmc_t = @pathx[@pathx - 2];
      my $server_t = @pathx[@pathx - 3];

      my $lpar_space_show = $lpar_space;
      $lpar_space_show =~ s/&&1/\//g;

      # find the right path of lpar
      my $lpar_url = $lpar_space_show;
      if ($hmc_t eq "RANK") {
		 $lpar_url = @pathx[@pathx - 1]
	  };
      if ($rrd_file_all =~ /\/POOL\// && $st_type =~ "SWIZ") {
		# something like 'data/pmdsk1/POOL/1.rrd'
		$lpar_url = $lpar_name_url;
		$lpar_url =~ s/\.rrd//;
      } 
      if ($rrd_file_all =~ /\/VOLUME\//) {
        # something like 'data/DS05/VOLUME/0001.rrc'
		# for this case name is like 'CMOD11_HB :0001' or 'sfutOa01       '
		# just take the first part
		($lpar_url, undef) = split (':',$lpar_space); 
        #print STDERR "\$lpar_url $lpar_url\n";
      }
	  $lpar_url =~ s/\.rr.$//;
      $lpar_url =~ s/^\s+|\s+$//g;
      $lpar_url =~ s/ /\+/g;
      $lpar_url =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg; # PH: keep it is it is exactly!!!
      $lpar_url =~ s/\#/%23/g;
      my $item_url = "$lpar_url";
      my $query_lpar = "<a href=\"/stor2rrd-cgi/detail.sh?host=$server_t&type=$hmc_t&name=$lpar_url&storage=$st_type&item=$item_url&gui=1&none=none\">$lpar_space_show</a>";

      #lowest level is not clickable
      # when $rrd_file_all == " " then no clickable legend is expected (DS5K and Controller graphs)
      #   --> sometimes there are more spaces 
      if ($hmc_t eq '' || $rrd_file_all eq '' || $rrd_file_all =~ m/^ *$/ ) { 
		$line2_act =~ s/clickabletd/toleft/;
		$query_lpar = "$lpar_space_show";
	  }
      $line2_act =~ s/xorux_lpar_avg/$average/;
      $line2_act =~ s/xorux_lpar_max/$max/;
      $line2_act =~ s/xorux_lpar_name/$query_lpar/;
      $line2_act =~ s/xorux_lpar_color/$color/;
      push  @table_out, $line2_act;
    }
    # print STDERR "print updated $line4\n";
    push @table_out, $line4;
    return $graphv_line;
  }

  error ("sub ret_graph_param - not recognised item : $item1_ret ".__FILE__.":".__LINE__);
  #print STDERR "??? @table_out\n";

}

# find list of vols for HOST
sub find_vols 
{
  my $host = shift;
  my $type = shift;
  my $lpar = shift;

  if ( ! -f "$wrkdir/$host/$type/hosts.cfg" ) {
    return "";
  }
  open(FHH, "< $wrkdir/$host/$type/hosts.cfg") || error ("Can't open $wrkdir/$host/$type/hosts.cfg : $! ".__FILE__.":".__LINE__) && return ""; 
  my @hosts = <FHH>;
  close(FHH);

  foreach my $line (@hosts) {
    chomp ($line);
    (my $host, my $volumes ) = split (/ : /,$line);

    # must be used this no regex construction otherwise m// does not work with names with ()
    if ( $host eq $lpar ) {
      return $volumes;
    }
  }
  return "";
}


sub draw_graph_host_volume {
  my $host = shift;     
  my $type = shift;     
  my $lpar = shift;     
  my $item = shift;     
  my $time = shift;     
  my $name_out = shift;     
  my $detail = shift;
  my $start_unix = shift;
  my $end_unix = shift;
  my $wrkdir = shift;
  my $act_time = shift;
  my $step = shift; # for volumes must be step correct due to DS8K and read/write stored in GAUGE instead of ABSOLUTE
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $act_time = localtime();
  my $act_time_u = time();
  my $req_time = 0;
  my $itemm = "";

  my $vols_list_line = find_vols ($host,$type,$lpar);
  if ( $vols_list_line eq '' ) {
    # something wrong as it should not come here through detail-cgi.pl when there is no volumes assigned
    error ("$host:$type: no volumes detected ".__FILE__.":".__LINE__);
    return 0;
  }
  my @vols_list = split(/ +/,$vols_list_line);

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$wrkdir/$host/VOLUME/volumes.col" ) {
    open(FHC, "< $wrkdir/$host/VOLUME/volumes.col") || error ("file does not exists : $wrkdir/$host/VOLUME/volumes.col ".__FILE__.":".__LINE__) && return 0;
    @color_save = <FHC>;
    close (FHC);
  }

  my $req_time = "";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;

  my $color_indx = 0; # reset colour index
  my $value_short = "";
  my $value_long = "";
  my $val = 1;
  my $suffix = "rrd";

  # do not use switch statement
  if ( $item =~ m/^data_rate$/ )     { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read$/ )          { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write$/ )         { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^io_rate$/ )       { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^read_io$/ )       { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io$/ )      { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp_t$/ )        { $value_short= "ms"; $value_long = "mili seconds"; }
  if ( $item =~ m/^resp_t_r$/ )      { $value_short= "ms"; $value_long = "mili seconds"; }
  if ( $item =~ m/^resp_t_w$/ )      { $value_short= "ms"; $value_long = "mili seconds"; }
  if ( $item =~ m/^r_cache_hit$/ )   { $value_short= "%%"; $value_long = "percent"; }
  if ( $item =~ m/^w_cache_hit$/ )   { $value_short= "%%"; $value_long = "percent"; }
  if ( $item =~ m/^r_cache_usage$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val=1024; }
  if ( $item =~ m/^w_cache_usage$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val=1024; }
  if ( $item =~ m/^read_b$/ )        { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write_b$/ )       { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read_io_b$/ )     { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io_b$/ )    { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp_t_r_b$/ )    { $value_short= "ms"; $value_long = "mili seconds"; }
  if ( $item =~ m/^resp_t_w_b$/ )    { $value_short= "ms"; $value_long = "mili seconds"; }
  if ( $item =~ m/^read_pct$/ )      { $value_short= "%%"; $value_long = "percent"; }

  if ( $st_type =~ m/^DS8K$/ && ( $type =~ /VOLUME/ || $type =~ /HOST/ ) ) {
    if ( $item =~ m/^resp_t_r$/ || $item =~ m/^resp_t_w$/ || $item =~ m/^r_cache_usage$/ || $item =~ m/^r_cache_hit$/ ||
         $item =~ m/^w_cache_hit$/ || $item =~ m/^w_cache_usage$/ || $item =~ m/^read_io$/ || $item =~ m/^write_io$/  ||
         $item =~ m/^read_io_b$/ || $item =~ m/^write_io_b$/ || $item =~ m/^read_b$/ || $item =~ m/^write_b$/ ||
         $item =~ m/^resp_t_r_b$/ || $item =~ m/^resp_t_w_b$/ ) {
      # those are stored in .rrc files
      $suffix = "rrc";
    }
  }
  if ( $st_type =~ m/^SWIZ$/ && ( $type =~ /VOLUME/ || $type =~ /HOST/ ) ) {
    if ( $item =~ m/^r_cache_usage$/ || $item =~ m/^r_cache_hit$/ || $item =~ m/^w_cache_hit$/ || $item =~ m/^w_cache_usage$/  ||
         $item =~ m/^total_usage$/ || $item =~ m/^res1$/ || $item =~ m/^res2$/  ) {
      # those are stored in .rrc files
      $suffix = "rrc";
    }
  }

  if ( $st_type =~ m/^DS8K$/ && ( $type =~ /VOLUME/ || $type =~ /HOST/ ) ) { #
    if ( $item =~ m/^read$/ || $item =~ m/^write$/ ) {
      # data is stored in wrong RRDTool type (GAUGE instead of ABSOLUTE)
      # this do data conversion
      $val = $step; # do not use $val=1024
    }
  }

  my $xgrid_all = xgrid_set($time,$detail);
  my $text = text_set($time);
  my $header = "$type : $name : $item last $text";
  if ( $detail == 2 ) {
    $header = "$name : $item $text";
  }

  my $start_time = "now-1$time";
  my $end_time = "now-1$time+1$time";
  if ( ! $start_unix eq '' && ! $end_unix eq '' ) {
    if ( isdigit($start_unix) > 0 && isdigit($end_unix) > 0 ) {
      # Historical report detected
      $start_time = $start_unix;
      $end_time = $end_unix;
      #$xgrid ="COMMENT: "; # just a trick to place there something otherwise rrdtool complains
      my $start_human = strftime "%H:%M:%S %d.%m.%Y",localtime($start_unix);
      my $end_human = strftime "%H:%M:%S %d.%m.%Y",localtime($end_unix);
      $header = "$type : $name : $item : $start_human - $end_human";
      $text = "";
      $xgrid_all= "--alt-y-grid";
      $font_def = $font_def_hist;  
      $font_tit = $font_tit_hist;  
      $req_time = $start_unix;
    }
  }

  if ($rrd_legend eq "table" && $detail < 1) {
    $no_legend = "--no-legend";
  }	  
  my $vertical_label="--vertical-label=\\\"$value_long\\\"";
  if ( $detail == 2 ) {
    $vertical_label="--interlaced";
    $no_legend = "--no-legend";
  }

  $cmd .= "$graph_cmd \\\"$name_out\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start \\\"$start_time\\\"";
  $cmd .= " --end \\\"$end_time\\\"";
  $cmd .= " --imgformat PNG";
  $cmd .= " --slope-mode";
  $cmd .= " --width=$width";
  $cmd .= " --height=$height";
  $cmd .= " --step=$step";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $vertical_label";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " $no_legend";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " $xgrid_all";
  $cmd .= " $font_def";
  $cmd .= " $font_tit";
  $cmd .= " --alt-y-grid";

    
  # print STDERR "001 $st_type,$type,$item,$suffix,$no_legend,\n";


  # add spaces to lpar name (for formating graph legend)
  my $item_short = $item;
  $item_short =~ s/r_cache_//;
  $item_short =~ s/w_cache_//;
  my $legend = sprintf ("%-38s","$item_short [$value_short]");
  $cmd .= " COMMENT:\\\"$legend        Avg       Max                                                Avg       Max\\l\\\"";

  my $legend_heading = "$item_short [$value_short] $delimiter  $delimiter Avg $delimiter Max ";

  my $gtype="AREA";
  if ( $item =~ m/resp_t/ || $item =~ m/cache_hit/ || $item =~ m/^read_pct$/ ) {
    $gtype="LINE1";
  }

  my $lpar_list = "";
  my $lpar_list_tmp = "";

  open(FHR, "< $wrkdir/$host/VOLUME/volumes.cfg") || error ("file does not exists : $wrkdir/$host/VOLUME/volumes.cfg ".__FILE__.":".__LINE__) && return 0;
  my @volumes = <FHR>;
  close (FHR);

  my $itemm = "";
  my $lpar_space = "";
  my $once = 0;
  my $last_time = "na";
  my $indx = 0;

  #print STDERR "$wrkdir/$host/VOLUME/*\.$suffix \n";
  foreach my $vol_file (<$wrkdir/$host/VOLUME/*\.$suffix>) {
    chomp($vol_file);

    my $vol_id = basename($vol_file);
    $vol_id =~ s/\.rrd$//;
    $vol_id =~ s/\.rrc$//;
    $vol_id =~ s/\-P.*$//; # vyhodit POOL ID

    # check if the volume is on the host list
    my $found_vol = 0;
    my $vol_id_cmp = $vol_id; #filter our perfixed zeros for SVC, DS8k use hexa
    $vol_id_cmp =~ s/^0*//;
    foreach my $vol_host (@vols_list) {
      chomp ($vol_host);
      $vol_host =~ s/^0x//; # cut off hexa prefix for DS8k
      $vol_host =~ s/ //g; 
      $vol_host =~ s/^0*//;
      if ( $vol_host =~ m/^$vol_id_cmp$/ ) {
        $found_vol = 1;
        last;
      }
    }
    if ( $found_vol == 0 ) {
      next; # the volume is not allocated for this host
    }
    
    my $vol_name = find_vol_name($vol_id,$st_type,\@volumes); 
    my $itemm = $item."m".$vol_id;

    if ( $once == 0 ) {
      # find out time stamp of last data update
      # take just one volume to keep it simple
      $once++; 
      RRDp::cmd qq(last "$vol_file");
      my $last_tt = RRDp::read;
      $last_time=localtime($$last_tt);
      $last_time =~ s/:/\\:/g;
    }


    # bulid RRDTool cmd
  
    # add spaces to lpar name to have 18 chars total (for formating graph legend)
    $lpar_space = sprintf ("%-38s","$vol_name");

    $cmd .= " DEF:$item${indx}=\\\"$vol_file\\\":$item:AVERAGE";
    $cmd .= " CDEF:$itemm${indx}=$item${indx},$val,/"; # convert into MB if necessary, normaly is there 1
    $cmd .= " $gtype:$itemm${indx}$color[$color_indx]:\\\"$lpar_space\\\"";

    $cmd .= " PRINT:$itemm${indx}:AVERAGE:\\\"%8.1lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd .= " PRINT:$itemm${indx}:MAX:\\\" %8.1lf $delimiter $vol_file\\\"";

    if ( $item !~ m/resp_t/ && $item !~ m/cache_hit/ && $item !~ m/^read_pct$/ ) {
      $gtype="STACK";
    }
  
    # put carriage return after each second lpar in the legend
    if ($j == 1) {
      if ( $item =~ m/io_rate/   ||  $item =~ m/read_io/ ||  $item =~ m/write_io/ ) {
        $cmd .= " GPRINT:$itemm${indx}:AVERAGE:\\\"%6.0lf \\\"";
        $cmd .= " GPRINT:$itemm${indx}:MAX:\\\"%6.0lf \\l\\\"";
      }
      else {
        $cmd .= " GPRINT:$itemm${indx}:AVERAGE:\\\"%6.1lf \\\"";
        $cmd .= " GPRINT:$itemm${indx}:MAX:\\\"%6.1lf \\l\\\"";
      }
      $j = 0;
    }
    else {
      if ( $item =~ m/io_rate/   ||  $item =~ m/read_io/ ||  $item =~ m/write_io/ ) {
        $cmd .= " GPRINT:$itemm${indx}:AVERAGE:\\\"%6.0lf \\\"";
        $cmd .= " GPRINT:$itemm${indx}:MAX:\\\"%6.0lf \\\"";
      }
      else {
        $cmd .= " GPRINT:$itemm${indx}:AVERAGE:\\\"%6.1lf \\\"";
        $cmd .= " GPRINT:$itemm${indx}:MAX:\\\"%6.1lf \\\"";
      }
      $j++
    }
    $color_indx++;
    if ($color_indx > $color_max ) {
      $color_indx = 0;
    }
    $indx++;
  }
  if ( $indx == 0 ) {
    # no volume has been found
    error ("No volume has been found ".__FILE__.":".__LINE__);
    return 0;
  }

  if ($j == 1) {
    $cmd .= " COMMENT:\\\"\\l\\\"";
  }

  if ( $time =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  #my $c = $cmd;
  #$c =~ s/         /\n/g;
  #print STDERR "$c\n";
  
  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error ("$host : Multi graph rrdtool error : $$ret  ".__FILE__.":".__LINE__);
    return 0;
  }
  $png_end_heading = ret_graph_param($ret);
  return 1;
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

sub find_vol_name
{
  my ($vol_id,$st_type,$volumes_tmp) = @_;
  my @volumes = @{$volumes_tmp};

  foreach my $volg (@volumes) {
    chomp($volg);
    (my $name, my $id) = split (/ : /,$volg) ;
    $name =~ s/ *$//;
    if ( $st_type =~ m/DS8K/ ) {
      #CMAL11 : 0x8008;0x8009;0x800A;0x800B;0x8014;0x8015;0x8108;0x8109;0x810A;0x810B;0x8114;0x8115;
      if ( $id =~ m/0x$vol_id;/ ) {
        return "$name \\:$vol_id";
      }
    }
    else {
      #CMAL11 : 0x8008;
      #storwize: BBpr : 0012;0023; 
      $id =~ s/ //g;
      if ( $id eq $vol_id || $id =~ m/^$vol_id;/ || $id =~ m/;$vol_id;/ || $id =~ m/;$vol_id$/ ) {
        # volume ID are HEXa, not digits!
        return $name;
      }
    }
  }

  return $vol_id;
}

# it finds out or create a file with first data stapm in all rank files of given pool
# it is necessary to know it as since that time is used 0 instead on NaN in rrdtool cmd
sub find_real_data_start_pool
{
  my $rank_dir = shift;
  my $pool_id = shift;
  if ( isdigit ($pool_id) == 1 ) {
    # only for decimals, XIV can use hexa
    $pool_id = $pool_id + 1 - 1; # trick to convert it into a number (it is "0001" here for example
  }
  my $rrd_pool_first = "$rank_dir/P$pool_id.first_pool";
  my $time_first_def = 2000000000; # just place here something hig engouh, higherb than actual unix time in seconds
  my $time_first = $time_first_def;

  if ( -f $rrd_pool_first ) {
    # read real last time of the record in rrdtool from the file (refresh every day)
    open(FHF, "< $rrd_pool_first") || error ("Can't open $rrd_pool_first : $! ".__FILE__.":".__LINE__);
    foreach my $line_frst (<FHF>)  {
      chomp($line_frst);
      if ( isdigit($line_frst) ) {
        $time_first = $line_frst;
        last;
      }
    }
    close (FHF);
  }
  #else {
  #  error ("Pool first time file has not been found: $rrd_pool_first ".__FILE__.":".__LINE__);
  #}
  if ( $time_first  < $time_first_def ) {
    return $time_first;
  }
  else {
    #error ("Pool first time has not been found in : $rrd_pool_first ".__FILE__.":".__LINE__);
    return 1; # something is wrong, "1" causes ignoring followed rrdtool construction
  }
}


# prints out the Top tables
sub volumes_top 
{
  my $host = shift;
  my $type = shift;
  my $name = shift;
  my $item = shift;
  my $time = shift;
  my $st_type = shift;
  my $in_file = "$tmp_dir/$host/$type-$name-$time.cmd";
  my $file_cmd_max = "/var/tmp/stor2rrd-$type-$name-max-$time.cmd";
  my @item_list = ("read","write","read_io","write_io","resp_t_r","resp_t_w","r_cache_hit","w_cache_hit");
  if ( $st_type =~ m/DS5K/ && -f "$wrkdir/$host/DS5K-v1" ) {
    @item_list = ("io_rate","data_rate","cache_hit");
  }
  if ( $st_type =~ m/DS5K/ && -f "$wrkdir/$host/DS5K-v2" ) {
    @item_list = ("io_rate","data_rate","resp_t","r_cache_hit","w_cache_hit","ssd_r_cache_hit");
  }


  print "<br><center>\n";
  if ( ! -f $in_file ) {
    error ("$host:VOLUME:top:$item - no cmd file:$in_file ".__FILE__.":".__LINE__) if ($DEBUG);
    return 0;
  }

  my $width = 288; # to get 5 minute per a pixel
  if ( $item =~ m/^d/ ) {
    print "last day<br>\n";
  }
  if ( $time =~ m/^w/ ) {
    print "last week without last day<br>\n";
    $width = 1728; # to get 5 minute per a pixel, 6d
  }
  if ( $time =~ m/^m/ ) {
    print "last month without last week<br>\n";
    $width = 6912; # to get 5 minute per a pixel, 24d
  }
  if ( $time =~ m/^y/ ) {
    print "last year without last month<br>\n";
    $width = 97056; # to get 5 minute per a pixel, 337d
  }

  if ( $st_type =~ m/SWIZ/ || $st_type =~ m/DS8K/ ) {
    print "<table class=\"lparsearch tablesorter\"><thead><tr> \n
         <th class=\"sortable\" align=\"center\" valign=\"top\">&nbsp;&nbsp;&nbsp;Volume&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;read&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>MB/sec</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;write&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>MB/sec</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;IO&nbsp;read&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>IOps</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;IO&nbsp;write&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>IOps</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;resp&nbsp;t&nbsp;r&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>ms</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;resp&nbsp;t&nbsp;w&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>ms</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;r&nbsp;cache&nbsp;hit&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>%</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;w&nbsp;cache&nbsp;hit&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>%</span>&nbsp;&nbsp;&nbsp;</th> \n
         </tr></thead><tbody>\n";
  }
  if ( $st_type =~ m/XIV/ ) {
    print "<table class=\"lparsearch tablesorter\"><thead><tr> \n
         <th class=\"sortable\" align=\"center\" valign=\"top\">&nbsp;&nbsp;&nbsp;Volume&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;read&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>MB/sec</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;write&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>MB/sec</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;IO&nbsp;read&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>IOps</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;IO&nbsp;write&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>IOps</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;resp&nbsp;t&nbsp;r&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>ms</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;resp&nbsp;t&nbsp;w&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>ms</span>&nbsp;&nbsp;&nbsp;</th> \n
         </tr></thead><tbody>\n";
  }
  if ( $st_type =~ m/DS5K/ && -f "$wrkdir/$host/DS5K-v1" ) {
    print "<table class=\"lparsearch tablesorter\"><thead><tr> \n
         <th class=\"sortable\" align=\"center\" valign=\"top\">&nbsp;&nbsp;&nbsp;Volume&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;io&nbsp;rate&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>IOps</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;data&nbsp;rate&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>MB/sec</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;cache&nbsp;hit&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>%</span>&nbsp;&nbsp;&nbsp;</th> \n
         </tr></thead><tbody>\n";
  }
  if ( $st_type =~ m/DS5K/ && -f "$wrkdir/$host/DS5K-v2" ) {
    print "<table class=\"lparsearch tablesorter\"><thead><tr> \n
         <th class=\"sortable\" align=\"center\" valign=\"top\">&nbsp;&nbsp;&nbsp;Volume&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;IO&nbsp;rate&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>IOps</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;data&nbsp;rate&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>MB/sec</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;resp&nbsp;time&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>ms</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;r&nbsp;cache&nbsp;hit&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>%</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;w&nbsp;cache&nbsp;hit&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>%</span>&nbsp;&nbsp;&nbsp;</th> \n
         <th class=\"sortable\" align=\"center\">&nbsp;&nbsp;&nbsp;SSD&nbsp;read&nbsp;cache&nbsp;hit&nbsp;&nbsp;&nbsp;<br>&nbsp;&nbsp;&nbsp;<span>%</span>&nbsp;&nbsp;&nbsp;</th> \n
         </tr></thead><tbody>\n";
  }


  if ( $item =~ m/max/ ) {
    # For printing peaks (MAX)
    open(FHR, "< $in_file") || error ("Can't open $in_file : $! ".__FILE__.":".__LINE__) && return 0;
    my @lines = <FHR>;
    close(FHR);
    open(FHW, "> $file_cmd_max") || error ("Can't open $file_cmd_max : $! ".__FILE__.":".__LINE__) && return 0;
    #binmode(FHW);

    foreach my $line (@lines) {
      $line =~ s/:AVERAGE:/:MAX:/g;
      $line =~ s/ --width=.* --height=/ --width=$width --height=/;
      $line =~ s/ --step=.* --units-exponent=/ --step=300 --units-exponent=/; # just to be sure ...
      print FHW "$line";
    }
    close(FHW);
    $in_file = $file_cmd_max;
  }


  open(FH, "< $in_file") || error("VOLUME: Can't open $in_file : $!".__FILE__.":".__LINE__) && return 0;
  my @lines = <FH>;
  close (FH);
  my $cmd = "";
  foreach my $line (@lines) {
    $cmd = $line;
    last;
  }
  if ( $cmd eq ''  ) {
    error ("$host : Multi graph rrdtool error $cmd ".__FILE__.":".__LINE__);
    return 0;
  }

  RRDp::cmd qq($cmd);
  my $ret = RRDp::read;
  if ( $$ret =~ "ERROR" ) {
    error ("$host : Multi graph rrdtool error : $$ret  ".__FILE__.":".__LINE__);
    return 0;
  }

  if ( $item =~ m/max/ ) {
    unlink ($in_file); # clean only temp files in /var/tmp
  }
  if ( $$ret =~ "ERROR" ) {
    if ( $$ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:VOLUME:$name:$item: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
      print "</tbody></table>";
    }
    else {
      error ("$host:VOLUME:$name:$item: Multi graph rrdtool error : $$ret ".__FILE__.":".__LINE__);
      print "</tbody></table>";
    }
  }

  # goes through all 4 files and create one outpud table with cache_hit
  my $volume_prev = "";
  (my @lines) = split(/====start /,$$ret);
  foreach my $line (@lines) {
    chomp ($line);
    if ( $line !~ m/^==== / ) {
      next;
    }

    $line =~ s/^==== / /g;
    $line =~ s/^ *//g;
    (my $volume, my $item, my $value) = split (/ +/,$line);
    $value =~ s/OK.*//g; #last one
    $value =~ s/ //g;
    chomp($value); # last one record has en enter at the end
    $volume =~ s/=====space=====/ /g;
    #print "001 --$line: $volume:$item:$value <br>";
    if ( ! defined ($value) || $value eq '' || $volume =~ m/^$/ ) {
      next;
    }

    if ($volume_prev eq '' || $volume_prev !~ m/^$volume$/ ) {
      if (! $volume_prev eq '' ) {
        print "</tr>\n";
      }
      print "<tr><td><a href=\"/stor2rrd-cgi/detail.sh?host=$host&type=VOLUME&name=$volume&storage=$st_type&none=none\">$volume</a></td>\n";
      $volume_prev = $volume;
    }
    print "<td align=\"right\">$value&nbsp;&nbsp;&nbsp;</td>";
  }

  print "</tr></tbody></table>\n";
  print "</center>\n";
  return 0; # must be 0 to do not issue print_png
}

sub encode_base64
{
     if ($] >= 5.006) {
       require bytes;
       if (bytes::length($_[0]) > length($_[0]) ||
         ($] >= 5.008 && $_[0] =~ /[^\0-\xFF]/))
       {
       require Carp;
       Carp::croak("The Base64 encoding is only defined for bytes");
       }
     }

     use integer;

     my $eol = $_[1];
     $eol = "\n" unless defined $eol;

     my $res = pack("u", $_[0]);
     # Remove first character of each line, remove newlines
     $res =~ s/^.//mg;
     $res =~ s/\n//g;

     $res =~ tr|` -_|AA-Za-z0-9+/|;               # `# help emacs
     # fix padding at the end
     my $padding = (3 - length($_[0]) % 3) % 3;
     $res =~ s/.{$padding}$/'=' x $padding/e if $padding;
     # break encoded string into lines of no more than 76 characters each
     if (length $eol) {
       $res =~ s/(.{1,76})/$1$eol/g;
     }
     return $res;
}

# if digit or hexa then true
sub ishexa
{
  my $digit = shift;

  if ( ! defined ($digit) || $digit eq '' ) {
    return 0;
  }

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  $digit_work =~ s/^-//;
  $digit_work =~ s/e//;
  $digit_work =~ s/\+//;
  $digit_work =~ s/\-//;

  # hexa filter
  $digit_work =~ s/[a|b|c|d|e|f|A|B|C|D|E|F]//g;

  if (length($digit_work) == 0) {
    # is a number
    return 1;
  }

  # NOT a number
  #main::error ("there was expected a digit but a string is there, field: , value: $digit");
  return 0;
}

