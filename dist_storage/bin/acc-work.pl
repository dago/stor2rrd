#
# used only for DHL accounting purposes
# etc/.magic : ACCOUTING=1 --> it has to be setup after initial installation!!!
#


use strict;
use Env qw(QUERY_STRING);
use Date::Parse;
use POSIX qw(strftime);
use RRDp;


my $inputdir = $ENV{INPUTDIR};
my $webdir = $ENV{WEBDIR};
my $rrdtool = $ENV{RRDTOOL};
my $pic_col = $ENV{PICTURE_COLOR};
my $wrkdir = "$inputdir/data";
my $STEP = $ENV{SAMPLE_RATE};
my $DEBUG = $ENV{DEBUG};
my $errlog = $ENV{ERRLOG};
my $height = $ENV{RRDHEIGHT};
my $width = $ENV{RRDWIDTH};
my $bindir = $ENV{BINDIR};
#$DEBUG = 2;

# from the storage perspective it is always tier 1
# Tiering is distinguished by pool name prefix
my $T1_string="T1";
my $T2_string="T2";
# T1-pool-name --> tier 1 (premium)
# T2-pool-name --> tier 2 (standard)
my $tier_real = 1; 

# only for development debuging purposes
my $acc_dev = 0;
if (defined $ENV{ACCOUTING_DEBUG}) {
  $acc_dev = $ENV{ACCOUTING_DEBUG};
}

open(OUT, ">> $errlog") if $DEBUG == 2 ;

print OUT "$QUERY_STRING\n" if $DEBUG == 2 ;

(my $tier, my $week, my $month, my $year, my $result_file, my $week_no, my $print_it, my $xport, my $smonth, my $emonth, my $storage_list) = split(/&/,$QUERY_STRING);

$tier =~ s/tier=//;
$smonth =~ s/smonth=//;
$emonth =~ s/emonth=//;
$month =~ s/month=//;
$year  =~ s/year=//;
$week_no =~ s/weekno=//;
$week =~ s/week=//;
$print_it =~ s/print=//;
$xport =~ s/xport=//;
$week =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$week =~ s/\+/ /g;
$result_file =~ s/result=//; # file to keep results which is counted in virtual-cpu-acc-cgi.pl
$result_file =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$result_file =~ s/\+/ /g;
my $result_file_full = "/var/tmp/".$result_file;
my $detail = 0;


# XPORT is export to XML and then to CVS
if ($xport) {
  # It should be here to do not influence normal report when XML is not in Perl
  require "$bindir/xml.pl";
  # use XML::Simple; --> it has to be in separete file
  print "Content-type: application/octet-stream\n";
  # for normal content type is printed just before picture print to be able print
  # text/html error if appears
}
else {
  print "Content-type: image/png\n\n";
}

# it must go into a temp file as direct stdout from RRDTOOL somehow does not work for me
my $name = "/var/tmp/lpar2rrd-virtual$$.png";
my $act_time = localtime();

if ( ! -d "$webdir" ) {
   die "$act_time: Pls set correct path to Web storage pages, it does not exist here: $webdir\n";
}

# start RRD via a pipe
if ( ! -f "$rrdtool" ) {
   die "$act_time: Set correct path to rrdtool binarry, it does not exist here: $rrdtool\n";
}
RRDp::start "$rrdtool";

  
graph_multi($week,$month,$year,"w",$name,$detail,$week_no,$smonth,$emonth,$storage_list);

 
# close RRD pipe
RRDp::end;


# exclude Export here
if (!$xport) {
  if ( $print_it > 0 ) {
    print_png(); 
  }
}

exit (0);

# Print the png out
sub print_png {

   open(PNG, "< $name") || die   "Cannot open  $name: $!";
   binmode(PNG);
   while (read(PNG,$b,4096)) {
      print "$b";
   }
   unlink ("$name");
}

sub err_html {
  my $text = shift;
  my $name = "$inputdir/tmp/general_error.png";

  if (! $xport) {
    open(PNG, "< $name") || die   "Cannot open  $name: $!";
    binmode(PNG);
    while (read(PNG,$b,4096)) {
      print "$b";
    }
  }

  exit 1;
}

# error handling
sub error
{
  my $text = shift;
  my $act_time = localtime();

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}


sub xport_print
{
  my $xml_org = shift;
  my $multi = shift;
  my $xml = "";

  if ($multi == 1) {
    #print OUT "--xport-- $xml_org\n";
    $xml = XMLin( $xml_org );
  }
  else {
    #print OUT "--xport++ $$xml_org\n";
    $xml = XMLin( $$xml_org );
  }

  print join(";", 'Day.Month.Year Hour', @{ $xml->{meta}{legend}{entry} } ), 
"\n";

  my $first = 0;
  foreach my $row ( @{ $xml->{data}{row} } ) {
    if ( $first ==  0 ) {
      #print "$line\n";
      $first = 1;
      next;
    }
    my $time = strftime "%d.%m.%y %H", localtime($row->{t});
    my $line = join(";", $time, @{$row->{v}});
    $line =~ s/NaNQ/0/g;
    $line =~ s/NaN/0/g;
    $line =~ s/nan/0/g; # rrdto0ol v 1.2.27
    my @line_parse = split(/;/,$line);

    # formate numbers to one decimal 
    my $first_item = 0;
    foreach my $item (@line_parse) {
      if ( $first_item ==  0 ) {
        print "$item";
        $first_item = 1;
        next;
      }
      else {
        my $out = sprintf ("%.2f",$item);
        $out =~ s/\./,/g; # use "," as a decimal separator
        print ";$out";
      }
    }
    print "\n";
  }
  return 0;
}



