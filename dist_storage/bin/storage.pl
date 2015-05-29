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
  use Date::Parse;
  use Math::BigInt;
  use File::Copy;
  use RRDp;

  # our modules
  use Storcfg2html;
  use LoadDataModule;
  use Xorux_lib;


  #use lib qw (/opt/freeware/lib/perl/5.8.0);
  # no longer need to use "use lib qw" as the library PATH is already in PERL5LIB env var (lpar2rrd.cfg)


  # set unbuffered stdout
  $| = 1;

  # get cmd line params
  my $version="$ENV{version}";
  my $storage = $ENV{STORAGE};
  my $host = $ENV{STORAGE};
  my $st_type = $ENV{STORAGE_TYPE};
  my $webdir = $ENV{WEBDIR};
  my $bindir = $ENV{BINDIR};
  my $basedir = $ENV{INPUTDIR};
  my $rrdtool = $ENV{RRDTOOL};
  my $DEBUG = $ENV{DEBUG};
  my $pic_col = $ENV{PICTURE_COLOR};
  my $STEP = $ENV{SAMPLE_RATE};
  my $stor2txt = $ENV{STOR2TXT};
  my $upgrade=$ENV{UPGRADE};
  my $h = $ENV{HOSTNAME};
  my $tmp_dir = "$basedir/tmp";
  my $new_change="$tmp_dir/$version-run";

  #print "++ $host $storage_user $basedir $webdir $STEP\n";
  my $wrkdir = "$basedir/data"; 

  if ( -f "$bindir/premium.pl" ) {
    require "$bindir/premium.pl";
  }
  else {
    require "$bindir/standard.pl";
  }

  # Global definitions
  my $not_execute_rrdtool = 1; # new GUI, create only RRDTool command files
  my $no_time = 1380; # says the time interval when RRDTOOL consideres a gap in input data, usually 3 * 5 + 2 = 17mins
		      # to avoid small gaps every midnight
                      # --> use 23 minutes as default
                      # XIV is further adjusted to 33 minutes (1980) as it uses 15 mins step
  my $YEAR_REFRESH = 72000 ;  # 20 hour, minimum time in sec when yearly graphs are updated (refreshed)
  my $MONTH_REFRESH = 20000 ; # 5 hour, minimum time in sec when monthly graphs are updated (refreshed)
  my $WEEK_REFRESH = 7000;    # minimum time in sec when weekly  graphs are updated (refreshed)
  my $font_def_normal =  "--font=DEFAULT:7:";
  my $font_tit_normal =  "--font=TITLE:9:";


  if ( $upgrade == 1 ) {
    $YEAR_REFRESH = 0;  # to force creation of trend graphs
  }

  my $IO_MAX = $ENV{VOLUME_IO_MAX}; # which volumes place into volume aggregated graph
  my $DATA_MAX = $ENV{VOLUME_DATA_MAX}; # which volumes place into volume aggregated graph
  my $RESPONSE_MAX = $ENV{VOLUME_RESPONSE_MAX}; # which volumes place into volume aggregated graph
  my $CACHE_MAX = $ENV{VOLUME_CACHE_MAX}; # which volumes place into volume aggregated graph

  if ( ! defined($IO_MAX) || $IO_MAX eq '' ) { 
    $IO_MAX = 50; # default IO max 
  }
  if ( ! defined($DATA_MAX) || $DATA_MAX eq '' ) { 
    $DATA_MAX = 500; # default data max  (kBytes)
  }
  if ( ! defined($RESPONSE_MAX) || $RESPONSE_MAX eq '' ) { 
    $RESPONSE_MAX = 1; # default response time max  (ms)
  }
  if ( ! defined($CACHE_MAX) || $CACHE_MAX eq '' ) { 
    $CACHE_MAX = 1; # default cache max (kBytes)
  }
  my $disable_rrdtool_tag = "--interlaced";  # just nope string, it is deprecated anyway
  my $delimiter = "XORUX"; # this is for rrdtool print lines for clickable legend
  my $delim_com = "XOR_COM"; #delimiter when comments from rrd are needed

  rrdtool_graphv();

  my @color=("#FF0000", "#0000FF", "#FFFF00", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#FF00FF", "#800080",
"#FDD017", "#0000A0", "#3BB9FF", "#008000", "#800000", "#ADD8E6", "#F778A1", "#800517", "#736F6E", "#F52887",
"#C11B17", "#5CB3FF", "#A52A2A", "#FF8040", "#2B60DE", "#736AFF", "#1589FF", "#98AFC7", "#8D38C9", "#307D7E",
"#F6358A", "#151B54", "#6D7B8D", "#FDEEF4", "#FF0080", "#F88017", "#2554C7", "#FFF8C6", "#D4A017", "#306EFF",
"#151B8D", "#9E7BFF", "#EAC117", "#E0FFFF", "#15317E", "#6C2DC7", "#FBB917", "#FCDFFF", "#15317E", "#254117",
"#FAAFBE", "#357EC7", "#4AA02C", "#38ACEC", "#C0C0C0");

  my $color_max = 53;
  my @color_lpar="";
  my $color_rest_of_vols = "#000000";
  my @mdisk_trans = ""; # mdisk name translation, must be global one

  # global for pool translation
  my @pool_tr_table_id = "";
  my @pool_tr_table_name = "";

  my $prem = premium ();
  print "STOR2RRD $prem version $version\n" if $DEBUG ;
  print "Host           : $h\n" if $DEBUG ;

  my $act_time = localtime();

  if ( ! -d "$webdir" ) {
     die "Pls set correct path to Web server pages, it does not exist here: $webdir\n";
  }

  cfg_config_change ();

  # use 1h alert here to be sure (it hang reading from FIFO in RB)
  my $timeout = 3600;
  if ( $upgrade == 1 ) {
    $timeout = $timeout * 10;
  }
  eval {
    my $act_time = localtime();
    local $SIG{ALRM} = sub {die "$act_time: $storage : died in SIG ALRM : load_host";};
    print "Alarm          : $timeout\n" if $DEBUG ;
    alarm($timeout);

    # start RRD via a pipe
    RRDp::start "$rrdtool";

    print "RRDTool version: $RRDp::VERSION \n";

    load_host();

    # close RRD pipe
    RRDp::end;
    alarm (0);
  };

  if ($@) {
    if ($@ =~ /died in SIG ALRM/) {
      my $act_time = localtime();
      error ("$storage : load_host timed out after : $timeout seconds ".__FILE__.":".__LINE__);
    }
    else {
      error ("$storage : load_host failed: $@ ".__FILE__.":".__LINE__);
      exit (1);
    }
  }

  exit (0);

sub load_host  
{

    my $rrd_ver = $RRDp::VERSION;
    if ( isdigit($rrd_ver) && $rrd_ver > 1.35 ) {
      $disable_rrdtool_tag = "--disable-rrdtool-tag";
    }

    if ( $host eq '' ) {
      error ("host not found : could not parse storage name : $host ".__FILE__.":".__LINE__);
      exit (1);
    }
    if ( $st_type eq '' ) {
      error ("host type not found : could not parse storage name : $st_type ".__FILE__.":".__LINE__);
      exit (1);
    }
    print "Storage        : $host\n" if $DEBUG ;
    print "Storage type   : $st_type\n" if $DEBUG ;
    print "IO/DATA limits : volume limits : IO_MAX:$IO_MAX; DATA_MAX:$DATA_MAX RESPONSE_MAX:$RESPONSE_MAX CACHE_MAX:$CACHE_MAX\n" if $DEBUG ;

    create_dir_structure ($webdir,$wrkdir,$host,$st_type,$tmp_dir);

    if ( $st_type =~ m/^SWIZ$/ ) {
      if ( ! -f "$wrkdir/$host/SWIZ" ) {
        `touch "$wrkdir/$host/SWIZ"`;
      }
      LoadDataModule::load_data_svc_all ($host, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }
    if ( $st_type =~ m/^DS8K$/ ) {
      if ( ! -f "$wrkdir/$host/DS8K" ) {
        `touch "$wrkdir/$host/DS8K"`;
      }
      LoadDataModule::load_data_ds8k_all ($host, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }
    if ( $st_type =~ m/^XIV$/ ) {
      if ( ! -f "$wrkdir/$host/XIV" ) {
        `touch "$wrkdir/$host/XIV"`;
      }
      $no_time = 1980; # XIV heart beat time increase due to bigger step (15 minutes)
      LoadDataModule::load_data_xiv_all ($host, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }
    if ( $st_type =~ m/^DS5K$/ ) {
      if ( ! -f "$wrkdir/$host/DS5K" ) {
        `touch "$wrkdir/$host/DS5K"`;
      }
      LoadDataModule::load_data_ds5_all ($host, $wrkdir, $webdir, $act_time, $STEP, $DEBUG, $no_time, $st_type);
    }

    # must be here before Storcfg2html::cfg_ds8k
    my $type = "VOLUME";
    LoadDataModule::load_nicks ($type,$wrkdir,$host,$act_time,$st_type,$DEBUG);
    set_colors_initial($host,$type);

    # storage independent so far ....
    my $ret = Storcfg2html::cfg_ds8k ($host, $wrkdir, $webdir, $act_time, $DEBUG, $st_type);
    if ( $ret == 2 ) {
      return 1; # when does not exist config files config.html, pool.cfg and volumes.cfg
    }

    clean_old_data_files ($host, $wrkdir,$DEBUG);

    pool_translate($act_time,$wrkdir,$host);

    if ( $st_type =~ m/^DS8K$/ ) {
      draw_graphs_ds8k($host,$act_time,$st_type);
    }
    if ( $st_type =~ m/^SWIZ$/ ) {
      draw_graphs_svc($host,$act_time,$st_type);
    }
    if ( $st_type =~ m/^XIV$/ ) {
      draw_graphs_xiv($host,$act_time,$st_type);
    }
    if ( $st_type =~ m/^DS5K$/ ) {
      draw_graphs_ds5($host,$act_time,$st_type);
    }
    print_storage_sys ($wrkdir,$host);
    return 1;
}

sub draw_graphs_ds5 
{
  my $host = shift;
  my $act_time = shift;
  my $st_type = shift;
  my $type = "";
  my $item = "";
  my $time_first = 1;


    cfg_copy($wrkdir,$webdir,$host,$act_time); # must be before volumes

    $type = "HOST";
    LoadDataModule::load_nicks ($type,$wrkdir,$host,$act_time,$st_type,$DEBUG);

    # Draw graphs

    # POOL
    # pool processing always after RANK due to *.first files, pool one are created based on already created for ranks
    #
    # here must be minimal time of the first data point from all files
    $time_first = find_real_data_start_all("$wrkdir/$host/VOLUME");

    $type = "POOL";
    $item = "io_rate";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "data_rate";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "data_cntl";
    draw_all_pool_controler ($host,$type,$item,$st_type);
    $item = "io_cntl";
    draw_all_pool_controler ($host,$type,$item,$st_type);
    if ( -f "$wrkdir/$host/DS5K-v2" ) {
      # only for new DS5K storages
      # No cache hit, it does not make sense here
      #$item = "r_cache_hit";
      #draw_all_pool ($host,$type,$item,$st_type);
      #$item = "w_cache_hit";
      #draw_all_pool ($host,$type,$item,$st_type);
      $item = "resp_t";
      draw_all_pool ($host,$type,$item,$st_type);
      # --PH: resp time per controller is a bit complicated, not supported for now
      #$item = "resp_t_cntl";
      #draw_all_pool_controler ($host,$type,$item,$st_type);
    }
    #else {
    #  $item = "cache_hit";
    #  draw_all_pool ($host,$type,$item,$st_type);
    #}

    #
    # HOST
    #
    # only touch files with used metrics
    $type = "HOST";
    $item = "io_rate";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "data_rate";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "read_pct";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    if ( -f "$wrkdir/$host/DS5K-v2" ) {
      $item = "r_cache_hit";
      print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
      `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
      $item = "w_cache_hit";
      print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
      `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
      $item = "resp_t";
      print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
      `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    }
    else {
      $item = "cache_hit";
      print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
      `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    }

    # VOLUME
    #
    # keep Volume graphs at the end as they might cause memory issues
    $type = "VOLUME";

    $item = "top";
    volumes_in_top_all ($host,$type,$item,$st_type);

    $item = "io_rate";
    my $ret = draw_all_volume ($host,$type,$item,$st_type);
    if ( $ret == 2 ) {
      # volumes.cfg does not exist, without that makes no sense to continue, most probably it is initial run
      return 1;
    }
    $item = "data_rate";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "read_pct";
    draw_all_volume ($host,$type,$item,$st_type);
    if ( -f "$wrkdir/$host/DS5K-v2" ) {
      # only for new DS5K storages
      $item = "r_cache_hit";
      draw_all_volume ($host,$type,$item,$st_type);
      $item = "w_cache_hit";
      draw_all_volume ($host,$type,$item,$st_type);
      $item = "resp_t";
      draw_all_volume ($host,$type,$item,$st_type);
      $item = "ssd_r_cache_hit";
      draw_all_volume ($host,$type,$item,$st_type);
    }
    else {
      $item = "cache_hit";
      draw_all_volume ($host,$type,$item,$st_type);
    }
    draw_volume_cache_hit_all ($host,$type,$st_type);


  return 1;
}

sub draw_graphs_xiv 
{
  my $host = shift;
  my $act_time = shift;
  my $st_type = shift;
  my $type = "";
  my $item = "";
  my $time_first = 1;


    cfg_copy($wrkdir,$webdir,$host,$act_time); # must be before volumes

    #$type = "HOST";
    #LoadDataModule::load_nicks ($type,$wrkdir,$host,$act_time,$st_type,$DEBUG);

    # Draw graphs

    # POOL
    # pool processing always after RANK due to *.first files, pool one are created based on already created for ranks
    #
    # here must be minimal time of the first data point from all files
    $time_first = find_real_data_start_all("$wrkdir/$host/VOLUME");

    $type = "POOL";
    $item = "read_io";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "read";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all_pool ($host,$type,$item,$st_type);

    $item = "write_io";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "write";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all_pool ($host,$type,$item,$st_type);

    #
    # HOST
    #
    # only touch files with used metrics
    #$type = "HOST";
    #$item = "read_io";
    #print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    #`touch "$tmp_dir/$host/$type-$item-d.cmd"`;


    # VOLUME
    #
    # keep Volume graphs at the end as they might cause memory issues
    $type = "VOLUME";

    $item = "top";
    volumes_in_top_all ($host,$type,$item,$st_type);

    $item = "read_io";
    my $ret = draw_all_volume ($host,$type,$item,$st_type);
    if ( $ret == 2 ) {
      # volumes.cfg does not exist, without that makes no sense to continue, most probably it is initial run
      return 1;
    }
    $item = "read";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all_volume ($host,$type,$item,$st_type);

    $item = "write_io";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "write";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all_volume ($host,$type,$item,$st_type);

  return 1;
}

sub draw_graphs_svc
{
  my $host = shift;
  my $act_time = shift;
  my $st_type = shift;
  my $type = "";
  my $item = "";
  my $time_first = 1;

  # mdisk name translation, must be global one
  if ( -f "$wrkdir/$host/mdisk.cfg" ) {
    open(FHR, "< $wrkdir/$host/mdisk.cfg") || error ("Can't open $wrkdir/$host/mdisk.cfg : $! ".__FILE__.":".__LINE__) && return 0;
    @mdisk_trans = <FHR>;
    close(FHR);
  }

    $type = "HOST";
    LoadDataModule::load_nicks ($type,$wrkdir,$host,$act_time,$st_type,$DEBUG);

    # Draw graphs

    # PORT
    #
    $type = "PORT";
    $item = "read_io";
    draw_all ($host,$type,$item,$st_type);
    draw_all_port_subsystem ($host,$type,$item);
    $item = "read";
    draw_all ($host,$type,$item,$st_type);
    draw_all_port_subsystem ($host,$type,$item);

    $item = "write_io";
    draw_all ($host,$type,$item,$st_type);
    draw_all_port_subsystem ($host,$type,$item);
    $item = "write";
    draw_all ($host,$type,$item,$st_type);
    draw_all_port_subsystem ($host,$type,$item);

    $item = "data_rate";
    draw_all ($host,$type,$item,$st_type);
    draw_all_port_subsystem ($host,$type,$item);

    $item = "io_rate";
    draw_all ($host,$type,$item,$st_type);
    draw_all_port_subsystem ($host,$type,$item);

    #$item = "read_io_fc";
    #draw_all ($host,$type,$item,$st_type);
    #$item = "read_io_sas";
    #draw_all ($host,$type,$item,$st_type);
    #$item = "read_io_iscsi";
    #draw_all ($host,$type,$item,$st_type);
    #$item = "read_io_iprep";
    #draw_all ($host,$type,$item,$st_type);

    # Drive
    #
    $type = "DRIVE";
    $item = "read_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "read";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all ($host,$type,$item,$st_type);

    $item = "write_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "write";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all ($host,$type,$item,$st_type);

    # here must be minimal time of the first data point from all files
    $time_first = find_real_data_start_all("$wrkdir/$host/$type");
    $item = "sum_io";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);
    $item = "sum_data";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);
    # CPU-CORE
    #
    # skip CPU-CORE, CPU-NODE is the prefered one
    #$type = "CPU-CORE";
    #$item = "sys";
    #draw_all ($host,$type,$item,$st_type);
    #$item = "compress";
    #draw_all ($host,$type,$item,$st_type);

    # CPU-NODE
    #
    $type = "CPU-NODE";
    $item = "sys";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);

    # RANK == mdisk
    #
    $type = "RANK";
    $item = "read_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "read";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all ($host,$type,$item,$st_type);

    $item = "write_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "write";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all ($host,$type,$item,$st_type);

    # here must be minimal time of the first data point from all files
    $time_first = find_real_data_start_all("$wrkdir/$host/$type");
    $item = "sum_io";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);
    $item = "sum_data";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);

    # POOL
    # pool processing always after RANK due to *.first files, pool one are created based on already created for ranks
    #
    $type = "POOL";

    # front-end graphs created from summed volume data
    $item = "read_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "read";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all ($host,$type,$item,$st_type);
    $item = "write_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "write";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all ($host,$type,$item,$st_type);

    # standard back-end (from mdisk data)
    $item = "read_io_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "read_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "resp_t_r_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "write_io_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "write_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "resp_t_w_b";
    draw_all_pool ($host,$type,$item,$st_type);

    # capacity
    $item = "sum_capacity";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);
    $item = "used";
    draw_pool_cap ($host,$type,$item,$st_type);
    $item = "real";
    draw_pool_cap ($host,$type,$item,$st_type);
    $item = "tier0";
    draw_all_sum  ($host,$type,$item,$st_type,$time_first);
    $item = "tier1";
    draw_all_sum  ($host,$type,$item,$st_type,$time_first);
    $item = "tier2";
    draw_all_sum  ($host,$type,$item,$st_type,$time_first);

    cfg_copy($wrkdir,$webdir,$host,$act_time); # must be before volumes

    #
    # HOST
    #
    # only touch files with used metrics
    $type = "HOST";
    $item = "read_io";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "write_io";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "read";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "write";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "resp_t_r";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "resp_t_w";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;


    # VOLUME
    #
    # keep Volume graphs at the end as they might cause memory issues
    $type = "VOLUME";

    $item = "top";
    volumes_in_top_all ($host,$type,$item,$st_type);

    $item = "read_io";
    my $ret = draw_all_volume ($host,$type,$item,$st_type);
    if ( $ret == 2 ) {
      # volumes.cfg does not exist, without that makes no sense to continue, most probably it is initial run
      return 1;
    }
    $item = "read";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all_volume ($host,$type,$item,$st_type);

    $item = "write_io";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "write";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "w_cache_usage";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "r_cache_usage";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "w_cache_hit";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "r_cache_hit";
    draw_all_volume ($host,$type,$item,$st_type);

    draw_volume_cache_hit_all ($host,$type,$st_type);


  return 1;
}

