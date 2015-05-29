
# workaround for AIX 7.1 problem: 
# Can't locate object method "new" via package "XML::LibXML::SAX" at /usr/opt/perl5/lib/site_perl/5.10.1/XML/SAX/ParserFactory.pm line 43. 

use XML::Simple; 

if ( $XML::SAX::PurePerl::VERSION > 0.90 ) {
  # PurePerl v0.90 causing this problem: Name contains invalid start character: '&#x3E;' so no workaround
  $XML::Simple::PREFERRED_PARSER = "XML::SAX::PurePerl"; 
  use XML::SAX::PurePerl; 
} 

# Sometimes on AIX can happen that perl 5.8.8 with PurePerl v0.90 and error: Can't locate object method "new" via package "XML::LibXML::SAX"
# perl -e 'use XML::Simple; use XML::SAX::PurePerl;  print "$XML::SAX::PurePerl::VERSION\n";'
# --> install v0.99 from here: http://search.cpan.org/~grantm/XML-SAX-0.99/
# or install from perzl.org
#                  perl-XML-LibXML-2.0012-1.aix5.1.ppc.rpm
#                  perl-XML-LibXML-Common-0.13-1.aix5.1.ppc.rpm
#                  perl-XML-SAX-0.99-1.aix5.1.noarch.rpm



return 1;
