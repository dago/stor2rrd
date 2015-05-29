#!/usr/bin/perl
# generates JSON data structures
use strict;

# use warnings;
# use CGI::Carp qw(fatalsToBrowser);
# use Data::Dumper;

my $DEBUG           = $ENV{DEBUG};
my $GUIDEBUG        = $ENV{GUIDEBUG};
my $DEMO            = $ENV{DEMO};
my $BETA            = $ENV{BETA};
my $version         = $ENV{version};
my $errlog          = $ENV{ERRLOG};
my $basedir         = $ENV{INPUTDIR};
my $webdir          = $ENV{WEBDIR};
my $inputdir        = $ENV{INPUTDIR};
my $dashb_rrdheight = $ENV{DASHB_RRDHEIGHT};
my $dashb_rrdwidth  = $ENV{DASHB_RRDWIDTH};
my $legend_height   = $ENV{LEGEND_HEIGHT};
my $jump_to_rank    = $ENV{JUMP_TO_RANK};

if ($jump_to_rank) {
  $jump_to_rank = "true";
}
else {
  $jump_to_rank = "false";
}

my $md5module = 1;
eval "use Digest::MD5 qw(md5_hex); 1" or $md5module = 0;

if ( !$md5module ) {
  use lib "../bin";
  use MD5 qw(md5_hex);
}

my @gtree;     # Globals
my @ctree;     # Customs
my @ftree;     # Favourites
my %htree;     # HMCs
my @ttree;     # Tail
my %stree;     # Servers
my %types;     # storage types
my %rtree;     # Removed LPARs
my %lstree;    # LPARs by Server
my %lhtree;    # LPARs by HMC
my %wtree;     # WPARs
my @lnames;    # LPAR name (for autocomplete)
my %times;     # server timestamps
my $free;      # 1 -> free / 0 -> full
my $entitle;

# set unbuffered stdout
#$| = 1;

open( OUT, ">> $errlog" ) if $DEBUG == 2;

# get QUERY_STRING
use Env qw(QUERY_STRING);
print OUT "-- $QUERY_STRING\n" if $DEBUG == 2;

#`echo "QS $QUERY_STRING " >> /tmp/xx32`;
my ( $jsontype, $par1, $par2 ) = split( /&/, $QUERY_STRING );

if ( $jsontype eq "" ) {
  if (@ARGV) {
    $jsontype = "jsontype=" . $ARGV[0];
    $basedir  = "..";
  }
  else {
    $jsontype = "jsontype=dump";
  }
}

$jsontype =~ s/jsontype=//;

if ( $jsontype eq "test" ) {
  $basedir = "..";
  &test();
  exit;
}

if ( $jsontype eq "dump" ) {
  &dumpHTML();
  exit;
}

# CGI-BIN HTML header
if ( !@ARGV ) {
  print "Content-type: application/json\n\n";
}

if ( $jsontype eq "menu" ) {
  &mainMenu();
  exit;
}

if ( $jsontype eq "menuh" ) {
  &mainMenuHmc();
  exit;
}
elsif ( $jsontype eq "lparsel" ) {
  &lparSelect();
  exit;
}
elsif ( $jsontype eq "hmcsel" ) {
  &hmcSelect();
  exit;
}
elsif ( $jsontype eq "times" ) {
  &times();
  exit;
}
elsif ( $jsontype eq "powersel" ) {
  &print_all_models();
  exit;
}
elsif ( $jsontype eq "pools" ) {
  &poolsSelect();
  exit;
}

elsif ( $jsontype eq "lparnames" ) {
  &readMenu();
  $par1 =~ s/term=//;
  &lparNames($par1);
  exit;
}
elsif ( $jsontype eq "histrep" ) {
  &readMenu();
  $par1 =~ s/hmc=//;
  $par2 =~ s/managedname=//;
  &histReport( $par1, $par2 );
  exit;
}
elsif ( $jsontype eq "env" ) {
  &readMenu();
  &sysInfo();
  exit;
}
elsif ( $jsontype eq "pre" ) {
  &readMenu();
  &genPredefined();
  exit;
}
elsif ( $jsontype eq "cust" ) {
  &readMenu();
  &custGroupsSelect();
  exit;
}
elsif ( $jsontype eq "aclgrp" ) {
  &readMenu();
  &aclGroups();
  exit;
}
elsif ( $jsontype eq "fleet" ) {
  &readMenu();
  &genFleetTree();
  exit;
}