sub draw_graphs_ds8k
{
  my $host = shift;
  my $act_time = shift;
  my $st_type = shift;
  my $time_first = 1;

    # load hosts info
    my $type = "HOST";
    LoadDataModule::load_nicks ($type,$wrkdir,$host,$act_time,$st_type,$DEBUG);

    # Draw graphs

    # PORT
    #
    $type = "PORT";
    my $item = "io_rate";
    draw_all ($host,$type,$item,$st_type);
    $item = "data_rate";
    draw_all ($host,$type,$item,$st_type);
    $item = "pprc_rio";
    draw_all ($host,$type,$item,$st_type);
    $item = "pprc_wio";
    draw_all ($host,$type,$item,$st_type);
    $item = "pprc_data_r";
    draw_all ($host,$type,$item,$st_type);
    $item = "pprc_data_w";
    draw_all ($host,$type,$item,$st_type);
    $item = "pprc_rt_r";
    draw_all ($host,$type,$item,$st_type);
    $item = "pprc_rt_w";
    draw_all ($host,$type,$item,$st_type);
    #$item = "resp_t"; #--> need to check it out what it is, valuas are tehre under 0
    #draw_all ($host,$type,$item,$st_type);

    # RANK
    #
    $type = "RANK";
    $item = "read_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "read";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all ($host,$type,$item,$st_type);
  
    $item = "write_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "write";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all ($host,$type,$item,$st_type);

    # here must be minimal time of the first data point from all files
    $time_first = find_real_data_start_all("$wrkdir/$host/$type");
    $item = "sum_io";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);
    $item = "sum_data";
    draw_all_sum ($host,$type,$item,$st_type,$time_first);

    # POOL
    #
    $type = "POOL";

    # standard back-end (from RANK data)
    $item = "read_io_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "read_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "resp_t_r_b";
    draw_all_pool ($host,$type,$item,$st_type);

    $item = "write_io_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "write_b";
    draw_all_pool ($host,$type,$item,$st_type);
    $item = "resp_t_w_b";
    draw_all_pool ($host,$type,$item,$st_type);

    cfg_copy($wrkdir,$webdir,$host,$act_time);

    # front-end graphs created from summed volume data
    $item = "read_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "read";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all ($host,$type,$item,$st_type);

    $item = "write_io";
    draw_all ($host,$type,$item,$st_type);
    $item = "write";
    draw_all ($host,$type,$item,$st_type);
    $item = "resp_t_w";
    draw_all ($host,$type,$item,$st_type);


    #
    # HOST
    #
    # only touch files with used metrics
    $type = "HOST";
    $item = "read_io";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "write_io";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "read";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "write";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "resp_t_r";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;
    $item = "resp_t_w";
    print "creating graph : $host:$type:$item:d\n" if $DEBUG ;
    `touch "$tmp_dir/$host/$type-$item-d.cmd"`;


    # VOLUME
    #
    # keep Volume graphs at the end as they might cause memory issues
    # front-end
    $type = "VOLUME";

    $item = "top";
    volumes_in_top_all ($host,$type,$item,$st_type);

    $item = "io_rate";
    my $ret = draw_all_volume ($host,$type,$item,$st_type);
    if ( $ret == 2 ) {
      # volumes.cfg does not exist, without that makes no sense to continue, most probably it is initial run
      return 1;
    }
    $item = "data_rate";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t";
    draw_all_volume ($host,$type,$item,$st_type);

    $item = "read_io";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "write_io";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "read";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "write";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_r";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_w";

    draw_all_volume ($host,$type,$item,$st_type);
    $item = "r_cache_hit";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "w_cache_hit";
    draw_all_volume ($host,$type,$item,$st_type);

    draw_volume_cache_hit_all ($host,$type,$st_type);

    # back-end
    $item = "read_io_b";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "write_io_b";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "read_b";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "write_b";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_r_b";
    draw_all_volume ($host,$type,$item,$st_type);
    $item = "resp_t_w_b";
    draw_all_volume ($host,$type,$item,$st_type);

  return 1;
}

sub cfg_config_change 
{
  # If any change in lpar2rrd.cfg  then must be run install-html.sh
  my $cfg_update = "$tmp_dir/cfg_update_storage";

  if ( -f "$cfg_update" ) {
    my $last_line = "";
    open(FHLT, "< $cfg_update") || error("Can't open $cfg_update: $! ".__FILE__.":".__LINE__) && return 0;
    foreach my $line (<FHLT>) {
      $last_line = $line;
    }
    close(FHLT);
    my $png_time = (stat("$basedir/etc/stor2rrd.cfg"))[9];
    if ($last_line < $png_time ) {
     LoadDataModule::touch ();
      open(FHLT, "> $cfg_update") || error("Can't open $cfg_update: $! ".__FILE__.":".__LINE__) && return 0;
      my $act_time = time();
      print FHLT "$act_time";
      close(FHLT);
    }
  }
  else {
   LoadDataModule::touch ();
    my $png_time = (stat("$basedir/etc/stor2rrd.cfg"))[9];
    open(FHLT, "> $cfg_update") || error ("Can't open $cfg_update: $! ".__FILE__.":".__LINE__) && return 0;
    my $act_time = time();
    print FHLT "$act_time";
    close(FHLT);
    #print "$cfg_update $basedir/etc/stor2rrd.cfg $png_time\n";
  }

  return 1;
}

# error handling
sub error
{
  my $text = shift;
  my $act_time = localtime();
  
  print "ERROR          : $text \n";
  print STDERR "$act_time: $text \n";

  return 1;
}

sub draw_all {
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;

  draw_graph ("day","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",$host,$type,$item,$st_type);
  draw_graph ("week","w","HOUR:8:DAY:1:DAY:1:86400:%a",$host,$type,$item,$st_type);
  draw_graph ("4 weeks","m","DAY:1:DAY:2:DAY:2:0:%d",$host,$type,$item,$st_type);
  draw_graph ("year","y","MONTH:1:MONTH:1:MONTH:1:0:%b",$host,$type,$item,$st_type);
  return 0;
}

sub draw_graph {
  my $text     = shift;
  my $type_gr  = shift;
  my $xgrid    = shift;
  my $host     = shift;
  my $type     = shift;
  my $item     = shift;
  my $st_type  = shift;
  my $name = "$tmp_dir/$host/$type-$item-agg-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my $step_new = $STEP;
  my $once = 0;
  my $last_time = "na";
  my $last_time_u =  time() - 3600;
  my $color_indx = 0; # reset colour index

  # PORT types for Storwize
  # this is not being used --> viz draw_all_port_subsystem
  my $port_type = 3; # default unknown port type
  if ( $item =~ m/_fc$/    ) { $port_type = 0; }
  if ( $item =~ m/_sas$/   ) { $port_type = 1; }
  if ( $item =~ m/_iscsi$/ ) { $port_type = 2; }
  if ( $item =~ m/_prep$/  ) { $port_type = 4; }



  my $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.cmd";
  my $act_utime = time();

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "y" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
        #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "m" && -f "$tmp_file"  ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "w" && -f "$tmp_file"  ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    print "creating graph : $host:$type:$item:$type_gr\n" if $DEBUG ;

  my $req_time = "";
  my $header = "$type aggregated $item: last $text";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;

  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end now-1$type_gr+1$type_gr";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $font_def_normal";
  $cmd .= " $font_tit_normal";

  my $value_short = "";
  my $value_long = "";
  my $val = 1; # base, the number will be devided by that constant

  my $suffix = "rrd"; #standard suffix

  # do not use switch statement
  if ( $item =~ m/^data_rate$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read$/ )      { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write$/ )     { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^io_rate$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^read_io$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io$/ )  { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp$/ )      { $value_short= "ms"; $value_long = "mili seconds";}
  if ( $item =~ m/^resp_t$/ )    { $value_short= "ms"; $value_long = "mili seconds";}
  if ( $item =~ m/^resp_t_r$/ )  { $value_short= "ms"; $value_long = "mili seconds";}
  if ( $item =~ m/^resp_t_w$/ )  { $value_short= "ms"; $value_long = "mili seconds";}
  if ( $item =~ m/^sys$/ )       { $value_short= "CPU util"; $value_long = "CPU utilization in %"; }
  if ( $item =~ m/^compress$/ )  { $value_short= "CPU util"; $value_long = "CPU utilization in %"; }
  if ( $item =~ m/^pprc_rio$/ )  { $suffix="rrp";$value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^pprc_wio$/ )  { $suffix="rrp";$value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^pprc_rt_r$/ ) { $suffix="rrp";$value_short= "ms"; $value_long = "mili seconds";}
  if ( $item =~ m/^pprc_rt_w$/ ) { $suffix="rrp";$value_short= "ms"; $value_long = "mili seconds";}
  if ( $item =~ m/^pprc_data_r$/){ $suffix="rrp";$value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^pprc_data_w$/){ $suffix="rrp";$value_short= "MB"; $value_long = "MBytes"; $val = 1024;}

  if ( $st_type !~ m/^DS8K$/ ) {
    # rrp suffix only on DS8K so far
    $suffix = "rrd"; 
  }

  if ( $st_type =~ m/^DS8K$/ && $type =~ m/^POOL$/ ) {
    # rrd for DS8K front end
    $suffix = "rrd"; 
  }

  # Why??? There should be 1024
  if ( $st_type =~ m/^DS8K$/ ) {
    if ( $item =~ m/^read$/ || $item =~ m/^write/ ) {
      $val = 1;
    }
  }

  if ( $item =~ m/^sys$/ || $item =~ m/^compress$/ ) {
    $cmd .= " --vertical-label=\\\"$value_long\\\"";
  }
  else{
    $cmd .= " --vertical-label=\\\"$item in $value_long\\\"";
  }

  $cmd .= " --units-exponent=1.00";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " --alt-y-grid";

  # add spaces to lpar name (for formating graph legend)
  my $legend = sprintf ("%-38s","$item [$value_short]");
  my $legend_heading = "$item $delimiter [$value_short] $delimiter Avg $delimiter Max ";
  $legend_heading =~ s/%/%%/g;
  $cmd .= " COMMENT:\\\"$legend       Avg      Max\\l\\\"";


  my $gtype="AREA";
  if ( $item =~ m/resp_t/ || $item =~ m/pprc_rt_/ ) {
    $gtype="LINE1";
  }

  my $dir = "$wrkdir/$host/$type";
  #if ( $type =~ m/^POOL$/ && $st_type =~ m/^DS8K$/ ) {
  #  $dir = "$wrkdir/$host/VOLUME"; # DS8K POOL front-end stuff created from volume stats
  #}

  my $lpar_list = "";
  my $pool_found = 0;
  my $pool_id_tmp = "";
  my $lpar_list_tmp = "";
  my $found_data = 0;
  my $cmd_print = ""; # print commands for clickable legend


  foreach my $line (<$dir/*$suffix>) {
    chomp($line);

    if ( $type =~ m/RANK/ && $line !~ m/\/.*-P[0-9][0-9]*\.$suffix$/ ) {
      #workaround for cleaning up rans without pool id (could hapen in the past by the error)
      next;
    }

    if ( $line =~ m/-cap.rrd$/ && $type =~ m/POOL/ ) {
      next; # exclude capacity data files from here (for POOL front-end stats
    } 
      

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = (stat("$line"))[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }

    my @link_l = split(/\//,$line);
    my $lpar = "";
    foreach my $m (@link_l) {
      $lpar = $m;
    }
    
    $lpar =~ s/\.rrd$//;
    $lpar =~ s/\.rrp$//;
    $lpar =~ s/\.rrc$//;
    $lpar =~ s/PORT-//;
    $lpar =~ s/RANK-//;
    $lpar =~ s/VOLUME-//;
    $lpar =~ s/0x//;
    $lpar =~ s/-P.*//; # filter pool info
    my $lpar_space = $lpar; # it is for fron-end POOL, like POOL/23.rrd

    if ( $type =~ m/POOL/ && ishexa($lpar_space) == 1 ) {
      # pool id tralslation to name
      $lpar_space = get_pool_name($lpar_space);
    }

    if ( $type =~ m/RANK/ &&  -f "$wrkdir/$host/mdisk.cfg" ) {
      # translate id into names only for MDISKS
      my $rank_found = 0;
      my $rank_id = "";
      foreach my $line (@mdisk_trans) {
        chomp($line);
        (my $id, my $name) = split (/:/,$line);
        if ( $id =~ m/^$lpar$/ ) {
          $lpar_space = $name;
          $rank_found = 1;
          $rank_id = $id;
          last;
        }
      }
      if ( $rank_found == 0 ) {
        my $lpar_id = $lpar;
        if (isdigit($lpar_id ) == 1 ) {
          $lpar_id = $lpar_id + 1 - 1; # to clean prefixed zeros
          $rank_id = $lpar_id;
        }
        $lpar_space = "del-$lpar_id";
      }
      # No, no, there ca be ranks with the same ID (under different pool Ids)
      #$rank_id =~ s/ //g;
      #if (isdigit($rank_id) == 1 ) {
      #  # use RANK ID to keep color same
      #  $color_indx = $rank_id;
      #  while ($color_indx > $color_max ) {
      #    $color_indx = $color_indx - $color_max;
      #  }
      #}
    }

    # add spaces to lpar name to have 8 chars total (for formating graph legend)
    if ( $st_type =~ m/^DS8K$/ && $type =~ m/^POOL$/ ) {
      $lpar_space =~ s/extpool-P//;
      $lpar_space =~ s/extpool_P//;
      $lpar_space =~ s/extpool_//;
      $lpar_space =~ s/extpool-//;
      $lpar_space =~ s/extpool//;
    }
    $lpar_space =~ s/\.rr[a-z]//;
    $lpar_space = sprintf ("%-38s","$lpar_space");


    my $rrd_file = "$line";
    my $rrd_file_first = $rrd_file;
    $rrd_file_first =~ s/rr.$/first/g;
    if ( $type_gr =~ m/d/ && $once == 0 ) {
      # find out time stamp of last data update
      # take just one volume to keep it simple
      $once++;
      RRDp::cmd qq(last "$line");
      my $last_tt = RRDp::read;
      chomp ($$last_tt);
      $last_time=localtime($$last_tt);
      $last_time =~ s/:/\\:/g;
      $last_time_u = $$last_tt;
    }

    $found_data++; # to avoid PPRC stats when there is no data files and empty PORT sas/iscsip/iprep ... stats

    # bulid RRDTool cmd
    my $itemm = $item."m";
    $itemm =~ s/\./Z/g;    # dots in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/ /X/g;   # space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/\#/Y/g;   # hash in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser

    my $rrd_file_conv = $line;
    $rrd_file_conv =~ s/\.rr[a-z]//;

    $cmd .= " DEF:$item${i}_u=\\\"$line\\\":$item:AVERAGE";

    # when UNKNOWN then place 0 --> there can be some old RANK datafiles without actual data then --> NaN in the GUI
    # if it is older than rrdtool first time then leave NaN to have proper average time
    # not summed then not care about NaN 

    $cmd .= " CDEF:$itemm${i}=$item${i}_u,$val,/"; # convert into MB if necessary, normaly is there 1
    $cmd .= " $gtype:$itemm${i}$color[$color_indx]:\\\"$lpar_space\\\"";

    $cmd_print .= " PRINT:$itemm${i}:AVERAGE:\\\"%6.0lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd_print .= " PRINT:$itemm${i}:MAX:\\\" %8.0lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";

    # put carriage return after each second lpar in the legend
    if ( $item =~ m/io/ ) {
      $cmd .= " GPRINT:$itemm${i}:AVERAGE:\\\"%6.0lf \\\"";
      $cmd .= " GPRINT:$itemm${i}:MAX:\\\"%6.0lf \\l\\\"";
    }
    else {
      if ( $item =~ m/^sys$/ || $item =~ m/^compress$/ ) {
        $cmd .= " GPRINT:$itemm${i}:AVERAGE:\\\"%3.1lf \\\"";
        $cmd .= " GPRINT:$itemm${i}:MAX:\\\"%3.1lf \\l\\\"";
      }
      else {
        $cmd .= " GPRINT:$itemm${i}:AVERAGE:\\\"%6.1lf \\\"";
        $cmd .= " GPRINT:$itemm${i}:MAX:\\\"%6.1lf \\l\\\"";
      }
    }
    if ( $item !~ m/resp_t/ && $item !~ m/pprc_rt_/ ) {
      $gtype="STACK";
    }
    $i++;
    $color_indx++;
    if ($color_indx > $color_max ) {
      $color_indx = 0;
    }
  }

  #if ( $found_data == 0 ) {
  #  print "no data files  : $host:$type:$item - skipped\n" if $DEBUG ;
  #  return 1; # mainly to avoid PPRC stats when there is no data files
  #}
  
  if ( $type_gr =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }
  
  if ( $i > 0 && ( $item =~ m/^sys$/ || $item =~ m/^compress$/ )) {
    my $total = $i * 100;
    #$cmd .= " LINE2:$total#000000:\\\"Total    $total % \\\"";
    $cmd .= " COMMENT:\\\"Total available \\\: $total %  \\\: $i CPU cores \\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
 
  $cmd .= $cmd_print; # for clickable legend

  $cmd =~ s/\\"/"/g;

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  
  if ( $not_execute_rrdtool == 1 ) { return 1;}

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    if ( $ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
    }
    else {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
    }
  }
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");

  # Create dirs here when all is fine above


  return 0;
}

sub draw_all_pool {
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;

  draw_graph_pool ("day","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",$host,$type,$item,$st_type);
  draw_graph_pool ("week","w","HOUR:8:DAY:1:DAY:1:86400:%a",$host,$type,$item,$st_type);
  draw_graph_pool ("4 weeks","m","DAY:1:DAY:2:DAY:2:0:%d",$host,$type,$item,$st_type);
  draw_graph_pool ("year","y","MONTH:1:MONTH:1:MONTH:1:0:%b",$host,$type,$item,$st_type);
  return 0;
}