sub graph_multi
{
  my ($week,$month,$year,$type,$name_out,$detail,$week_no,$smonth,$emonth,$storage_list) = @_;
  #my @storage_list = @{$storage_list_tmp};
  my $text = "";
  #my $step = 60; # --PH dodelat --> no problem it could be here 60 fixed
  #my $step = 86400; # --PH dodelat --> no problem it could be here 60 fixed
  my $step = 3600 ; # must be same as for XPORT CSV!!!
  my $xgrid = "";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $step_new = $step;
  my $last ="COMMENT: ";
  my $act_time = localtime();
  my $act_time_u = time();
  my $req_time = 0;
  my $font_def =  "--font=DEFAULT:8:";
  my $font_tit =  "--font=TITLE:9:";
  my $line_items = 0; # how many items in the legend per a line (default 2, when detail then 3)
  my $stime = 0;
  my $etime = 0;


  if ($smonth > 0 && $emonth > 0 ) {
    # monthly summary only for xport XLS
    $stime = $smonth;
    $etime = $emonth;
  }
  else {
    ($stime, $etime) = split(/ /,$week);
  }
  
  # 48 colors like for HMC bellow + 216 basic HTML colors x 6 == 1296 + 48
  my @color=("#FF0000","#0000FF","#00FF00","#FFFF00","#FF3399","#00FFFF","#999933","#0099CC","#3300CC",
"#FF8080", "#FFFF80", "#80FF80", "#00FF80", "#80FFFF", "#0080FF", "#FF80C0", "#FF80FF", "#FF0000", "#FFFF00", "#80FF00",
"#00FF40", "#00FFFF", "#0080C0", "#8080C0", "#FF00FF", "#804040", "#FF8040", "#00FF00", "#008080", "#004080", "#8080FF",
"#800040", "#FF0080", "#800000", "#FF8000", "#008000", "#008040", "#0000FF", "#0000A0", "#800080", "#8000FF", "#400000",
"#804000", "#004000", "#004040", "#000080", "#000040", "#400040", "#400080", "#000000", "#808000", "#808040", "#808080",
"#408080", "#C0C0C0", "#400040", "#AAAAAA",
"#CC0000","#FF0000", "#CC00CC","#FF00CC","#0000CC","#0000FF","#00CCCC","#00FFFF","#00CC00","#00FF00",
"#CCCC00","#000000","#FFFF00","#333300","#FFFFFF","#330000","#999990","#336600","#FFCC00","#339900",
"#FF9900","#33CC00","#FF6600","#33FF00","#FF3300","#66FF00","#660000","#663300","#66CC00","#669900",
"#666600","#330033","#FFFF33","#333333","#FF0033","#336633","#FFCC33","#339933","#FF9933","#33CC33",
"#FF6633","#33FF33","#FF3333","#66FF33","#660033","#663333","#66CC33","#669933","#666633","#330066",
"#FFFF66","#333366","#FF0066","#336666","#FFCC66","#339966","#FF9966","#33CC66","#FF6666","#33FF66",
"#FF3366","#66FF66","#660066","#663366","#66CC66","#669966","#666666","#330099","#FFFF99","#333399",
"#FF0099","#336699","#FFCC99","#339999","#FF9999","#33CC99","#FF6699","#33FF99","#FF3399","#66FF99",
"#660099","#663399","#66CC99","#669999","#666699","#3300CC","#FFFFCC","#3333CC","#3366CC","#FFCCCC",
"#3399CC","#FF99CC","#33CCCC","#FF66CC","#33FFCC","#FF33CC","#66FFCC","#6600CC","#6633CC","#66CCCC",
"#6699CC","#6666CC","#3300FF","#FFFFFF","#3333FF","#FF00FF","#3366FF","#FFCCFF","#3399FF","#FF99FF",
"#33CCFF","#FF66FF","#33FFFF","#FF33FF","#66FFFF","#6600FF","#6633FF","#66CCFF","#6699FF","#6666FF",
"#CCFFFF","#0033FF","#CC00FF","#0066FF","#CCCCFF","#0099FF","#CC99FF","#00CCFF","#CC66FF","#CC33FF",
"#99FFFF","#9900FF","#9933FF","#99CCFF","#9999FF","#9966FF","#CCFFCC","#0033CC","#0066CC","#CCCCCC",
"#0099CC","#CC99CC","#CC66CC","#00FFCC","#CC33CC","#99FFCC","#9900CC","#9933CC","#99CCCC","#9999CC",
"#9966CC","#000099","#CCFF99","#003399","#CC0099","#006699","#CCCC99","#009999","#CC9999","#00CC99",
"#CC6699","#00FF99","#CC3399","#99FF99","#990099","#993399","#99CC99","#999999","#996699","#000066",
"#CCFF66","#003366","#CC0066","#006666","#CCCC66","#009966","#CC9966","#00CC66","#CC6666","#00FF66",
"#CC3366","#99FF66","#990066","#993366","#99CC66","#999966","#996666","#000033","#CCFF33","#003333",
"#CC0033","#006633","#CCCC33","#009933","#CC9933","#00CC33","#CC6633","#00FF33","#CC3333","#99FF33",
"#990033","#993333","#99CC33","#999933","#996633","#CCFF00","#003300","#006600","#009900","#CC9900",
"#CC6600","#CC3300","#99FF00","#990000","#993300","#99CC00","#999900","#996600",
"#CC0000","#FF0000","#CC00CC","#FF00CC","#0000CC","#0000FF","#00CCCC","#00FFFF","#00CC00","#00FF00",
"#CCCC00","#FFFF00","#000000","#999999","#FFFFFF","#330000","#333300","#336600","#FFCC00","#339900",
"#FF9900","#33CC00","#FF6600","#33FF00","#FF3300","#66FF00","#660000","#663300","#66CC00","#669900",
"#666600","#330033","#FFFF33","#333333","#FF0033","#336633","#FFCC33","#339933","#FF9933","#33CC33",
"#FF6633","#33FF33","#FF3333","#66FF33","#660033","#663333","#66CC33","#669933","#666633","#330066",
"#FFFF66","#333366","#FF0066","#336666","#FFCC66","#339966","#FF9966","#33CC66","#FF6666","#33FF66",
"#FF3366","#66FF66","#660066","#663366","#66CC66","#669966","#666666","#330099","#FFFF99","#333399",
"#FF0099","#336699","#FFCC99","#339999","#FF9999","#33CC99","#FF6699","#33FF99","#FF3399","#66FF99",
"#660099","#663399","#66CC99","#669999","#666699","#3300CC","#FFFFCC","#3333CC","#3366CC","#FFCCCC",
"#3399CC","#FF99CC","#33CCCC","#FF66CC","#33FFCC","#FF33CC","#66FFCC","#6600CC","#6633CC","#66CCCC",
"#6699CC","#6666CC","#3300FF","#FFFFFF","#3333FF","#FF00FF","#3366FF","#FFCCFF","#3399FF","#FF99FF",
"#33CCFF","#FF66FF","#33FFFF","#FF33FF","#66FFFF","#6600FF","#6633FF","#66CCFF","#6699FF","#6666FF",
"#CCFFFF","#0033FF","#CC00FF","#0066FF","#CCCCFF","#0099FF","#CC99FF","#00CCFF","#CC66FF","#CC33FF",
"#99FFFF","#9900FF","#9933FF","#99CCFF","#9999FF","#9966FF","#CCFFCC","#0033CC","#0066CC","#CCCCCC",
"#0099CC","#CC99CC","#CC66CC","#00FFCC","#CC33CC","#99FFCC","#9900CC","#9933CC","#99CCCC","#9999CC",
"#9966CC","#000099","#CCFF99","#003399","#CC0099","#006699","#CCCC99","#009999","#CC9999","#00CC99",
"#CC6699","#00FF99","#CC3399","#99FF99","#990099","#993399","#99CC99","#999999","#996699","#000066",
"#CCFF66","#003366","#CC0066","#006666","#CCCC66","#009966","#CC9966","#00CC66","#CC6666","#00FF66",
"#CC3366","#99FF66","#990066","#993366","#99CC66","#999966","#996666","#000033","#CCFF33","#003333",
"#CC0033","#006633","#CCCC33","#009933","#CC9933","#00CC33","#CC6633","#00FF33","#CC3333","#99FF33",
"#990033","#993333","#99CC33","#999933","#996633","#CCFF00","#003300","#006600","#009900","#CC9900",
"#CC6600","#CC3300","#99FF00","#990000","#993300","#99CC00","#999900","#996600",
"#CC0000","#FF0000","#CC00CC","#FF00CC","#0000CC","#0000FF","#00CCCC","#00FFFF","#00CC00","#00FF00",
"#CCCC00","#FFFF00","#000000","#999999","#FFFFFF","#330000","#333300","#336600","#FFCC00","#339900",
"#FF9900","#33CC00","#FF6600","#33FF00","#FF3300","#66FF00","#660000","#663300","#66CC00","#669900",
"#666600","#330033","#FFFF33","#333333","#FF0033","#336633","#FFCC33","#339933","#FF9933","#33CC33",
"#FF6633","#33FF33","#FF3333","#66FF33","#660033","#663333","#66CC33","#669933","#666633","#330066",
"#FFFF66","#333366","#FF0066","#336666","#FFCC66","#339966","#FF9966","#33CC66","#FF6666","#33FF66",
"#FF3366","#66FF66","#660066","#663366","#66CC66","#669966","#666666","#330099","#FFFF99","#333399",
"#FF0099","#336699","#FFCC99","#339999","#FF9999","#33CC99","#FF6699","#33FF99","#FF3399","#66FF99",
"#660099","#663399","#66CC99","#669999","#666699","#3300CC","#FFFFCC","#3333CC","#3366CC","#FFCCCC",
"#3399CC","#FF99CC","#33CCCC","#FF66CC","#33FFCC","#FF33CC","#66FFCC","#6600CC","#6633CC","#66CCCC",
"#6699CC","#6666CC","#3300FF","#FFFFFF","#3333FF","#FF00FF","#3366FF","#FFCCFF","#3399FF","#FF99FF",
"#33CCFF","#FF66FF","#33FFFF","#FF33FF","#66FFFF","#6600FF","#6633FF","#66CCFF","#6699FF","#6666FF",
"#CCFFFF","#0033FF","#CC00FF","#0066FF","#CCCCFF","#0099FF","#CC99FF","#00CCFF","#CC66FF","#CC33FF",
"#99FFFF","#9900FF","#9933FF","#99CCFF","#9999FF","#9966FF","#CCFFCC","#0033CC","#0066CC","#CCCCCC",
"#0099CC","#CC99CC","#CC66CC","#00FFCC","#CC33CC","#99FFCC","#9900CC","#9933CC","#99CCCC","#9999CC",
"#9966CC","#000099","#CCFF99","#003399","#CC0099","#006699","#CCCC99","#009999","#CC9999","#00CC99",
"#CC6699","#00FF99","#CC3399","#99FF99","#990099","#993399","#99CC99","#999999","#996699","#000066",
"#CCFF66","#003366","#CC0066","#006666","#CCCC66","#009966","#CC9966","#00CC66","#CC6666","#00FF66",
"#CC3366","#99FF66","#990066","#993366","#99CC66","#999966","#996666","#000033","#CCFF33","#003333",
"#CC0033","#006633","#CCCC33","#009933","#CC9933","#00CC33","#CC6633","#00FF33","#CC3333","#99FF33",
"#990033","#993333","#99CC33","#999933","#996633","#CCFF00","#003300","#006600","#009900","#CC9900",
"#CC6600","#CC3300","#99FF00","#990000","#993300","#99CC00","#999900","#996600",
"#CC0000","#FF0000","#CC00CC","#FF00CC","#0000CC","#0000FF","#00CCCC","#00FFFF","#00CC00","#00FF00",
"#CCCC00","#FFFF00","#000000","#999999","#FFFFFF","#330000","#333300","#336600","#FFCC00","#339900",
"#FF9900","#33CC00","#FF6600","#33FF00","#FF3300","#66FF00","#660000","#663300","#66CC00","#669900",
"#666600","#330033","#FFFF33","#333333","#FF0033","#336633","#FFCC33","#339933","#FF9933","#33CC33",
"#FF6633","#33FF33","#FF3333","#66FF33","#660033","#663333","#66CC33","#669933","#666633","#330066",
"#FFFF66","#333366","#FF0066","#336666","#FFCC66","#339966","#FF9966","#33CC66","#FF6666","#33FF66",
"#FF3366","#66FF66","#660066","#663366","#66CC66","#669966","#666666","#330099","#FFFF99","#333399",
"#FF0099","#336699","#FFCC99","#339999","#FF9999","#33CC99","#FF6699","#33FF99","#FF3399","#66FF99",
"#660099","#663399","#66CC99","#669999","#666699","#3300CC","#FFFFCC","#3333CC","#3366CC","#FFCCCC",
"#3399CC","#FF99CC","#33CCCC","#FF66CC","#33FFCC","#FF33CC","#66FFCC","#6600CC","#6633CC","#66CCCC",
"#6699CC","#6666CC","#3300FF","#FFFFFF","#3333FF","#FF00FF","#3366FF","#FFCCFF","#3399FF","#FF99FF",
"#33CCFF","#FF66FF","#33FFFF","#FF33FF","#66FFFF","#6600FF","#6633FF","#66CCFF","#6699FF","#6666FF",
"#CCFFFF","#0033FF","#CC00FF","#0066FF","#CCCCFF","#0099FF","#CC99FF","#00CCFF","#CC66FF","#CC33FF",
"#99FFFF","#9900FF","#9933FF","#99CCFF","#9999FF","#9966FF","#CCFFCC","#0033CC","#0066CC","#CCCCCC",
"#0099CC","#CC99CC","#CC66CC","#00FFCC","#CC33CC","#99FFCC","#9900CC","#9933CC","#99CCCC","#9999CC",
"#9966CC","#000099","#CCFF99","#003399","#CC0099","#006699","#CCCC99","#009999","#CC9999","#00CC99",
"#CC6699","#00FF99","#CC3399","#99FF99","#990099","#993399","#99CC99","#999999","#996699","#000066",
"#CCFF66","#003366","#CC0066","#006666","#CCCC66","#009966","#CC9966","#00CC66","#CC6666","#00FF66",
"#CC3366","#99FF66","#990066","#993366","#99CC66","#999966","#996666","#000033","#CCFF33","#003333",
"#CC0033","#006633","#CCCC33","#009933","#CC9933","#00CC33","#CC6633","#00FF33","#CC3333","#99FF33",
"#990033","#993333","#99CC33","#999933","#996633","#CCFF00","#003300","#006600","#009900","#CC9900",
"#CC6600","#CC3300","#99FF00","#990000","#993300","#99CC00","#999900","#996600",
"#CC0000","#FF0000","#CC00CC","#FF00CC","#0000CC","#0000FF","#00CCCC","#00FFFF","#00CC00","#00FF00",
"#CCCC00","#FFFF00","#000000","#999999","#FFFFFF","#330000","#333300","#336600","#FFCC00","#339900",
"#FF9900","#33CC00","#FF6600","#33FF00","#FF3300","#66FF00","#660000","#663300","#66CC00","#669900",
"#666600","#330033","#FFFF33","#333333","#FF0033","#336633","#FFCC33","#339933","#FF9933","#33CC33",
"#FF6633","#33FF33","#FF3333","#66FF33","#660033","#663333","#66CC33","#669933","#666633","#330066",
"#FFFF66","#333366","#FF0066","#336666","#FFCC66","#339966","#FF9966","#33CC66","#FF6666","#33FF66",
"#FF3366","#66FF66","#660066","#663366","#66CC66","#669966","#666666","#330099","#FFFF99","#333399",
"#FF0099","#336699","#FFCC99","#339999","#FF9999","#33CC99","#FF6699","#33FF99","#FF3399","#66FF99",
"#660099","#663399","#66CC99","#669999","#666699","#3300CC","#FFFFCC","#3333CC","#3366CC","#FFCCCC",
"#3399CC","#FF99CC","#33CCCC","#FF66CC","#33FFCC","#FF33CC","#66FFCC","#6600CC","#6633CC","#66CCCC",
"#6699CC","#6666CC","#3300FF","#FFFFFF","#3333FF","#FF00FF","#3366FF","#FFCCFF","#3399FF","#FF99FF",
"#33CCFF","#FF66FF","#33FFFF","#FF33FF","#66FFFF","#6600FF","#6633FF","#66CCFF","#6699FF","#6666FF",
"#CCFFFF","#0033FF","#CC00FF","#0066FF","#CCCCFF","#0099FF","#CC99FF","#00CCFF","#CC66FF","#CC33FF",
"#99FFFF","#9900FF","#9933FF","#99CCFF","#9999FF","#9966FF","#CCFFCC","#0033CC","#0066CC","#CCCCCC",
"#0099CC","#CC99CC","#CC66CC","#00FFCC","#CC33CC","#99FFCC","#9900CC","#9933CC","#99CCCC","#9999CC",
"#9966CC","#000099","#CCFF99","#003399","#CC0099","#006699","#CCCC99","#009999","#CC9999","#00CC99",
"#CC6699","#00FF99","#CC3399","#99FF99","#990099","#993399","#99CC99","#999999","#996699","#000066",
"#CCFF66","#003366","#CC0066","#006666","#CCCC66","#009966","#CC9966","#00CC66","#CC6666","#00FF66",
"#CC3366","#99FF66","#990066","#993366","#99CC66","#999966","#996666","#000033","#CCFF33","#003333",
"#CC0033","#006633","#CCCC33","#009933","#CC9933","#00CC33","#CC6633","#00FF33","#CC3333","#99FF33",
"#990033","#993333","#99CC33","#999933","#996633","#CCFF00","#003300","#006600","#009900","#CC9900",
"#CC6600","#CC3300","#99FF00","#990000","#993300","#99CC00","#999900","#996600",
"#CC0000","#FF0000","#CC00CC","#FF00CC","#0000CC","#0000FF","#00CCCC","#00FFFF","#00CC00","#00FF00",
"#CCCC00","#FFFF00","#000000","#999999","#FFFFFF","#330000","#333300","#336600","#FFCC00","#339900",
"#FF9900","#33CC00","#FF6600","#33FF00","#FF3300","#66FF00","#660000","#663300","#66CC00","#669900",
"#666600","#330033","#FFFF33","#333333","#FF0033","#336633","#FFCC33","#339933","#FF9933","#33CC33",
"#FF6633","#33FF33","#FF3333","#66FF33","#660033","#663333","#66CC33","#669933","#666633","#330066",
"#FFFF66","#333366","#FF0066","#336666","#FFCC66","#339966","#FF9966","#33CC66","#FF6666","#33FF66",
"#FF3366","#66FF66","#660066","#663366","#66CC66","#669966","#666666","#330099","#FFFF99","#333399",
"#FF0099","#336699","#FFCC99","#339999","#FF9999","#33CC99","#FF6699","#33FF99","#FF3399","#66FF99",
"#660099","#663399","#66CC99","#669999","#666699","#3300CC","#FFFFCC","#3333CC","#3366CC","#FFCCCC",
"#3399CC","#FF99CC","#33CCCC","#FF66CC","#33FFCC","#FF33CC","#66FFCC","#6600CC","#6633CC","#66CCCC",
"#6699CC","#6666CC","#3300FF","#FFFFFF","#3333FF","#FF00FF","#3366FF","#FFCCFF","#3399FF","#FF99FF",
"#33CCFF","#FF66FF","#33FFFF","#FF33FF","#66FFFF","#6600FF","#6633FF","#66CCFF","#6699FF","#6666FF",
"#CCFFFF","#0033FF","#CC00FF","#0066FF","#CCCCFF","#0099FF","#CC99FF","#00CCFF","#CC66FF","#CC33FF",
"#99FFFF","#9900FF","#9933FF","#99CCFF","#9999FF","#9966FF","#CCFFCC","#0033CC","#0066CC","#CCCCCC",
"#0099CC","#CC99CC","#CC66CC","#00FFCC","#CC33CC","#99FFCC","#9900CC","#9933CC","#99CCCC","#9999CC",
"#9966CC","#000099","#CCFF99","#003399","#CC0099","#006699","#CCCC99","#009999","#CC9999","#00CC99",
"#CC6699","#00FF99","#CC3399","#99FF99","#990099","#993399","#99CC99","#999999","#996699","#000066",
"#CCFF66","#003366","#CC0066","#006666","#CCCC66","#009966","#CC9966","#00CC66","#CC6666","#00FF66",
"#CC3366","#99FF66","#990066","#993366","#99CC66","#999966","#996666","#000033","#CCFF33","#003333",
"#CC0033","#006633","#CCCC33","#009933","#CC9933","#00CC33","#CC6633","#00FF33","#CC3333","#99FF33",
"#990033","#993333","#99CC33","#999933","#996633","#CCFF00","#003300","#006600","#009900","#CC9900",
"#CC6600","#CC3300","#99FF00","#990000","#993300","#99CC00","#999900","#996600");

  if ( $detail == 1 ) {
    $font_def =  "--font=DEFAULT:10:";
    $font_tit =  "--font=TITLE:13:";
    $line_items = 2;
  }

  my $stime_text = localtime($stime);
  my $etime_text = localtime($etime);

  if ( $type =~ m/d/ ) { 
    $text="day";     
    if ( $detail == 0 ) {
      $xgrid="MINUTE:60:HOUR:2:HOUR:4:0:%H";
    }
    else {
      $xgrid="MINUTE:60:HOUR:1:HOUR:1:0:%H";
    }
  }
  if ( $type =~ m/w/ ) { 
    $text="$stime_text - $etime_text";    
    if ( $detail == 0 ) {
      #$xgrid="HOUR:8:DAY:1:DAY:1:0:%a";
      #$xgrid="\"HOUR:24:HOUR:6:HOUR:24:0:%a %H\"";
      $xgrid="HOUR:12:DAY:1:DAY:1:0:%d";
    }
    else {
      $xgrid="\"HOUR:12:HOUR:6:HOUR:12:0:%a %H\"";
    }
  }
  if ( $type =~ m/m/ ) { 
    $text="4 weeks"; 
    if ( $detail == 0 ) {
      $xgrid="DAY:1:DAY:2:DAY:2:0:%d";
    }
    else {
      $xgrid="HOUR:12:DAY:1:DAY:1:0:%d";
    }
  }
  if ( $type =~ m/y/ ) { 
    $text="year";    
    if ( $detail == 0 ) {
      $xgrid="MONTH:1:MONTH:1:MONTH:1:0:%b";
    }
    else {
      $xgrid="MONTH:1:MONTH:1:MONTH:1:0:%b";
    }
  }

  my $header = "$text";
  $header =~ s/00:00:00 //g;

  #if ( $type =~ "y" ) {
  #  $step_new=86400;
  #}



  # Check if anything has been selected
  my @files = "";
  my $files_indx = 0;
  my @storages = "";
  (my @storage_rows) = split (/SERVERS=/,$storage_list);
  print OUT "001 $week_no : $storage_list\n" if $DEBUG == 2 ;
  foreach my $line (@storage_rows) {
    chomp ($line);
    $line =~ s/\%20$//g;
    $line =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
    $line =~ s/ Report=Generate\+Report//g;
    $line =~ s/\+/ /g;
    $line =~ s/^SERVERS=//g;
    if ( $line eq '' ) {
      next; # trash
    }
    $storages[$files_indx] = $line;
    $files_indx++;
  }
  if ( $files_indx == 0 ) {
    error ("No storage has been selected");
    err_html();
  }

  my $file = "";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;
  my $cmd_xport = "";


  $cmd .= "graph \\\"$name_out\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start $stime-120";
  $cmd .= " --end $etime-120";
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
  $cmd .= " --vertical-label=\\\"Allocated space in TB\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --alt-y-grid";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " $font_def";
  $cmd .= " $font_tit";
  if ( $detail == 1 ) {
    $cmd .= " COMMENT:\\\"Allocated space in TB\\:    average                               average                               average\\l\\\"";
  }
  else {
    $cmd .= " COMMENT:\\\"Allocated space in TB\\:                        average\\l\\\"";
    $cmd .= " COMMENT:\\\"  POOL                Storage\\l\\\"";
  }

  my $cmd_sum = $cmd; # store a linne for finding out Total value


  my $gtype="AREA";
  my $col_indx = 0;
  my $line_indx = 0; # place enter evry 3rd line
  my $storage_indx = 0;
  my $prev = -1;
  my $last_vol = -1;

  # $tier_real is alway 1, tiering is distingushed via the prefix of the pool name
  my $tiercap = "tier".$tier_real."cap";
  my $tierfree = "tier".$tier_real."free";

  foreach my $storage (@storages) {
    # go through all storages
    chomp($storage);
    print OUT "003 $week_no : $storage\n" if $DEBUG == 2 ;

    opendir(LDIR, "$wrkdir/$storage/POOL") || die "$act_time: directory does not exists : $wrkdir/$storage/POOL";
    my @pool_list = grep(/\-cap.rrd$/,readdir(LDIR));
    closedir(LDIR);

    # POOL capacity --> load translate table
    open(FHP, "< $wrkdir/$storage/pool.cfg") || die "$act_time: Can't open $wrkdir/$storage/pool.cfg : $!";
    my @lines_translate = <FHP>;
    close(FHP);


    # go through all POOLS
    foreach $file (@pool_list) {
      chomp($file);

      $lpar = $file;
      $lpar =~ s/-cap.rrd//;

      my $pool_name = $lpar;
      foreach my $linep (@lines_translate) {
        chomp ($linep);
        (my $id, my $name) = split (/:/,$linep);
        if ( $id =~ m/^$lpar$/ ) {
          $pool_name = $name;
          last;
        }
      }

      # TIER 1 selection
      if ( $tier == 1 && $pool_name !~ m/^$T1_string/ ) {
        if ( $acc_dev == 0 ) { 
          next; # pool is not in tier 1 (premium)
        }
        else {
          # only for development purposes
          if ( $tier == 1 && $pool_name !~ m/300/ ) {
            next;
          }
        }
      }

      # TIER 2 selection
      if ( $tier == 2 && $pool_name !~ m/^$T2_string/ ) {
        if ( $acc_dev == 0 ) { 
          next; # pool is not in tier 2 (standard)
        }
        else {
          # only for development purposes
          if ( $tier == 2 && $pool_name !~ m/600/ ) {
            next;
          }
        }
      }


      # find out storage name
      #my $legend = sprintf ("%-20s","$storages[$storage_indx]").sprintf ("%-20s","$lpar");
      my $legend = sprintf ("%-20s","$pool_name").sprintf ("%-20s","$storages[$storage_indx]");
      print OUT "004 $week_no : $storages[$storage_indx] : $lpar : $legend \n" if $DEBUG == 2 ;

      # bulid RRDTool cmd
      $cmd .= " DEF:cap${i}=\\\"$wrkdir/$storage/POOL/$file\\\":$tiercap:AVERAGE";
      $cmd_xport .= "\\\"DEF:cap${i}=$wrkdir/$storage/POOL/$file:$tiercap:AVERAGE\\\"\n";
      $cmd_sum .= " DEF:cap${i}=\\\"$wrkdir/$storage/POOL/$file\\\":$tiercap:AVERAGE";

      $cmd .= " DEF:free${i}=\\\"$wrkdir/$storage/POOL/$file\\\":$tierfree:AVERAGE";
      $cmd_xport .= "\\\"DEF:free${i}=$wrkdir/$storage/POOL/$file:$tierfree:AVERAGE\\\"\n";
      $cmd_sum .= " DEF:free${i}=\\\"$wrkdir/$storage/POOL/$file\\\":$tierfree:AVERAGE";

      # Do not use that as it has an effect on the result when there is no data!
      #$cmd .= " CDEF:cap${i}=capnull${i},UN,0,capnull${i},IF"; # it must be here!!!
      #$cmd_xport .= "\\\"CDEF:cap${i}=capnull${i},UN,0,capnull${i},IF\\\"\n"; # it must be here!!!
      #$cmd_sum .= " CDEF:cap${i}=capnull${i},UN,0,capnull${i},IF"; # it must be here!!!

      #$cmd .= " CDEF:free${i}=freenull${i},UN,0,freenull${i},IF"; # it must be here!!!
      #$cmd_xport .= "\\\"CDEF:free${i}=freenull${i},UN,0,freenull${i},IF\\\"\n"; # it must be here!!!
      #$cmd_sum .= " CDEF:free${i}=freenull${i},UN,0,freenull${i},IF"; # it must be here!!!

      $cmd .= " CDEF:used${i}=cap${i},free${i},-"; 
      $cmd_xport .= "\\\"CDEF:used${i}=cap${i},free${i},-\\\"\n"; 
      $cmd_sum .= " CDEF:used${i}=cap${i},free${i},-"; 
  
      $cmd .= " $gtype:used${i}$color[$col_indx]:\\\"$legend\\\"";
      $cmd_xport .= "\\\"XPORT:used${i}:$legend\\\"\n";
      $cmd_sum .= " PRINT:used${i}:AVERAGE:\\\"%8.3lf \\\"";  # MUST be X.3 othervise does not work total ... ???

      $col_indx++;
  
      $cmd .= " GPRINT:used${i}:AVERAGE:\\\"%5.3lf \\\"";
      #$cmd_sum .= " PRINT:virt${i}:AVERAGE:\\\"%5.3lf \\\"";  # MUST be X.3 othervise does not work total ... ???
      # do not print total summary individual lines!! print only the sum line

      # get only the summ line for total average
      #if ( $prev == -1 ) {
      #  $cmd_sum .= " CDEF:used_sum${i}=used${i}";
      #  $prev++;
      #}
      #else {
      #  $cmd_sum .= " CDEF:used_sum${i}=used_sum${last_vol},used${i},+";
      #}
      #$last_vol++;

      $gtype="STACK";
      $i++;
      if ($line_indx == $line_items) {
        # put carriage return after each second lpar in the legend
        $cmd .= " COMMENT:\\\"\\l\\\"";
        $line_indx = 0;
      }
      else {
        $line_indx++;
      }
    }
    $storage_indx++;
  }

  #$cmd_sum .= " PRINT:used_sum${last_vol}:AVERAGE:\\\"%8.3lf \\\"";  # MUST be X.3 othervise does not work total ... ???
  $cmd_sum =~ s/\\"/"/g;

  my $tmp_file_sum="/var/tmp/stor2rrd-used-sum.tmp-$$";

  # Find out total value
  open(FH, "> $tmp_file_sum") || die "$act_time: Can't open $tmp_file_sum : $!";
  print FH "$cmd_sum\n";
  close (FH);
  print OUT "006 $week_no : $cmd_sum\n" if $DEBUG == 2 ;

  my $ret  = `$rrdtool - < "$tmp_file_sum" 2>&1`;
  print OUT "007 $week_no : $ret\n" if $DEBUG == 2 ;

  my $total_tmp = 0;
  foreach my $ret_line (split(/\n/,$ret)) {
    chomp($ret_line);
    #print "110 $ret_line\n";
    if ( $ret_line =~ m/:/ || $ret_line =~ m/x/ ) {
      next;
    }
    $ret_line =~ s/0x0//g;
    $ret_line =~ s/ //g;
    $ret_line =~ s/OK.*$//g;
    chomp($ret_line); # must be here as well !!
    if ( $ret_line eq '' ) {
      next;
    }
    my $ret_digit = isdigit($ret_line);
    #print "111 $ret_line - ret_digit = $ret_digit\n";
    if ( $ret_digit == 0 ) {
      next;
    }
    $total_tmp = $total_tmp + $ret_line;
    #print "112 $ret_line : $total \n";
  }
  close (FH);
  unlink ($tmp_file_sum);
  my $total = sprintf("%.1f",$total_tmp); # rounding week total to 1 decimal as was agreed
  my $total_print = sprintf("%.3f",$total_tmp); # rounding week total to 3 decimal to have it in the chart only
  $cmd .= " LINE2:$total_print#000000:\\\"Total                                      $total_print\\\"";

  print OUT "008 $week_no : $total : $total_tmp \n" if $DEBUG == 2 ;

  # write down the result into result file
  my $number_active_days = active_days($stime,$etime,$month,$year);
  open(FHR, ">> $result_file_full") || die "$act_time: Can't open $result_file_full : $!";
  print FHR "$week_no:$number_active_days:$total\n";
  close (FHR);


  #$cmd .= " COMMENT:\\\"  Total                                        $total\\l\\\"";
  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my  $FH;
  my $tmp_file="/var/tmp/stor2rrd-used.tmp-$$";
  open(FH, "> $tmp_file") || die "$act_time: Can't open $tmp_file : $!";
  print FH "$cmd\n";
  close (FH);

  print OUT "009 $week_no : $total : $total_tmp \n" if $DEBUG == 2 ;

  if ($xport) {
    $cmd_xport =~ s/\\"/"/g;
    print "Content-Disposition: attachment;filename=$year\_$month\_$week_no.csv\n\n";
    $step = 86400; # daily averages
    $step = 60; # daily averages
    $step = 3600; # hourly averages
    # keep there "-120 secs, otherwise start and enad times are wrong
    RRDp::cmd qq(xport
         "--start" "$stime-120"
         "--end" "$etime-120"
         "--step" "$step"
         "--maxrows" "65000"
         $cmd_xport
    );
    my $ret = RRDp::read;
    #print OUT "---- $ret\n +++ $cmd_xport";
    my $tmp_file="/var/tmp/stor2rrd.tmp-$$";
    my  $FH;
    open(FH, "> $tmp_file") || die "$act_time: Can't open $tmp_file : $!";
    print FH "$$ret";
    close (FH);

    open(FH, "< $tmp_file") || die "$act_time: Can't open $tmp_file : $!";
    my $out = 0;
    my $out_txt = "";
    while (my $line = <FH>) {
      if ($out == 0 ){
        if ($line =~ m/xml version=/ ) {
          $out_txt .= $line;
          $out = 1;
        }
      }
      else {
        if ($line !~ m/^OK u:/ ) {
          $out_txt .= $line;
        }
      }
    }
    close (FH);
    #unlink ("$tmp_file");
    #print OUT "--xport $out_txt\n";
    #print OUT "++xport $$ret\n";
    xport_print ($out_txt,1);
  }
  else {

    # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
    my $ret  = `$rrdtool - < "$tmp_file" 2>&1`;
    if ( $ret =~ "ERROR" ) {
      error ("acc-work.pl: Multi graph rrdtool error : $ret");
      if ( $ret =~ "is not an RRD file" ) {
        (my $err,  my $file, my $txt) = split(/'/,$ret);
        error ("Removing as it seems to be corrupted: $file");
        unlink("$file") || die "Cannot rm $file : $!";
      }
      else {
        error ("acc-work.pl: $cmd : Multi graph rrdtool error : $ret");
      }
      err_html();
    }
    unlink ("$tmp_file");
  }
  print OUT "010 \n"; 

  return $total;
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

sub isdigit
{
  my $digit = shift;

  my $digit_work = $digit;
  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;

  if (length($digit_work) == 0) {
    # is a number
    return 1;
  }

  #if (($digit * 1) eq $digit){
  #  # is a number
  #  return 1;
  #}

  # NOT a number
  #error ("there was expected a digit but a string is there, field: $text , value: $digit");
  return 0;
}

# it returns number of active days in actual week
sub active_days {
  my $stime = shift;
  my $etime = shift;
  my $month = shift;
  my $year = shift;
  my $month_next = $month;
  my $year_next = $year;


  my $stime_month = str2time("$month/1/$year");

  if ( $month < 12 ) {
    $month_next++;
  }
  else {
    $month_next = 1;
    $year_next++;
  }
  my $etime_month = str2time("$month_next/1/$year_next");

  while ( $stime < $stime_month ) {
    $stime = $stime + 86400;
  }

  while ( $etime > $etime_month ) {
    $etime = $etime - 86400;
  }

  my $number_of_days = 0;
  while ( $stime < $etime ) {
    $stime = $stime + 86400;
    $number_of_days++;
  }

  return $number_of_days;

}