sub sysInfo() {
  print "{\n";    # envelope begin
  print "\"version\":\"$version\",\n";
  print "\"free\":\"$free\",\n";
  print "\"entitle\":\"$entitle\",\n";
  print "\"dashb_rrdheight\":\"$dashb_rrdheight\",\n";
  print "\"dashb_rrdwidth\":\"$dashb_rrdwidth\",\n";
  print "\"legend_height\":\"$legend_height\",\n";
  print "\"jump_to_rank\":$jump_to_rank,\n";
  print "\"guidebug\":\"$GUIDEBUG\",\n";
  print "\"beta\":\"$BETA\",\n";
  print "\"demo\":\"$DEMO\"\n";
  print "}\n";    # envelope end
}

sub dumpHTML() {
  print "Content-type: application/octet-stream\n";
  print("Content-Disposition:attachment;filename=debug.txt\n\n");
  my $buffer;
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
  my @pairs = split( /&/, $buffer );

  my @q = split( /=/, $pairs[1] );
  my $html = urldecode( $q[1] );
  print $html;

  #use CGI;
  #use CGI('header');
  #print header(-type=>'application/octet-stream',
  #       -attachment=>'debug.txt');
  #my $q = new CGI;
  #print $q->param('tosave');

}

sub test () {
  &readMenu();
  print Dumper %htree;
  if ( exists $htree{'sdmc'} ) {
    print $htree{'sdmc'};
  }
  print "\n";
}

sub mainMenu () {
  &readMenu();
  my $hash = substr( md5_hex("DASHBOARD"), 0, 7 );
  ### Generate JSON
  print "[\n";    # envelope begin
  print
      "{\"title\":\"DASHBOARD\",\"extraClasses\":\"boldmenu\",\"href\":\"dashboard.html\",\"hash\":\"$hash\"},\n";
  &globalWoTitle();

  &genServersReduced();    # List by Servers

  #	&genHMCs ();  # List by HMCs

  &tail();
  print "\n]\n";           # envelope end
  ### End of JSON
}

sub mainMenuHmc () {
  &readMenu();
  my $hash = substr( md5_hex("DASHBOARD"), 0, 7 );
  ### Generate JSON
  print "[\n";             # envelope begin
  print
      "{\"title\":\"DASHBOARD\",\"extraClasses\":\"boldmenu\",\"href\":\"dashboard.html\",\"hash\":\"$hash\"},\n";
  &globalWoTitle();

  &genHMCs();              # List by HMCs

  &tail();
  print "\n]\n";           # envelope end
  ### End of JSON
}

sub lparSelect() {
  &readMenu();
  ### Generate JSON
  print "[\n";             # envelope begin
  &genLpars();             # List by Servers
  print "\n]\n";           # envelope end
  ### End of JSON
}

sub hmcSelect() {
  &readMenu();
  ### Generate JSON
  print "[\n";             # envelope begin
  &genHmcSelect();         # List by HMCs
  print "\n]\n";           # envelope end
  ### End of JSON
}

sub times () {
  &readMenu();
  my @sorted = sort { $times{$b} <=> $times{$a} } keys %times;

  print Dumper \%times;

  #	print Dumper \@sorted;
  for my $srv ( sort keys %times ) {
    for my $hmc (
      sort { $times{$srv}{$b} <=> $times{$srv}{$a} }
      keys %{ $times{$srv} }
        )
    {
      print Dumper $hmc;
    }
  }
}

sub poolsSelect() {
  &readMenu();
  ### Generate JSON
  print "[\n";      # envelope begin
  &genPools();      # generate list of Pools
  print "\n]\n";    # envelope end
  ### End of JSON
}