sub draw_graph_pool {
  my $text     = shift;
  my $type_gr  = shift;
  my $xgrid    = shift;
  my $host     = shift;
  my $type     = shift;
  my $item     = shift;
  my $st_type  = shift;
  my $name = "$tmp_dir/$host-$type-$item-agg-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my $step_new=$STEP;
  my $once = 0;
  my $last_time = "na";
  my $color_indx = 0; # reset colour index
  my $item_org = $item;


  my $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.cmd";
  my $act_utime = time();

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "y" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
        #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "m" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "w" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

  print "creating graph : $host:$type:$item:$type_gr\n" if $DEBUG ;

  my $req_time = "";
  my $header = "$type aggregated $item: last $text";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;


  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 


  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end now-1$type_gr+1$type_gr";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $font_def_normal";
  $cmd .= " $font_tit_normal";

  my $value_short = "";
  my $value_long = "";
  my $val = 1;
  $item =~ s/_b$//; # cut back-end info for DS8k, just cmd file will contain the backend info

  # do not use switch statement
  if ( $item =~ m/^data_rate$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read$/ )      { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write$/ )     { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^io_rate$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^read_io$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io$/ )  { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp_t$/ )    { $value_short= "ms"; $value_long = "mili seconds"; $val=1;}
  if ( $item =~ m/^resp_t_r$/ )  { $value_short= "ms"; $value_long = "mili seconds"; $val=1;}
  if ( $item =~ m/^resp_t_w$/ )  { $value_short= "ms"; $value_long = "mili seconds"; $val=1;}

  $cmd .= " --vertical-label=\\\"$item in $value_long\\\"";

  $cmd .= " --units-exponent=1.00";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " --alt-y-grid";

  # add spaces to lpar name (for formating graph legend)
  my $legend = sprintf ("%-38s","$item [$value_short]");

  my $legend_heading = "$item $delimiter [$value_short] $delimiter Avg $delimiter Max ";
  $cmd .= " COMMENT:\\\"$legend        Avg        Max\\l\\\"";

  my $gtype="AREA";
  if ( $item =~ m/resp_t/ ) {
    $gtype="LINE1";
  }

  my $lpar_list = "";
  my $pool_found = 0;
  my $pool_id_tmp = "";
  my $lpar_list_tmp = "";

  my $rank_vol="RANK";
  if ( $st_type =~ m/XIV/ || $st_type =~ m/DS5K/ ) {
    $rank_vol= "VOLUME"; # XIV uses pools
  }
  # DS8K front-end stats are created in draw_all

  my $dir= "$wrkdir/$host/$rank_vol";
  chdir $dir;

  my @rank_list = "";
  my $rank_list_indx = 0;

  # check all ranks and then sort them per pool id
  foreach my $line (<*-P[0-9]*\.rrd>) {
    chomp($line);
    if ( $line !~ m/\.rrd$/ ) {
      next; # it does not end bu .rrd suffix, "$ cannt be use in foreach <>
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = (stat("$line"))[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }

    $rank_list[$rank_list_indx] = $line;
    $rank_list_indx++;
  }

  if ($rank_list_indx == 0) {
    # no new data found, skipping ...
    print "creating graph : $host:$type:$item_org:$type_gr no new data found, skipping ...\n" if $DEBUG ;
    return 0;
  }

  @rank_list = sort { (split '-', $a)[1] cmp (split '-', $b)[1] } @rank_list;

  my $pool_id_old = -1;
 
  my $print_now = 0;
  my $index_last = 0;
  my $rrd_file_last = "";
  my $index_actual = 0;
  my $pool_name_space = "NA";
  my $pool_id = 0;
  my $pool_name_actual = "NA";
  my $itemm = "";
  my $no_of_ranks = 0;
  my $print_now_pool_id = 0;


  # go through all ranks sorted per pool id, once a pool id is changed then is printed the old one
  foreach my $line  (@rank_list) {
    chomp($line);
    $pool_id = $line;
    $pool_id =~ s/^.*-P//;
    $pool_id =~ s/\.rrd$//;


    my $ret = ishexa($pool_id);
    if ( $ret == 0 ) {
      next;
    }

    if ( ishexa($pool_id_old) && $pool_id_old =~ m/^-1$/ ) {
      # could be already haxa here
      $pool_id_old = $pool_id;
    }
    else {
      if ($pool_id_old !~ m/^$pool_id$/ ) {
        $print_now = 1;
        $print_now_pool_id = $pool_id_old;
        $pool_name_actual = $pool_name_space;
        $pool_id_old = $pool_id;
      }
    }


    # get pool name, be aware this is a new pool name
    #print "002 $line\n";
    my $pool_name = "NA";
    $pool_name = get_pool_name($pool_id);
    $pool_name_space = $pool_name;

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    $pool_name_space =~ s/extpool_P//;
    $pool_name_space =~ s/extpool-P//;
    $pool_name_space =~ s/extpool-//;
    $pool_name_space =~ s/extpool_//;
    $pool_name_space =~ s/extpool//;
    $pool_name_space = sprintf ("%-38s","$pool_name_space");

    my $rrd_file = "$dir/$line";
    $rrd_file_last = "$dir/$line"; 
    if ( "$type_gr" =~ "d" ) {
      # find out time stamp of last data update
      # take just one volume to keep it simple
      RRDp::cmd qq(last "$rrd_file");
      my $last_tt = RRDp::read;
      chomp ($$last_tt);
      $last_time =localtime($$last_tt);
      $last_time =~ s/:/\\:/g;
    }

    my $time_first = find_real_data_start_pool("$dir",$pool_id);
 
    $itemm = $item."m";
    $itemm =~ s/\./Z/g;    # dots in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/ /X/g;   # space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/\#/Y/g;   # space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser

    $cmd .= " DEF:$item${i}_u=\\\"$dir/$line\\\":$item:AVERAGE";
    #$cmd .= " VDEF:$item${i}_avrg_u=$item${i}_u,AVERAGE"; # gets 1 everage value per all time range
    # TIME,937521357,GT,value,value,UN,0,value,IF,IF
    # if it is older than rrdtool first time
    # e then leave NaN to have proper average time
    # Do not use UNKN as one NaN in sum causes NaN in total
    $cmd .= " CDEF:$item${i}=TIME,$time_first,LT,$item${i}_u,$item${i}_u,UN,0,$item${i}_u,IF,IF";
    $cmd .= " CDEF:$itemm${i}=$item${i},$val,/";

    #print "001 $line - $print_now - $i - $index_actual : $index_last\n";

    if ($print_now) {

      # use pool ID for color definition
      # No, no, XIV has pool ID very big numbers
      #if ( isdigit($pool_id_old) && $pool_id_old != -1 ) {
      #  $color_indx = $pool_id_old;
      #  while ($color_indx > $color_max ) {
      #    $color_indx = $color_indx - $color_max;
      #  }
      #}

      $print_now = 0;
      $index_actual = $index_last;
      $cmd .= " CDEF:pool${print_now_pool_id}=$itemm${index_actual},0,+"; # workaround for pools with 1 rank
      $index_actual++;
      for (; $index_actual < $i; $index_actual++) { 
        $cmd .= ",$itemm${index_actual},+";
      }

      if ( $item =~ m/resp_t/ ) {
        # response time is not summary, must be average of all time (devide number of ranks)
        $cmd .= ",$no_of_ranks,/";
      }
      $no_of_ranks=0;

      $pool_name_actual =~ s/extpool_P//;
      $pool_name_actual =~ s/extpool-P//;
      $pool_name_actual =~ s/extpool-//;
      $pool_name_actual =~ s/extpool_//;
      $pool_name_actual =~ s/extpool//;
      my $rrd_file_conv = $rrd_file;
      if ( $st_type =~ m/^DS8K$/ || $st_type =~ m/^SWIZ$/ ) {
	# DS8K stats from RANK mus be converted here to point to POOL to make working legend links
	$rrd_file_conv =~ s/\/RANK\/.*/\/POOL\/$print_now_pool_id\.rrd/;
      }
      if ( $st_type =~ m/^DS5K$/ || $st_type =~ m/^XIV$/ ) {
	# DS8K stats from RANK mus be converted here to point to POOL to make working legend links
	$rrd_file_conv =~ s/\/VOLUME\/.*/\/POOL\/$print_now_pool_id\.rrd/;
      }
      #print "00 $rrd_file - $rrd_file_conv - $print_now_pool_id\n";

      $cmd .= " $gtype:pool${print_now_pool_id}$color[$color_indx]:\\\"$pool_name_actual \\\"";
      if ( $item =~ m/resp_t/ )    { 
        $cmd .= " GPRINT:pool${print_now_pool_id}:AVERAGE:\\\"%7.1lf \\\"";
        $cmd .= " GPRINT:pool${print_now_pool_id}:MAX:\\\"%7.1lf \\l\\\"";
        $cmd .= " PRINT:pool${print_now_pool_id}:AVERAGE:\\\"%7.1lf $delimiter $pool_name_actual $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
        $cmd .= " PRINT:pool${print_now_pool_id}:MAX:\\\" %7.1lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";
      }
      else {
        $cmd .= " GPRINT:pool${print_now_pool_id}:AVERAGE:\\\"%7.0lf \\\"";
        $cmd .= " GPRINT:pool${print_now_pool_id}:MAX:\\\"%7.0lf \\l\\\"";
        $cmd .= " PRINT:pool${print_now_pool_id}:AVERAGE:\\\"%7.0lf $delimiter $pool_name_actual $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
        $cmd .= " PRINT:pool${print_now_pool_id}:MAX:\\\" %7.0lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";
      }

      $index_last = $i;
      if ( $item !~ m/resp_t/ ) {
        $gtype="STACK";
      }
      #next;
      $color_indx++;
      if ($color_indx > $color_max ) { 
        $color_indx = 0;
      }
    }
    $no_of_ranks++;
    $i++;
  }

  # add last pool
  $index_actual = $index_last;
  $cmd .= " CDEF:pool${i}=$itemm${index_actual},0,+"; # workaround for pools with 1 rank
  $index_actual++;
  for (; $index_actual < $i; $index_actual++) { 
    $cmd .= ",$itemm${index_actual},+";
  }

  if ( $item =~ m/resp_t/ ) {
     # response time is not summary, must be average of all time (devide number of ranks)
     $cmd .= ",$no_of_ranks,/";
  }

  $pool_name_space =~ s/extpool_P//;
  $pool_name_space =~ s/extpool-P//;
  $pool_name_space =~ s/extpool-//;
  $pool_name_space =~ s/extpool_//;
  $pool_name_space =~ s/extpool//;
  my $rrd_file_conv = $rrd_file_last;
  if ( $st_type =~ m/^DS8K$/ || $st_type =~ m/^SWIZ$/ ) {
	# DS8K back end stats from RANK mus be converted here to point to POOL
	$rrd_file_conv =~ s/\/RANK\/.*/\/POOL\/$pool_id\.rrd/; # file does not have to exist, ID is parsed in the GUI
	#$rrd_file_conv =~ s/\/RANK\/.*-P/\/POOL\//;
  }
  if ( $st_type =~ m/^DS5K$/ || $st_type =~ m/^XIV$/ ) {
        $rrd_file_conv =~ s/\/VOLUME\/.*/\/POOL\/$print_now_pool_id\.rrd/;
  }
  $cmd .= " $gtype:pool${i}$color[$color_indx]:\\\"$pool_name_space \\\"";
  if ( $item =~ m/resp_t/ )    { 
    $cmd .= " PRINT:pool${i}:AVERAGE:\\\"%7.1lf $delimiter $pool_name_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd .= " PRINT:pool${i}:MAX:\\\" %7.1lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";

    $cmd .= " GPRINT:pool${i}:AVERAGE:\\\"%7.1lf \\\"";
    $cmd .= " GPRINT:pool${i}:MAX:\\\"%7.1lf \\l\\\"";
  }
  else {
    $cmd .= " PRINT:pool${i}:AVERAGE:\\\"%7.0lf $delimiter $pool_name_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd .= " PRINT:pool${i}:MAX:\\\" %7.0lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";

    $cmd .= " GPRINT:pool${i}:AVERAGE:\\\"%7.0lf \\\"";
    $cmd .= " GPRINT:pool${i}:MAX:\\\"%7.0lf \\l\\\"";
  }

  if ( $type_gr =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  #$cmd =~ s/ /\n/g;
  #print  "00 $cmd\n";

  
  if ( $not_execute_rrdtool == 1 ) { return 1;}

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    if ( $ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
    }
    else {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
    }
  }
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");

  return 0;
}

sub cfg_copy
{
  my $wrkdir = shift;
  my $webdir = shift;
  my $host = shift;
  my $act_time = shift;
 
  if ( -f "$wrkdir/$host/config.html" ) {
    copy ("$wrkdir/$host/config.html","$webdir/$host/config.html") || error("Can't copy cfg file : $wrkdir/$host/config.html to $webdir/$host/config.html : $! ".__FILE__.":".__LINE__) && return 0;
  }
  return 1;
}

sub draw_all_sum {
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;
  my $time_first = shift;

  draw_graph_sum ("day","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",$host,$type,$item,$st_type,$time_first);
  draw_graph_sum ("week","w","HOUR:8:DAY:1:DAY:1:86400:%a",$host,$type,$item,$st_type,$time_first);
  draw_graph_sum ("4 weeks","m","DAY:1:DAY:2:DAY:2:0:%d",$host,$type,$item,$st_type,$time_first);
  draw_graph_sum ("year","y","MONTH:1:MONTH:1:MONTH:1:0:%b",$host,$type,$item,$st_type,$time_first);
  return 0;
}

sub draw_graph_sum {
  my $text     = shift;
  my $type_gr  = shift;
  my $xgrid    = shift;
  my $host     = shift;
  my $type     = shift;
  my $item     = shift;
  my $st_type = shift;
  my $time_first = shift;
  my $name = "$tmp_dir/$host-$type-$item-agg-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my $step_new = $STEP;
  my $once = 0;
  my $last_time = "na";


  my $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.cmd";
  my $act_utime = time();

  # do not update charts if there is not new data in RRD DB
  if ( $type_gr =~ "y" && -f "$tmp_file" ) {
    my $png_time = (stat("$tmp_file"))[9];
    if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
      #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
      if ( $upgrade == 0 ) { return 0;}
    }
  }

  # do not update charts if there is not new data in RRD DB
  if ( $type_gr =~ "m" && -f "$tmp_file" ) {
    my $png_time = (stat("$tmp_file"))[9];
    if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
      #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
      if ( $upgrade == 0 ) { return 0;}
    }
  }

  # do not update charts if there is not new data in RRD DB
   if ( $type_gr =~ "w" && -f "$tmp_file" ) {
    my $png_time = (stat("$tmp_file"))[9];
    if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
      #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
      if ( $upgrade == 0 ) { return 0;}
     }
  }

  my $type_text = $type;
  if ( $st_type =~ m/SWIZ/ && $type =~ m/RANK/ ) {
    $type_text = "MDISK";
  }

  print "creating graph : $host:$type_text:$item:$type_gr\n" if $DEBUG ;

  my $req_time = "";
  my $header = "$type_text aggregated $item: last $text";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;

  my $color_indx = 0; # reset colour index

  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end now-1$type_gr+1$type_gr";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $font_def_normal";
  $cmd .= " $font_tit_normal";

  my $value_short = "";
  my $value_long = "";
  my $val = 1;

  # do not use switch statement
  if ( $item =~ m/^sum_data$/ )     { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^sum_io$/ )       { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^sum_capacity$/ ) { $value_short= "TB"; $value_long = "TBytes"; }
  if ( $item =~ m/^tier0$/ )        { $value_short= "TB"; $value_long = "TBytes"; }
  if ( $item =~ m/^tier1$/ )        { $value_short= "TB"; $value_long = "TBytes"; }
  if ( $item =~ m/^tier2$/ )        { $value_short= "TB"; $value_long = "TBytes"; }
  if ( $item =~ m/^sys$/ )          { $value_short= "%"; $value_long = "%"; }

  my $item_label = uc($item);
  $item_label =~ s/SUM_//;
  $cmd .= " --vertical-label=\\\"$item_label in $value_long\\\"";

  $cmd .= " --units-exponent=1.00";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " --alt-y-grid";

  # add spaces to lpar name (for formating graph legend)
  my $legend = sprintf ("%-38s","$item [$value_short]");
  $cmd .= " COMMENT:\\\"$legend        Avg        Max \\l\\\"";

  my $gtype="LINE";
  if ( $item =~ m/resp_t/ ) {
    $gtype="LINE1";
  }

  my $lpar_list = "";
  my $pool_found = 0;
  my $pool_id_tmp = "";
  my $lpar_list_tmp = "";
  my $itemm = "";
  my $nothing_to_sum=1;

  
  foreach my $line (<$wrkdir/$host/$type/*rrd>) {
    chomp($line);
    if ( $line !~ m/\.rrd$/ ) {
      next; # it does not end by .rrd suffix, "$ cannt be use in foreach <>
    }

    if ( $type =~ m/RANK/ && $line !~ m/\/.*-P[0-9][0-9]*\.rrd$/ ) {
      #workaround for cleaning up ranks without pool id (could hapened in the past by the error)
      next;
    }
    if ( $type =~ m/POOL/ && $line !~ m/-cap\.rrd$/ ) {
      if ( $item =~ m/^sum_capacity$/ || $item =~ m/^tier[0-9]$/ ) {
        next; # use only *-cap.rrd file for POOL capacity stuff (there can be even POOL front-end stuff like $pool_id.rrd
      }
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = (stat("$line"))[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }
    $nothing_to_sum=0;

    my $rrd_file = "$line";
    if ( $type_gr =~ m/d/ && $once == 0 ) {
      $once++;
      # find out time stamp of last data update
      # take just one volume to keep it simple
      RRDp::cmd qq(last "$rrd_file");
      my $last_tt = RRDp::read;
      $last_time =localtime($$last_tt);
      $last_time =~ s/:/\\:/g;
    }

    my @link_l = split(/\//,$line);
    my $lpar = "";
    foreach my $m (@link_l) {
      $lpar = $m;
    }
    $lpar =~ s/\.rrd$//;
    $lpar =~ s/-P.*//; # filter pool info
    $lpar =~ s/PORT-//;
    $lpar =~ s/RANK-//;
    $lpar =~ s/MDISK-//;
    $lpar =~ s/VOLUME-//;
    $lpar =~ s/0x//;
    $lpar =~ s/-cap//;


    # bulid RRDTool cmd
    $itemm = $item."m";
    $itemm =~ s/\./Z/g;    # dots in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/ /X/g;   # space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/\#/Y/g;   # space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser

    # do not use below UNKN as this is total sum and one NaN --. whole sum is NaN 
    if ( $item =~ m/sys/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":sys:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":compress:AVERAGE";
      $cmd .= " CDEF:$itemm${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,UNKN,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,UNKN,$item${i}_w_u,IF,IF";
    }
    if ( $item =~ m/sum_io/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":read_io:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":write_io:AVERAGE";
      $cmd .= " CDEF:$item${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,0,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$item${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,0,$item${i}_w_u,IF,IF";
    }
    if ( $item =~ m/sum_data/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":read:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":write:AVERAGE";
      $cmd .= " CDEF:$item${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,0,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$item${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,0,$item${i}_w_u,IF,IF";
    }
    if ( $item =~ m/sum_data/ || $item =~ m/sum_io/ ) {
      $cmd .= " CDEF:$itemm${i}_r=$item${i}_r,$val,/"; # convert into MB if necessary, normaly is there 1
      $cmd .= " CDEF:$itemm${i}_w=$item${i}_w,$val,/"; # convert into MB if necessary, normaly is there 1
    }
    if ( $item =~ m/sum_capacity/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":real:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":free:AVERAGE";
      $cmd .= " CDEF:$itemm${i}_r=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,0,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,0,$item${i}_w_u,IF,IF";
    }
    if ( $item =~ m/tier0/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":tier0cap:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":tier0free:AVERAGE";
      $cmd .= " CDEF:$itemm${i}_r_cap=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,0,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,0,$item${i}_w_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_r=$itemm${i}_r_cap,$itemm${i}_w,-";
    }
    if ( $item =~ m/tier1/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":tier1cap:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":tier1free:AVERAGE";
      $cmd .= " CDEF:$itemm${i}_r_cap=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,0,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,0,$item${i}_w_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_r=$itemm${i}_r_cap,$itemm${i}_w,-";
    }
    if ( $item =~ m/tier2/ ) {
      $cmd .= " DEF:$item${i}_r_u=\\\"$line\\\":tier2cap:AVERAGE";
      $cmd .= " DEF:$item${i}_w_u=\\\"$line\\\":tier2free:AVERAGE";
      $cmd .= " CDEF:$itemm${i}_r_cap=TIME,$time_first,LT,$item${i}_r_u,$item${i}_r_u,UN,0,$item${i}_r_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_w=TIME,$time_first,LT,$item${i}_w_u,$item${i}_w_u,UN,0,$item${i}_w_u,IF,IF";
      $cmd .= " CDEF:$itemm${i}_r=$itemm${i}_r_cap,$itemm${i}_w,-";
    }
    $i++;
  }

  if ( $nothing_to_sum == 1) {
    # there is nothing to sum at the moment
    print "creating graph : $host:$type:$lpar:$type_gr:$type nothing to summ\n" if $DEBUG ;
    return 1;
  }

  
  # Load all items into the $cmd
  # Read
  my $index_actual = 0;
  $cmd .= " CDEF:rsum${i}=$itemm${index_actual}_r";
  $index_actual++;
  for (; $index_actual < $i; $index_actual++) { 
    $cmd .= ",$itemm${index_actual}_r,+";
  }
  
  if ($item =~ m/sys/ && $index_actual > 0 ) {
    # create an average (not total sum)
    $cmd .= ",$index_actual,/";
  }

  # Write
  $index_actual = 0;
  $cmd .= " CDEF:wsum${i}=$itemm${index_actual}_w";
  $index_actual++;
  for (; $index_actual < $i; $index_actual++) { 
    $cmd .= ",$itemm${index_actual}_w,+";
  }

  if ($item =~ m/sys/ && $index_actual > 0 ) {
    # create an average (not total sum)
    $cmd .= ",$index_actual,/";
  }

  #
  # read || total
  #

  # print LINE read and write
  if ( $item =~ m/sum_io/ || $item =~ m/sum_data/) {
    my $lpar_space = sprintf ("%-38s","read");
    $cmd .= " $gtype:rsum${i}#00FF00:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:rsum${i}:AVERAGE:\\\"%9.0lf \\\"";
  }
  if ( $item =~ m/sum_capacity/ ) {
    #my $lpar_space = sprintf ("%-38s","read");
    #$cmd .= " $gtype:rsum${i}#00FF00:\\\"$lpar_space\\\"";
    my $lpar_space = sprintf ("%-38s","Used");
    $cmd .= " AREA:rsum${i}#FF3333:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:rsum${i}:AVERAGE:\\\"%7.2lf \\\"";
  }
  if ( $item =~ m/tier/ ) {
    my $lpar_space = sprintf ("%-38s","Used");
    $cmd .= " AREA:rsum${i}#FF3333:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:rsum${i}:AVERAGE:\\\"%7.2lf \\\"";
  }
  if ( $item =~ m/sys/ ) {
    my $lpar_space = sprintf ("%-38s","CPU sys");
    $cmd .= " AREA:rsum${i}#FF3333:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:rsum${i}:AVERAGE:\\\"%7.2lf \\\"";
  }

  if ( $item =~ m/sum_data/ || $item =~ m/sum_io/ ) {
    $cmd .= " GPRINT:rsum${i}:MAX:\\\"%9.0lf \\l\\\"";
  }
  if ( $item =~ m/sum_capacity/ || $item =~ m/tier/ ) {
    $cmd .= " GPRINT:rsum${i}:MAX:\\\"%7.2lf \\l\\\"";
  }
  if ( $item =~ m/sys/ ) {
    $cmd .= " GPRINT:rsum${i}:MAX:\\\"%7.2lf \\l\\\"";
  }
  
  #
  # write || free
  #

  # print LINE read and write
  if ( $item =~ m/sum_io/ || $item =~ m/sum_data/ ) {
    my $lpar_space = sprintf ("%-38s","write");
    $cmd .= " $gtype:wsum${i}#4444FF:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:wsum${i}:AVERAGE:\\\"%9.0lf \\\"";
  }
  if ( $item =~ m/sum_capacity/ || $item =~ m/tier/ ) {
    my $lpar_space = sprintf ("%-38s","Free");
    $cmd .= " STACK:wsum${i}#33FF33:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:wsum${i}:AVERAGE:\\\"%7.2lf \\\"";
  }
  if ( $item =~ m/sys/ ) {
    my $lpar_space = sprintf ("%-38s","Compress");
    $cmd .= " STACK:wsum${i}#3333FF:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:wsum${i}:AVERAGE:\\\"%7.2lf \\\"";
  }

  # print legend
  if ( $item =~ m/sum_data/ || $item =~ m/sum_io/ ) {
    $cmd .= " GPRINT:wsum${i}:MAX:\\\"%9.0lf \\l\\\"";
  }
  if ( $item =~ m/sum_capacity/ || $item =~ m/tier/ ) {
    $cmd .= " GPRINT:wsum${i}:MAX:\\\"%7.2lf \\l\\\"";
  }
  if ( $item =~ m/sys/ ) {
    $cmd .= " GPRINT:wsum${i}:MAX:\\\"%7.2lf \\l\\\"";
  }

  #
  # capacity total
  #
  if ( $item =~ m/sum_capacity/ ) {
    my $lpar_space = sprintf ("%-40s","Total");
    $cmd .= " COMMENT:\\\"$lpar_space\\\"";
    $cmd .= " CDEF:total=rsum${i},wsum${i},+"; # convert into MB if necessary, normaly is there 1
    $cmd .= " GPRINT:total:AVERAGE:\\\"%7.2lf \\l\\\"";
  }

  if ( $type_gr =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  
  if ( $not_execute_rrdtool == 1 ) { return 1;}

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    if ( $ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
    }
    else {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
    }
  }
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");

  return 0;
}

