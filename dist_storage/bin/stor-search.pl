
#use strict;
use RRDp;
use POSIX qw(strftime);
use Env qw(QUERY_STRING);

my $DEBUG = $ENV{DEBUG};
#$DEBUG = "2";
my $inputdir = $ENV{INPUTDIR};
my $refer = $ENV{HTTP_REFERER};
my $errlog = $ENV{ERRLOG};
my $FIRST_GLOBAL="sum_io";
my $FIRST_GLOBAL_SUB="RANK";


open(OUT, ">> $errlog")  if $DEBUG == 2 ;

# print HTML header
print "Content-type: text/html\n";
my $time = gmtime();
print "Expires: $time\n\n";
print "<HTML><HEAD>
<TITLE>STOR2RRD</TITLE>
<style>
<!--
a {text-decoration: none}
-->
</style>
</HEAD>
<BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\" >";


# case sensitive search was canceled
my $case = 0;

print OUT "-- $QUERY_STRING\n" if $DEBUG == 2 ;
(my $lpar, my $sort_order, my $base, my $search)  = split(/&/,$QUERY_STRING);

$lpar =~ s/LPAR=//;
$sort_order =~ s/sort=//;
$lpar =~ tr/+/ /;
$lpar =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/eg;
$base =~ s/BASE=//;

#$case =~ s/Search=Search:\.//;
#$case =~ s/case=//;

if (length($case) == 0 ) {
  # convert searched string to case non sensitive in find
  my $lpar_new="";

  for (my $i=0; $i < length($lpar); $i++) {
    $lpar_new .= "[".lc(substr($lpar,$i,1))."|".uc(substr($lpar,$i,1))."]";
  }

  $lpar = $lpar_new;
}

my @out = "";
if ( $sort_order =~ m/lpar/ ) {
  # sorting per LPARs
  @out=`cd $inputdir/data;  egrep "\.\*$lpar\.\* : " */VOLUME/volumes.cfg |sed 's/\\/VOLUME\\/volumes.cfg:/ ===separator=== /g'|sort -f -k 4`;
}
else {
  if ($sort_order =~ m/hmc/ ) {
    # sorting per Storage/SDMC/IVM
    @out=`cd $inputdir/data;  egrep "\.\*$lpar\.\* : " */VOLUME/volumes.cfg |sed 's/\\/VOLUME\\/volumes.cfg:/ ===separator=== /g'|sort -f -k 1 `;
  }
  else {
    #sorting per server
    @out=`cd $inputdir/data;  egrep "\.\*$lpar\.\* : " */VOLUME/volumes.cfg |sed 's/\\/VOLUME\\/volumes.cfg:/ ===separator=== /g'|sort -f -k 3 `;
  }
}

#print OUT "-- $inputdir $lpar +$case+ \n" if $DEBUG == 2 ;
#print "-- $inputdir $lpar -- $sort_order -- $out[0]  \n";
print "<table align=\"center\" summary=\"Graphs\">";

# Check whether AIX or another OS due to "grep -p" which supports only AIX
my $uname = `uname -a`;
chomp($uname);
my $aix = 0;
my @u_a = split(/ /,$uname);
foreach my $u (@u_a) {
  if ($u =~ "AIX") {
    $aix = 1;
  }
  break;
}

