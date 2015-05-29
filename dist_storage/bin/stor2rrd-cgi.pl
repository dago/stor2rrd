use strict;
use Date::Parse;

my $DEBUG = $ENV{DEBUG};
my $errlog = $ENV{ERRLOG};
my $xport = $ENV{EXPORT_TO_CSV};
my $inputdir = $ENV{INPUTDIR};
my $tmp_dir = "$inputdir/tmp";
open(OUT, ">> $errlog")  if $DEBUG == 2 ;

# print HTML header
print "Content-type: text/html\n\n";

my $shour = "";
my $sday = "";
my $smon = "";
my $syear = "";
my $ehour = "";
my $eday = "";
my $emon = "";
my $eyear = "";
my $height = "";
my $width = "";
my $storage = "";
my @item_list = "";
my @port_row = "";
my @pool_row = "";
my @rank_row = "";
my @host_row = "";
my @volume_row = "";
my @out_item_list = "";


# First check whether POST or GET
my $r_method = $ENV{'REQUEST_METHOD'};
if ( $r_method eq '' ) {
  $r_method = "GET";
}
else {
 $r_method =~ tr/a-z/A-Z/;
}

if ( $r_method =~ m/POST/ )
{
  # POST is being used since 1.0 to avoid:
  #   Request-URI Too Large, and The requested URL's length exceeds the capacity limit for this server.

  my $buffer = "";
  my @pairs = "";
  my $pair = "";
  my $name = "";
  my $value = "";
  my %FORM = "";
  my $port_indx = 0;
  my $pool_indx = 0;
  my $rank_indx = 0;
  my $host_indx = 0;
  my $volume_indx = 0;
  my $out_item_indx = 0;
  read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});

  # Split information into name/value pairs
  @pairs = split(/&/, $buffer);

  foreach $pair (@pairs)
  {
    ($name, $value) = split(/=/, $pair);
    if ( $name =~ m/^POOL$/ ) {
      $pool_row[$pool_indx] = $value;
      $pool_indx++;
      next;
    }
    if ( $name =~ m/^PORT$/ ) {
      $port_row[$port_indx] = $value;
      $port_indx++;
      next;
    }
    if ( $name =~ m/^RANK$/ ) {
      $rank_row[$rank_indx] = $value;
      $rank_indx++;
      next;
    }
    if ( $name =~ m/^VOLUME$/ ) {
      $volume_row[$volume_indx] = $value;
      $volume_indx++;
      next;
    }
    if ( $name =~ m/^HOST$/ ) {
      $host_row[$host_indx] = $value;
      $host_indx++;
      next;
    }
    if ( $name =~ m/^output$/ ) {
      $out_item_list[$out_item_indx] = $value;
      $out_item_indx++;
      next;
    }
    # no URL decode here, as it goes immediately into URL again
    #$value =~ tr/+/ /;
    #$value =~ s/%(..)/pack("C", hex($1))/seg;
    $FORM{$name} = $value;
  }
  $smon = $FORM{"start-mon"};
  $sday = $FORM{"start-day"};
  $shour = $FORM{"start-hour"};
  $syear = $FORM{"start-yr"};
  $emon = $FORM{"end-mon"};
  $eday = $FORM{"end-day"};
  $ehour = $FORM{"end-hour"};
  $eyear = $FORM{"end-yr"};
  $height = $FORM{"HEIGHT"};
  $width = $FORM{"WIDTH"};
  $storage = $FORM{"storage"};
  #print STDERR "$shour, $sday, $smon, $syear, $ehour, $eday, $emon,$eyear, $height, $width, $storage, port_row[0]: $port_row[0]\n";
}
else {
  print STDERR "Bad FORM method was used: $r_method (POST should be)\n";
  print "Bad FORM method was used: $r_method (POST should be)\n";
  exit (1);
}

my $start=$syear.$smon.$sday;
my $end=$eyear.$emon.$eday;
my $human_start=$shour.":00:00 ".$sday.".".$smon.".".$syear;
my $human_end=$ehour.":00:00 ".$eday.".".$emon.".".$eyear;

my $start_unix = str2time($syear."-".$smon."-".$sday." ".$shour.":00:00");
my $end_unix = "";

# workaround for 24:00. If is used proper 00:00 of the next day then there are 2 extra records in cvs after the midnight
# looks like rrdtool issue
if ( $ehour == 24 ) {
  $end_unix = str2time($eyear."-".$emon."-".$eday." 23:59:00");
}
else {
  $end_unix = str2time($eyear."-".$emon."-".$eday." ".$ehour.":00:00");
}

my $l=length($start_unix);
print OUT "$human_start : $human_end : $start_unix : $end_unix : $l \n" if $DEBUG == 2 ;

if (length($start_unix) < 1) {
  print "<center><br>Start date (<B>$sday.$smon.$syear</B>) does not seem to be valid";
  print "</center>";
  exit (0);
}

if (length($end_unix) < 1) {
  print "<center><br>End date (<B>$eday.$emon.$eyear</B>) does not seem to be valid";
  print "</center>";
  exit (0);
}