sub draw_all_volume {
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;

  draw_graph_volume ("day","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",$host,$type,$item,$st_type);
  draw_graph_volume ("week","w","HOUR:8:DAY:1:DAY:1:86400:%a",$host,$type,$item,$st_type);
  draw_graph_volume ("4 weeks","m","DAY:1:DAY:2:DAY:2:0:%d",$host,$type,$item,$st_type);
  draw_graph_volume ("year","y","MONTH:1:MONTH:1:MONTH:1:0:%b",$host,$type,$item,$st_type);
  return 0;
}


sub draw_graph_volume {
  my $text     = shift;
  my $type_gr  = shift;
  my $xgrid    = shift;
  my $host     = shift;
  my $type     = shift;
  my $item     = shift;
  my $st_type  = shift;
  my $name = "$tmp_dir/$host/$type-$item-agg-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my @low_volumes = "";
  my $indx_low = 0;
  my $prev = -1;
  my $step_new = $STEP;
  my $once = 0;
  my $last_time = "na";



  my $act_utime = time();
  my $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.cmd";

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "y" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
        #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "m" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "w" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

  print "creating graph : $host:$type:$item:$type_gr\n" if $DEBUG ;

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$wrkdir/$host/$type/volumes.col" ) {
    open(FHC, "< $wrkdir/$host/$type/volumes.col") || error ("file does not exists : $wrkdir/$host/$type/volumes.col ".__FILE__.":".__LINE__) && return 0;
    @color_save = <FHC>;
    close (FHC);
  }

  my $req_time = "";
  my $header = "$type aggregated $item: last $text";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;

  my $color_indx = 0; # reset colour index

  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end now-1$type_gr+1$type_gr";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $font_def_normal";
  $cmd .= " $font_tit_normal";

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
  if ( $item =~ m/^cache_hit$/ )     { $value_short= "%"; $value_long = "percent"; }
  if ( $item =~ m/^ssd_r_cache_hit$/ ){ $value_short= "%"; $value_long = "percent"; }
  if ( $item =~ m/^r_cache_hit$/ )   { $value_short= "%"; $value_long = "percent"; }
  if ( $item =~ m/^w_cache_hit$/ )   { $value_short= "%"; $value_long = "percent"; }
  if ( $item =~ m/^read_pct$/ )      { $value_short= "%"; $value_long = "percent"; }
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
      $val = $step_new; # do not use $val=1024
    }
  }
    
  #print "001 $st_type $type $item $suffix\n";

  $cmd .= " --vertical-label=\\\"$item in $value_long\\\"";
  $cmd .= " --units-exponent=1.00";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " --alt-y-grid";

  # add spaces to lpar name (for formating graph legend)
  my $item_short = $item;
  $item_short =~ s/r_cache_//;
  $item_short =~ s/w_cache_//;
  my $legend = sprintf ("%-38s","$item_short [$value_short]");
  my $legend_heading = "$item_short $delimiter [$value_short] $delimiter Avg $delimiter Max ";
  $legend_heading =~ s/%/%%/g;
  $cmd .= " COMMENT:\\\"$legend       Avg       Max                                                Avg       Max\\l\\\"";

  my $gtype="AREA";
  if ( $item =~ m/resp_t/ || $item =~ m/cache_hit/ || $item =~ m/read_pct/ ) {
    $gtype="LINE1";
  }

  my $lpar_list = "";
  my $lpar_list_tmp = "";

  # read volume cfg files with grouped volumes
  if ( ! -f "$wrkdir/$host/$type/volumes.cfg" ) {
    error("$host: No volumes cfg files has been found (ignore after fresh install): $wrkdir/$host/$type/volumes.cfg ".__FILE__.":".__LINE__);
    return 2;
  }
  open(FHR, "< $wrkdir/$host/$type/volumes.cfg") || error ("$host: file does not exists : $wrkdir/$host/$type/volumes.cfg ".__FILE__.":".__LINE__) && return 0;
  my @files = <FHR>;
  close (FHR);

  my $vols = "";
  my $itemm_sum = "";
  my $lpar_space = "";
  my $last_vol = -1;
  my $color_file_change = 0;
  my $item_name_for_print_comment = "";
  my $cmd_print = ""; # print commands for clickable legend
  my $once_report = 0;

  foreach my $volg (@files) {
    chomp($volg);
    $vols = $volg;
    $volg =~ s/ : .*//;
    $vols =~ s/^.* : //;

    my @vol_array = split(';', $vols);

    $prev = -1;
    my $itemm = $item."m".$volg;
    $itemm =~ s/\./Z/g;	# dots in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/ /X/g; 	# space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/\#/Y/g; # hash in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser
    $itemm_sum = $itemm."sum";

    my $one_volume_nick = 2;  # volume nick has 1 physical volume == 1, or more < 1;
    foreach my $lpar (@vol_array) {
      $lpar =~ s/ //; # it must be there!!!
      if ( $lpar eq '' ) {
        next;
      }
      $one_volume_nick--;
    }

    # avoid volumes not being loaded during the given interval
    # multivolumes (more volumes under one nick
    # print "002 $volg : $one_volume_nick : $type,$type_gr,$item,$val,$type_gr\n";
    if ( $one_volume_nick < 1 ) {
      my $low_util = find_max_load_multi ($st_type,$step_new,$req_time,$volg,$basedir,$wrkdir,$host,$type,$type_gr,$item,$val,$type_gr,\@vol_array);
      # print "003 $volg : $low_util \n";
      if ( $low_util == 1 ) {
        foreach my $lpar (@vol_array) {
          $lpar =~ s/ //; # it must be there!!!
          $lpar =~ s/^0x//;
          if ( $lpar eq '' ) {
            next;
          }
          my $file = "$wrkdir/$host/$type/$lpar.$suffix";
          $low_volumes[$indx_low] = $file; # list of all not graphed volumes
          $indx_low++; # summ total of all low volumes must be displayed as the last line
        }
        next; # avoid low loaded volume # print it i total at the end
      }
    }

    #
    # follow each volume (there migh be more volumes under 1 volume nick!!!
    # first run just select files ... must be for mutilevel resp_t a cache_hit to count how many items are summed
    my @vol_array_work = "";
    my $vol_array_work_indx = 0;
    foreach my $lpar (@vol_array) {

      $lpar =~ s/^0x//;
      $lpar =~ s/ //; # it must be there!!!
      my $file = "$wrkdir/$host/$type/$lpar.$suffix";

      if ( $st_type =~ m/XIV/ || $st_type =~ m/DS5K/ ) {
        # XIV volumes contain pool_id in their names: 00273763-P102932.rrd
        foreach my $file_xiv (<$wrkdir/$host/$type/$lpar-P*\.$suffix>) {
          $file = $file_xiv;
          last;
        }
      }

      if ( $lpar eq '' ) {
        next;
      }

      if ( ! -f $file ) {
        if ( $once_report == 0 ) {
          # It might appear after the upgrade to 1.00 as *rrc files are not in place yet
          error("volumes stats: $file does not exist, continuing ".__FILE__.":".__LINE__);
          $once_report++;
        }
        next;
      }

      # go every each volume for particular group

      # avoid old lpars which do not exist in the period
      my $rrd_upd_time = (stat("$file"))[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }
  
      # avoid volumes not being loaded enough during the given interval
      if ( $one_volume_nick == 1 ) {
        # avoid that for caching
        if (  $item !~ m/cache_hit/ && $item !~ m/read_pct/ ) {
        # only for 1 phys volume nicks
        my $low_util = find_max_load ($st_type,$type,$step_new,$file,$item,$val,$type_gr);
        if ( $low_util == 1 ) {
          $low_volumes[$indx_low] = $file;
          $indx_low++; # summ total of all low volumes must be displayed as the last line
          next;
        }
        }
      }
      $vol_array_work[$vol_array_work_indx] = $file;
      #print "001  $vol_array_work[$vol_array_work_indx] : $file : $vol_array_work_indx\n";
      $vol_array_work_indx++;
    }

    # lets make $cmd for multilevels ones
    my $file_for_print = "";
    foreach my $file (@vol_array_work) {
      if ( $file eq '' ) {
        next;
      }
      $file_for_print = $file; 

      if ( $type_gr =~ m/d/ && $once == 0 ) {
        # find out time stamp of last data update
        # take just one volume to keep it simple
        $once++; 
        RRDp::cmd qq(last "$file");
        my $last_tt = RRDp::read;
        $last_time=localtime($$last_tt);
        $last_time =~ s/:/\\:/g;
      }


      # bulid RRDTool cmd
  
      $cmd .= " DEF:$item${i}=\\\"$file\\\":$item:AVERAGE";
      if ( $vol_array_work_indx > 1 ) {
        my $val_tot = $val;
        if ( $item =~ m/resp_t/ || $item =~ m/cache_hit/ || $item =~ m/read_pct/ ) {
          # resp_t and cache_hit must be averaged not summed for multivolumes ...
          $val_tot = $val * $vol_array_work_indx;
        }
        $cmd .= " CDEF:$itemm${i}=$item${i},$val_tot,/"; # convert into MB if necessary, normaly is there 1
      }
      else {
        $cmd .= " CDEF:$itemm${i}=$item${i},$val,/"; # convert into MB if necessary, normaly is there 1
      }

      if ( $prev == -1 ) {
          $cmd .= " CDEF:$itemm_sum${i}=$itemm${i}"; 
      }
      else {
          $cmd .= " CDEF:$itemm_sum${i}=$itemm_sum${last_vol},$itemm${i},+"; 
      }
      $i++;
      $prev++;
      $last_vol++;
    }

    if ( $prev == -1 ) {
      next; # have not found any volume
    }

    # add spaces to lpar name to have 18 chars total (for formating graph legend)
    $lpar_space = $volg;
    $lpar_space = sprintf ("%-38s","$lpar_space");

    # Found out stored color index to keep same color for the volume across all graphs
    my $color_indx_found = -1;
    my $col_index = 0;
    foreach my $line_col (@color_save) {
      chomp ($line_col);
      if ( $line_col eq '' ) {
        next;
      }
      (my $color_indx_found_act, my $volg_save) = split (/:/,$line_col);
      if ( $volg =~ m/^$volg_save$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx = $color_indx_found;
        last;
      }
      $col_index++;
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$col_index] = $color_indx.":".$volg;
    }
    while ($color_indx > $color_max ) { # this should not normally happen, just to be sure
      $color_indx = $color_indx - $color_max;
    }
    # end color

    $cmd .= " $gtype:$itemm_sum${last_vol}$color[$color_indx]:\\\"$lpar_space\\\"";
    $item_name_for_print_comment = "$itemm_sum${last_vol}";

    if ( $item !~ m/resp_t/ && $item !~ m/cache_hit/ && $item !~ m/read_pct/ ) {
      $gtype="STACK";
    }
  
    # put carriage return after each second lpar in the legend
    if ($j == 1) {
      if ( $item =~ m/io_rate/ || $item =~ m/read_io/ || $item =~ m/write_io/ ) {
        $cmd .= " GPRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.0lf \\\"";
        $cmd .= " GPRINT:$itemm_sum${last_vol}:MAX:\\\"%6.0lf \\l\\\"";

        $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.0lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
        $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %6.0lf $delimiter $file_for_print $delimiter $st_type\\\"";
      }
      else {
        if ( $item !~ m/cache_hit/ && $item !~ m/read_pct/ ) {
          $cmd .= " GPRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf \\\"";
          $cmd .= " GPRINT:$itemm_sum${last_vol}:MAX:\\\"%6.1lf \\l\\\"";

          $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
          $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %6.1lf $delimiter $file_for_print $delimiter $st_type\\\"";
        }
        else {
          # cache_hit
          my $lpar_print = $volg;
          $lpar_print =~ s/ /=====space=====/g;
          $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"$lpar_print %6.1lf \\\"";
          $cmd .= " GPRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf \\\"";
          $cmd .= " GPRINT:$itemm_sum${last_vol}:MAX:\\\"%6.1lf \\l\\\"";

          $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf $delimiter $lpar_print $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
	  $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %6.1lf $delimiter $file_for_print $delimiter $st_type\\\"";
        }
      }
      $j = 0;
    }
    else {
      if ( $item =~ m/io_rate/ || $item =~ m/read_io/ || $item =~ m/write_io/ ) {
        $cmd .= " GPRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.0lf \\\"";
        $cmd .= " GPRINT:$itemm_sum${last_vol}:MAX:\\\"%6.0lf \\\"";

        $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.0lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
	$cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %6.0lf $delimiter $file_for_print $delimiter $st_type\\\"";
      }
      else {
        if ( $item !~ m/cache_hit/ && $item !~ m/read_pct/ ) {
          $cmd .= " GPRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf \\\"";
          $cmd .= " GPRINT:$itemm_sum${last_vol}:MAX:\\\"%6.1lf \\\"";

          $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
          $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %6.1lf $delimiter $file_for_print $delimiter $st_type\\\"";
        }
        else {
          # cache_hit
          my $lpar_print = $volg;
          $lpar_print =~ s/ /=====space=====/g;
          $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"$lpar_print %6.1lf \\\"";
          $cmd .= " GPRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf \\\"";
          $cmd .= " GPRINT:$itemm_sum${last_vol}:MAX:\\\"%6.1lf \\\"";

          $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf $delimiter $lpar_print $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
          $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %6.1lf $delimiter $file_for_print $delimiter $st_type\\\"";
        }
      }
      $j++
    }
    $color_indx++;
    if ($color_indx > $color_max ) {
      $color_indx = 0;
    }
  }
  if ($j == 1) {
    $cmd .= " COMMENT:\\\"\\l\\\"";
  }

    # Found out stored color index to keep same color for the volume across all graphs
    # must be done for rest of vols once more
    my $color_indx_found = -1;
    my $cindx = 0;
    foreach my $line_col (@color_save) {
      chomp ($line_col);
      if ( $line_col eq '' ) {
        next;
      }
      (my $color_indx_found_act, my $volg_save) = split (/:/,$line_col);
      if ( $volg_save =~ m/^rest_of_vols$/ ) {
        $color_indx_found = $color_indx_found_act;
        last;
      }
      $cindx++; 
    }
    if ( $color_indx_found == -1 ) {
      $color_indx_found = $color_indx;
      $color_save[$cindx] = $color_indx.":rest_of_vols";
    }
    # end color
  
  if ( $item !~ m/cache_hit/ && $item !~ m/resp_t/ && $item !~ m/read_pct/ ) {
    # cache_hit do not need it
    # response time also does not make sense show low volumes
    # place there total for rest of not displayed volumes (low loaded)
    $cmd .= sum_low_volume($val,$gtype,$i,$j,$last_vol,$color_indx_found,$item,\@low_volumes);
  }
  if ( $item =~ m/resp_t/ ) {
    $cmd .= " COMMENT:\\\"Volumes under $RESPONSE_MAX msec in a peak are not graphed\\l\\\"";
    $cmd .= " COMMENT:\\\"etc/stor2rrd.cfg\\:VOLUME_RESPONSE_MAX\\\"";

    my $cmd_txp1 = "Volumes under $RESPONSE_MAX msec in a peak are not graphed";
    my $cmd_txp2 = "etc/stor2rrd.cfg\\:VOLUME_RESPONSE_MAX";
    $cmd .= " PRINT:$item_name_for_print_comment:MAX:\\\" %8.1lf $delim_com $cmd_txp1\\\"";
    $cmd .= " PRINT:$item_name_for_print_comment:MAX:\\\" %8.1lf $delim_com $cmd_txp2\\\"";

  }


  if ( $type_gr =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  # write colors into a file
  if ( $color_file_change == 1 ) {
    open(FHC, "> $wrkdir/$host/$type/volumes.col") || error ("file does not exists : $wrkdir/$host/$type/volumes.col ".__FILE__.":".__LINE__) && return 0;
    foreach my $line_cs (@color_save) {
      chomp ($line_cs);# it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/:/ ) {
        print FHC "$line_cs\n";
      }
    }
    close (FHC);
  }
  # colours

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  
  # this has to be executed as working with the ouptut $ret
  if ( $not_execute_rrdtool == 1 ) { 
    if ( $item !~ m/cache_hit/ && $item !~ m/read_pct/ ) {
      return 0;
    }
  }

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    if ( $ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
    }
    else {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
    }
  }
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");

  if ( $item =~ m/cache_hit/ || $item =~ m/read_pct/ ) {
    # store output for cache_hit text table
    $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.out";
    open(FH, "> $tmp_file") || error("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
    print FH "$ret\n";
    close (FH);
  }

  return 0;
}