sub custGroupsSelect() {
  ### Generate JSON
  print "[\n";      # envelope begin
  &genCusts();      #
  print "\n]\n";    # envelope end
  ### End of JSON
}

sub readMenu () {
  my $skel = "$basedir/tmp/menu.txt";

  open( SKEL, $skel ) or die "Cannot open file: $!\n";

  while ( my $line = <SKEL> ) {
    my ( $hmc, $srv, $txt, $url );
    chomp $line;
    my @val = split( ':', $line );
    for (@val) {
      &collons($_);
    }
    {
      "O" eq $val[0] && do {
        $free = ( $val[1] == 1 ) ? 1 : 0;
        last;
      };
      "G" eq $val[0] && do {
        my ( $txt, $url ) = ( $val[2], $val[3] );
        if ( $txt eq "HMC totals" ) { last; }
        push @gtree, [ $txt, $url ];
        last;
      };
      "F" eq $val[0] && do {
        my ( $txt, $url ) = ( $val[2], $val[3] );
        push @ftree, [ $txt, $url ];
        last;
      };
      "C" eq $val[0] && do {
        my ( $txt, $url ) = ( $val[2], $val[3] );
        push @ctree, [ $txt, $url ];
        last;
      };
      "H" eq $val[0] && do {
        ( $hmc, $txt, $url ) = ( $val[1], $val[2], $val[3] );
        if ( $txt . $url ) {
          $htree{$hmc}{$txt} = $url;
        }
        last;
      };

# aggregates
#A:DS05:POOL:read_io:Read IO:/stor2rrd-cgi/detail.sh?host=DS05&type=POOL&name=read_io&storage=DS8K&item=sum&gui=1&none=none::
      "A" eq $val[0] && do {
        my ( $storage, $subsys, $agg, $txt, $url, $timestamp )
            = ( $val[1], $val[2], $val[3], $val[4], $val[5], $val[7] );
        if ($timestamp) {
          $times{$subsys}{$storage} = $timestamp;
        }
        $subsys =~ s/&nbsp;/ /g;
        push @{ $stree{$subsys}{$storage} }, [ $txt, $url, $agg ];
        if ( !exists $types{$storage} ) {
          $url =~ /.*&storage=([^&]*)/;
          $types{$storage} = $1;
        }
        last;
      };
      "L" eq $val[0] && do {
        my ( $storage, $subsys, $atxt, $txt, $url ) = ( $val[1], $val[2], $val[3], $val[4], $val[5] );
        $subsys =~ s/&nbsp;/ /g;
        push @{ $lhtree{$storage}{$subsys} }, [ $txt => $url, $atxt ];
        if ( $subsys eq "Managed disk" ) {
          $subsys = 'RANK';
        }
        elsif ( $subsys eq "CPU-CORE" ) {
          $subsys = 'CPU-NODE';
        }
        elsif ( $subsys eq "CPU util" ) {
          $subsys = 'CPU-NODE';
        }
        push @{ $lstree{$storage}{$subsys} }, [ $txt => $url, $atxt ];
        push @lnames, $txt;
        last;
      };

#R:ahmc11:BSRV21:BSRV21LPAR5:BSRV21LPAR5:/lpar2rrd-cgi/detail.sh?host=ahmc11&server=BSRV21&lpar=BSRV21LPAR5&item=lpar&entitle=0&gui=1&none=none::
      "R" eq $val[0] && do {
        my ( $hmc, $srv, $txt, $url ) = ( $val[1], $val[2], $val[4], $val[5] );
        push @{ $rtree{$hmc}{$srv} }, [ $txt => $url ];

        # push @lnames, $txt;
        last;
      };
      "T" eq $val[0] && do {
        my ( $txt, $url ) = ( $val[2], $val[3] );
        push @ttree, [ $txt, $url ];
        last;
      };

    };
  }

  close(SKEL);
}

