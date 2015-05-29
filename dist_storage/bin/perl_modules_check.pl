# test if all perl modules are in place
# Usage: . etc/stor2rrd.cfg; $PERL bin/perl_modules_check.pl $PERL
#

use strict;
use warnings;

my $arg = $ARGV[0];
if ( $#ARGV == -1 ) {
  $arg = "";
}


my @modules= (
	"Date::Parse",
	"RRDp",
	"POSIX qw(strftime)",
	"File::Copy",
	"File::Compare",
	"IO::Socket::INET",
	"MIME::Base64",
        "Data::Dumper", 
        "Env",
        "Storable",
        "XML::Simple",
	"Socket"
);

# those modules are not necessary so far
#"XML::Simple",
#"XML::SAX::PurePerl",

my $error = 0;
foreach (@modules) {
	my $module = $_;
	my $module_def = 1;
	eval "use $module; 1" or $module_def = 0; 	
	if (!$module_def) {
            if ( $error == 0 ) {
               print "\n";
            }
	    print "ERROR: Perl module has not been found: $module\n";
            $error++;
        } 
}

if ( $error > 0 ) {
  print "\n";
  print "Install all missing Perl modules and do this test again, check http://www.stor2rrd.com/install.htm:\n";
  print "Usage: . etc/stor2rrd.cfg; \$PERL bin/perl_modules_check.pl \$PERL\n\n";
  exit (1);
}
exit (0);