# it return 1 if there is avg load higher than $limit othervise 0
# it is for filtering data especially unused volumes
# this one is for multi volume nicks
sub find_max_load_multi {
  my ($st_type,$STEP,$req_time,$volg,$basedir,$wrkdir,$host,$type,$type_gr,$item,$val,$time_range,$vol_array_tmp) = @_;
  my @vol_array = @{$vol_array_tmp};
  my $rrd = "";
  my $limit = 0;
  my $cmd = "";
  my $itemm = $item."m".$volg;
  $itemm =~ s/\./Z/g; 	# dots in rrdtool variable names causing problems for rrdtool parser
  $itemm =~ s/ /X/g;   # space in rrdtool variable names causing problems for rrdtool parser
  $itemm =~ s/\#/Y/g; # hash in rrdtool variable names causing problems for rrdtool parser
  $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser
  my $itemm_sum = $itemm."sum";
  my $last_vol = -1;

  if ( $item =~ m/io_rate/ ||  $item =~ m/read_io/ ||  $item =~ m/write_io/ ) {
    $limit = $IO_MAX;
  }

  if ( $item =~ m/data_rate/  ||  $item =~ m/^read$/ ||  $item =~ m/^write$/ || $item =~ m/^read_b$/ ||  $item =~ m/^write_b$/ ) {
    $limit = $DATA_MAX;
  }

  if ( $item =~ m/resp/ ) {
    $limit = $RESPONSE_MAX;
  }

  if ( $item =~ m/cache_usage/ ) {
    $limit = $CACHE_MAX;
  }

  if ( $item =~ m/cache_hit/ ) {
    return 0; # do not use it for cache_hit
  }

  $cmd .= "graph \\\"$basedir/tmp/name.png\\\"";
  $cmd .= " --start now-1$time_range";
  $cmd .= " --end now";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$STEP";

  my $prev = -1;
  my $i = 0;

  $val = 1; 
  my $valmb = 1;
  my $suffix = ".rrd";
  if ( $st_type =~ m/^DS8K$/ && $type =~ /VOLUME/ ) {
    if ( $item =~ m/^read$/ || $item =~ m/^write$/ ) {
      # data is stored in wrong RRDTool type (GAUGE instead of ABSOLUTE)
      # this do data conversion
      $val = $STEP; # it must be multiplied by STEP as it is cumulated since every 5 minutes
      $valmb = 1024;
    }
    if ( $item =~ m/^resp_t_r$/ || $item =~ m/^resp_t_w$/ || $item =~ m/^read_io$/ || $item =~ m/^write_io$/ || $item =~ m/^read_b$/ || 
         $item =~ m/^write_b$/ || $item =~ m/^read_io_b$/ || $item =~ m/^write_io_b$/ || $item =~ m/^resp_t_r_b$/ || $item =~ m/^resp_t_w_b$/  ||
         $item =~ m/^w_cache_hit$/ || $item =~ m/^r_cache_hit$/ ) {
      $suffix = ".rrc";
    }
  }
  if ( $st_type =~ m/^SWIZ$/ && $type =~ /VOLUME/ ) {
    if ( $item =~ m/^r_cache_hit$/ || $item =~ m/^w_cache_hit$/  || $item =~ m/^r_cache_usage$/ || $item =~ m/^w_cache_usage$/ ) {
      $suffix = ".rrc";
    }
  }


  # follow each volume (there migh be more volumes under 1 volume nick!!!
  foreach my $lpar (@vol_array) {
      $lpar =~ s/^0x//;
      $lpar =~ s/ //;
      if ( $lpar eq '' ) {
        next;
      }
      my $file = "$wrkdir/$host/$type/$lpar$suffix";

      # avoid old lpars which do not exist in the period
      if ( ! -f $file ) {
        next;
      }
      my $rrd_upd_time = (stat("$file"))[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }
  
      # bulid RRDTool cmd
      $i++;
      $last_vol++;
  
      $cmd .= " DEF:$item${i}-tmp_nan=\\\"$file\\\":$item:AVERAGE";
      $cmd .= " CDEF:$item${i}-tmp=$item${i}-tmp_nan,UN,0,$item${i}-tmp_nan,IF"; # it must be here to make cauculation regardless of already deleted volumes! since 1.10
      $cmd .= " CDEF:$item${i}kb=$item${i}-tmp,$val,*";
      $cmd .= " CDEF:$item${i}=$item${i}kb,$valmb,/";
      if ( $prev == -1 ) {
        $cmd .= " CDEF:$itemm_sum${i}=$item${i}"; 
      }
      else {
        $cmd .= " CDEF:$itemm_sum${i}=$itemm_sum${last_vol},$item${i},+"; 
      }
      $prev++;
  }
  if ( $prev == -1 ) {
    return 0;
  }

  $cmd .= " CDEF:result=$itemm_sum${i},$limit,LT,UNKN,$itemm_sum${i},IF";
  $cmd .= " PRINT:result:MAX:%10.1lf";
  $cmd =~ s/\\"/"/g;

  RRDp::cmd qq($cmd);
  my $answer = RRDp::read;

  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    #print "001 $host-$type-$item-$volg: $val : $limit : $$answer";
    return 1;
  }
  #print "010 $host-$type-$item-$volg: $val : $limit : $$answer";
  return 0;
}


# same as above only for single volume nicks
sub find_max_load {
  my $st_type= shift;
  my $type = shift;
  my $STEP = shift;
  my $rrd = shift;
  my $item = shift;
  my $val = shift;;
  my $time_range = shift;
  my $limit = 0;

  if ( $item =~ m/io_rate/  ||  $item =~ m/read_io/ ||  $item =~ m/write_io/ ) {
    $limit = $IO_MAX;
  }

  if ( $item =~ m/data_rate/  ||  $item =~ m/^read$/ ||  $item =~ m/^write$/ || $item =~ m/^read_b$/ ||  $item =~ m/^write_b$/ ) {
    $limit = $DATA_MAX;
  }

  if ( $item =~ m/resp/ ) {
    $limit = $RESPONSE_MAX;
  }

  if ( $item =~ m/cache_usage/ ) {
    $limit = $CACHE_MAX;
  }

  if ( $item =~ m/cache_hit/ ) {
    return 0; # do not use it for cache_hit
  }

  $val = 1; 
  my $valmb = 1;
  if ( $st_type =~ m/^DS8K$/ && $type =~ /VOLUME/ ) {
    if ( $item =~ m/^read$/ || $item =~ m/^write$/ ) {
      # data is stored in wrong RRDTool type (GAUGE instead of ABSOLUTE)
      # this do data conversion
      $val = $STEP; # it must be multiplied by STEP as it is cumulated since every 5 minutes
      $valmb = 1024;
    }
  }


  RRDp::cmd qq(graph "$basedir/tmp/name.png"
      "--start" "now-1$time_range"
      "--end" "now"
      "--width=400"
      "--height=150"
      "--step=$STEP"
      "DEF:item1=$rrd:$item:AVERAGE"
      "CDEF:itemkb=item1,$val,*"
      "CDEF:item=itemkb,$valmb,/"
      "CDEF:result=item,$limit,LT,UNKN,item,IF"
      "PRINT:result:MAX: %10.2lf"
  );

  my $answer = RRDp::read;
  #print "$rrd $$answer\n";
  if ( $$answer =~ m/NaN/ || $$answer =~ m/nan/ ) {
    #print "011 $rrd: $type-$item: $val : $limit : $$answer";
    return 1;
  }
  #print "111 $rrd: $type-$item: $val : $limit : $$answer";
  return 0;
}