### Generate STORAGE submenu
sub genHMCs {
  print "{\"title\":\"STORAGE\",\"folder\":\"true\",\"expanded\":true,\"children\":[\n";
  my $n1 = "";
  for my $hmc ( sort keys %lhtree ) {
    print $n1 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
    hmcTotals($hmc);
    $n1 = ",";
    my $n2 = "";
    foreach my $srv ( 'CPU-NODE', 'CPU util', 'POOL', 'RANK', 'Managed disk', 'VOLUME', 'DRIVE', 'PORT',
      'HOST' )
    {
      if ( exists $stree{$srv}->{$hmc} ) {

        # if (exists $lhtree{$hmc}{$srv} ) {
        print $n2 . "{\"title\":\"$srv\",\"folder\":\"true\",\"children\":[\n";
        $n2 = ",";
        if ( exists $stree{$srv}->{$hmc} ) {
          server( $hmc, $srv );
          if ( exists $lhtree{$hmc}{$srv} ) {
            print ",\n";
          }
        }
        if ( exists $lhtree{$hmc}{$srv} ) {
          print "{\"title\":\"Items\",\"folder\":\"true\",\"children\":[\n";
          my $n3 = "";
          for my $lpar ( @{ $lhtree{$hmc}->{$srv} } ) {

            #print Dumper $lpar;
            my $alt = @$lpar[2];

            # my $alt = "";
            # if ($srv eq 'POOL' || $srv eq 'RANK' || $srv eq 'Managed disk') {
            #  $alt = @$lpar[2];
            #}
            print $n3 . &fullNode( @$lpar[0], @$lpar[1], $hmc, $srv, 1, $alt );
            $n3 = ",";
          }    # L3 END
          if ( exists $rtree{$hmc}->{$srv} ) {
            print $n3 . "\n{\"title\":\"Removed\",\"folder\":\"true\",\"children\":[\n";
            my $n4 = "";
            for my $removed ( @{ $rtree{$hmc}->{$srv} } ) {
              print $n4 . &fullNode( @$removed[0], @$removed[1], $hmc, $srv, 1 );
              $n4 = ",\n";
            }
            print "]}";
          }
          print "]}";
        }
        print "]}\n";
      }    # L2 END
    }
    print "]}\n";
  }
  print "]},\n";
}

### Generate HMC select tree
sub genHmcSelect {
  my $n1 = "";
  for my $hmc ( sort keys %lhtree ) {
    print $n1 . "{\"title\":\"$hmc\",\"folder\":\"true\",\"children\":[\n";
    $n1 = ",";
    my $n2 = "";
    for my $srv ( sort keys %{ $lhtree{$hmc} } ) {
      print $n2 . "{\"title\":\"$srv\",\"folder\":\"true\",\"children\":[\n";
      $n2 = ",";
      print "{\"title\":\"LPAR\",\"folder\":\"true\",\"children\":[\n";
      my $n3 = "";
      for my $lpar ( @{ $lhtree{$hmc}->{$srv} } ) {
        my $value = "$hmc|$srv|@$lpar[0]";
        print $n3 . "{\"title\":\"@$lpar[0]\",\"icon\":false,\"key\":\"$value\"}";
        $n3 = ",";
      }    # L3 END
      if ( exists $rtree{$hmc}->{$srv} ) {
        for my $removed ( @{ $rtree{$hmc}->{$srv} } ) {
          my $value = "$hmc|$srv|@$removed[0]";
          print $n3 . "\n"
              . "{\"title\":\"@$removed[0]\",\"icon\":false,\"extraClasses\":\"removed\",\"key\":\"$value\"}";
        }
      }
      print "]}]}";
    }    # L2 END
    print "]}\n";
  }
}

sub histReport {
  my ( $hmc, $server ) = @_;
  print "[\n";

  # print "{\"title\":\"SELECT ALL\",\"folder\":\"true\",\"expanded\":true,\"children\":[\n";
  my $n3 = "";
  for my $lpar ( @{ $lstree{$hmc}->{$server} } ) {

    #print Dumper $lpar;
    my $value = "@$lpar[2]";

    #if ($server eq 'POOL' || $server eq 'RANK') {
    # 	$value = "@$lpar[2]";
    #}
    print $n3 . "{\"title\":\"@$lpar[0]\",\"icon\":false,\"key\":\"$value\"}";
    $n3 = ",\n";
  }
  if ( exists $rtree{$hmc}->{$server} ) {
    for my $removed ( @{ $rtree{$hmc}->{$server} } ) {
      print $n3 . "\n"
          . "{\"title\":\"@$removed[0]\",\"icon\":false,\"extraClasses\":\"removed\",\"key\":\"@$removed[0]\"}";
    }
  }

  #print "]}";

  print "]";

}