if ($end_unix <= $start_unix) {
  print "<center><br>Start (<B>$human_start</B>) should be less than end (<B>$human_end</B>)";
  print "</center>";
  exit (0);
}


# create tab header
my @items_high = "POOL PORT RANK VOLUME";
my $tab_number = 0;
print "<div  id=\"tabs\"> <ul>\n";

# Pools
foreach my $item (<@pool_row>) {
    if ( $item eq '' ) {next;}
    my $data_type = "tabbackend";
    print "  <li class=\"$data_type\"><a href=\"#tabs-$tab_number\">Pools</a></li>\n";
    $tab_number++;
    last;
}

# Ports
foreach my $item (<@port_row>) {
    if ( $item eq '' ) {next;}
    my $data_type = "tabfrontend";
    print "  <li class=\"$data_type\"><a href=\"#tabs-$tab_number\">Ports</a></li>\n";
    $tab_number++;
    last;
}

# Ranks
foreach my $item (<@rank_row>) {
    if ( $item eq '' ) {next;}
    my $data_type = "tabbackend";
    print "  <li class=\"$data_type\"><a href=\"#tabs-$tab_number\">Ranks</a></li>\n";
    $tab_number++;
    last;
}

# Volumes
foreach my $item (<@volume_row>) {
    if ( $item eq '' ) {next;}
    my $data_type = "tabfrontend";
    print "  <li class=\"$data_type\"><a href=\"#tabs-$tab_number\">Volumes</a></li>\n";
    $tab_number++;
    last;
}
print "   </ul> \n";


# create individual tabs
$tab_number = 0;
foreach my $item (<@pool_row>) {
  if ( $item eq '' ) {next;}
  create_tab("POOL",$storage,$start_unix,$end_unix,$height,$width,$tab_number,\@pool_row,\@out_item_list);
  $tab_number++;
  last;
}
foreach my $item (<@port_row>) {
  if ( $item eq '' ) {next;}
  create_tab("PORT",$storage,$start_unix,$end_unix,$height,$width,$tab_number,\@port_row,\@out_item_list);
  $tab_number++;
  last;
}
foreach my $item (<@rank_row>) {
  if ( $item eq '' ) {next;}
  create_tab("RANK",$storage,$start_unix,$end_unix,$height,$width,$tab_number,\@rank_row,\@out_item_list);
  $tab_number++;
  last;
}
foreach my $item (<@volume_row>) {
  if ( $item eq '' ) {next;}
  create_tab("VOLUME",$storage,$start_unix,$end_unix,$height,$width,$tab_number,\@volume_row,\@out_item_list);
  $tab_number++;
  last;
}
print "</div>\n";

close(OUT)  if $DEBUG == 2;
exit (0);



sub create_tab
{
  my ($type,$storage,$start_unix,$end_unix,$height,$width,$tab_number,$name_tmp,$item_list_tmp) = @_;
  my @name_list  = @{$name_tmp};
  my @item_list  = @{$item_list_tmp};

  
  print "<div id=\"tabs-$tab_number\"><br><br><center>\n";
  print "<table align=\"center\" summary=\"Graphs $type\">";

  # loop per each selected item  
  foreach my $name (@name_list) {
    #print STDERR "000 $name $type\n";

    # loop per each selected metric 
    my $found = 0;
    foreach my $item (@item_list) {
  
      if ( $type =~ m/^RANK$/ && $item =~ m/^data_rate$/ ) {
        $item = "data";
      }
      if ( $type =~ m/^RANK$/ && $item =~ m/^io_rate$/ ) {
        $item   = "io";
      }
      if ( $type =~ m/^PORT$/ && $item =~ m/pprc/ ) {
        # not all ports have PPRC data files
        if ( ! -f "$inputdir/data/$storage/$type/$name.rrp" ) {
          next; 
        }
      }

      #print STDERR "001 $name $tmp_dir/$storage/$type-$item-d.cmd\n";
      if ( ! -f "$tmp_dir/$storage/$type-$item-d.cmd" ) {
        next; # non existing item
      }
      #print STDERR "002 $name $tmp_dir/$storage/$type-$item-d.cmd\n";

      if ( $found == 0 ) {
        print "<tr><td align=center><h3>$type: $name</h3></td></tr>\n";
        $found = 1;
      }
      print_item ($storage,$type,$name,$item,"d",0,$start_unix,$end_unix,$height,$width);
    }
    if ( $found == 1 ) {
      print "<tr><td><hr></td></tr>\n";
    }
  }
  print "</table></div>\n";
  return 1;
}


sub print_item
{
  my $host = shift;
  my $type = shift;
  my $name = shift;
  my $item = shift;
  my $time = shift;
  my $detail = shift;
  my $sunix = shift;
  my $eunix = shift;
  my $height = shift;
  my $width = shift;

  print "<tr><td><img src=\"/stor2rrd-cgi/detail-graph.sh?host=$storage&type=$type&name=$name&item=$item&time=d&detail=0&sunix=$sunix&eunix=$eunix&height=$height&width=$width&none=none\"></td></tr>\n";

  return 1;
}