sub sum_low_volume
{
  my ($val,$gtype,$i,$j,$last_vol,$color_indx,$item,$low) = @_;
  my @low_volumes = @{$low};
  my $volg = "rest";
  my $cmd = "";
  my $cmd_text = "";
  my $cmd_txp1 = "";
  my $cmd_txp2 = "";
  my $itemm = $item."m".$volg;
  $itemm =~ s/\./Z/g; # dots in rrdtool variable names causing problems for rrdtool parser
  $itemm =~ s/ /X/g;  # space in rrdtool variable names causing problems for rrdtool parser
  $itemm =~ s/\#/Y/g; # hash in rrdtool variable names causing problems for rrdtool parser
  $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser
  my $itemm_sum = $itemm."sum";
  my $lpar_space = sprintf ("%-38s","rest of vols total");
  my $found = 0;
  my $prev=-1; # must be reinitialized
  
  if ( $item =~ m/io_rate/   ||  $item =~ m/read_io/ ||  $item =~ m/write_io/ ) {
    $cmd_text .= " COMMENT:\\\"Volumes under $IO_MAX iops in a peak are not graphed\\l\\\"";
    $cmd_text .= " COMMENT:\\\"etc/stor2rrd.cfg\\:VOLUME_IO_MAX etc/storage-list.cfg\\:VOLUME_AGG_IO_LIM\\\"";
    $cmd_txp1 = "Volumes under $IO_MAX iops in a peak are not graphed";
    $cmd_txp2 = "etc/stor2rrd.cfg\\:VOLUME_IO_MAX etc/storage-list.cfg\\:VOLUME_AGG_IO_LIM";
  }

  if ( $item =~ m/data_rate/  ||  $item =~ m/^read$/ ||  $item =~ m/^write$/ ) {
    $cmd_text .= " COMMENT:\\\"Volumes under $DATA_MAX kBytes in a peak are not graphed\\l\\\"";
    $cmd_text .= " COMMENT:\\\"etc/stor2rrd.cfg\\:VOLUME_DATA_MAX etc/storage-list.cfg\\:VOLUME_AGG_DATA_LIM\\\"";
    $cmd_txp1 = "Volumes under $DATA_MAX kBytes in a peak are not graphed";
    $cmd_txp2 = "etc/stor2rrd.cfg\\:VOLUME_DATA_MAX etc/storage-list.cfg\\:VOLUME_AGG_DATA_LIM";
  }

  if ( $item =~ m/resp/ ) {
    $cmd_text .= " COMMENT:\\\"Volumes under $RESPONSE_MAX msec in a peak are not graphed\\l\\\"";
    $cmd_text .= " COMMENT:\\\"etc/stor2rrd.cfg\\:VOLUME_RESPONSE_MAX\\\"";
    $cmd_txp1 = "Volumes under $RESPONSE_MAX msec in a peak are not graphed";
    $cmd_txp2 = "etc/stor2rrd.cfg\\:VOLUME_RESPONSE_MAX";
  }

  if ( $item =~ m/cache_usage/ ) {
    $cmd_text .= " COMMENT:\\\"Volumes under $CACHE_MAX kBytes in a peak are not graphed\\l\\\"";
    $cmd_text .= " COMMENT:\\\"etc/stor2rrd.cfg\\:VOLUME_CACHE_MAX\\\"";
    $cmd_txp1 = "Volumes under $CACHE_MAX kBytes in a peak are not graphed";
    $cmd_txp2 = "etc/stor2rrd.cfg\\:VOLUME_CACHE_MAX";
  }

  foreach my $file (@low_volumes) {

      if ( $file eq '' ) {
        next;
      }
      # bulid RRDTool cmd
      $cmd .= " DEF:$item${i}_nan=\\\"$file\\\":$item:AVERAGE";
      $cmd .= " CDEF:$item${i}=$item${i}_nan,UN,0,$item${i}_nan,IF"; # it must be here to make cauculation regardless of already deleted volumes! since 1.10
      $cmd .= " CDEF:$itemm${i}=$item${i},$val,/"; # convert into MB if necessary, normaly is there 1
      if ( $prev == -1 ) {
        $cmd .= " CDEF:$itemm_sum${i}=$itemm${i}"; 
      }
      else {
        $cmd .= " CDEF:$itemm_sum${i}=$itemm_sum${last_vol},$itemm${i},+"; 
      }
      $i++;
      $prev++;
      $found++;
      $last_vol++;
  }

  if ( $found == 0 ) {
    return "$cmd_text"; # have not found any low volume
  }
  $cmd .= " COMMENT:\\\"\\l\\\"";
  $cmd .= " $gtype:$itemm_sum${last_vol}$color_rest_of_vols:\\\"$lpar_space\\\"";
  $cmd .= " GPRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf \\\"";
  $cmd .= " GPRINT:$itemm_sum${last_vol}:MAX:\\\"%6.1lf \\l\\\"";

  my $legend_heading = "item_short $delimiter [value_short] $delimiter Avg $delimiter Max ";
  $legend_heading =~ s/%/%%/g;
  my $file_for_print = "";
  $cmd .= " PRINT:$itemm_sum${last_vol}:AVERAGE:\\\"%6.1lf $delimiter $lpar_space $delimiter $legend_heading $delimiter $color_rest_of_vols\\\"";
  $cmd .= " COMMENT:\\\" $delimiter $file_for_print $delimiter $st_type\\\"";
  $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %8.1lf $delimiter\\\"";
  $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %8.1lf $delim_com $cmd_txp1\\\"";
  $cmd .= " PRINT:$itemm_sum${last_vol}:MAX:\\\" %8.1lf $delim_com $cmd_txp2\\\"";

  $cmd .= $cmd_text;

  return $cmd;
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

sub clean_old_data_files {
  my ($host, $wrkdir, $DEBUG) = @_;


  # runs that once a day
  my $file = "$tmp_dir/clean-$host.touch";
  if ( -f "$file" ) {
    my $ret = Storcfg2html::once_a_day ($file);
    if ( $ret == 0 ) {
      print "clean old tmp  : not this time - same day\n" if $DEBUG ;
      return 1;
    }
  }
  `touch "$file"`;
  print "clean old tmp  : $host: now \n" if $DEBUG ;

  # go through all tmp files like DS8300-1.perf.20130429-0020-tmp
  # and delete older than 5 days


  my $week = 604800;
  my $time_u = time();
  my @files = <$wrkdir/$host/$host.perf*-tmp>;
  foreach $file (@files) {
    chomp($file);
    my $time = (stat("$file"))[9];
    if ( $time + $week < $time_u ) {
      #delete old file
      my $filesize = -s "$file";
      my $loc_time = localtime($time);
      error ("delete old tmp : $host:$file : $loc_time : size:$filesize ".__FILE__.":".__LINE__);
      unlink ($file);
    }
  }

  return 1;
}

sub draw_pool_cap {
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;

  draw_graph_pool_cap ("day","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",$host,$type,$item,$st_type);
  draw_graph_pool_cap ("week","w","HOUR:8:DAY:1:DAY:1:86400:%a",$host,$type,$item,$st_type);
  draw_graph_pool_cap ("4 weeks","m","DAY:1:DAY:2:DAY:2:0:%d",$host,$type,$item,$st_type);
  draw_graph_pool_cap ("year","y","MONTH:1:MONTH:1:MONTH:1:0:%b",$host,$type,$item,$st_type);
  return 0;
}

sub draw_graph_pool_cap {
  my $text     = shift;
  my $type_gr  = shift;
  my $xgrid    = shift;
  my $host     = shift;
  my $type     = shift;
  my $item     = shift;
  my $st_type = shift;
  my $name = "$tmp_dir/$host/$type-$item-agg-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my $step_new = $STEP;
  my $once = 0;
  my $last_time = "na";
  my $color_indx = 0;


  my $act_utime = time();
  my $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.cmd";

  # do not update charts if there is not new data in RRD DB
  if ( $type_gr =~ "y" && -f "$tmp_file" ) {
    my $png_time = (stat("$tmp_file"))[9];
    if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
      #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
      if ( $upgrade == 0 ) { return 0;}
    }
  }

  # do not update charts if there is not new data in RRD DB
  if ( $type_gr =~ "m" && -f "$tmp_file" ) {
    my $png_time = (stat("$tmp_file"))[9];
    if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
      #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
      if ( $upgrade == 0 ) { return 0;}
    }
  }

  # do not update charts if there is not new data in RRD DB
   if ( $type_gr =~ "w" && -f "$tmp_file" ) {
    my $png_time = (stat("$tmp_file"))[9];
    if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
      #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
      if ( $upgrade == 0 ) { return 0;}
     }
  }

  my $type_text = $type;
  if ( $st_type =~ m/SWIZ/ && $type =~ m/RANK/ ) {
    $type_text = "MDISK";
  }

  print "creating graph : $host:$type_text:$item:$type_gr\n" if $DEBUG ;

  my $req_time = "";
  my $header = "$type_text capacity $item: last $text";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;

  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end now-1$type_gr+1$type_gr";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $font_def_normal";
  $cmd .= " $font_tit_normal";

  my $value_short = "";
  my $value_long = "";
  my $val = 1;

  # do not use switch statement
  if ( $item =~ m/^used$/ ) { $value_short= "TB"; $value_long = "TBytes"; $val = 1024;}
  if ( $item =~ m/^real$/ ) { $value_short= "TB"; $value_long = "TBytes"; $val = 1024;}

  my $item_label = uc($item);
  $cmd .= " --vertical-label=\\\"Capacity in $value_long\\\"";

  $cmd .= " --units-exponent=1.00";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " --alt-y-grid";

  # add spaces to lpar name (for formating graph legend)
  my $legend = sprintf ("%-38s","$item [$value_short]");

  $cmd .= " COMMENT:\\\"$legend         Avg         Max \\l\\\"";

  my $gtype="AREA";

  my $lpar_list = "";
  my $pool_found = 0;
  my $pool_id_tmp = "";
  my $lpar_list_tmp = "";
  my $nothing_to_sum=1;

  foreach my $line (<$wrkdir/$host/$type/*-cap.rrd>) {
    chomp($line);
    if ( $line !~ m/-cap\.rrd$/ ) {
      next; # it does not end bu .rrd suffix, "$ cannt be use in foreach <>
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = (stat("$line"))[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }

    if ( $type_gr =~ m/d/ && $once == 0 ) {
      # find out time stamp of last data update
      # take just one volume to keep it simple
      $once++;
      RRDp::cmd qq(last "$line");
      my $last_tt = RRDp::read;
      $last_time=localtime($$last_tt);
      $last_time =~ s/:/\\:/g;
    }

    my @link_l = split(/\//,$line);
    my $lpar = "";
    foreach my $m (@link_l) {
      $lpar = $m;
    }
    $lpar =~ s/-cap\.rrd$//; # filter pool info

    if (ishexa($lpar) == 1 ) {
      # use POOL ID to keep color same
      # $color_indx = $lpar; --> no no, XIV ...
      while ($color_indx > $color_max ) {
        $color_indx = $color_indx - $color_max;
      }
    }

    my $pool_tr_table_indx = 0;
    my $pool_name = "NA";
    $pool_name = get_pool_name($lpar);

    # add spaces to lpar name to have 25 chars total (for formating graph legend)
    my $lpar_space = $pool_name;
    $lpar_space = sprintf ("%-38s","$lpar_space");


    # bulid RRDTool cmd

    if ( $item =~ m/used/ ) {
      $cmd .= " DEF:$item${i}_used=\\\"$line\\\":used:AVERAGE";
    }
    if ( $item =~ m/real/ ) {
      $cmd .= " DEF:$item${i}_used=\\\"$line\\\":real:AVERAGE";
    }
    $cmd .= " $gtype:$item${i}_used$color[$color_indx]:\\\"$lpar_space\\\"";
    $cmd .= " GPRINT:$item${i}_used:AVERAGE:\\\"%6.2lf \\\"";
    $cmd .= " GPRINT:$item${i}_used:MAX:\\\"%6.2lf \\l\\\"";
    $i++;
    $color_indx++;
    if ($color_indx > $color_max ) {
      $color_indx = 0;
    }
    $gtype="STACK";
  }


  if ( $type_gr =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  
  if ( $not_execute_rrdtool == 1 ) { return 1;}

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    if ( $ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
    }
    else {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
    }
  }
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");

  return 0;
}

sub pool_translate 
{
  my $act_time = shift;
  my $wrkdir = shift;
  my $host = shift;

  # read  pool table to translate id to pool names

  open(FHP, "< $wrkdir/$host/pool.cfg") || error ("Can't open $wrkdir/$host/pool.cfg : $! : (ignore after fresh install) ".__FILE__.":".__LINE__) && return 0;
  my @lines = <FHP>;
  close (FHP);
  @pool_tr_table_id = "";
  @pool_tr_table_name = "";
  my $pool_tr_table_indx = 0;
  foreach my $line_p  (@lines) {
    chomp($line_p);
    (my $id,  my $name) = split(/:/,$line_p);
    if ( ! defined ($id) || $id eq '' ||  ! defined ($name) || $name eq '' ) {
      next;
    }
    $id =~ s/ //g;
    $name =~ s/^ //;
    $pool_tr_table_id[$pool_tr_table_indx] = $id; 
    $pool_tr_table_name[$pool_tr_table_indx] = $name; 
    $pool_tr_table_indx++;
  }

  return 0;
}

sub get_pool_name
{
  my $pool_id = shift;
  my $counter = 0;
  
  foreach my $id (@pool_tr_table_id) {
    if ( $id eq $pool_id ) {
      if ( defined($pool_tr_table_name[$counter]) && ! $pool_tr_table_name[$counter] eq '' ) {
        return $pool_tr_table_name[$counter];
      }
    }
    $counter++;
  }
  return "NA";
}

sub draw_all_port_subsystem {
  my $host = shift;
  my $type = shift;
  my $item = shift;

  draw_graph_port_subsystem ("day","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",$host,$type,$item);
  draw_graph_port_subsystem ("week","w","HOUR:8:DAY:1:DAY:1:86400:%a",$host,$type,$item);
  draw_graph_port_subsystem ("4 weeks","m","DAY:1:DAY:2:DAY:2:0:%d",$host,$type,$item);
  draw_graph_port_subsystem ("year","y","MONTH:1:MONTH:1:MONTH:1:0:%b",$host,$type,$item);
  return 0;
}

sub draw_graph_port_subsystem {
  my $text     = shift;
  my $type_gr  = shift;
  my $xgrid    = shift;
  my $host     = shift;
  my $type     = shift;
  my $item     = shift;
  my $name = "$tmp_dir/$host/$type-$item-agg-subsys-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my $step_new = $STEP;
  my $once = 0;
  my $last_time = "na";
  my $color_indx = 0; # reset colour index


  my $act_utime = time();
  my $tmp_file="$tmp_dir/$host/$type-$item-subsys-$type_gr.cmd";

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "y" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
        #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "m" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "w" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    print "creating graph : $host:$type:$item:subsys:$type_gr\n" if $DEBUG ;

  my $req_time = "";
  my $header = "$type per subsystem $item: last $text";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;


  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end now-1$type_gr+1$type_gr";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $font_def_normal";
  $cmd .= " $font_tit_normal";

  my $value_short = "";
  my $value_long = "";
  my $val = 1; # base, the number will be devided by that constant

  # do not use switch statement
  if ( $item =~ m/^data_rate$/ ) { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^read$/ )     { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^write$/ )    { $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^io_rate$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^read_io$/ )   { $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^write_io$/ )  { $value_short= "IOPS"; $value_long = "IO per second"; }

  if ( $item =~ m/^sys$/ || $item =~ m/^compress$/ ) {
    $cmd .= " --vertical-label=\\\"$value_long\\\"";
  }
  else{
    $cmd .= " --vertical-label=\\\"$item in $value_long\\\"";
  }

  $cmd .= " --units-exponent=1.00";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " --alt-y-grid";

  # add spaces to lpar name (for formating graph legend)
  my $legend = sprintf ("%-38s","$item [$value_short]");
  $cmd .= " COMMENT:\\\"$legend    Avg      Max \\l\\\"";

  my $gtype="LINE1";

  my $lpar_list = "";
  my $pool_found = 0;
  my $pool_id_tmp = "";
  my $lpar_list_tmp = "";

  foreach my $line (<$wrkdir/$host/$type/*rrd>) {
    chomp($line);
    if ( $line !~ m/\.rrd$/ ) {
      next; # it does not end bu .rrd suffix, "$ cannt be use in foreach <>
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = (stat("$line"))[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }

    my @link_l = split(/\//,$line);
    my $lpar = "";
    foreach my $m (@link_l) {
      $lpar = $m;
    }
    $lpar =~ s/\.rrd$//;
    $lpar =~ s/PORT-//;
    $lpar =~ s/0x//;

    if ( $type_gr =~ m/d/ && $once == 0 ) {
      # find out time stamp of last data update
      # take just one volume to keep it simple
      $once++;
      RRDp::cmd qq(last "$line");
      my $last_tt = RRDp::read;
      chomp ($$last_tt);
      $last_time=localtime($$last_tt);
      $last_time =~ s/:/\\:/g;
    }



    # bulid RRDTool cmd
    my $itemm = $item."m";
    $itemm =~ s/\./Z/g; # dots in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/ /X/g;  # space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/\#/Y/g; # hash in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser

    $cmd .= " DEF:$item${i}=\\\"$line\\\":$item:AVERAGE";
    $cmd .= " DEF:type${i}=\\\"$line\\\":type:AVERAGE";
    $cmd .= " CDEF:$itemm${i}=$item${i},$val,/"; # convert into MB if necessary, normaly is there 1

    # summ up traffic per FC/SAS and iSCSI sources
    $cmd .= " CDEF:fc${i}=type${i},0,EQ,$itemm${i},0,IF";     # FC disky
    $cmd .= " CDEF:sas${i}=type${i},1,EQ,$itemm${i},0,IF";    # SAS disky
    $cmd .= " CDEF:iscsi${i}=type${i},2,EQ,$itemm${i},0,IF";   # iSCSI disky
    $cmd .= " CDEF:iprep${i}=type${i},4,EQ,$itemm${i},0,IF";   # IPREP disky
    $i++;
  }

  # Load all items into the $cmd
  # FC  
  my $index_actual = 0;
  $cmd .= " CDEF:fc=fc${index_actual}";
  $index_actual++;
  for (; $index_actual < $i; $index_actual++) { 
    $cmd .= ",fc${index_actual},+";
  }
  $cmd .= " $gtype:fc#00FF00:\\\"FC          \\\"";
  if ( $item =~ m/io/ ) {
    $cmd .= " GPRINT:fc:AVERAGE:\\\"%6.0lf \\\"";
    $cmd .= " GPRINT:fc:MAX:\\\"%6.0lf \\l\\\"";
  }
  else {
    $cmd .= " GPRINT:fc:AVERAGE:\\\"%6.1lf \\\"";
    $cmd .= " GPRINT:fc:MAX:\\\"%6.1lf \\l\\\"";
  }
  

  # SAS 
  $index_actual = 0;
  $cmd .= " CDEF:sas=sas${index_actual}";
  $index_actual++;
  for (; $index_actual < $i; $index_actual++) { 
    $cmd .= ",sas${index_actual},+";
  }
  $cmd .= " $gtype:sas#4444FF:\\\"SAS         \\\"";
  if ( $item =~ m/io/ ) {
    $cmd .= " GPRINT:sas:AVERAGE:\\\"%6.0lf \\\"";
    $cmd .= " GPRINT:sas:MAX:\\\"%6.0lf \\l\\\"";
  }
  else {
    $cmd .= " GPRINT:sas:AVERAGE:\\\"%6.1lf \\\"";
    $cmd .= " GPRINT:sas:MAX:\\\"%6.1lf \\l\\\"";
  }
  

  # iSCSI
  $index_actual = 0;
  $cmd .= " CDEF:iscsi=iscsi${index_actual}";
  $index_actual++;
  for (; $index_actual < $i; $index_actual++) { 
    $cmd .= ",iscsi${index_actual},+";
  }
  $cmd .= " $gtype:iscsi#FFFF00:\\\"iSCSI       \\\"";
  if ( $item =~ m/io/ ) {
    $cmd .= " GPRINT:iscsi:AVERAGE:\\\"%6.0lf \\\"";
    $cmd .= " GPRINT:iscsi:MAX:\\\"%6.0lf \\l\\\"";
  }
  else {
    $cmd .= " GPRINT:iscsi:AVERAGE:\\\"%6.1lf \\\"";
    $cmd .= " GPRINT:iscsi:MAX:\\\"%6.1lf \\l\\\"";
  }
  
  # IPREP
  $index_actual = 0;
  $cmd .= " CDEF:iprep=iprep${index_actual}";
  $index_actual++;
  for (; $index_actual < $i; $index_actual++) { 
    $cmd .= ",iprep${index_actual},+";
  }
  $cmd .= " $gtype:iprep#FF4444:\\\"IP replicat \\\"";
  if ( $item =~ m/io/ ) {
    $cmd .= " GPRINT:iprep:AVERAGE:\\\"%6.0lf \\\"";
    $cmd .= " GPRINT:iprep:MAX:\\\"%6.0lf \\l\\\"";
  }
  else {
    $cmd .= " GPRINT:iprep:AVERAGE:\\\"%6.1lf \\\"";
    $cmd .= " GPRINT:iprep:MAX:\\\"%6.1lf \\l\\\"";
  }
  

  if ( $type_gr =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }
  
  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  
  if ( $not_execute_rrdtool == 1 ) { return 1;}

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    if ( $ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
    }
    else {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
    }
  }
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");

  return 0;
}

sub draw_volume_cache_hit_all
{
  my $host = shift;
  my $type = shift;
  my $st_type = shift;

  if ( $st_type =~ m/^DS5K$/ ) {
    if ( -f "$wrkdir/$host/DS5K-v2" ) {
      draw_volume_cache_hit ($host,$type,"w_cache_hit",$st_type);
      draw_volume_cache_hit ($host,$type,"r_cache_hit",$st_type);
      draw_volume_cache_hit ($host,$type,"read_pct",$st_type);
      draw_volume_cache_hit ($host,$type,"ssd_r_cache_hit",$st_type);
    }
    else {
      # Old DS5K has only cache_hit
      draw_volume_cache_hit ($host,$type,"cache_hit",$st_type);
      draw_volume_cache_hit ($host,$type,"read_pct",$st_type);
    }
  }
  else {
    draw_volume_cache_hit ($host,$type,"w_cache_hit",$st_type);
    draw_volume_cache_hit ($host,$type,"r_cache_hit",$st_type);
  }

}

sub draw_volume_cache_hit 
{
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;

  my $dfile = "$tmp_dir/$host/$type-$item-d.out";
  my $wfile = "$tmp_dir/$host/$type-$item-w.out";
  my $mfile = "$tmp_dir/$host/$type-$item-m.out";
  my $yfile = "$tmp_dir/$host/$type-$item-y.out";
  my $out_file = "$webdir/$host/cache-$item.html";

  my @dout = "";
  my @wout = "";
  my @mout = "";
  my @yout = "";

  if ( -f $dfile ) {
    open(FHD, "< $dfile") || error ("Can't open $dfile : $! ".__FILE__.":".__LINE__) && return 0;
    @dout = <FHD>;
    close(FHD);
  }
  else {
    error ("$host:$type:$item - no daily file ".__FILE__.":".__LINE__) if ($DEBUG);
    return 0;
  }
  
  if ( -f $wfile ) {
    open(FHD, "< $wfile") || error ("Can't open $wfile : $! ".__FILE__.":".__LINE__) && return 0;
    @wout = <FHD>;
    close(FHD);
  }
  if ( -f $mfile ) {
    open(FHD, "< $mfile") || error ("Can't open $mfile : $! ".__FILE__.":".__LINE__) && return 0;
    @mout = <FHD>;
    close(FHD);
  }
  if ( -f $yfile ) {
    open(FHD, "< $yfile") || error ("Can't open $yfile : $! ".__FILE__.":".__LINE__) && return 0;
    @yout = <FHD>;
    close(FHD);
  }

  #@dout = sort { (split ' ', $a)[2] cmp (split ' ', $b)[2] } @dout;
  #@dout = sort { (split ' ', $a)[3] <=> (split ' ', $b)[3] } @dout;


  my @name = "";
  my @util = "";
  my $indx = 0;

  # goes through all 4 files and create one outpud table with cache_hit
  foreach my $dline (@dout) {
    chomp ($dline);
    if ( $dline =~ m/^OK u:/ || $dline =~ m/^$/ || $dline !~ m/ / ) {
      next;
    }
    $dline =~ s/=====space=====/ /g;
    (my $dlpar, my $dutil) = split (/ +/,$dline);
    if ( $dlpar =~ m/^$/ ) {
      next;
    }
    $dutil =~ s/NaNQ/NA/g;
    $dutil =~ s/NaN/NA/g;
    $dutil =~ s/nan/NA/g;
    $name[$indx] = $dlpar;
    $util[$indx] .= "<td align=\"right\">$dutil</td>";
    $indx++;

  }

  foreach my $wline (@wout) {
    if ( $wline =~ m/^OK u:/ || $wline =~ m/^$/ || $wline !~ m/ / ) {
      next;
    }
    $wline =~ s/=====space=====/ /g;
    (my $wlpar, my $wutil) = split (/ +/,$wline);
    if ( $wlpar =~ m/^$/ ) {
      next;
    }
    $wutil =~ s/NaNQ/NA/g;
    $wutil =~ s/NaN/NA/g;
    $wutil =~ s/nan/NA/g;
    my $found = 0;
    $indx = 0;
    foreach my $line (@name) {
      if ( $line =~ m/^$wlpar$/ ) {
       $util[$indx] .= "<td align=\"right\">$wutil</td>";
       $found = 1;
       last;
      }
      $indx++;
    }
    if ( $found == 0 ) {
       $name[$indx] = $wlpar;
       $util[$indx] .= "<td align=\"right\">NA</td><td align=\"right\">$wutil</td>";
       #print "003 $name[$indx] : $util[$indx]\n";
    }
  }

  foreach my $mline (@mout) {
    if ( $mline =~ m/^OK u:/ || $mline =~ m/^$/ || $mline !~ m/ / ) {
      next;
    }
    $mline =~ s/=====space=====/ /g;
    (my $mlpar, my $mutil) = split (/ +/,$mline);
    if ( $mlpar =~ m/^$/ ) {
      next;
    }
    $mutil =~ s/NaNQ/NA/g;
    $mutil =~ s/NaN/NA/g;
    $mutil =~ s/nan/NA/g;
    my $found = 0;
    $indx = 0;
    foreach my $line (@name) {
      if ( $line =~ m/^$mlpar$/ ) {
       $util[$indx] .= "<td align=\"right\">$mutil</td>";
       $found = 1;
       last;
      }
      $indx++;
    }
    if ( $found == 0 ) {
       $name[$indx] = $mlpar;
       $util[$indx] .= "<td align=\"right\">NA</td><td align=\"right\">NA</td><td align=\"right\">$mutil</td>";
       #print "003 $name[$indx] : $util[$indx]\n";
    }
  }

  foreach my $yline (@yout) {
    if ( $yline =~ m/^OK u:/ || $yline =~ m/^$/ || $yline !~ m/ / ) {
      next;
    }
    $yline =~ s/=====space=====/ /g;
    (my $ylpar, my $yutil) = split (/ +/,$yline);
    if ( $ylpar =~ m/^$/ ) {
      next;
    }
    $yutil =~ s/NaNQ/NA/g;
    $yutil =~ s/NaN/NA/g;
    $yutil =~ s/nan/NA/g;
    my $found = 0;
    $indx = 0;
    foreach my $line (@name) {
      if ( $line =~ m/^$ylpar$/ ) {
       $util[$indx] .= "<td align=\"right\">$yutil</td>";
       $found = 1;
       last;
      }
      $indx++;
    }
    if ( $found == 0 ) {
       $name[$indx] = $ylpar;
       $util[$indx] .= "<td align=\"right\">NA</td><td align=\"right\">NA</td><td align=\"right\">NA</td><td align=\"right\">$yutil</td>";
    }
  }

  open(FHD, "> $out_file") || error ("Can't open $out_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FHD "<center><table class=\"lparsearch tablesorter\"><thead><tr><th class=\"sortable\">Volume</th><th class=\"sortable\">&nbsp;day&nbsp;&nbsp;&nbsp;&nbsp;</th><th class=\"sortable\">&nbsp;week&nbsp;&nbsp;&nbsp;&nbsp;</th><th class=\"sortable\">&nbsp;month&nbsp;&nbsp;&nbsp;&nbsp;</th><th class=\"sortable\">&nbsp;year&nbsp;&nbsp;&nbsp;&nbsp;</th></tr></thead><tbody>\n";
  $indx = 0;
  foreach my $line (@name) {
    print FHD "<tr><td><a href=\"/stor2rrd-cgi/detail.sh?host=$host&type=$type&name=$line&storage=$st_type&none=none\">$line</a></td>$util[$indx]</tr>\n";
    #print  "$line : $util[$indx]\n";
    $indx++;
  }

  print FHD "</tbody></table></center>";
  close (FHD);

  return 0;
}

# it check if rrdtool supports graphv --> then zoom is supported
sub  rrdtool_graphv
{
  my $graph_cmd = "graph";
  my $graphv_file = "$tmp_dir/graphv";

  my $ansx = `$rrdtool`;

  if (index($ansx, 'graphv') != -1) {
    # graphv exists, create a file to pass it to cgi-bin commands
    if ( ! -f $graphv_file ) {
      `touch $graphv_file`;
    }
  }
  else {
    if ( -f $graphv_file ) {
      unlink ($graphv_file);
    }
  }

  return 0;
}

 
# it is iportant to have real data start, as before that are take NaN to keep good average and since then when NaN exist then == 0
# to make summary graphs working
# it is about total graphs, all POOL graphs, CPU, Drives total ...

sub find_real_data_start
{
  my $rrd_file = shift;
  my $time_first = 1;
  my $refresh_time = 86400; # 1 day
  my $data_line = "";

    
  my $rrd_file_first = $rrd_file;
  $rrd_file_first =~ s/rr.$/first/g;

  # find out time stamp of first data update
  # note first data point with data, not first with NaN which returns rrdtool first
  RRDp::cmd qq(first "$rrd_file");
  my $first_tt = RRDp::read;
  chomp($$first_tt); # start of predefined data points in rrdtool  , tehre could be NaN

  # find real start of data
  $time_first = $$first_tt;
  my $unix_act = time();
  if ( -f $rrd_file_first && ((stat("$rrd_file_first"))[9] + $refresh_time) > $unix_act ) {
    # read real last time of the record in rrdtool from the file (refresh every day)
    open(FHF, "< $rrd_file_first") || error ("Can't open $rrd_file_first : $! ".__FILE__.":".__LINE__);
    foreach my $line_frst (<FHF>)  {
      chomp($line_frst);
      if ( isdigit($line_frst) ) {
        $time_first = $line_frst;
        last;
      }
    }
    #print "002 $rrd_file_first $time_first \n";
    close (FHF);
  }
  else {
    my $time_year_before = time() - 31622400; # unix time - 1 year
    #RRDp::cmd qq(fetch "$rrd_file" AVERAGE --end $time_year_before );
    # rrdtool fetch and found the first record is a bit tricky, must be used --end stuff!!!
    RRDp::cmd qq(fetch "$rrd_file" AVERAGE --start $time_year_before );
    # strange, --start must be used!! at least on 1.4.8 RRDTool
    my $data = RRDp::read;
    my $time_first_act = 2000000000; # just place here something hig engouh, higherb than actual unix time in seconds
    foreach $data_line (split(/\n/,$$data)) {
      chomp($data_line);
      (my $time_first_act_tmp, my $item1, my $item2) = split (/ /,$data_line);
      if ( isdigit($item1) || isdigit($item2) ) {
        $time_first_act = $time_first_act_tmp;
        $time_first_act =~ s/://g;
        $time_first_act =~ s/ //g;
        if ( isdigit($time_first_act) ) {
          last;
        }
      }
    }
    if ( isdigit($time_first_act) && $time_first_act > $time_first ) {
      # when is rrdtool DB file older than retention of 300s data then rrdtool first has the right value of the first record
      $time_first = $time_first_act;
    }
    open(FHF, "> $rrd_file_first") || error ("Can't open $rrd_file_first : $! ".__FILE__.":".__LINE__);
    print FHF "$time_first";
    close (FHF);
  }
  
  $time_first =~ s/://g;
  if ( isdigit($time_first) == 0 ) {
    #error ("Pool first time has not been found in : $rrd_file_first : $time_first : $data_line ".__FILE__.":".__LINE__);
    return 1; # something is wrong, "1" causes ignoring followed rrdtool construction
  }
  return $time_first;
}


# it finds out or create a file with first data stapm in all rank files of given pool
# it is necessary to know it as since that time is used 0 instead on NaN in rrdtool cmd
sub find_real_data_start_pool
{
  my $rank_dir = shift;
  my $pool_id = shift;
  if ( isdigit($pool_id) == 1 ) {
    $pool_id = $pool_id + 1 - 1; # integer conversion
  }
  my $rrd_pool_first = "$rank_dir/P$pool_id.first_pool";
  my $refresh_time = 86400; # 1 day
  my $time_first_def = 2000000000; # just place here something hig engouh, higherb than actual unix time in seconds
  my $time_first = $time_first_def;

  my $unix_act = time();
  # daily refresh pool first time
  if ( -f $rrd_pool_first && ((stat("$rrd_pool_first"))[9] + $refresh_time) > $unix_act ) {
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
  else {
    foreach my $file_rank (<$rank_dir/*-P$pool_id\.first>) {
      # use *-P[0-9][0-9]*\.first to avoid some bogus 000P.first without the pool ID
      open(FHF, "< $file_rank") || error ("Can't open $file_rank : $! ".__FILE__.":".__LINE__);
      foreach my $line_frst (<FHF>)  {
        chomp($line_frst);
        if ( isdigit($line_frst) && $line_frst < $time_first ) {
          $time_first = $line_frst;
          last;
        }
      }
      close (FHF);
    }
    if ( $time_first  < $time_first_def ) {
      # time has been found, save it to do not have to search it every run as it does not get changed often
      open(FHF, "> $rrd_pool_first") || error ("Can't open $rrd_pool_first : $! ".__FILE__.":".__LINE__);
      print FHF "$time_first";
      close (FHF);
    }
  }
  if ( $time_first  < $time_first_def ) {
    return $time_first;
  }
  else {
    #error ("Pool first time has not been found: $rank_dir/*-P$pool_id*\.first : $pool_id ".__FILE__.":".__LINE__);
    return 1; # something is wrong, "1" causes ignoring followed rrdtool construction
  }
}


# it finds the first valid data point in all rank files first files
# it is necessary to know it as since that time is used 0 instead on NaN in rrdtool cmd
# work for RANK and DRIVE and POOLs (capacity)
sub find_real_data_start_all 
{
  my $rank_dir = shift;
  my $time_first_def = 2000000000; # just place here something hig engouh, higherb than actual unix time in seconds
  my $time_first = $time_first_def;
  my $found_file = 0;

  #create first files
  foreach my $rrd_rank (<$rank_dir/*-P*\.rrd>) {
    find_real_data_start($rrd_rank);
  }


  foreach my $file_first (<$rank_dir/*\.first>) {
    # read real last time of the record in rrdtool from the file (refresh every day)
    open(FHF, "< $file_first") || error ("Can't open $file_first : $! ".__FILE__.":".__LINE__);
    foreach my $line_frst (<FHF>)  {
      chomp($line_frst);
      if ( isdigit($line_frst) ) {
        if ( $line_frst < $time_first) {
          $time_first = $line_frst;
        }
        last;
      }
    }
    close (FHF);
    $found_file = 1;
  }
  #if ( $found_file == 0 ) {
  #  error ("Pool first time files have not been found: $rank_dir/*\.first (it could happen fist run after the upgrade) ".__FILE__.":".__LINE__);
  #}

  if ( $time_first  < $time_first_def ) {
    return $time_first;
  }
  else {
    #error ("Pool first time has not been found in: $rank_dir  (it could happen fist run after the upgrade) ".__FILE__.":".__LINE__);
    return 1; # something is wrong, "1" causes ignoring followed rrdtool construction
  }
}


sub volumes_in_top_all 
{
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;

  volumes_in_top    ("d",$host,$type,$st_type,$item);
  volumes_in_top    ("w",$host,$type,$st_type,$item);
  volumes_in_top    ("m",$host,$type,$st_type,$item);
  volumes_in_top    ("y",$host,$type,$st_type,$item);
  return 0;
}

sub volumes_in_top  {
  my $type_gr  = shift;
  my $host     = shift;
  my $type     = shift;
  my $st_type  = shift;
  my $item = shift;
  my $name = "$tmp_dir/$host/$type-$item-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my @low_volumes = "";
  my $indx_low = 0;
  my $prev = -1;
  my $step_new = $STEP;
  my $once = 0;
  my @item_list = ("read","write","read_io","write_io","resp_t_r","resp_t_w","r_cache_hit","w_cache_hit");
  my $no_of_items = 8; # number items in @item_list
  if ( $st_type =~ m/DS5K/ && -f "$wrkdir/$host/DS5K-v1" ) {
    @item_list = ("io_rate","data_rate","cache_hit");
    $no_of_items = 3; # number items in @item_list
  }
  if ( $st_type =~ m/DS5K/ && -f "$wrkdir/$host/DS5K-v2" ) {
    @item_list = ("io_rate","data_rate","resp_t","r_cache_hit","w_cache_hit","ssd_r_cache_hit");
    $no_of_items = 6; # number items in @item_list
  }
  if ( $st_type =~ m/XIV/ ) {
    @item_list = ("read","write","read_io","write_io","resp_t_r","resp_t_w");
    $no_of_items = 6; # number items in @item_list
  }

  my $act_utime = time();
  my $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.cmd";

  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "y" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
        #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "m" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "w" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

  print "creating top   : $host:$type:$item:$type_gr\n" if $DEBUG ;


  my $req_time = "";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";

  my $color_indx = 0; # reset colour index

  my $end_time = "now";
  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
    $end_time = "now-1d";
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
    $end_time = "now-1w";
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
    $end_time = "now-1m";
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 

  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end $end_time";
  $cmd .= " --imgformat PNG";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --units-exponent=1.00";
  my $gtype="LINE1";

  my $lpar_list = "";
  my $lpar_list_tmp = "";

  # read volume cfg files with grouped volumes
  if ( ! -f "$wrkdir/$host/$type/volumes.cfg" ) {
    error("$host: No volumes cfg files has been found : $wrkdir/$host/$type/volumes.cfg ".__FILE__.":".__LINE__);
    return 1;
  }
  open(FHR, "< $wrkdir/$host/$type/volumes.cfg") || error ("$host: file does not exists : $wrkdir/$host/$type/volumes.cfg ".__FILE__.":".__LINE__) && return 0;
  my @files = <FHR>;
  close (FHR);

  my $vols = "";
  my $lpar_space = "";
  my $once_report = 0;
  
  foreach my $volg (@files) {
    chomp($volg);
    $vols = $volg;
    $volg =~ s/ : .*//;
    $vols =~ s/^.* : //;

    my @vol_array = split(';', $vols);

    $prev = -1;

    my $one_volume_nick = 2;  # volume nick has 1 physical volume == 1, or more < 1;
    foreach my $lpar (@vol_array) {
      $lpar =~ s/ //; # it must be there!!!
      if ( $lpar eq '' ) {
        next;
      }
      $one_volume_nick--;
    }

    #
    # follow each volume (there migh be more volumes under 1 volume nick!!!
    # first run just select files ... must be for mutilevel resp_t a cache_hit to count how many items are summed
    my @vol_array_work = "";
    my $vol_array_work_indx = 0;
    foreach my $lpar (@vol_array) {

      $lpar =~ s/^0x//;
      $lpar =~ s/ //; # it must be there!!!
      my $file = "$wrkdir/$host/$type/$lpar.rrd"; # always test .rrd

      if ( $lpar eq '' ) {
        next;
      }

      if ( $st_type =~ m/XIV/ || $st_type =~ m/DS5K/ ) {
        # XIV volumes contain pool_id in their names: 00273763-P102932.rrd
        foreach my $file_xiv (<$wrkdir/$host/$type/$lpar-P*\.rrd>) {
          $file = $file_xiv;
          last;
        }
      }


      if ( ! -f $file ) {
        if ( $once_report == 0 ) {
          # It might appear after the upgrade to 1.00 as *rrc files are not in place yet
          error("volumes stats: $file does not exist, continuing ".__FILE__.":".__LINE__);
          $once_report++;
        }
        next;
      }

      # go every each volume for particular group

      # avoid old lpars which do not exist in the period
      my $rrd_upd_time = (stat("$file"))[9];
      if ( $rrd_upd_time < $req_time ) {
        next;
      }
      $vol_array_work[$vol_array_work_indx] = $file;
      $vol_array_work_indx++;
    }
  
    # lets make $cmd for multilevels ones
    foreach my $file (@vol_array_work) {
      if ( $file eq '' ) {
        next;
      }

      foreach my $item_act (@item_list) {

        my $file_act = $file;
        if ( $st_type =~ m/^DS8K$/ && ($item_act =~ m/^read_io$/ || $item_act =~ m/^write_io$/ || $item_act =~ m/^resp_t_r$/ || $item_act =~ m/^resp_t_w$/ )) {
            $file_act =~ s/\.rrd$/\.rrc/;
        }
        if ( $item_act =~ m/^w_cache_hit$/ || $item_act =~ m/^r_cache_hit$/ ) {
            if ( $st_type =~ m/XIV/ ) {
              next; # XIV do not support cache stats
            }
            if ( $st_type !~ m/DS5K/ ) {
              $file_act =~ s/\.rrd$/\.rrc/;
            }
        }

        # bulid RRDTool cmd
        $cmd .= " DEF:$item_act${i}=\\\"$file_act\\\":$item_act:AVERAGE";

        if ( $prev == -1 ) {
          $cmd .= " CDEF:$item_act${i}_sum=$item_act${i}"; 
        }
        else {
            my $last_vol_item = $i - $no_of_items; 
            $cmd .= " CDEF:$item_act${i}_sum=$item_act${last_vol_item}_sum,$item_act${i},+"; 
        }
        $i++;
      }
      $prev++;
    }

    if ( $prev == -1 ) {
      next; # nothing found for that volume
    }
    my $index_last = $i - $no_of_items;  # 8 items are printed
    my $volg_space = $volg;
    $volg_space =~ s/ /=====space=====/g;

    foreach my $item_act (@item_list) {
      my $val = 1;
      if ( $item_act =~ m/^read$/ || $item_act =~ m/^write$/ || $item_act =~ m/^data_rate/ ) {
        $val = 1024;
      }
      if ( $item_act =~ m/resp_t/ || $item_act =~ m/cache_hit/ ) {
        # multivolumes
        # resp_t and cache_hit must be averaged not summed for multivolumes ...
        $val = $vol_array_work_indx;
      }
      if ( $st_type =~ m/^DS8K$/ && ($item_act =~ m/^read$/ || $item_act =~ m/^write$/ )) {
        # data is stored in wrong RRDTool type (GAUGE instead of ABSOLUTE)
        # this do data conversion
        $val = $step_new; # do not use $val=1024 for them!!
      }
      $cmd .= " CDEF:$item_act${index_last}_sum_val=$item_act${index_last}_sum,$val,/"; # convert into MB if necessary, normaly is there 1

      if ( $item_act =~ m/resp/ || $item_act =~ m/^read$/ || $item_act =~ m/^write$/ ) {
        $cmd .= " PRINT:$item_act${index_last}_sum_val:AVERAGE:\\\"====start ==== $volg_space $item_act %6.1lf\\\"";
      }
      else {
        $cmd .= " PRINT:$item_act${index_last}_sum_val:AVERAGE:\\\"====start ==== $volg_space $item_act %6.0lf\\\"";
      }
      $index_last++; # go back to show all items per a volume
    }
  }
  $cmd =~ s/\\"/"/g;
  #$cmd =~ s/ /\n/g; # for debug purposes

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  
  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  #my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #if ( $ret =~ "ERROR" ) {
  #  if ( $ret =~ "ERROR: malloc fetch data area" ) {
  #    error ("$host:$type:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
  #  }
  #  else {
  #    error ("$host:$type:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
  #  }
  #}
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");
  #print "$ret\n";

  return 0;
}