sub genPredefined() {
  print "[\n";    # envelope begin
  my $delim = "";
  my $hash  = "";
  for my $srv ( sort keys %types ) {
    $hash = substr( md5_hex( $srv . "POOL" . "SubSys_SUM" ), 0, 7 );
    if ( $types{$srv} eq "DS5K" ) {
      print $delim . "\"" . $hash . "jd\"";    # POLL IO daily total
      $delim = ",\n";
    }
    else {
      print $delim . "\"" . $hash . "md\"";    # POOL IO daily read
      $delim = ",\n";
      print $delim . "\"" . $hash . "nd\"";    # POOL IO daily write
    }
  }
  print "\n]\n";                               # envelope end
}

sub urlencode {
  my $s = shift;
  $s =~ s/ /+/g;
  $s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  $s =~ s/\+/ /g;
  return $s;
}

### Global section
sub global {
  my $fsub = 0;
  my $csub = 0;
  my $hsub = 0;

  print "{\"title\":\"GLOBAL\",\"folder\":\"true\",\"children\":[\n";
  if ( @ftree > 0 ) {
    $fsub = 1;
  }
  if ( @ctree > 0 ) {
    $csub = 1;
  }
  my $delim = '';
  for (@gtree) {
    my ( $t, $u ) = ( @$_[0], @$_[1] );
    {
      print $delim;
      ( ( lc $t eq "favourites" )    && $fsub ) && do { &favs();  last; };
      ( ( lc $t eq "custom groups" ) && $csub ) && do { &custs(); last; };
      if ( lc $t eq "cpu workload estimator"
        || lc $t eq "resource configuration advisor" )
      {
        print &txthrefbold( $t, $u );
      }
      else {
        print &txthref( $t, $u );
      }
    }
    $delim = ",\n";
  }
  print "]},";
}

### Global section without Title
sub globalWoTitle {
  my $fsub = 0;
  my $csub = 0;
  my $hsub = 0;

  if ( @ftree > 0 ) {
    $fsub = 1;
  }
  if ( @ctree > 0 ) {
    $csub = 1;
  }
  my $delim = '';
  for (@gtree) {
    my ( $t, $u ) = ( @$_[0], @$_[1] );
    {
      print $delim;
      ( ( lc $t eq "favourites" )    && $fsub ) && do { &favs();  last; };
      ( ( lc $t eq "custom groups" ) && $csub ) && do { &custs(); last; };
      if ( lc $t eq "cpu workload estimator"
        || lc $t eq "resource configuration advisor" )
      {
        print &txthrefbold( $t, $u );
      }
      else {
        print &txthref( $t, $u );
      }
    }
    $delim = ",\n";
  }
  print $delim;
}

### Favourites
sub favs {
  print "{\"title\":\"FAVOURITES\",\"folder\":\"true\",\"children\":[\n";
  my $delim = '';
  for (@ftree) {
    print $delim . &txthref( @$_[0], @$_[1] );
    $delim = ",\n";
  }
  print "]}";
}
### Custom Groups
sub custs {
  print "{\"title\":\"CUSTOM GROUPS\",\"folder\":\"true\",\"children\":[\n";
  my $delim = '';
  for (@ctree) {
    print $delim . &fullNode( @$_[0], @$_[1], "na", "na", 0 );

    # print $delim . &txthref(@$_[0], @$_[1]);
    $delim = ",\n";
  }
  print "]}";
}

### HMC submenu
sub hmcs {

  #	print "{\"title\":\"HMC totals\",\"folder\":\"true\",\"children\":[\n";
  my $delim = '';
  for (%htree) {
    print $delim . &txthref( @$_[0], @$_[1] );
    $delim = ",\n";
  }

  #	print "]}";
}

