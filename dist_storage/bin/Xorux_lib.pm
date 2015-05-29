package Xorux_lib; 

use strict;
use warnings;
use RRDp;

my $rrdtool = $ENV{RRDTOOL};

sub create_check {
# This function check if rrdtool create will be successful finished.
#
# Usage:
#
# - Program, which calls this function must have:
#     RRDp::start "$rrdtool";
#     RRDp::cmd qq(create ...
#
# - This function is called:
#     if (! lpar2rrd_lib::create_check ("file: $rrd, $one_minute_sample, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
#       error ("unable to create $rrd : at ".__FILE__.": line ".__LINE__);
#       RRDp::end;
#       RRDp::start "$rrdtool";
#       return 0;
#     }
#     return 1;
#
# - return 0 if: RRDp::read error (disc space is full)
#                rrdtool info error (rrd file is not all)
#                wrong sum rows (rows in create procedure are not equal as rows in rrdtool info)
# - else return 1
# - you can set timeout for alarm in eval


  my $data = shift;
  my $timeout = "10";  ##### timeout for alarm
  my $rrdtool = $ENV{RRDTOOL};
  my @rrd_create = split (",", $data);
  my $rrd_file = "";
  my @create_rows;
  my $index = 0;
  foreach my $line (@rrd_create) {
    chomp $line;
    $line =~ s/"//g;
    if ( $line =~ /^file:/ ) {
      $line =~ s/^file: //g;
      $rrd_file = $line;
      next;
    }
    $index++;
    if ( $line =~ /[0-9]+/) {
      $line =~ s/\s+//g;
      push (@create_rows, "$index:$line\n");
    }
  }
  my $answer = "";
### first control
  eval {
    local $SIG{ALRM} = sub {die "rrdtool read died in SIG ALRM: ";};
    alarm($timeout);
    $answer = RRDp::read;
  };
  alarm (0); # must be here after eval
  if ($@) {
    unlink("$rrd_file");
    error ("RRDp::create read error : $rrd_file : $@") && return 0;
  }
  if ( defined $answer ) {
    my $answer_i = "";
### second control
    eval {
      local $SIG{ALRM} = sub {die "rrdtool info died in SIG ALRM: ";};
      alarm($timeout);
      RRDp::cmd qq(info "$rrd_file");
      $answer_i = RRDp::read;
    };
    alarm (0); # must be here after eval
    if ($@) {
      unlink("$rrd_file");
      error ("rrdtool info error : $rrd_file : $@") && return 0;
    }
    my $ret = $$answer_i;
    my @info_rows = split("\n",$ret);
    my $index_i = 0;
    foreach my $line (@info_rows) {
      if ( $line !~ /^rra\[[0-9]\]\.rows/ ) { next; }
      $index_i++;
      $line =~ s/^rra\[[0-9]\]\.rows\s=\s//g;
### third control
      if ( grep {/$index_i:$line/} @create_rows ) {
        next;
      }
      else {
        unlink("$rrd_file");
        error ("RRDp error : $rrd_file : wrong sum rows : $line") && return 0;
      }
		}
  }
  return 1;
}

# error handling
sub error {
  my $text = shift;
  my $act_time = localtime();
  chomp ($text);

#  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}