# set colors for volumes in $wrkdir/$host/$type/volumes.col
sub set_colors_initial
{
  my $host = shift;
  my $type = shift;

  my $color_file_change = 0;
  my $color_indx = 0;

  # open a file with stored colours
  my @color_save = "";
  if ( -f "$wrkdir/$host/$type/volumes.col" ) {
    open(FHC, "< $wrkdir/$host/$type/volumes.col") || error ("file does not exists : $wrkdir/$host/$type/volumes.col ".__FILE__.":".__LINE__) && return 0;
    @color_save = <FHC>;
    close (FHC);
  }

  # read volume cfg files with grouped volumes
  if ( ! -f "$wrkdir/$host/$type/volumes.cfg" ) {
    error("$host: No volumes cfg files has been found : $wrkdir/$host/$type/volumes.cfg ".__FILE__.":".__LINE__);
    return 1;
  }
  open(FHR, "< $wrkdir/$host/$type/volumes.cfg") || error ("$host: file does not exists : $wrkdir/$host/$type/volumes.cfg ".__FILE__.":".__LINE__) && return 0;
  my @volumes = <FHR>;
  close (FHR);

  foreach my $volume (@volumes) {
    chomp($volume);
    if ( ! defined ($volume) || $volume eq '' || $volume !~ m/ : / ) {
      next;
    }
    $volume =~ s/ : .*//;

    #print "001 $color_indx : $volume\n";
    # Found out stored color index to keep same color for the volume across all graphs
    my $color_indx_found = -1;
    my $save_index = 0;
    foreach my $line_col (@color_save) {
      chomp ($line_col);
      if ( $line_col eq '' ) {
        next;
      }
      (my $color_indx_found_act, my $volume_save) = split (/:/,$line_col);
      if ( $volume =~ m/^$volume_save$/ ) {
        $color_indx_found = $color_indx_found_act;
        $color_indx = $color_indx_found;
        last;
      }
      $save_index++;
    }
    if ( $color_indx_found == -1 ) {
      $color_file_change = 1;
      $color_save[$save_index] = $color_indx.":".$volume;
    }
    $color_indx++;
    if ($color_indx > $color_max ) {
      $color_indx = 0;
    }
  }


  # write colors into a file
  if ( $color_file_change == 1 ) {
    open(FHC, "> $wrkdir/$host/$type/volumes.col") || error ("file does not exists : $wrkdir/$host/$type/volumes.col ".__FILE__.":".__LINE__) && return 0;
    foreach my $line_cs (@color_save) {
      chomp ($line_cs);# it must be there, somehow appear there \n ...
      if ( $line_cs eq '' ) {
        next;
      }
      if ( $line_cs =~ m/:/ ) {
        print FHC "$line_cs\n";
      }
    }
    close (FHC);
  }

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

sub create_dir_structure 
{
  my $webdir = shift;
  my $wrkdir = shift;
  my $host = shift;
  my $st_type = shift;
  my $tmp_dir = shift;

    # be carefull, all those directories are also created in bin/data_load.pl
    if (! -d "$webdir/$host" ) {
      print "mkdir          : $webdir/$host\n" if $DEBUG ;
      mkdir("$webdir/$host", 0755) || die   "$act_time: Cannot mkdir $webdir/$host: $!";
      LoadDataModule::touch();
    } 
    if (! -d "$webdir/$host/VOLUME" ) {
      print "mkdir          : $webdir/$host/VOLUME\n" if $DEBUG ;
      mkdir("$webdir/$host/VOLUME", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/VOLUME: $!";
      LoadDataModule::touch();
    } 
    if (! -d "$wrkdir/$host" ) {
      print "mkdir          : $wrkdir/$host\n" if $DEBUG ;
      mkdir("$wrkdir/$host", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host: $!";
      LoadDataModule::touch();
    } 
    if (! -d "$wrkdir/$host/VOLUME" ) {
      print "mkdir          : $wrkdir/$host/VOLUME\n" if $DEBUG ;
      mkdir("$wrkdir/$host/VOLUME", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/VOLUME: $!";
      LoadDataModule::touch();
    } 
    if (! -d "$webdir/$host" ) {
      print "mkdir          : $host $webdir/$host\n" if $DEBUG ;
      mkdir("$webdir/$host", 0755) || die   "$act_time: Cannot mkdir $webdir/$host: $!";
    }
    if (! -d "$wrkdir/$host/POOL" ) {
      print "mkdir          : $wrkdir/$host/POOL\n" if $DEBUG ;
      mkdir("$wrkdir/$host/POOL", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/POOL: $!";
      LoadDataModule::touch();
    } 
    if (! -d "$webdir/$host/POOL" ) {
      print "mkdir          : $webdir/$host/POOL\n" if $DEBUG ;
      mkdir("$webdir/$host/POOL", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/POOL: $!";
      LoadDataModule::touch();
    } 
  
    if ( $st_type =~ m/^SWIZ$/ || $st_type =~ m/^DS8K$/ ) {
      if (! -d "$webdir/$host/RANK" ) {
        print "mkdir          : $webdir/$host/RANK\n" if $DEBUG ;
        mkdir("$webdir/$host/RANK", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/RANK: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$webdir/$host/PORT" ) {
        print "mkdir          : $webdir/$host/PORT\n" if $DEBUG ;
        mkdir("$webdir/$host/PORT", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/PORT: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$webdir/$host/HOST" ) {
        print "mkdir          : $webdir/$host/HOST\n" if $DEBUG ;
        mkdir("$webdir/$host/HOST", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/HOST: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$wrkdir/$host/RANK" ) {
        print "mkdir          : $wrkdir/$host/RANK\n" if $DEBUG ;
        mkdir("$wrkdir/$host/RANK", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/RANK: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$wrkdir/$host/PORT" ) {
        print "mkdir          : $wrkdir/$host/PORT\n" if $DEBUG ;
        mkdir("$wrkdir/$host/PORT", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/PORT: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$wrkdir/$host/HOST" ) {
        print "mkdir          : $wrkdir/$host/HOST\n" if $DEBUG ;
        mkdir("$wrkdir/$host/HOST", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/HOST: $!";
        LoadDataModule::touch();
      } 
    }

    if ( $st_type =~ m/^DS5K$/ ) {
      if (! -d "$wrkdir/$host/HOST" ) {
        print "mkdir          : $wrkdir/$host/HOST\n" if $DEBUG ;
        mkdir("$wrkdir/$host/HOST", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/HOST: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$webdir/$host/HOST" ) {
        print "mkdir          : $webdir/$host/HOST\n" if $DEBUG ;
        mkdir("$webdir/$host/HOST", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/HOST: $!";
        LoadDataModule::touch();
      } 
    }

    if ( $st_type =~ m/^SWIZ$/ ) {
      if (! -d "$wrkdir/$host/DRIVE" ) {
        print "mkdir          : $wrkdir/$host/DRIVE\n" if $DEBUG ;
        mkdir("$wrkdir/$host/DRIVE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/DRIVE: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$wrkdir/$host/CPU-CORE" ) {
        print "mkdir          : $wrkdir/$host/CPU-CORE\n" if $DEBUG ;
        mkdir("$wrkdir/$host/CPU-CORE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/CPU-CORE: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$wrkdir/$host/CPU-NODE" ) {
        print "mkdir          : $wrkdir/$host/CPU-NODE\n" if $DEBUG ;
        mkdir("$wrkdir/$host/CPU-NODE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/CPU-NODE: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$wrkdir/$host/NODE-CACHE" ) {
        print "mkdir          : $wrkdir/$host/NODE-CACHE\n" if $DEBUG ;
        mkdir("$wrkdir/$host/NODE-CACHE", 0755) || die   "$act_time: Cannot mkdir $wrkdir/$host/NODE-CACHE: $!";
        LoadDataModule::touch();
      } 
      if (! -l "$wrkdir/$host/MDISK" ) {
        print "ln -s          : $wrkdir/$host/RANK $wrkdir/$host/MDISK\n" if $DEBUG ;
        symlink("$wrkdir/$host/RANK","$wrkdir/$host/MDISK") || die   "$act_time: Cannot ln -s $wrkdir/$host/MDISK: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$webdir/$host/DRIVE" ) {
        print "mkdir          : $webdir/$host/DRIVE\n" if $DEBUG ;
        mkdir("$webdir/$host/DRIVE", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/DRIVE: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$webdir/$host/CPU-CORE" ) {
        print "mkdir          : $webdir/$host/CPU-CORE\n" if $DEBUG ;
        mkdir("$webdir/$host/CPU-CORE", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/CPU-CORE: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$webdir/$host/CPU-NODE" ) {
        print "mkdir          : $webdir/$host/CPU-NODE\n" if $DEBUG ;
        mkdir("$webdir/$host/CPU-NODE", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/CPU-NODE: $!";
        LoadDataModule::touch();
      } 
      if (! -d "$webdir/$host/NODE-CACHE" ) {
        print "mkdir          : $webdir/$host/NODE-CACHE\n" if $DEBUG ;
        mkdir("$webdir/$host/NODE-CACHE", 0755) || die   "$act_time: Cannot mkdir $webdir/$host/NODE-CACHE: $!";
        LoadDataModule::touch();
      } 
      if (! -l "$webdir/$host/MDISK" ) {
        print "ln -s          : $webdir/$host/RANK $webdir/$host/MDISK\n" if $DEBUG ;
        symlink("$webdir/$host/RANK","$webdir/$host/MDISK") || die   "$act_time: Cannot ln -s $webdir/$host/MDISK: $!";
        LoadDataModule::touch();
      } 
    }
    if (! -d "$tmp_dir/$host" ) {
      print "mkdir          : $tmp_dir/$host\n" if $DEBUG ;
      mkdir("$tmp_dir/$host", 0755) || die   "$act_time: Cannot mkdir $tmp_dir/$host: $!";
      LoadDataModule::touch();
    } 
    # be carefull, all those directories are also created in bin/data_load.pl
   
  return 0;
}

sub draw_all_pool_controler {
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;

  draw_graph_pool_controler ("day","d","MINUTE:60:HOUR:2:HOUR:4:0:%H",$host,$type,$item,$st_type);
  draw_graph_pool_controler ("week","w","HOUR:8:DAY:1:DAY:1:86400:%a",$host,$type,$item,$st_type);
  draw_graph_pool_controler ("4 weeks","m","DAY:1:DAY:2:DAY:2:0:%d",$host,$type,$item,$st_type);
  draw_graph_pool_controler ("year","y","MONTH:1:MONTH:1:MONTH:1:0:%b",$host,$type,$item,$st_type);
  return 0;
}

sub draw_graph_pool_controler {
  my $text     = shift;
  my $type_gr  = shift;
  my $xgrid    = shift;
  my $host     = shift;
  my $type     = shift;
  my $item     = shift;
  my $st_type  = shift;
  my $name = "$tmp_dir/$host-$type-$item-agg-$type_gr";
  my $t="COMMENT: ";
  my $t2="COMMENT:\\n";
  my $last ="COMMENT: ";
  my $rrd_time = "";
  my $step_new=$STEP;
  my $once = 0;
  my $last_time = "na";
  my $color_indx = 0; # reset colour index
  my $item_org = $item;

  my $cntl = 0; # controler A
  if ( $item =~ m/^B/ ) {
    $cntl = 1; # controler B
  }


  my $tmp_file="$tmp_dir/$host/$type-$item-$type_gr.cmd";
  my $act_utime = time();

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "y" && -f "$tmp_file" ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $YEAR_REFRESH ) {
        #print "creating graph : $host:$:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "m" && -f "$tmp_file"  ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $MONTH_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

    # do not update charts if there is not new data in RRD DB
    if ( $type_gr =~ "w" && -f "$tmp_file"  ) {
      my $png_time = (stat("$tmp_file"))[9];
      if ( ($act_utime - $png_time) < $WEEK_REFRESH ) {
        #print "creating graph : $host:$type:$lpar:$type_gr:$type no update\n" if $DEBUG ;
	if ( $upgrade == 0 ) { return 0;}
      }
    }

  print "creating graph : $host:$type:$item:$type_gr\n" if $DEBUG ;

  my $req_time = "";
  my $header = "$type aggregated $item: last $text";
  my $i = 0;
  my $lpar = "";
  my $cmd = "";
  my $j = 0;


  if ( "$type_gr" =~ "d" ) {
    $req_time = $act_utime - 86400;
  }
  if ( "$type_gr" =~ "w" ) {
    $req_time = $act_utime - 604800;
  }
  if ( "$type_gr" =~ "m" ) {
    $req_time = $act_utime - 2764800;
  }
  if ( "$type_gr" =~ "y" ) {
    $req_time = $act_utime - 31536000;
  }
  if ( ! -f "$tmp_file" ) {
    LoadDataModule::touch();
  } 


  $cmd .= "graph \\\"$name.png\\\"";
  $cmd .= " --title \\\"$header\\\"";
  $cmd .= " --start now-1$type_gr";
  $cmd .= " --end now-1$type_gr+1$type_gr";
  $cmd .= " --imgformat PNG";
  $cmd .= " $disable_rrdtool_tag";
  $cmd .= " --slope-mode";
  $cmd .= " --width=400";
  $cmd .= " --height=150";
  $cmd .= " --step=$step_new";
  $cmd .= " --lower-limit=0.00";
  $cmd .= " --color=BACK#$pic_col";
  $cmd .= " --color=SHADEA#$pic_col";
  $cmd .= " --color=SHADEB#$pic_col";
  $cmd .= " --color=CANVAS#$pic_col";
  $cmd .= " --alt-autoscale-max";
  $cmd .= " --interlaced";
  $cmd .= " --upper-limit=0.1";
  $cmd .= " $font_def_normal";
  $cmd .= " $font_tit_normal";

  my $value_short = "";
  my $value_long = "";
  my $val = 1;
  $item =~ s/_b$//; # cut back-end info for DS8k, just cmd file will contain the backend info
  my $item_real = $item;

  # do not use switch statement
  if ( $item =~ m/^data_cntl$/ )    { $item_real = "data_rate"; $value_short= "MB"; $value_long = "MBytes"; $val = 1024;}
  if ( $item =~ m/^io_cntl$/ )      { $item_real = "io_rate"; $value_short= "IOPS"; $value_long = "IO per second"; }
  if ( $item =~ m/^resp_t_cntl$/ )  { $item_real = "resp_t"; $value_short= "ms"; $value_long = "mili seconds"; $val=1;}

  $cmd .= " --vertical-label=\\\"$item in $value_long\\\"";

  $cmd .= " --units-exponent=1.00";
  $cmd .= " --x-grid=$xgrid";
  $cmd .= " --alt-y-grid";

  # add spaces to lpar name (for formating graph legend)
  my $legend = sprintf ("%-20s","$item [$value_short]"); # -20s is OK here, here is fixed length of items!!

  my $legend_heading = "$item $delimiter [$value_short] $delimiter Avg $delimiter Max ";
  $cmd .= " COMMENT:\\\"$legend         Avg       Max\\l\\\"";


  my $gtype="AREA";
  if ( $item =~ m/resp_t/ ) {
    $gtype="LINE1";
  }

  my $lpar_list = "";
  my $pool_found = 0;
  my $pool_id_tmp = "";
  my $lpar_list_tmp = "";

  my $rank_vol="RANK";
  if ( $st_type =~ m/XIV/ || $st_type =~ m/DS5K/ ) {
    $rank_vol= "VOLUME"; # XIV uses pools
  }
  # DS8K front-end stats are created in draw_all

  my $dir= "$wrkdir/$host/$rank_vol";
  chdir $dir;

  my @rank_list = "";
  my $rank_list_indx = 0;

  # check all ranks and then sort them per pool id
  foreach my $line (<*-P[0-9]*\.rrd>) {
    chomp($line);
    if ( $line !~ m/\.rrd$/ ) {
      next; # it does not end bu .rrd suffix, "$ cannt be use in foreach <>
    }

    # avoid old lpars which do not exist in the period
    my $rrd_upd_time = (stat("$line"))[9];
    if ( $rrd_upd_time < $req_time ) {
      next;
    }

    $rank_list[$rank_list_indx] = $line;
    $rank_list_indx++;
  }

  if ($rank_list_indx == 0) {
    # no new data found, skipping ...
    print "creating graph : $host:$type:$item_org:$type_gr no new data found, skipping ...\n" if $DEBUG ;
    return 0;
  }

  @rank_list = sort { (split '-', $a)[1] cmp (split '-', $b)[1] } @rank_list;

  my $pool_id_old = -1;
 
  my $print_now = 0;
  my $index_last = 0;
  my $rrd_file_last = "";
  my $index_actual = 0;
  my $pool_name_space = "NA";
  my $pool_id = 0;
  my $pool_name_actual = "NA";
  my $itemm = "";
  my $no_of_ranks = 0;
  my $print_now_pool_id = 0;


  # go through all ranks sorted per pool id, once a pool id is changed then is printed the old one
  foreach my $line  (@rank_list) {
    chomp($line);
    $pool_id = $line;
    $pool_id =~ s/^.*-P//;
    $pool_id =~ s/\.rrd$//;


    my $ret = ishexa($pool_id);
    if ( $ret == 0 ) {
      next;
    }

    if ( ishexa ($pool_id_old) && $pool_id_old =~ m/^-1$/ ) {
      # could be already haxa here
      $pool_id_old = $pool_id;
    }
    else {
      if ($pool_id_old !~ m/^$pool_id$/ ) {
        $print_now = 1;
        $print_now_pool_id = $pool_id_old;
        $pool_name_actual = $pool_name_space;
        $pool_id_old = $pool_id;
      }
    }


    # get pool name, be aware this is a new pool name
    #print "002 $line\n";
    my $pool_name = "NA";
    $pool_name = get_pool_name($pool_id);

    my $rrd_file = "$dir/$line";
    $rrd_file_last = "$dir/$line"; 
    if ( "$type_gr" =~ "d" ) {
      # find out time stamp of last data update
      # take just one volume to keep it simple
      RRDp::cmd qq(last "$rrd_file");
      my $last_tt = RRDp::read;
      chomp ($$last_tt);
      $last_time =localtime($$last_tt);
      $last_time =~ s/:/\\:/g;
    }

    my $time_first = find_real_data_start_pool("$dir",$pool_id);
 
    $itemm = $item."m";
    $itemm =~ s/\./Z/g; # dots in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/ /X/g;  # space in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/\#/Y/g; # hash in rrdtool variable names causing problems for rrdtool parser
    $itemm =~ s/:/R/g;  # hash in rrdtool variable names causing problems for rrdtool parser

    $cmd .= " DEF:$item${i}_u_nan=\\\"$dir/$line\\\":$item_real:AVERAGE";
    $cmd .= " DEF:$item${i}_cntl_nan=\\\"$dir/$line\\\":controller:AVERAGE";
    $cmd .= " CDEF:$item${i}_u=$item${i}_u_nan,UN,0,$item${i}_u_nan,IF";
    $cmd .= " CDEF:$item${i}_cntl=$item${i}_cntl_nan,UN,2,$item${i}_cntl_nan,IF";
    $cmd .= " CDEF:$item${i}_val=$item${i}_u,$val,/";
    $cmd .= " CDEF:$item${i}_a=$item${i}_cntl,0,EQ,$item${i}_val,0,IF";
    $cmd .= " CDEF:$item${i}_b=$item${i}_cntl,1,EQ,$item${i}_val,0,IF";
    $cmd .= " CDEF:$itemm${i}_a=TIME,$time_first,LT,UNKN,$item${i}_a,IF";
    $cmd .= " CDEF:$itemm${i}_b=TIME,$time_first,LT,UNKN,$item${i}_b,IF";
    # UNKN must be there otherwise: ERROR: RPN stack underflow

    if ( $i > 0 ) {
      my $j = $i;
      $j--;
      $cmd .= " CDEF:cntlA${i}=cntlA${j},$itemm${i}_a,+";
      $cmd .= " CDEF:cntlB${i}=cntlB${j},$itemm${i}_b,+";
    }
    else {
      # first run
      $cmd .= " CDEF:cntlA${i}=$itemm${i}_a,0,+";
      $cmd .= " CDEF:cntlB${i}=$itemm${i}_b,0,+";
    }

    $no_of_ranks++;
    $i++;
  }
  $i--;

  if ( $item =~ m/resp_t/ ) {
     # response time is not summary, must be average of all time (devide number of ranks)
     # --PH: resp time is a bit complicated, not supported for now
     $cmd .= ",$no_of_ranks,/";
  }

  # print Controller A
  my $rrd_file_conv = " "; # switch off clickable links in the POOL Controller legend, there is no reason for them
  $pool_name_space = sprintf ("%-20s","Controller A"); # -20s is OK here, here is fixed length of items!!
  $cmd .= " $gtype:cntlA${i}$color[$color_indx]:\\\"$pool_name_space\\\"";
  if ( $item =~ m/resp_t/ )    { 
    $cmd .= " PRINT:cntlA${i}:AVERAGE:\\\"%7.1lf $delimiter $pool_name_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd .= " PRINT:cntlA${i}:MAX:\\\" %7.1lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";

    $cmd .= " GPRINT:cntlA${i}:AVERAGE:\\\"%7.1lf \\\"";
    $cmd .= " GPRINT:cntlA${i}:MAX:\\\"%7.1lf \\l\\\"";
  }
  else {
    $cmd .= " PRINT:cntlA${i}:AVERAGE:\\\"%7.0lf $delimiter $pool_name_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd .= " PRINT:cntlA${i}:MAX:\\\" %7.0lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";

    $cmd .= " GPRINT:cntlA${i}:AVERAGE:\\\"%7.0lf \\\"";
    $cmd .= " GPRINT:cntlA${i}:MAX:\\\"%7.0lf \\l\\\"";
  }

  # print Controller B
  $pool_name_space = sprintf ("%-20s","Controller B"); # -20s is OK here, here is fixed length of items!!
  $color_indx++;
  $gtype="STACK";
  $cmd .= " $gtype:cntlB${i}$color[$color_indx]:\\\"$pool_name_space\\\"";
  if ( $item =~ m/resp_t/ )    { 
    $cmd .= " PRINT:cntlB${i}:AVERAGE:\\\"%7.1lf $delimiter $pool_name_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd .= " PRINT:cntlB${i}:MAX:\\\" %7.1lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";

    $cmd .= " GPRINT:cntlB${i}:AVERAGE:\\\"%7.1lf \\\"";
    $cmd .= " GPRINT:cntlB${i}:MAX:\\\"%7.1lf \\l\\\"";
  }
  else {
    $cmd .= " PRINT:cntlB${i}:AVERAGE:\\\"%7.0lf $delimiter $pool_name_space $delimiter $legend_heading $delimiter $color[$color_indx]\\\"";
    $cmd .= " PRINT:cntlB${i}:MAX:\\\" %7.0lf $delimiter $rrd_file_conv $delimiter $st_type\\\"";

    $cmd .= " GPRINT:cntlB${i}:AVERAGE:\\\"%7.0lf \\\"";
    $cmd .= " GPRINT:cntlB${i}:MAX:\\\"%7.0lf \\l\\\"";
  }


  if ( $type_gr =~ m/d/ ) {
    # last update timestamp
    $cmd .= " COMMENT:\\\"Updated\\\: $last_time\\\"";
  }

  $cmd .= " HRULE:0#000000";
  # $cmd .= " VRULE:0#000000";  --> it is causing sigsegv on linuxeS
  $cmd =~ s/\\"/"/g;

  my $FH;
  open(FH, "> $tmp_file") || error ("Can't open $tmp_file : $! ".__FILE__.":".__LINE__) && return 0;
  print FH "$cmd\n";
  close (FH);
  #$cmd =~ s/ /\n/g;
  #print  "00 $cmd\n";

  
  if ( $not_execute_rrdtool == 1 ) { return 1;}

  # execute rrdtool, it is not possible to use RRDp Perl due to the syntax issues therefore use not nice direct rrdtool way
  my $ret  = `$rrdtool - < $tmp_file 2>&1`;
  #my $ret  = `echo  "$cmd" | $rrdtool - 2>&1`;
  if ( $ret =~ "ERROR" ) {
    if ( $ret =~ "ERROR: malloc fetch data area" ) {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : ERROR: malloc fetch data area ".__FILE__.":".__LINE__);
    }
    else {
      error ("$host:$type:$item:$type_gr: Multi graph rrdtool error : $ret ".__FILE__.":".__LINE__);
    }
  }
  # Do not remove it!! It is used for detail pop-ups!!
  #unlink ("$tmp_file");

  return 0;
}

sub print_storage_sys 
{
  my $wrkdir = shift;
  my $host = shift;

  # print storage sys info, firmwares etc
  my $file = "$wrkdir/$host/config_sys_storage.txt";

  if ( ! -f $file ) {
    return 0;
  }
  open(FHCFG, "< $file") || error ("Can't open $file : $! ".__FILE__.":".__LINE__) && return 0;
  my @lines = <FHCFG>;
  close(FHCFG);

  foreach my $line (@lines) {
    print "Storage sys inf: $host:$line";
  }
  return 0;
}