### single HMC Totals
sub hmcTotals {
  my ($hmc) = @_;

  #	print Dumper \%htree;
  if ( exists $htree{$hmc} ) {
    my $delim = '';
    for ( sort keys %{ $htree{$hmc} } ) {
      print $delim . &txthref( $_, $htree{$hmc}{$_} );
      $delim = ",\n";
    }
    print "$delim";
  }
}

### Tail menu section
sub tail {
  print
      "{\"title\":\"STOR2RRD <span style='font-weight: normal'>($version)</span>\",\"folder\":\"true\",\"children\":[\n";
  my $delim = '';
  for (@ttree) {
    print $delim . &txthref( @$_[0], @$_[1] );
    $delim = ",\n";
  }
  if ( $GUIDEBUG == 1 ) {
    print $delim . &txthref( "Load debug content", "debug.txt" );
  }
  print "]}";
}

### Single Server menu
# params: (hmc, srv)
sub server {
  my ( $h, $s ) = @_;
  my $delim = '';
  my $isLpar = ( $s eq "HOST" ) ? 1 : 0;
  for ( @{ $stree{$s}->{$h} } ) {
    print $delim . &fullNode( @$_[0], @$_[1], $h, $s, $isLpar, @$_[2] );
    $delim = ",\n";
  }
}

sub lparNames () {
  my @unique = sort ( do {
      my %seen;
      grep { !$seen{$_}++ } @lnames;
        }
  );
  print "[";
  if (@_) {
    @unique = grep( {/@_/i} @unique );
  }
  my $delim = '';
  for (@unique) {

    #		print Dumper $_;
    print $delim . "{\"value\":\"$_\"}";
    $delim = ",\n";
  }
  print "]";
}

sub txthref {
  my $hash = substr( md5_hex( $_[0] ), 0, 7 );
  return "{\"title\":\"$_[0]\",\"icon\":false,\"href\":\"$_[1]\",\"hash\":\"$hash\"}";
}

sub fullNode {
  my ( $title, $href, $hmc, $srv, $islpar, $altname ) = @_;
  my $key = ( $srv eq "na" ? "" : $srv ) . " " . $title;
  if ( $srv eq "Managed disk" ) {
    $srv = "RANK";
  }
  if ( $srv eq "CPU util" ) {
    $srv = "CPU-NODE";
  }
  if ( $srv eq "CPU-CORE" ) {
    $srv = "CPU-NODE";
  }
  if ( !$islpar ) {
    my $hashstr = $hmc . $srv . "SubSys_SUM";
    my $hash = substr( md5_hex($hashstr), 0, 7 );

# return "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"altname\":\"$altname\",\"agg\":true,\"str\":\"$key\",\"hashstr\":\"$hashstr\"}";
    return
        "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"altname\":\"$altname\",\"agg\":true,\"str\":\"$key\"}";
  }
  else {
    my $hashstr = $hmc . $srv . $altname;
    my $hash = substr( md5_hex($hashstr), 0, 7 );

# return "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"altname\":\"$altname\",\"str\":\"$key\",\"hashstr\":\"$hashstr\"}";
    return
        "{\"title\":\"$title\",\"href\":\"$href\",\"hash\":\"$hash\",\"hmc\":\"$hmc\",\"srv\":\"$srv\",\"altname\":\"$altname\",\"str\":\"$key\"}";
  }
}

sub txthrefbold {
  return "{\"title\":\"$_[0]\",\"icon\":false,\"extraClasses\":\"boldmenu\",\"href\":\"$_[1]\"}";
}

sub txthref_wchld {
  return "{\"title\":\"$_[0]\",\"icon\":false,\"href\":\"$_[1]\",\"children\":[";
}

sub txtkey {
  return "{\"title\":\"$_[0]\",\"icon\":false,\"key\":\"$_[1]\"}";
}

sub txtkeysel {
  return "{\"title\":\"$_[0]\",\"icon\":false,\"selected\":true,\"key\":\"$_[1]\"}";
}

sub collons {
  return s/===double-col===/:/g;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}
