

  #use strict;
  # no strict as definition of @inp does not work with it, o idea why ....

  #use lib qw (/opt/freeware/lib/perl/5.8.0);
  # no longer need to use "use lib qw" as the library PATH is already in PERL5LIB (lpar2rrd.cfg)

  use Env qw(QUERY_STRING);
  use Date::Parse;

  $QUERY_STRING .= ":.";

  my $inputdir = $ENV{INPUTDIR};
  my $webdir = $ENV{WEBDIR};
  my $wrkdir = "$inputdir/data";
  my $DEBUG = $ENV{DEBUG};
  my $errlog = $ENV{ERRLOG};

  my $bindir = $ENV{BINDIR};


  open(OUT, ">> $errlog") if $DEBUG == 2 ;

  (my $ftype, my $gui) = split(/&/,$QUERY_STRING);

  $ftype =~ s/name=//;
  $ftype =~ s/:\.$//;
  $gui   =~ s/gui=//;

  if ( ! isdigit($gui) ) {
    $gui=0
  }

  if ( $gui == 0 ) {
    print_header();
  }



  if ( $ftype =~ m/^maincfg$/ )  { print_plain ($ftype,"stor2rrd.cfg","Main configuration file: ") }
  if ( $ftype =~ m/^stcfg$/ )    { print_plain ($ftype,"storage-list.cfg","Storage list: ") }
  if ( $ftype =~ m/^aliascfg$/ ) { print_plain ($ftype,"alias.cfg","Alias config file") }
  if ( $ftype =~ m/^errlog$/ )   { print_log   ($ftype,"error.log","Main error log (last 500 rows):") }
  if ( $ftype =~ m/^errcgi$/ )   { print_log   ($ftype,"error-cgi.log","CGI-BIN error log (last 500 rows):") }
  if ( $ftype =~ m/^errcli$/ )   { print_log   ($ftype,"error_st.log","Storage CLI error log (last 500 rows):") }

  print_trailer ();

  exit 0;



sub print_plain
{
  my $ftype = shift;
  my $file_base = shift;
  my $text = shift;
  my $file = $inputdir."/etc/".$file_base;

  open(FH, "< $file") || error ("$0: Can't open $file") && return 0;
  print "<CENTER><B>$text $file</B></CENTER><PRE>";
  foreach my $line (<FH>) {
    print "$line";
  }
  return 1;
}

sub print_valid
{
  my $ftype = shift;
  my $file_base = shift;
  my $text = shift;
  my $file = $inputdir."/etc/".$file_base;

  open(FH, "< $file") || error ("$0: Can't open $file") && return 0;
  print "<CENTER><B>$text $file</B></CENTER><PRE>";
  foreach my $line (<FH>) {
    if ( $line =~ m/^#LPAR/ || $line =~ m/^#POOL/ ) {
      next; # print only valid lines
    }
    if ( $ftype =~ m/custcfg/ ) {
      if ( $line =~ m/^LPAR/ || $line =~ m/^POOL/ ) {
        my $group = "";
        (my $type, my $server, my $lpar, $group) = split(/:/,$line);
        if ( $group =~ m/^$/ ) {
          next; # print only valid lines
        }
      }
    }
    print "$line";
  }
  return 1;
}

sub print_log
{
  my $ftype = shift;
  my $file_base = shift;
  my $text = shift;
  my $file = $inputdir."/logs/".$file_base;

  open(FH, "< $file") || error ("$0: Can't open $file") && return 0;
  print "<CENTER><B>$text $file</B></CENTER><PRE>";

  my @lines = reverse <FH>;
  my $count = 0;
  foreach my $line (@lines) {
    $count++;
    if ( $count == 500 ) {
      last;
    }
    print "$line";
  }
  return 1;
}

sub print_trailer
{

  print "</pre></body></html>\n";

  return 1;
}

sub print_header
{

# print HTML header
print "Content-type: text/html

<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 Final//EN\">
<HTML>
<HEAD>
  <TITLE>STOR2RRD</TITLE>
  <META HTTP-EQUIV=\"pragma\" CONTENT=\"no-cache\">
  <META HTTP-EQUIV=\"Expires\" CONTENT=\"NOW\">
  <META HTTP-EQUIV=\"last modified\" CONTENT=\"NOW\">
<style>
<!--
a {text-decoration: none}
-->
</style>
</HEAD>
<BODY BGCOLOR=\"#D3D2D2\" TEXT=\"#000000\" LINK=\"#0000FF\" VLINK=\"#0000FF\" ALINK=\"#FF0000\" >
";

return 0;
}

# error handling
sub error
{
  my $text = shift;
  my $act_time = localtime();

  print "<pre>\n\nERROR          : $text : $!\n</pre>";
  print STDERR "$act_time: $text : $!\n";

  return 1;
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