# find out HTML_BASE
# renove from the path last 4 things
# http://nim.praha.cz.ibm.com/stor2rrd/hmc1/PWR6B-9117-MMA-SN103B5C0%20ttt/pool/top.html
# --> http://nim.praha.cz.ibm.com/stor2rrd
my @full_path = split(/\//, $refer);
my $k = 0;
foreach my $path (@full_path){
  $k++
}

#
# if it goes through "custom groups" then there are ony 2 subdirs instead standard 3 in stor2rrd refere path!!!
#

if ( $refer =~ m/\/custom\// ) {
  $k--;
  $k--;
  $k--;
}
else {
  $k--;
  $k--;
  $k--;
  $k--;
}

my $j = 0;
my $html_base = "";
foreach my $path (@full_path){
  if ($j < $k) {
    if ( $j == 0 ) {
      $html_base .= $path;
    }
    else {
      $html_base .= "/".$path;
    }
    $j++;
  }
}
my $html_base_en = $html_base;
$html_base_en =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;

if ( ! $base eq '' ) {
  $html_base_en = $base;
  $base =~ tr/+/ /;
  $base =~ s/%([\dA-Fa-f][\dA-Fa-f])/ pack ("C",hex ($1))/eg;
  $html_base = $base;
}

#$html_base_en contain encoded htlml_base (got from REFER) which has to be passed as Storage/Volume sorting have there cgi-bin/...

#print "<BR>-- $html_base -- $refer <BR>";

if ( $aix == 1) {
  # AIX with grep -p support
  if ( $sort_order =~ m/lpar/ ) {
    # sorting per LPARs
    print "<tr><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=hmc&BASE=$html_base_en\" target=\"sample\"><B>Storage</B></A></td><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=&BASE=$html_base_en\" target=\"sample\"><B>Volume</B></A></td><td align=\"center\"><B>Vol ID</B></td></tr>\n";
  }
  else {
    if ($sort_order =~ m/hmc/ ) {
      # sorting per Storage/SDMC/IVM
      print "<tr><td align=\"center\"><B>Storage</B></td><td align=\"center\">&nbsp;&nbsp;<A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=&BASE=$html_base_en\" target=\"sample\"><B>Volume</B></A></td><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=lpar&BASE=$html_base_en\" target=\"sample\"><B>Vol ID</B></A></td></tr>\n";
    }
    else {
      #sorting per server
      print "<tr><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=hmc&BASE=$html_base_en\" target=\"sample\"><B>Storage</B></A></td><td align=\"center\">&nbsp;&nbsp;<B>Volume</B></td><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=lpar&BASE=$html_base_en\" target=\"sample\"><B>Vol ID</B></A></td></tr>\n";
    }
  }
}
else {
  # other platforms without OS support
  if ( $sort_order =~ m/lpar/ ) {
    # sorting per LPARs
    print "<tr><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=hmc&BASE=$html_base_en\" target=\"sample\"><B>Storage</B></A></td><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=&BASE=$html_base_en\" target=\"sample\"><B>Volume</B></A></td><td align=\"center\"><B>Vol ID</B></td></tr>\n";
  }
  else {
    if ($sort_order =~ m/hmc/ ) {
      # sorting per Storage/SDMC/IVM
      print "<tr><td align=\"center\"><B>Storage</B></td><td align=\"center\">&nbsp;&nbsp;<A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=&BASE=$html_base_en\" target=\"sample\"><B>Volume</B></A></td><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=lpar&BASE=$html_base_en\" target=\"sample\"><B>Vol ID</B></A></td></tr>\n";
    }
    else {
      #sorting per server
      print "<tr><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=hmc&BASE=$html_base_en\" target=\"sample\"><B>Storage</B></A></td><td align=\"center\"><B>Volume</B></td><td align=\"center\"><A HREF=\"/stor2rrd-cgi/stor-search.sh?LPAR=$lpar&sort=lpar&BASE=$html_base_en\" target=\"sample\"><B>Vol ID</B></A></td></tr>\n";
    }
  }
}

#print OUT "$uname $aix\n";

#print "<BR><BR>$html_base -- $html_base_en -- $base -- $refer\n";

my $managedname_exl = "";
my @m_excl = "";


foreach my $line (@out) {
  #print "$line<br>\n";
  chomp ($line);
  my $line_org = $line;
  my $managed = $line;
  my $hmc = $line;
  my $lpar = $line;
  $hmc =~ s/ ===separator===.*//;
  $managed =~ s/^.*===separator=== //;
  $managed =~ s/ : .*$//;
  $lpar =~ s/^.*===separator===.* : //;
  $lpar =~ s/;//g;
  $lpar =~ s/0x/ /g;

  my  $lpar_slash = $lpar;
  $lpar_slash =~ s/\&\&1/\//g;
  my $lpar_ok = $lpar_slash;
  #$lpar_slash =~ s/ /&nbsp;/g;
  my $managedn = $managed;
  #$managedn =~ s/ /&nbsp;/g;
  my $hmcn = $hmc;
  #$hmcn =~ s/ /&nbsp;/g;

  print "<tr><td nowrap><A HREF=\"$html_base/$hmc/$FIRST_GLOBAL_SUB/$FIRST_GLOBAL/index.html\" target=\"main\">$hmcn</A></td>\n";

  my $managed_url = urlencode ($managed);

  my $st_type="DS8K";
  if ( -d "$inputdir/data/$hmc/MDISK" ) {
    $st_type="SWIZ";
  }

  print "<td nowrap>&nbsp;&nbsp;<a href=\"/stor2rrd-cgi/detail.sh?host=$hmc&type=VOLUME&name=$managed_url&BASE=$html_base_en&storage=$st_type&none=none\" target=\"sample\">$managedn</a></td>\n";
  print "<td nowrap>$lpar_slash</td></tr>";

}
print "</table><br></BODY></HTML>";

sub urlencode {
    my $s = shift;
    $s =~ s/ /+/g;
    $s =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
    return $s;
}


close (OUT) if $DEBUG == 2;
exit (0);

