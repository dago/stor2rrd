# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


  use strict;
  use LoadDataModule;

  # get cmd line params
  my $version="$ENV{version}";
  my $storage = $ENV{STORAGE_NAME};
  my $st_type = $ENV{STORAGE_TYPE};
  my $webdir = $ENV{WEBDIR};
  my $bindir = $ENV{BINDIR};
  my $basedir = $ENV{INPUTDIR};
  my $DEBUG = $ENV{DEBUG};
  my $new_change="$basedir/tmp/$version-run";
  my $wrkdir = "$basedir/data";
  my $act_time = localtime();
  my $STEP = $ENV{SAMPLE_RATE};
  my $no_time = 1380; # says the time interval when RRDTOOL consideres a gap in input data, usually 3 * 5 + 2 = 17mins
                      # to avoid small gaps every midnight
                      # --> use 23 minutes as default
                      # XIV is further adjusted to 33 minutes (1980) as it uses 15 mins step
                      # When you change it here then update also bin/data_load.pl !!!!
  my $rrdtool = $ENV{RRDTOOL};
  my $upgrade=$ENV{UPGRADE};;


  if ( -f "$bindir/premium.pl" ) {
    require "$bindir/premium.pl";
  }
  else {
    require "$bindir/standard.pl";
  }

  if ( ! -d "$webdir" ) {
     die "$act_time: Pls set correct path to Web server pages, it does not exist here: $webdir\n";
  }

  # start RRD via a pipe
  use RRDp;
  RRDp::start "$rrdtool";

  load_storage();

  # close RRD pipe
  RRDp::end;

  exit (0);

sub load_storage
{
    my $act_time = localtime();

    if ( $storage eq '' ) {
      error ("storage not found : could not parse storage name ");
      exit (1);
    }
    if ( $st_type eq '' ) {
      error ("storage type not found : could not parse storage name ");
      exit (1);
    }
    print "Storage        : $storage\n" if $DEBUG ;
    print "Storage type   : $st_type\n" if $DEBUG ;

    if (! -d "$wrkdir/$storage" ) {
      print "mkdir          : $wrkdir/$storage\n" if $DEBUG ;
      mkdir("$wrkdir/$storage", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage: $!";
    }
    if (! -d "$wrkdir/$storage/VOLUME" ) {
      print "mkdir          : $wrkdir/$storage/VOLUME\n" if $DEBUG ;
      mkdir("$wrkdir/$storage/VOLUME", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/VOLUME: $!";
    }
    if (! -d "$wrkdir/$storage/POOL" ) {
      print "mkdir          : $wrkdir/$storage/POOL\n" if $DEBUG ;
      mkdir("$wrkdir/$storage/POOL", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/POOL: $!";
    }
    if (! -d "$wrkdir/$storage/HOST" ) {
      print "mkdir          : $wrkdir/$storage/HOST\n" if $DEBUG ;
      mkdir("$wrkdir/$storage/HOST", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/HOST: $!";
    }

    if ( $st_type =~ m/^DS8K$/ ) {
      if (! -d "$wrkdir/$storage/RANK" ) {
        print "mkdir          : $wrkdir/$storage/RANK\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/RANK", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/RANK: $!";
      }
      if (! -d "$wrkdir/$storage/PORT" ) {
        print "mkdir          : $wrkdir/$storage/PORT\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/PORT", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/PORT: $!";
      }
      if (! -d "$wrkdir/$storage/VOLUME" ) {
        print "mkdir          : $wrkdir/$storage/VOLUME\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/VOLUME", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/VOLUME: $!";
      }
    }

    if ( $st_type =~ m/^SWIZ$/ ) {
      if (! -d "$wrkdir/$storage/RANK" ) {
        print "mkdir          : $wrkdir/$storage/RANK\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/RANK", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/RANK: $!";
      }
      if (! -d "$wrkdir/$storage/PORT" ) {
        print "mkdir          : $wrkdir/$storage/PORT\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/PORT", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/PORT: $!";
      }
      if (! -d "$wrkdir/$storage/VOLUME" ) {
        print "mkdir          : $wrkdir/$storage/VOLUME\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/VOLUME", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/VOLUME: $!";
      }
      if (! -d "$wrkdir/$storage/DRIVE" ) {
        print "mkdir          : $wrkdir/$storage/DRIVE\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/DRIVE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/DRIVE: $!";
      }
      if (! -d "$wrkdir/$storage/CPU-CORE" ) {
        print "mkdir          : $wrkdir/$storage/CPU-CORE\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/CPU-CORE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/CPU-CORE: $!";
      }
      if (! -d "$wrkdir/$storage/CPU-NODE" ) {
        print "mkdir          : $wrkdir/$storage/CPU-NODE\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/CPU-NODE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/CPU-NODE: $!";
      }
      if (! -d "$wrkdir/$storage/NODE-CACHE" ) {
        print "mkdir          : $wrkdir/$storage/NODE-CACHE\n" if $DEBUG ;
        mkdir("$wrkdir/$storage/NODE-CACHE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$storage/NODE-CACHE: $!";
      }
      if (! -l "$wrkdir/$storage/MDISK" ) {
        print "ln -s          : $wrkdir/$storage/RANK $wrkdir/$storage/MDISK\n" if $DEBUG ;
        symlink("$wrkdir/$storage/RANK","$wrkdir/$storage/MDISK") || die   "$act_time: Cannot ln -s $wrkdir/$storage/MDISK: $!";
      }
    }

    print "data_load      : start : $act_time : $STEP\n" if $DEBUG ;

    if ( $st_type =~ m/^SWIZ$/ ) {
      LoadDataModule::load_data_svc_all ($storage, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }
    if ( $st_type =~ m/^DS8K$/ ) {
      LoadDataModule::load_data_ds8k_all ($storage, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }
    if ( $st_type =~ m/^XIV$/ ) {
      $no_time = 1980; # XIV heart beat time increase due to bigger step (15 minutes)
      LoadDataModule::load_data_xiv_all ($storage, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }
    if ( $st_type =~ m/^DS5K$/ ) {
      LoadDataModule::load_data_ds5_all ($storage, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }

    $act_time = localtime();
    print "data_load      : end   : $act_time\n" if $DEBUG ;
}

sub error
{
  my $text = shift;
  my $act_time = localtime();

  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

sub isdigit
{
  my $digit = shift;
  my $text = shift;

  if ( ! defined($digit) ) {
    return 0;
  }
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


