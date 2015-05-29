package LoadDataModule;  #
use strict;
use Date::Parse;
use RRDp;
use File::Copy;
use File::Compare;
use Xorux_lib;



my $rrdtool = $ENV{RRDTOOL};

# standard data retentions 
# note this is set up once more in load_retentions
my $five_mins_sample=25920;
my $one_hour_sample=4320;
my $five_hours_sample=1734; # in fact 6 hours
my $one_day_sample=1080;

# must be Global here to persist load through more files
my @rank_name = "";
my @rank_time = "";
my @port_name = "";
my @port_time = "";
my @mdisk_name = "";
my @mdisk_time = "";
my @vol_name = "";
my @vol_time = "";
my @cpuc_name = "";
my @cpuc_time = "";
my @cpun_name = "";
my @cpun_time = "";
my @drive_name = "";
my @drive_time = "";
my @pool_cap_name = "";
my @pool_cap_time = "";
my @volume_cache_name = "";
my @volume_cache_time = "";
my $KEEP_OUT_FILES = $ENV{KEEP_OUT_FILES};
if ( ! defined($KEEP_OUT_FILES) || $KEEP_OUT_FILES eq '' ) {
    $KEEP_OUT_FILES = 0; # delete data out files as default
}


###################################################
#  DS3000/4000/5000
###################################################

sub load_data_ds5_all {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, my $st_type) = @_;

  print "updating RRD   : $host:$st_type\n" if $DEBUG ;

  #
  # at first config files like xivconf_20130904_115351.out
  #

  my $perf_string = "ds5conf";
  opendir(DIR, "$wrkdir/$host") || main::error ("directory does not exists : $wrkdir/$host ".__FILE__.":".__LINE__) && return 0;

  my @files_unsorted = grep(/$host\_$perf_string\_20.*out/,readdir(DIR));
  my @files = sort { lc $a cmp lc $b } @files_unsorted;
  closedir(DIR);

  my $in_exist = 0;

  foreach my $file (@files) {
    chomp($file);
    if ( $file =~ m/-tmp$/ ) {
      next; it is not finised inpud data file
    }
    $in_exist = 1;
    my $in_file = "$wrkdir/$host/$file";

    my $ret = load_data_ds5_conf ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type);

    if ( $ret == 0 && $KEEP_OUT_FILES == 0 ) {
      unlink ($in_file);  # delete already processed file
      print "remove used    : $host:$in_file\n" if $DEBUG ;
    }

  }

  if ( $in_exist == 0 ) {
    print "config file    : $host: no new config input file found\n" if $DEBUG ;
  }

  #
  # now data files like xiv_svcperf_20130904_115351.out
  #

  $perf_string = "ds5perf";
  opendir(DIR, "$wrkdir/$host") || main::error ("directory does not exists : $wrkdir/$host ".__FILE__.":".__LINE__) && return 0;

  @files_unsorted = grep(/$host\_$perf_string\_20.*/,readdir(DIR));
  @files = sort { lc $a cmp lc $b } @files_unsorted;
  closedir(DIR);

  $in_exist = 0;

  foreach my $file (@files) {
    chomp($file);
    if ( $file =~ m/-tmp$/ ) {
      next; it is not finised inpud data file
    }
    $in_exist = 1;
    my $in_file = "$wrkdir/$host/$file";

    my $ret = load_data_ds5_perf ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type);

    if ( $ret == 0 && $KEEP_OUT_FILES == 0 ) {
      unlink ($in_file);  # delete already processed file
      print "remove used    : $host:$in_file\n" if $DEBUG ;
    }

    if ( $ret == 2 ) {
      last; # RRD create issue, skip everything until it is resolved (usually caused by full filesystem)
    }
  }

  if ( $in_exist == 0 ) {
    #main::error ("$host: NOTE: no new input files, exiting data load");
    return 1;
  }

  return 0;
}

sub load_data_ds5_conf  {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type) = @_;
  my $counter=0;
  my $counter_ins=0;
  my $act_time_u = time();
  my $ltime=localtime($act_time_u);
  my $cfg_load_data_ok = 0; # it is updated when there is found any mdisk, if 0 then something wrong and do not replace config.html

  print "updating RRD   : $host:$in_file\n" if $DEBUG ;
  my $pool_file = "$wrkdir/$host/pool.cfg";
  my $config_file = "$wrkdir/$host/config.html";
  my $pool_file_write = 0; # true if any write there 
  my $config_file_write = 0; # true if any write there 
  open(FH, "< $in_file") || main::error ("Can't open $in_file : $! : (ignore after fresh install) ".__FILE__.":".__LINE__) && return 0;
  open(FCFG, "> $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
  print FCFG "<HTML> <HEAD> <TITLE>STOR2RRD</TITLE> </HEAD> 
	<BODY BGCOLOR=#D3D2D2 TEXT=#000000 LINK=#0000FF VLINK= #000080 ALINK=#FF0000 > 
        <HR><CENTER><B>System overview:</B>(it is generated once a day, last run : $ltime)</CENTER><HR><PRE>\n";


  my @lines = <FH>;
  my $line = "";

  my @pool_name = "";
  my @pool_name_id = "";
  my @pool_capacity_tot = "";
  my @pool_capacity_free= "";
  my @pool_cfg_id = "";
  my @rank_cfg_id = "";
  my $pool_indx = 0;
  my $cfg_print = 1;
  my $pool_cfg_processing = 0;

  foreach $line (@lines) {
    #print "$line";
    chomp ($line);

    # print config file
    print FCFG "$line\n";
    $counter_ins++;

    if ( $line =~ m/DS5K type : / ) {
      # read storage version v1 vrs v2
      (my $trash, my $st_version) = split (/:/,$line);
      if ( defined($st_version) && ! $st_version eq '' ) {
        $st_version =~ s/ //g;
        $st_version =~ s/v//g;
        if ( isdigit ($st_version) == 1 && ! -f "$wrkdir/$host/$st_type-v$st_version"  ) {
          `touch "$wrkdir/$host/$st_type-v$st_version"`;
        }
      }
      next;
    }
  }  # foreach

  print FCFG "</pre></body></html>\n";
  close (FCFG);

  # POOL table is created in ds5_tmp as only there is know pool ID for DS5K!!!
  #if ($counter_ins) {
  #  print "cfg processed  : $host cfg rows: $counter_ins\n" if $DEBUG ;
  #}

  # check if cfg section has been in the input file and pools have been found, if so then replace pool.cfg by pool.cfg-tmp
  #open(FHR, "< $pool_file-tmp") || main::error ("Can't open $pool_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
  #@lines = <FHR>;
  #close(FHR); 
  #my @lines_write = sort { (split ':', $a)[0] <=> (split ':', $b)[0] } @lines; #numeric sorting 

  #foreach $line (@lines) {
  #  # mean there is at least one row, --> replace
  #  open(FHR, "> $pool_file") || main::error ("Can't open $pool_file : $! ".__FILE__.":".__LINE__) && return 0;
  #  foreach my $line_write (@lines_write) {
  #    print FHR "$line_write";
  #    #print "$line_write";
  #  }
  #  close (FHR);
  #  print "cfg pool found : $pool_file-tmp --> $pool_file\n" if $DEBUG ;
  #  unlink ("$pool_file-tmp");
  #  last;
  #}

  # same as above for config.html
    open(FCFGR, "< $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
    @lines = <FCFGR>;
    close(FCFGR); 
    my $cfg_section = 0;
    foreach $line (@lines) {
      chomp ($line);
      if ( $line =~ m/Volume Level/ ) {
        # the file must contain all 3 sections
        $cfg_section++;
      }
    }

    if ($cfg_section > 0) {
      print "cfg found      : $config_file-tmp --> $config_file\n" if $DEBUG ;
    }
    else {
      if ( $cfg_section > 0 ) {
        main::error ("problem with config file number of sections: $cfg_section ".__FILE__.":".__LINE__);
      }
      else {
        print "cfg not found  : no config in this data file\n" if $DEBUG ;
      }
    }
    if ( -f "$config_file-tmp" ) {
      rename ("$config_file-tmp","$config_file"); # rename it anyway even if some problem
    }

  close(FH); 
  return 0;
}

sub load_data_ds5_perf  {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type) = @_;

  my $counter_ins=0;
  my $last_rec = "";
  my $rrd ="";
  my $time = 3600;
  my $t = "";
  my $type = "NA";
  my $t1 = "";
  my $t2 = "";
  my $t3 = "";
  my $t4 = "";
  my $t5 = "";
  my $t6 = "";
  my $t7 = "";
  my $t8 = "";
  my $t9 = "";
  my $t10 = "";
  my $t11 = "";
  my $t12 = "";
  my $t13 = "";
  my $act_time_u = time();
  my $ltime=localtime($act_time_u);
  my $cfg_load_data_ok = 0; # it is updated when there is found any mdisk, if 0 then something wrong and do not replace config.html
  my $pool_file = "$wrkdir/$host/pool.cfg";
  my @pool_name_list = "";
  if  ( -f $pool_file ) {
    open(FHP, "< $pool_file") || main::error ("Can't open $pool_file : $! ".__FILE__.":".__LINE__) && return 0;
    my @pool_name_list = <FHP>;
    close (FHP);
  }

  print "updating RRD   : $host:$in_file\n" if $DEBUG ;
  my $pool_file_write = 0; # true if any write there 
  my $config_file_write = 0; # true if any write there 
  open(FH, "< $in_file") || main::error ("Can't open $in_file : $! ".__FILE__.":".__LINE__) && return 0;

  my @lines = <FH>;
  my $line = "";

  my @pool_cfg_id = "";
  my @pool_name = "";
  my @pool_name_id = "";
  my $pool_name_indx = 0;
  my $port_type_once = 0;
  my $volume_cache_once = 0;
  my $error_once = 0;
  my $pool_table_created = 0;

  #$DEBUG=2;

  foreach $line (@lines) {
    #print "$line";
    chomp ($line);

    if ( $line =~ m/Level Statistics/ ) {
      (my $type_temp, my $trash) = split(/ /,$line);
      $type = uc($type_temp);
      next;
    }
    
    if ( $line =~ m/Interval End:/ ) {
      $line =~ s/	//g;
      $line =~ s/Interval End:     //g;
      $line =~ s/GMT.*//g;
      (my $trash1, my $trash2, my $date, my $time_only) = split(/ /,$line);
      $time = str2time($line);
      if ( ! defined ($time) || isdigit ($time) == 0 ) {
        $type = "NA"; # clear out type when empty line
        main::error("no corret time format: $line ".__FILE__.":".__LINE__);
      }
      print "003 $line - $time\n" if $DEBUG == 3;
      next;
    }
     
    if ( $line =~ m/^$/ ) {
      $type = "NA"; # clear out type when empty line
      next;
    }

    if ( $line =~ /^name,id/ || $line =~ m/^  Interval / || $line =~ m/^	Interval/ || $line =~ m/^-----------/ || $line =~ m/^Node,Time/ || $line =~ m/^Node,cfav/ || $line =~ m/^CPU Core,Time/ || $line =~ m/^Port,Time/ || $line =~ m/^Drive,Time/ || $line =~ m/^Managed Disk ID,Time/ || $line =~ m/^Volume ID,Time/ ) {
      # avoid other trash
      next;
    }


    # Volume
    ########################

    if ( $type =~ m/^VOLUME$/ ){
      print "000 $line\n" if $DEBUG == 3;
      (my $volume_id, my $t1, my $t2, my $volume_name, my $pool_name, my $controller, my $total_io, my $total_io_rate, my $total_data_rate, my $read_hits, my $write_hits,
       my $read_pct, my $ssd_read_cache_hit, my $io_latency, my $cache_hits_v1, my $used_cap) = split(/,/,$line);

      # Volume ID,Time,Interval (s),Volume Name,Pool Name,Controler,Total IOs,Total IO Rate (IO/s),Total Data Rate (KB/s),Read Hits,Write Hits,Cache read %,SSD Read Cache Hit %,IO Latency,Cache hits, Capacity (MB)
      # v1
      #60080e500018450a0000af3a4dccbc49,2015:04:07T10:55:10,300,ADS11_ASRV11LPAR10_DATA0,ADS11_SATA_ARRAY1,B,57.0,0.2,29.1,,,100.0,,,84.2,1024000
      # v2
      #60080e50003e33340000029d54dca3b3,2015:04:07T11:05:11,300,ADS12_CLUSTER_ACCEPT_disk1,Disk_Pool_1,B,322.0,1.0,0,0.0,100.0,,0.0,0.2,750000

      #print "000 $line : $total_io\n";

      if ( ! defined ($pool_name) || $pool_name eq '' ) {
        if ( $error_once == 0 ) {
          main::error ("$host:$type - pool name is not defined: $pool_name , reported only once  : $line".__FILE__.":".__LINE__);
          $error_once++;
        }
        next;
      }

      if ( ! defined ($controller) || $controller eq '' ) {
        if ( $error_once == 0 ) {
          main::error ("$host:$type - controller name is not defined: $controller , reported only once  : $line".__FILE__.":".__LINE__);
          $error_once++;
        }
        next;
      }

      $pool_name =~ s/===coma===/,/g;
      if ( ! defined($read_hits) || $read_hits eq '' ) {
        $read_hits = 'U';
      }
      if ( ! defined($write_hits) || $write_hits eq '' ) {
        $write_hits = 'U';
      }
      if ( ! defined($read_pct) || $read_pct eq '' ) {
        $read_pct = 'U';
      }
      if ( ! defined($ssd_read_cache_hit) || $ssd_read_cache_hit eq '' ) {
        $ssd_read_cache_hit = 'U';
      }
      if ( ! defined($io_latency) || $io_latency eq '' ) {
        $io_latency = 'U';
      }
      if ( ! defined($total_io) || $total_io eq '' ) {
        $total_io = 'U';
      }
      if (! $controller eq '' && $controller =~ m/^[a|A]$/ ) {
        $controller = 0;
      }
      if (! $controller eq '' && $controller =~ m/^[b|B]$/ ) {
        $controller = 1;
      }
      if ( main::isdigit($controller) == 0 ) {
        if ( $error_once == 0 ) {
          main::error ("$host:$type - controler info is not found : $controller , reported only once  : $line".__FILE__.":".__LINE__);
          $error_once++;
        }
        next;
      }

      #Volume ID,Time,Interval (s),Volume Name,Pool Name,Controler,Total IOs,Total IO Rate (IO/s),Total Data Rate (KB/s),Read Hits,Write Hits

      if ( ! defined ($volume_id) || $volume_id eq '' || ! main::ishexa($volume_id) ) {
        if ( $error_once == 0 ) {
          main::error ("$host:$type - volume ID is not a digit or hexa: $volume_id , reported only once  : $line".__FILE__.":".__LINE__);
          $error_once++;
        }
        next;
      }

      #find pool_id
      my $pool_id = -1;
      my $pool_indx_tmp = 0;
      #print "001 $volume_id \n";
      foreach my $line_p (@pool_name_list) {
        chomp($line_p);
        if ( ! defined ($line_p) || $line_p eq '' || $line_p =~ m/^ *$/ ) {
          next;
        }
        (my $pool_id_tmp, my $pool_name_tmp, my $volumes_ids_tmp) = split (/:/,$line_p);
        if ( ! defined($volumes_ids_tmp) || $volumes_ids_tmp eq '' ) {
          next;
        }
        if ( $volumes_ids_tmp =~ m/$volume_id,/ ) {
          $pool_id = $pool_id_tmp;
          # last; let it go through all pools to find last record index
        }
        if ( $pool_name eq $pool_name_tmp ) {
          $pool_id = $pool_id_tmp;
          $pool_name_list[$pool_indx_tmp] = $line_p.$volume_id.","; # add a volume id to the pool name
          $pool_table_created++;
          last;
        }
        $pool_indx_tmp++;
      }
      if ( $pool_id == -1 ) {
        # set pool id
        $pool_name_list[$pool_indx_tmp] = "$pool_indx_tmp:$pool_name:$volume_id,"; 
        $pool_id = $pool_indx_tmp;
        $pool_table_created++;
      } 

      #print "001 $pool_id : $wrkdir/$host/$type/$volume_id-P$pool_id.rrd \n";
      #print "001 $pool_indx_tmp : $pool_name_list[$pool_indx_tmp] \n";

      if ( ! defined ($pool_id) || $pool_id eq '' || ! main::isdigit($pool_id) || $pool_id == -1 ) {
        if ( $error_once == 0 ) {
          main::error ("$host:$type - pool id issue: $pool_id (it should be a digit > 1) , reported only once : $line ".__FILE__.":".__LINE__);
          $error_once++;
        }
        next;
      }

      $rrd = "$wrkdir/$host/$type/$volume_id-P$pool_id.rrd";

      #create rrd db if necessary
      if ( create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type)  == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@vol_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $vol_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $vol_name[$l_count] = $rrd;
	  $vol_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          #print "005: $rrd : $volume_id: $ltime \n";
      }
      #print "006: $rrd : $volume_id: $ltime : $time \n";

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $vol_time[$l_count] = $time;
        $counter_ins++;
        if ( ! defined($total_io) || $total_io eq '' ) { 
          $total_io = 'U'; 
        }
        else {
          if ( isdigit($total_io) && $total_io == 0 ) {
            # when 0.0 then sprintf returns null!!
            $total_io = 0;
          }
          else {
            if ( isdigit($total_io) ) {
              my $total_io_tmp = $total_io;
              $total_io = sprintf("%.0d",$total_io_tmp);
            }
          }
        }
        if ( ! defined($total_io_rate) || $total_io_rate eq '' )           { $total_io_rate = 'U'; }
        if ( ! defined($total_data_rate) || $total_data_rate eq '' )       { $total_data_rate = 'U'; }
        if ( ! defined($read_hits) || $read_hits eq '' )                   { $read_hits = 'U'; }
        if ( ! defined($write_hits) || $write_hits eq '' )                 { $write_hits = 'U'; }
        if ( ! defined($read_pct) || $read_pct eq '' )                     { $read_pct = 'U'; }
        if ( ! defined($ssd_read_cache_hit) || $ssd_read_cache_hit eq '' ) { $ssd_read_cache_hit = 'U'; }
        if ( ! defined($io_latency) || $io_latency eq '' )                 { $io_latency = 'U'; }
        if ( ! defined($cache_hits_v1) || $cache_hits_v1 eq '' )           { $cache_hits_v1 = 'U'; }
        if ( ! defined($used_cap) || $used_cap eq '' )                     { $used_cap = 'U'; }


        #print "004: VOL $volume_id = $time:$controller:$total_io:$total_io_rate:$total_data_rate:$cache_hits_v1:$read_hits:$write_hits:$read_pct:$ssd_read_cache_hit:$io_latency:$used_cap\n";
        RRDp::cmd qq(update "$rrd" $time:$controller:$total_io:$total_io_rate:$total_data_rate:$cache_hits_v1:$read_hits:$write_hits:$read_pct:$ssd_read_cache_hit:$io_latency:$used_cap);
        my $answer = RRDp::read; 

	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
      }
    }
  }  # foreach


  if ($counter_ins) {
    print "inserted       : $host $counter_ins record(s)\n" if $DEBUG ;
  }

  # write down timestamp of last record , not for daily avg from HMC
  open(FHLT, "> $wrkdir/$host/last_rec") || main::error ("Can't open $wrkdir/$host/last_rec : $!".__FILE__.":".__LINE__) && return 0;
  print FHLT "$time";
  close(FHLT);

  close(FH); 

  # save pool translate table
  if ( $pool_table_created > 0 ) {
    # replace pool.cfg only if there is no any problem and the table has been created, it does not have to happen if any corruption in the data
    open(FHPW, "> $pool_file") || main::error ("Can't open $pool_file : $! ".__FILE__.":".__LINE__) && return 0;
    foreach my $line_p (@pool_name_list) {
      if ( $line_p eq '' ) {
        next;
      }
      print FHPW "$line_p\n";
    }
    close (FHPW);
  }
  return 0;
}


###################################################
#  XIV  section : IBM XIV     
###################################################

sub load_data_xiv_all {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, my $st_type) = @_;

  print "updating RRD   : $host:$st_type\n" if $DEBUG ;

  #
  # at first config files like xivconf_20130904_115351.out
  #

  my $perf_string = "xivconf";
  opendir(DIR, "$wrkdir/$host") || main::error ("directory does not exists : $wrkdir/$host ".__FILE__.":".__LINE__) && return 0;

  my @files_unsorted = grep(/$host\_$perf_string\_20.*out/,readdir(DIR));
  my @files = sort { lc $a cmp lc $b } @files_unsorted;
  closedir(DIR);

  my $in_exist = 0;

  foreach my $file (@files) {
    chomp($file);
    if ( $file =~ m/-tmp$/ ) {
      next; it is not finised inpud data file
    }
    $in_exist = 1;
    my $in_file = "$wrkdir/$host/$file";

    my $ret = load_data_xiv_conf ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type);

    if ( $ret == 0 && $KEEP_OUT_FILES == 0 ) {
      unlink ($in_file);  # delete already processed file
      print "remove used    : $host:$in_file\n" if $DEBUG ;
    }

  }

  if ( $in_exist == 0 ) {
    print "config file    : $host: no new config input file found\n" if $DEBUG ;
  }

  #
  # now data files like xiv_svcperf_20130904_115351.out
  #

  $perf_string = "xivperf";
  opendir(DIR, "$wrkdir/$host") || main::error ("directory does not exists : $wrkdir/$host ".__FILE__.":".__LINE__) && return 0;

  @files_unsorted = grep(/$host\_$perf_string\_20.*/,readdir(DIR));
  @files = sort { lc $a cmp lc $b } @files_unsorted;
  closedir(DIR);

  $in_exist = 0;

  foreach my $file (@files) {
    chomp($file);
    if ( $file =~ m/-tmp$/ ) {
      next; it is not finised inpud data file
    }
    $in_exist = 1;
    my $in_file = "$wrkdir/$host/$file";

    my $ret = load_data_xiv_perf ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type);

    if ( $ret == 0 && $KEEP_OUT_FILES == 0 ) {
      unlink ($in_file);  # delete already processed file
      print "remove used    : $host:$in_file\n" if $DEBUG ;
    }

    if ( $ret == 2 ) {
      last; # RRD create issue, skip everything until it is resolved (usually caused by full filesystem)
    }
  }

  if ( $in_exist == 0 ) {
    #main::error ("$host: NOTE: no new input files, exiting data load");
    return 1;
  }

  return 0;
}

sub load_data_xiv_conf  {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type) = @_;
  my $counter=0;
  my $counter_ins=0;
  my $act_time_u = time();
  my $ltime=localtime($act_time_u);
  my $cfg_load_data_ok = 0; # it is updated when there is found any mdisk, if 0 then something wrong and do not replace config.html

  print "updating RRD   : $host:$in_file\n" if $DEBUG ;
  my $pool_file = "$wrkdir/$host/pool.cfg";
  my $config_file = "$wrkdir/$host/config.html";
  my $pool_file_write = 0; # true if any write there 
  my $config_file_write = 0; # true if any write there 
  open(FH, "< $in_file") || main::error ("Can't open $in_file : $! ".__FILE__.":".__LINE__) && return 0;
  open(FHW, "> $pool_file-tmp") || main::error ("Can't open $pool_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
  open(FCFG, "> $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
  print FCFG "<HTML> <HEAD> <TITLE>STOR2RRD</TITLE> </HEAD> 
	<BODY BGCOLOR=#D3D2D2 TEXT=#000000 LINK=#0000FF VLINK= #000080 ALINK=#FF0000 > 
        <HR><CENTER><B>System overview:</B>(it is generated once a day, last run : $ltime)</CENTER><HR><PRE>\n";

  my @lines = <FH>;
  my $line = "";

  my @pool_name = "";
  my @pool_name_id = "";
  my @pool_capacity_tot = "";
  my @pool_capacity_free= "";
  my @pool_cfg_id = "";
  my @rank_cfg_id = "";
  my $pool_indx = 0;
  my $cfg_print = 1;
  my $pool_cfg_processing = 0;

  foreach $line (@lines) {
    #print "$line";
    chomp ($line);

    # print config file
    print FCFG "$line\n";
    $counter_ins++;

    if ( $line =~ m/Pool Level Configuration/ ) {
      $pool_cfg_processing = 1;
      next;
    }

    if ($pool_cfg_processing) {
      if ($line =~ m/^$/ ) {
        $pool_cfg_processing=0;
        # load capacity usage of pools (once a day into *.rrc)
        # --PH not done yet
        #load_rank_capacity($st_type,$wrkdir,$host,"POOL",$act_time_u,$DEBUG,$act_time,\@rank_cfg_id,\@pool_cfg_id,\@pool_capacity_tot,\@pool_capacity_free);
        next; # end of cfg
      }
      $line =~ s/^0x//;

      if ( $line =~ m/^---/ || $line =~ m/^name,id,status/ ) {
        next; # some trash like "---"
      }

      $cfg_load_data_ok = 1;

      # create an array with mapping table between ranks and pools
      my ($pool_name_cfg_item, $pool_id_cfg_item, $t1,$t2,$t3, $pool_cap_tot, $t4, $pool_cap_free) = split(/,/,$line);
      $pool_id_cfg_item =~ s/^.*\///;
      $pool_capacity_tot[$pool_indx] = $pool_cap_tot;
      $pool_capacity_free[$pool_indx] = $pool_cap_free;

      # save actual pool cfg
      $pool_name[$pool_indx] = $pool_name_cfg_item;
      $pool_name_id[$pool_indx] = $pool_id_cfg_item;
      $pool_indx++;
      print FHW "$pool_id_cfg_item:$pool_name_cfg_item\n";
      next;
    }
     
  }  # foreach

  close (FHW);
  print FCFG "</pre></body></html>\n";
  close (FCFG);

  if ($counter_ins) {
    print "cfg processed  : $host cfg rows: $counter_ins\n" if $DEBUG ;
  }

  # check if cfg section has been in the input file and pools have been found, if so then replace pool.cfg by pool.cfg-tmp
  open(FHR, "< $pool_file-tmp") || main::error ("Can't open $pool_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
  @lines = <FHR>;
  close(FHR); 
  my @lines_write = sort { (split ':', $a)[0] cmp (split ':', $b)[0] } @lines; # not numeric sorting! alphabetical one as pool ID might be in hexa

  foreach $line (@lines) {
    # mean there is at least one row, --> replace
    if ( ! defined($line) || $line eq '' ) {
      next;
    }
    open(FHR, "> $pool_file") || main::error ("Can't open $pool_file : $! ".__FILE__.":".__LINE__) && return 0;
    foreach my $line_write (@lines_write) {
      print FHR "$line_write";
      #print "$line_write";
    }
    close (FHR);
    print "cfg pool found : $pool_file-tmp --> $pool_file\n" if $DEBUG ;
    unlink ("$pool_file-tmp");
    last;
  }

  # same as above for config.html
    open(FCFGR, "< $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
    @lines = <FCFGR>;
    close(FCFGR); 
    my $cfg_section = 0;
    foreach $line (@lines) {
      chomp ($line);
      if ( $line =~ m/Pool Level/ || $line =~ m/Volume Level/ ) {
        # the file must contain all 3 sections
        $cfg_section++;
      }
    }

    if ($cfg_section > 1) {
      print "cfg found      : $config_file-tmp --> $config_file\n" if $DEBUG ;
    }
    else {
      if ( $cfg_section > 0 ) {
        main::error ("problem with config file number of sections: $cfg_section ".__FILE__.":".__LINE__);
      }
      else {
        print "cfg not found  : no config in this data file\n" if $DEBUG ;
      }
    }
    if ( -f "$config_file-tmp" ) {
      rename ("$config_file-tmp","$config_file"); # rename it anyway even if some problem
    }

  close(FH); 
  return 0;
}

sub load_data_xiv_perf  {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type) = @_;

  my $counter_ins=0;
  my $last_rec = "";
  my $rrd ="";
  my $time = 3600;
  my $t = "";
  my $type = "NA";
  my $t1 = "";
  my $t2 = "";
  my $t3 = "";
  my $t4 = "";
  my $t5 = "";
  my $t6 = "";
  my $t7 = "";
  my $t8 = "";
  my $t9 = "";
  my $t10 = "";
  my $t11 = "";
  my $t12 = "";
  my $t13 = "";
  my $act_time_u = time();
  my $ltime=localtime($act_time_u);
  my $cfg_load_data_ok = 0; # it is updated when there is found any mdisk, if 0 then something wrong and do not replace config.html

  print "updating RRD   : $host:$in_file\n" if $DEBUG ;
  my $pool_file_write = 0; # true if any write there 
  my $config_file_write = 0; # true if any write there 
  open(FH, "< $in_file") || main::error ("Can't open $in_file : $! ".__FILE__.":".__LINE__) && return 0;

  my @lines = <FH>;
  my $line = "";

  my @pool_cfg_id = "";
  my @pool_name = "";
  my @pool_name_id = "";
  my $pool_name_indx = 0;
  my $port_type_once = 0;
  my $volume_cache_once = 0;
  my $error_once = 0;

  #$DEBUG=2;

  foreach $line (@lines) {
    #print "$line";
    chomp ($line);


    if ( $line =~ m/Pool Capacity Statistics/ ) {
      $type = "POOLcap";
      next;
    }
    if ( $line =~ m/Volume Cache Level Statistics/ ) {
      $type = "VOLUMECache";
      next;
    }

    if ( $line =~ m/Level Statistics/ ) {
      (my $type_temp, my $trash) = split(/ /,$line);
      if ( $type_temp =~ m/Managed/ ) {
        $type = "RANK"; #  Managed --> RANK conversion (mdisk --> rank)
      }
      else {
        $type = uc($type_temp);
      }
      next;
    }
    
    if ( $line =~ m/Interval End:/ ) {
      $line =~ s/	//g;
      $line =~ s/Interval End:     //g;
      $line =~ s/GMT.*//g;
      (my $trash1, my $trash2, my $date, my $time_only) = split(/ /,$line);
      $time = str2time($line);
      if ( isdigit ($time) == 0 ) {
        $type = "NA"; # clear out type when empty line
        main::error("no corret time format: $line : $time ".__FILE__.":".__LINE__);
      }
      print "003 $line - $time\n" if $DEBUG == 3;
      next;
    }
     
    if ( $line =~ m/^$/ ) {
      $type = "NA"; # clear out type when empty line
      next;
    }

    if ( $line =~ /^name,id/ || $line =~ m/^	Interval/ || $line =~ m/^-----------/ || $line =~ m/^Node,Time/ || $line =~ m/^Node,cfav/ || $line =~ m/^CPU Core,Time/ || $line =~ m/^Port,Time/ || $line =~ m/^Drive,Time/ || $line =~ m/^Managed Disk ID,Time/ || $line =~ m/^Volume ID,Time/ ) {
      # avoid other trash
      next;
    }

    # Port
    ########################

    if ( $type =~ m/^PORT$/ ){
      # Not yet included 
      print "000 $line\n" if $DEBUG == 3;
      # Port statistics
      (my $name,my $t1,my $t2,my $write_io,my $read_io,my $io_rate,my $write,my $read,my $data_rate,my $t10,my $t11,my $t12,my $t13,my $t14,my $t15,my $t16,my $t17,my $t18,my $t19,my $t20,my $t21,my $t22,my $t23,my $t24,my $t25,my $t26,my $t27,my $t28,my $t29,my $t30,my $t31,my $t32,my $t33,my $t34,my $t35,my $t36,my $t37,my $t38,my $t39,my $t40,my $t41,my $t42,my $t43,my $t44,my $port_type_text)=split(/,/,$line);

      # type : FC / iSCSI / SAS (PCIe)
      my $port_type = 3; # default unknown port type
      if ( $port_type_text eq '' ) {
        next;
      }
      if ( $port_type_text =~ m/^FC$/    ) { $port_type = 0; }
      if ( $port_type_text =~ m/^PCIe$/  ) { $port_type = 1; }
      if ( $port_type_text =~ m/^SAS$/   ) { $port_type = 1; }
      if ( $port_type_text =~ m/^iSCSI$/ ) { $port_type = 2; }
      if ( $port_type_text =~ m/^IPREP$/ ) { $port_type = 4; }
      # IPREP addition ...  replikaci pro asynchronní remote copy.

      if ( $port_type == 3 && $port_type_once == 0 ) {
        # unknown port type detected, print error message just once
        main::error ("$host: unknown port type: $name : $port_type_text ".__FILE__.":".__LINE__);
        $port_type_once = 1;
      }

      #print "001 PORT $name - $write_io - $read_io - $io_rate - $write - $read - $data_rate - type:$port_type:$port_type_text\n";
      print "001 PORT $name - $write_io - $read_io - $io_rate - $write - $read - $data_rate - type:$port_type\n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/$type/$name\.rrd";

      #create rrd db if necessary
      if ( create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }
      #print "001 $rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type\n" if $DEBUG == 3;

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@port_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $port_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $port_name[$l_count] = $rrd;
	  $port_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          #print "005: $name: $ltime - $l_count : $rrd : $port_name[$l_count] - $port_time[$l_count]\n" if $DEBUG == 3;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $port_time[$l_count] = $time;
        $counter_ins++;
        my $resp_t = "0"; # not available yet, could be in the next release
        print "004: PORT $time:$write_io:$read_io:$io_rate:$data_rate:$resp_t:$read:$write\n" if $DEBUG == 3;
        RRDp::cmd qq(update "$rrd" $time:$write_io:$read_io:$io_rate:$data_rate:$resp_t:$read:$write:$port_type);
        my $answer = RRDp::read; 

	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
      }
    }


    # Volume
    ########################

    if ( $type =~ m/^VOLUME$/ ){
      print "000 $line\n" if $DEBUG == 3;
      # Port statistics
      (my $name, my $t1, my $t2, my $io_read, my $io_write, my $total_io, my $read, my $write, my $total, $t3,$t4,$t5, my $resp_t_r, my $resp_t_w,
      $t6,$t7,$t8,$t9,$t10,my $read_hits,my $write_hits,$t11,$t12,$t13, my $pool_id) = split(/,/,$line);

      # Volume ID,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),
      # Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Read Response Time (ms),Write Response Time (ms),Overall Response Time (ms),
      # Peak Read Response Time (ms),Peak Write Response Time (ms),,,Read Hits,Write Hits,Data Read (KB),Data Written (KB),Volume Name,Pool ID,Pool Name,,,,,,,
      # ,,,,,,,,,,,,,,,,Source Volume Name

      # 00102832,2014:10:26T06:10:07.000000,602,0.028,2.020,2.048,0.113,9.349,9.462,4.000,4.628,4.620,0.424,0.749,0.000,,,,,,,,,vio_1p_01,IBMTSDS:IBM.2810-XXXXXXX-VP102778,VIO_1P,,,,

      $pool_id =~ s/^.*VP//;
      if ( ! defined ($name) || $name eq '' || ! main::ishexa($name) || $name =~ m/\./ || ! defined ($pool_id) || $pool_id eq '' || ! main::ishexa($pool_id) || $pool_id =~ m/\./ ) {
        if ( $error_once == 0 ) {
          main::error ("$host:$type - volume ID is not a digit or hexa: $name or pool id is not a digit: $pool_id , reported only once ".__FILE__.":".__LINE__);
          $error_once++;
        }
        next;
      }
      if ( $read_hits eq '' ) {
        $read_hits = 'U';
      }
      if ( $write_hits eq '' ) {
        $write_hits = 'U';
      }

      print "001 VOL $name - $io_read - $io_write - $resp_t_r - $resp_t_w - $read - $write\n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/$type/$name-P$pool_id.rrd";

      #create rrd db if necessary
      if ( create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type)  == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@vol_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $vol_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $vol_name[$l_count] = $rrd;
	  $vol_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          #print "005: $name: $ltime - $l_count : $rrd : $port_name[$l_count] - $port_time[$l_count]\n" if $DEBUG == 3;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $vol_time[$l_count] = $time;
        $counter_ins++;
        print "004: VOL $time:$io_read:$io_write:$resp_t_r:$resp_t_w:$read:$write:$read_hits:$write_hits\n" if $DEBUG == 3;
        RRDp::cmd qq(update "$rrd" $time:$io_read:$io_write:$resp_t_r:$resp_t_w:$read:$write:$read_hits:$write_hits);
        my $answer = RRDp::read; 

	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
      }
    }
  }  # foreach


  if ($counter_ins) {
    print "inserted       : $host $counter_ins record(s)\n" if $DEBUG ;
  }

  # write down timestamp of last record , not for daily avg from HMC
  open(FHLT, "> $wrkdir/$host/last_rec") || main::error ("Can't open $wrkdir/$host/last_rec : $!".__FILE__.":".__LINE__) && return 0;
  print FHLT "$time";
  close(FHLT);

  close(FH); 
  return 0;
}

###################################################
#  DS8K section
###################################################

sub load_data_ds8k_all {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, my $st_type) = @_;

  print "updating RRD   : $host:$st_type\n" if $DEBUG ;

  opendir(DIR, "$wrkdir/$host") || main::error ("directory does not exists : $wrkdir/$host ".__FILE__.":".__LINE__) && return 0;
  my $perf_string = "perf";

  my @files_unsorted = grep(/$host\.$perf_string\.20.*/,readdir(DIR));
  my @files = sort { lc $a cmp lc $b } @files_unsorted;
  closedir(DIR);

  my $in_exist = 0;

  foreach my $file (@files) {
    chomp($file);
    if ( $file =~ m/-tmp$/ ) {
      next; it is not finised inpud data file
    }
    $in_exist = 1;
    my $in_file = "$wrkdir/$host/$file";

    my $ret = load_data_ds8k ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type);

    if ( $ret == 0 && $KEEP_OUT_FILES == 0 ) {
      unlink ($in_file);  # delete already processed file
      print "remove used    : $host:$in_file\n" if $DEBUG ;
    }

    if ( $ret == 2 ) {
      last; # RRD create issue, skip everything until it is resolved (usually caused by full filesystem)
    }
  }

  if ( $in_exist == 0 ) {
    #main::error ("$host: NOTE: no new input files, exiting data load");
    return 1;
  }

  return 0;
}

sub load_data_ds8k {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type) = @_;
  my @rank_capacity_tot = "";
  my @rank_capacity_used = "";
  my $counter_ins=0;
  my $last_rec = "";
  my $rrd ="";
  my $time = 3600;
  my $t = "";
  my $type = "NA";
  my $t1 = "";
  my $t2 = "";
  my $t3 = "";
  my $t4 = "";
  my $t5 = "";
  my $t6 = "";
  my $t7 = "";
  my $t8 = "";
  my $t9 = "";
  my $t10 = "";
  my $t11 = "";
  my $t12 = "";
  my $act_time_u = time();
  my $ltime=localtime($act_time_u);
  my $cfg_load_data_ok = 0; # it is updated when there is found any rank, if 0 then something wrong and do not replace config.html

  print "updating RRD   : $host:$in_file\n" if $DEBUG ;
  my $pool_file = "$wrkdir/$host/pool.cfg";
  my $config_file = "$wrkdir/$host/config.html";
  my $pool_file_write = 0; # true if any write there 
  my $config_file_write = 0; # true if any write there 
  open(FH, "< $in_file") || main::error ("Can't open $in_file : $! ".__FILE__.":".__LINE__) && return 0;
  open(FHW, "> $pool_file-tmp") || main::error ("Can't open $pool_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
  open(FCFG, "> $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
  print FCFG "<HTML> <HEAD> <TITLE>STOR2RRD</TITLE> </HEAD> 
	<BODY BGCOLOR=#D3D2D2 TEXT=#000000 LINK=#0000FF VLINK= #000080 ALINK=#FF0000 > 
        <HR><CENTER><B>System overview:</B>(it is generated once a day, last run : $ltime)</CENTER><HR><PRE>\n";

  my @lines = <FH>;
  my $line = "";

  my @rank_cfg_id = "";
  my @pool_cfg_id = "";
  my $rank_cfg_processing = 0;
  my $rank_cfg_indx = 0;
  my @pool_name = "";
  my @pool_name_id = "";
  my $pool_name_indx = 0;
  my $cfg_print = 1;
  my $error_pprc_once = 0;

  # pool fron-end data from volume data
  my @pool_read = "";
  my @pool_write = "";
  my @pool_io_read = "";
  my @pool_io_write = "";
  my @pool_resp_r = "";
  my @pool_resp_w = "";
  my @pool_ids = "";
  my $pool_time = 0;
  my $pool_ltime = 0;

  foreach $line (@lines) {
    #print "$line";
    chomp ($line);


    if ( $line =~ m/Level Statistics/ ) {
      (my $type_temp, my $trash) = split(/ /,$line);
      $type = uc($type_temp);
      if ( $cfg_print == 1) {
        print FCFG "</pre></body></html>\n";
        close (FCFG);
      }
      $cfg_print = 0;
      next;
    }

    if ( $cfg_print == 1) { 
      # print config file
      print FCFG "$line\n";
    }
    

    if ( $line =~ m/Rank Level Configuration/ ) {
      $rank_cfg_processing = 1;
      next;
    }

    if ($rank_cfg_processing) {
      if ($line =~ m/^$/ ) {
        $rank_cfg_processing=0;
        # load capacity usage of ranks (once a day into *.rrc)
        load_rank_capacity($st_type,$wrkdir,$host,"RANK",$act_time_u,$DEBUG,$act_time,\@rank_cfg_id,\@pool_cfg_id,\@rank_capacity_tot,\@rank_capacity_used);
        next; # end of cfg
      }
      $line =~ s/^0x//;

      if ( $line =~ m/---/ || $line =~ m/^Rank ID/ ) {
        next; # some trash like "---"
      }

      $cfg_load_data_ok = 1;

      # create an array with mapping table between ranks and pools
      (my $rank_id_cfg_item, my $pool_id_cfg_item, $t3, my $rank_cap_tot, $t5, $t6, $t7 ,$t8, my $pool_name_cfg_item, my $rank_cap_used) = split(/,/,$line);
      $pool_id_cfg_item =~ s/^.*\///;
      #$rank_id_cfg_item =~ s/^0x//;
      $rank_cfg_id[$rank_cfg_indx] = $rank_id_cfg_item;
      $pool_cfg_id[$rank_cfg_indx] = $pool_id_cfg_item;
      $rank_capacity_tot[$rank_cfg_indx] = $rank_cap_tot;
      $rank_capacity_used[$rank_cfg_indx] = $rank_cap_used;
      #print "009 $rank_cfg_id[$rank_cfg_indx] $pool_cfg_id[$rank_cfg_indx]\n";
      #print "009 $rank_cfg_id[$rank_cfg_indx] $pool_cfg_id[$rank_cfg_indx]\n";

      # save actual pool cfg
      my $found = -1;
      foreach my $pool_item (@pool_name) {
        if ( $pool_item =~ m/^$pool_name_cfg_item$/ ) {
          $found = $pool_name_indx;
          last;
        }
      }
      if ( $found == -1 ) {
        $pool_name[$pool_name_indx] = $pool_name_cfg_item;
        $pool_name_id[$pool_name_indx] = $pool_id_cfg_item;
        $pool_name_indx++;
        my $pool_number = $pool_id_cfg_item; # there is still P letter
        $pool_number =~ s/^P//;
        print FHW "$pool_number:$pool_name_cfg_item\n";
      }

      $rank_cfg_indx++; 
      next;
    }
     
    if ( $line =~ m/Interval End:/ ) {
      $line =~ s/	//g;
      $line =~ s/Interval End:     //g;
      $line =~ s/GMT.*//g;
      (my $trash1, my $trash2, my $date, my $time_only) = split(/ /,$line);
      $time = str2time($line);
      if ( isdigit ($time) == 0 ) {
        $type = "NA"; # clear out type when empty line
        main::error("no corret time format: $line : $time ".__FILE__.":".__LINE__);
      }
      print "003 $line - $time\n" if $DEBUG == 2;
      next;
    }
     
    if ( $line =~ m/^$/ ) {
      $type = "NA"; # clear out type when empty line
      if ( $pool_time > 0 ) {
        # insert summed pool data based on volume front-end data, it must be even at the enf of that foreach as volumes normally ends the perf file
        if ( $pool_time > $pool_ltime ) {
           $pool_ltime = pool_sum_insert($wrkdir,$step,$DEBUG,$host,$no_time,$act_time,$st_type,$pool_time,$pool_ltime,\@pool_read,\@pool_write,\@pool_io_read,\@pool_io_write,\@pool_resp_r,\@pool_resp_w,\@pool_ids);
        }
        # reinitialize structures
        @pool_ids  = "";
        @pool_read = "";
        @pool_write = "";
        @pool_io_read = "";
        @pool_io_write = "";
        @pool_resp_r = "";
        @pool_resp_w = "";
        $pool_time = 0;
      }
      next;
    }

    if ( $line !~ m/^0x/ ) {
      # avoid other trash
      next;
    }
    $line =~ s/^0x//;
   
    # Port
    ########################

    if ( $type =~ m/PORT/ ){
      print "000 $line\n" if $DEBUG == 2;
      # Port statistics
      (my $name,$t1,my $io_rate,my $data_rate,$t2,my $resp_t,$t3,$t4,my $read,my $write,$t5,$t6,$t7,$t8,$t9,$t10,$t11,$t12,
          my $pprc_rio,my $pprc_wio,my $pprc_data_r,my $pprc_data_w,my $pprc_rt_r,my $pprc_rt_w) = split(/,/,$line);
      # 0x30,4.0,218.721154,6366.153846,29.106256,0.836330,0,0,0,0,0,0,0,0,0,0,0,0,0,45494,0,1324160,0,38048,208
      #Port ID,Speed (Gbps),I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,FB Read I/Os,FB Write I/Os,FB KBs Read,FB KBs Written,FB Accum Read Time,FB Accum
      #Write Time,CKD Read I/Os,CKD Write I/Os,CKD KBs Read,CKD KBs Written,CKD Accum Read Time,CKD Accum Write Time,PPRC Receive I/Os,PPRC Send I/Os,PPRC
      #KBs Received,PPRC KBs Sent,PPRC Accum Recv Time,PPRC Accum Send Time,Interval Length

      print "001 $name - $io_rate - $data_rate - $resp_t - $read - $write\n" if $DEBUG == 2;

      # PPRC response times : PPRC Accum Recv Time,PPRC Accum Send Time
      if ( $pprc_rio != 0 ) {
        $pprc_rt_r = $pprc_rt_r / $pprc_rio * 1000; # to have that in ms
      }
      else {
        $pprc_rt_r = 0;
      }
      if ( $pprc_wio != 0 ) {
        $pprc_rt_w = $pprc_rt_w / $pprc_wio * 1000; # to have that in ms
      }
      else {
        $pprc_rt_w = 0;
      }


      $rrd = "$wrkdir/$host/$type/$name\.rrd";
      my $rrdp = "$wrkdir/$host/$type/$name\.rrp"; # PPRC DBs

      my $pprc_yes = 0 ;
      if ( isdigit($pprc_rio) && isdigit ($pprc_wio) && isdigit ($pprc_data_r) && isdigit ($pprc_data_w) && isdigit ($pprc_rt_r) && isdigit ($pprc_rt_w)) {
        $pprc_yes = $pprc_rio + $pprc_wio + $pprc_data_r + $pprc_data_w + $pprc_rt_r + $pprc_rt_w;
      }
      else {
        if ( $error_pprc_once == 0 ) {
          main::error("$rrdp: PPRC data digit issue: $pprc_rio,$pprc_wio,$pprc_data_r,$pprc_data_w,$pprc_rt_r,$pprc_rt_w ".__FILE__.":".__LINE__);
          $error_pprc_once++;
        }
      }

      #create rrd db if necessary
      if ( create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }
      
      if ( $pprc_yes > 0 ) {
        # create PPRC data files only when any trafic is there
        if (create_rrd($rrdp,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
          return 2; # leave uit if any error during RRDTool file creation to keep data
        }
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@port_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $port_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array

          # construction against crashing daemon Perl code when RRDTool error appears
          # this does not work well in old RRDTOool: $RRDp::error_mode = 'catch';
          # construction is not too costly as it runs once per each load
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  $port_name[$l_count] = $rrd;
	  $port_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          #print "005: $name: $ltime - $l_count : $rrd : $port_name[$l_count] - $port_time[$l_count]\n" if $DEBUG == 2;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $port_time[$l_count] = $time;
        $counter_ins++;
        print "004: $time:$io_rate:$data_rate:$resp_t:$read:$write\n" if $DEBUG == 2;
        RRDp::cmd qq(update "$rrd" $time:$io_rate:$data_rate:$resp_t:$read:$write);
        my $answer = RRDp::read; 

	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
        if ( $pprc_yes > 0 ) {
          # go further only for ports where PPRC traffic has been identified and DB created, no matter is all is 0!
          print "004: $time:$pprc_rio:$pprc_wio:$pprc_data_r:$pprc_data_w:$pprc_rt_r:$pprc_rt_w\n" if $DEBUG == 2;
          RRDp::cmd qq(update "$rrdp" $time:$pprc_rio:$pprc_wio:$pprc_data_r:$pprc_data_w:$pprc_rt_r:$pprc_rt_w);
          my $answer = RRDp::read; 
        }
      }
    }

    # RANK
    ########################

    if ( $type =~ m/RANK/ ){
      print "100 $line\n" if $DEBUG == 2;
      # Rank statistics
      (my $name, $t1, $t2, my $read_io, my $write_io, my $read, my $write, $t7, $t8, my $resp_t_r, my $resp_t_w) = split(/,/,$line);

      #(my $name, $t1, $t2, my $t3, my $t4, my $t5, my $t6, $t7, $t8, my $resp_t_r, my $resp_t_w, my $read_io, my $write_io, my $read, my $write) = split(/,/,$line);
      #Rank ID,RAID Type,Num of Arrays,Read I/O Rate,Write I/O Rate,Read Data Rate,Write Data Rate,Avg Read Xfer Size,Avg Write Xfer Size,Avg Read Resp Time
      #,Avg Write Resp Time,Read I/Os,Write I/Os,KBs Read,KBs Written,Accum Read Time,Accum Write Time,Interval Length
      #0x0,RAID-0,1,25.454090,1.704508,1294.103506,980.834725,50.840690,575.435847,2.575195,18.664055,15247,1021,775168,587520,39264,19056,599

      if ( $pool_name_indx == 0 ) { 
        # mean that cfg header has not been in the file
        # map pool id to ranks id only first time
        $pool_name_indx = 1;
        my @files = <$wrkdir/$host/$type/*.rrd>;
        my $indx_tmp = 0;
        foreach my $filep (@files) {
          chomp($filep);
          $filep =~ s/.*\///;
          $filep =~ s/.rrd//;
          (my $rank_id, my $pool_id) = split (/-/,$filep);
          # print "001 $rank_id, $pool_id , $filep, $indx_tmp\n";
          $rank_cfg_id[$indx_tmp] = $rank_id;
          $pool_cfg_id[$indx_tmp] = $pool_id;
          $indx_tmp++;
        }
      }

      # find out pool id for the rank and place it into rrd file name
      $rank_cfg_indx = 0;
      foreach my $r_id (@rank_cfg_id) {
        if ( $r_id =~ m/^$name$/ ) {
          last;
        }
        $rank_cfg_indx++;
      }

      if ( ! defined ($name) || $name eq '' || ! isdigit($name) || $name =~ m/\./ ) {
        next;
      }

      $rrd = "$wrkdir/$host/$type/$name-$pool_cfg_id[$rank_cfg_indx]\.rrd";
      
      if ( $pool_cfg_id[$rank_cfg_indx] !~ /P/ ) {
        next; # some problem with pool name (does not contain P) --> leave it here 
      }

      #create rrd db if necessary
      if ( create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@rank_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $rank_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  $rank_name[$l_count] = $rrd;
	  $rank_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          print "005: $ltime - $l_count\n" if $DEBUG == 2;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $rank_time[$l_count] = $time;
        $counter_ins++;
        print "104: $time:$read_io:$write_io:$read:$write:$resp_t_r,$resp_t_w\n" if $DEBUG == 2;
        my $io_rate = $read_io + $write_io;
        my $date_rate = $read + $write;
        RRDp::cmd qq(update "$rrd" $time:$read_io:$write_io:$read:$write:$resp_t_r:$resp_t_w);
        my $answer = RRDp::read; 

	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
      }
    }


    # Volume
    ########################

    if ( $type =~ m/VOLUME/ ){
      print "000 $line\n" if $DEBUG == 2;
      #print "000 $line\n";
      # Port statistics
      my ( $name,$io_rate,$data_rate, $t1,$resp_t,$t2,$t3,$r_cache_hit,$w_cache_hit,$readio_ns,$writeio_ns,
        $readio_se,$writeio_se,$t9,$t10,$t11,$t12,$read,$write,$resp_t_r,$resp_t_w,$x1,$x2,$x3,$x4,$x5,$x6,$x7,$x8,$x9,$x10
        ,$x11,$x12,$x13,$x14,$x15,$x16,$x17,$x18,$x19,$x20,$read_io_b,$write_io_b,$read_b,$write_b,$resp_t_r_b,$resp_t_w_b,
        $x21,$x22,$x23,$x24,$pool_id) = split(/,/,$line);
	# 0x0000,4.324503,1.907285,0.441041,0.128637,0.000000,100.000000,100.000000,100.000000,1432,1180,0,0,1432,1180,0,0,640.000000,
	#  512.000000,80,256,0,0,1,1180,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0.000000,0.000000,0,144,0,0,0,604,IBM.2107-75ANM81/P0
        # Volume ID,I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,Delayed I/O Perc,Total Hit Perc,Read Hit Perc,Write Hit Perc,Non-seq Read I/Os,
	#  Non-seq Write I/Os,Seq Read I/Os,Seq Write I/Os,Non-seq Read Hits,Non-seq Write Hits,Seq Read Hits,Seq Write Hits,KBs Read,KBs Written,
	#  Accum Read Time,Accum Write Time,Non-seq Disk->Cache Ops,Seq Disk->Cache Ops,Cache->Disk Ops,NVS Allocs,Non-seq DFW I/Os,Seq DFW I/Os,
	#  NVS Delayed DFW I/Os,Cache Delayed I/Os,Rec Mode Read I/Os,Rec Mode Read Hits,CC/XRC Trks Read,CC/XRC Contam Writes,PPRC Trk Xfers,
	#  Quick Write Prom,CFW Read I/Os,CFW Write I/Os,CFW Read Hits,CFW Write Hits,Irreg Trk Acc,Irreg Trk Acc Hits,Backend Read Ops,
	#  Backend Write Ops,Backend KBs Read,Backend KBs Written,Backend Accum Read Time,Backend Accum Write Time,ICL Read I/Os,
	#  Cache Bypass Write I/Os,Backend Data Xfer Time,Interval Length,Pool ID 

      my $read_io = $readio_ns + $readio_se;
      my $write_io = $writeio_ns + $writeio_se;
      if ( $read != 0 ) {
        $read = $read / 1024;
      }
      if ( $write != 0 ) {
        $write = $write / 1024;
      }
     
      print "001 $name - $io_rate - $data_rate - $resp_t - $read - $write - $r_cache_hit - $w_cache_hit - $resp_t_r - $resp_t_w - $read_io - $write_io\n" if $DEBUG == 2;
      $rrd = "$wrkdir/$host/$type/$name\.rrd";

      # read response time = Accum Read Time / ( Non-seq Read I/Os + Seq Read I/Os)
      # write response time = Accum Write Time / ( Non-seq Write I/Os + Seq Write I/Os )
      # fron-end
      my $pool_resp_t_r = $resp_t_r; #save original value for pool usage
      if ( $read_io != 0 ) {
        $resp_t_r = $resp_t_r / $read_io;
      }
      else {
        $resp_t_r = 0;
        $pool_resp_t_r = 0;
      }
      my $pool_resp_t_w = $resp_t_w; #save original value for pool usage
      if ( $write_io != 0 ) {
        $resp_t_w = $resp_t_w / $write_io;
      }
      else {
        $pool_resp_t_r = 0;
        $resp_t_w = 0;
      }

      # back end
      if ( $read_io_b != 0 ) {
        $resp_t_r_b = $resp_t_r_b / $read_io_b;
      }
      else {
        $resp_t_r_b = 0;
      }
      if ( $write_io_b != 0 ) {
        $resp_t_w_b = $resp_t_w_b / $write_io_b;
      }
      else {
        $resp_t_w_b = 0;
      }
      my $rrdc = "$wrkdir/$host/$type/$name\.rrc"; # response times and cache stats

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }
      if (create_rrd($rrdc,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@vol_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $vol_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  $vol_name[$l_count] = $rrd;
	  $vol_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          #print "005: $name: $ltime - $l_count : $rrd : $port_name[$l_count] - $port_time[$l_count]\n" if $DEBUG == 2;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $vol_time[$l_count] = $time;
        $counter_ins++;
        print "004: $time:$io_rate:$data_rate:$resp_t:$read:$write\n" if $DEBUG == 2;
        RRDp::cmd qq(update "$rrd" $time:$io_rate:$data_rate:$resp_t:$read:$write);
        my $answer = RRDp::read; 
        RRDp::cmd qq(update "$rrdc" $time:$r_cache_hit:$w_cache_hit:$resp_t_r:$resp_t_w:$read_io:$write_io:$read_b:$write_b:$read_io_b:$write_io_b:$resp_t_r_b:$resp_t_w_b);
        $answer = RRDp::read; 

        if ( ! $pool_id eq '' && $pool_id =~ m/\/P/ ) {
          # keep volume fron-end data summ per pool and save it at the end
          $pool_id =~ s/^.*\/P//;
          if ( isdigit($pool_id) == 1 ) {
            if ( ! defined $pool_read[$pool_id]      || $pool_read[$pool_id] eq '' )    { $pool_read[$pool_id] = 0; }
            if ( ! defined $pool_write[$pool_id]     || $pool_write[$pool_id] eq '' )   { $pool_write[$pool_id] = 0; }
            if ( ! defined $pool_io_read[$pool_id]   || $pool_io_read[$pool_id] eq '' ) { $pool_io_read[$pool_id] = 0; }
            if ( ! defined $pool_io_write[$pool_id]  || $pool_io_write[$pool_id] eq '' ){ $pool_io_write[$pool_id] = 0; }
            if ( ! defined $pool_resp_r[$pool_id]    || $pool_resp_r[$pool_id] eq '' )  { $pool_resp_r[$pool_id] = 0; }
            if ( ! defined $pool_resp_w[$pool_id]    || $pool_resp_w[$pool_id] eq '' )  { $pool_resp_w[$pool_id] = 0; }
            $pool_read[$pool_id] += $read;
            $pool_write[$pool_id] += $write;
            $pool_io_read[$pool_id] += $read_io;
            $pool_io_write[$pool_id] += $write_io;
            $pool_resp_r[$pool_id] += $pool_resp_t_r;
            $pool_resp_w[$pool_id] += $pool_resp_t_w;
            $pool_time = $time;
            $pool_ids[$pool_id] = $pool_id;
          }
        }
      }
    }
  }  # foreach

  close (FHW);

  # insert summed pool data based on volume front-end data, it must be even at the enf of that foreach as volumes normally ends the perf file
  if ( $pool_time > $pool_ltime ) {
    pool_sum_insert($wrkdir,$step,$DEBUG,$host,$no_time,$act_time,$st_type,$pool_time,$pool_ltime,\@pool_read,\@pool_write,\@pool_io_read,\@pool_io_write,\@pool_resp_r,\@pool_resp_w,\@pool_ids);
  }

  if ($counter_ins) {
    print "inserted       : $host $counter_ins record(s)\n" if $DEBUG ;
  }

  # write down timestamp of last record , not for daily avg from HMC
  open(FHLT, "> $wrkdir/$host/last_rec") || main::error ("Can't open $wrkdir/$host/last_rec : $! ".__FILE__.":".__LINE__) && return 0;
  print FHLT "$time";
  close(FHLT);


  # check if cfg section has been in the input file and pools have been found, if so then replace pool.cfg by pool.cfg-tmp
  open(FHR, "< $pool_file-tmp") || main::error ("Can't open $pool_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
  @lines = <FHR>;
  close(FHR); 
  my @lines_write = sort { lc $a cmp lc $b } @lines;

  foreach $line (@lines) {
    # mean there is at least one row, --> replace
    if ( ! defined($line) || $line eq '' ) {
      next;
    }
    open(FHR, "> $pool_file") || main::error ("Can't open $pool_file : $! ".__FILE__.":".__LINE__) && return 0;
    foreach my $line_write (@lines_write) {
      print FHR "$line_write";
      #print "$line_write\n";
    }
    close (FHR);
    print "cfg pool found : $pool_file-tmp --> $pool_file\n" if $DEBUG ;
    last;
  }

  # same as above for config.html
  if ( $cfg_load_data_ok == 1 ) {
    open(FCFGR, "< $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
    @lines = <FCFGR>;
    close(FCFGR); 
    my $cfg_section = 0;
    foreach $line (@lines) {
      chomp ($line);
      if ( $line =~ m/Port Level/ || $line =~ m/Rank Level/ || $line =~ m/Volume Level/ ) {
        # the file must contain all 3 sections
        $cfg_section++;
      }
    }

    if ($cfg_section == 3) {
      print "cfg found      : $config_file-tmp --> $config_file\n" if $DEBUG ;
    }
    else {
      if ( $cfg_section > 0 ) {
        main::error ("problem with config file ".__FILE__.":".__LINE__);
      }
      else {
        print "cfg not found  : no config in this data file\n" if $DEBUG ;
      }
    }
    if ( -f "$config_file-tmp" ) {
      rename ("$config_file-tmp","$config_file"); # rename it anyway even if some problem
    }
  }

  close(FH); 
  return 0;
}

sub create_rrd {
  my $rrd = shift;
  my $start_time = shift;
  my $step = shift;
  my $DEBUG= shift;
  my $host = shift;
  my $no_time = shift;
  my $act_time = shift;
  my $type = shift;
  my $st_type = shift;
  my $step_new = $step;
  my $no_time_new = $no_time;

  $start_time = $start_time - 3600; # there must be actual time due to further summing pools and ranks and dealing with NaN

  if (not -f $rrd){
    load_retentions($step,$act_time); # load data retentions
    {
    $type =~ m/^PORT$/ && do {
      #print "0000 - $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd PORT: $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      if ( $st_type =~ m/^SWIZ$/ ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:write_io:GAUGE:$no_time_new:0:100000000"
          "DS:read_io:GAUGE:$no_time_new:0:100000000"
          "DS:io_rate:GAUGE:$no_time_new:0:100000000"
          "DS:data_rate:GAUGE:$no_time_new:0:10000000000"
          "DS:resp_t:GAUGE:$no_time_new:0:1000000"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
          "DS:type:GAUGE:$no_time_new:0:10"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
        );
	# type : FC (0) / SAS (PCIe) (1) / iSCSI (2)
      }
      if ( $st_type =~ m/^DS8K$/ ) {
        if ( $rrd =~ m/rrp$/ ) { 
          # PPRC stats --> *.rrp
          # must be ABSOLUTE data type here for all
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:pprc_rio:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:pprc_wio:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:pprc_data_r:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:pprc_data_w:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:pprc_rt_r:ABSOLUTE:$no_time_new:0:10000000"
          "DS:pprc_rt_w:ABSOLUTE:$no_time_new:0:10000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
          );
        }
        else {
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:io_rate:GAUGE:$no_time_new:0:1000000000"
          "DS:data_rate:GAUGE:$no_time_new:0:10000000000"
          "DS:resp_t:GAUGE:$no_time_new:0:1000000"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
         );
       }
      }
      last;
    };

    $type =~ m/^RANK$/ && do {
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd RANK: $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      if ( rename_only($rrd,$host,$DEBUG) == 1 ) {
        return  0; # rank already exist under different pool ID, it has been renamed
      }
      touch ();
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:read_io:GAUGE:$no_time_new:0:1000000000"
          "DS:write_io:GAUGE:$no_time_new:0:1000000000"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
          "DS:resp_t_r:GAUGE:$no_time_new:0:100000"
          "DS:resp_t_w:GAUGE:$no_time_new:0:100000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };

    $type =~ m/^DRIVE$/ && do {
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd DRIV: $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:read_io:GAUGE:$no_time_new:0:1000000000"
          "DS:write_io:GAUGE:$no_time_new:0:1000000000"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
          "DS:resp_t_r:GAUGE:$no_time_new:0:100000"
          "DS:resp_t_w:GAUGE:$no_time_new:0:100000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };

    $type =~ m/^POOL$/ && do {
      # Pool front-end stats
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd POOL: $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      if ( $st_type =~ m/^DS8K$/ ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:read:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:write:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:read_io:ABSOLUTE:$no_time_new:0:100000000"
          "DS:write_io:ABSOLUTE:$no_time_new:0:100000000"
          "DS:resp_t_r:GAUGE:$no_time_new:0:1000000"
          "DS:resp_t_w:GAUGE:$no_time_new:0:1000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
        );
      }
      else {
        # Storwize only
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
          "DS:read_io:GAUGE:$no_time_new:0:100000000"
          "DS:write_io:GAUGE:$no_time_new:0:100000000"
          "DS:resp_t_r:GAUGE:$no_time_new:0:1000000"
          "DS:resp_t_w:GAUGE:$no_time_new:0:1000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
        );
      }
      last;
    };

    $type =~ m/^VOLUME$/ && do {
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd VOL : $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      if ( $st_type =~ m/^DS5K$/ ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:controller:GAUGE:$no_time_new:0:10"
          "DS:io_total:ABSOLUTE:$no_time_new:0:10000000"
          "DS:io_rate:GAUGE:$no_time_new:0:100000000"
          "DS:data_rate:GAUGE:$no_time_new:0:100000000"
          "DS:cache_hit:GAUGE:$no_time_new:0:1000"
          "DS:r_cache_hit:GAUGE:$no_time_new:0:1000"
          "DS:w_cache_hit:GAUGE:$no_time_new:0:1000"
          "DS:read_pct:GAUGE:$no_time_new:0:1000"
          "DS:ssd_r_cache_hit:GAUGE:$no_time_new:0:1000"
          "DS:resp_t:GAUGE:$no_time_new:0:100000000"
          "DS:used_cap:GAUGE:$no_time_new:0:100000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
        );
      }
      if ( $st_type =~ m/^XIV$/ ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:read_io:GAUGE:$no_time_new:0:100000000"
          "DS:write_io:GAUGE:$no_time_new:0:100000000"
          "DS:resp_t_r:GAUGE:$no_time_new:0:1000000"
          "DS:resp_t_w:GAUGE:$no_time_new:0:1000000"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
          "DS:read_hits:GAUGE:$no_time_new:0:10000000000"
          "DS:write_hits:GAUGE:$no_time_new:0:10000000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
        );
      }
      if ( $st_type =~ m/^SWIZ$/ ) {
        RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:read_io:GAUGE:$no_time_new:0:100000000"
          "DS:write_io:GAUGE:$no_time_new:0:100000000"
          "DS:resp_t_r:GAUGE:$no_time_new:0:1000000"
          "DS:resp_t_w:GAUGE:$no_time_new:0:1000000"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
          "DS:cap:GAUGE:$no_time_new:0:10000000000"
          "DS:cap_real:GAUGE:$no_time_new:0:10000000000"
          "DS:cap_used:GAUGE:$no_time_new:0:10000000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
        );
      }
      if ( $st_type =~ m/^DS8K$/ ) {
        if ( $rrd =~ m/rrc$/ ) {
          # *.rrc --> $r_cache_hit:$w_cache_hit:$resp_t_r:$resp_t_w
          # ABSOLUTE data type is here, data is zeroead after each interval
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:r_cache_hit:GAUGE:$no_time_new:0:10000"
          "DS:w_cache_hit:GAUGE:$no_time_new:0:10000"
          "DS:resp_t_r:GAUGE:$no_time_new:0:1000000"
          "DS:resp_t_w:GAUGE:$no_time_new:0:1000000"
          "DS:read_io:ABSOLUTE:$no_time_new:0:100000000"
          "DS:write_io:ABSOLUTE:$no_time_new:0:100000000"
          "DS:read_b:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:write_b:ABSOLUTE:$no_time_new:0:10000000000"
          "DS:read_io_b:ABSOLUTE:$no_time_new:0:100000000"
          "DS:write_io_b:ABSOLUTE:$no_time_new:0:100000000"
          "DS:resp_t_r_b:GAUGE:$no_time_new:0:1000000"
          "DS:resp_t_w_b:GAUGE:$no_time_new:0:1000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
          );
        }
        else {
          # ABSOLUTE should be also read and write items, unfortunatelly too late discovered therefore devided by $step in CDEF during graphing
          RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:io_rate:GAUGE:$no_time_new:0:100000000"
          "DS:data_rate:GAUGE:$no_time_new:0:10000000000"
          "DS:resp_t:GAUGE:$no_time_new:0:10000"
          "DS:read:GAUGE:$no_time_new:0:10000000000"
          "DS:write:GAUGE:$no_time_new:0:10000000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
          );
        }
      }
      last;
    };

    $type =~ m/^RANKcapacity$/ && do {
      # only for capacity of ranks/pools, once a day data
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd RC  : $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:tot:GAUGE:$no_time_new:0:10000000"
          "DS:used:GAUGE:$no_time_new:0:10000000"
	  "RRA:AVERAGE:0.5:1:$one_day_sample"  
      );
      last;
    };

    $type =~ m/^CPU-CORE$/ && do {
      # only for SWIZ
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd CPU : $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:sys:GAUGE:$no_time_new:0:10000000"
          "DS:compress:GAUGE:$no_time_new:0:10000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };

    $type =~ m/^CPU-NODE$/ && do {
      # only for SWIZ
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd CPU : $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:bussy:GAUGE:$no_time_new:0:10000"
          "DS:lim:GAUGE:$no_time_new:0:10000"
          "DS:sys:GAUGE:$no_time_new:0:10000000"
          "DS:compress:GAUGE:$no_time_new:0:10000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };

    $type =~ m/^POOLcap$/ && do {
      # only for capacity of pools for SVC
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd PC  : Pool capacity: $host:$type $rrd ; STEP=$step_new \n" if $DEBUG;
      touch ();
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:total:GAUGE:$no_time_new:0:10000000000"
          "DS:free:GAUGE:$no_time_new:0:10000000000"
          "DS:virt:GAUGE:$no_time_new:0:10000000000"
          "DS:used:GAUGE:$no_time_new:0:10000000000"
          "DS:real:GAUGE:$no_time_new:0:10000000000"
          "DS:tier0cap:GAUGE:$no_time_new:0:10000000000"
          "DS:tier0free:GAUGE:$no_time_new:0:10000000000"
          "DS:tier1cap:GAUGE:$no_time_new:0:10000000000"
          "DS:tier1free:GAUGE:$no_time_new:0:10000000000"
          "DS:tier2cap:GAUGE:$no_time_new:0:10000000000"
          "DS:tier2free:GAUGE:$no_time_new:0:10000000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };

    $type =~ m/^VOLUMECache$/ && do {
      # only for capacity of pools for SVC
      #print "0000 $five_mins_sample - $one_hour_sample - $five_hours_sample - $one_day_sample\n";
      print "002 $start_time - $step - $rrd\n" if $DEBUG == 2;
      print "create_rrd VC  : Volume cache: $host:$type $rrd ; STEP=$step_new time=$start_time\n" if $DEBUG;
      touch ();
      RRDp::cmd qq(create "$rrd"  --start "$start_time"  --step "$step_new"
          "DS:r_cache_hit:GAUGE:$no_time_new:0:1000"
          "DS:w_cache_hit:GAUGE:$no_time_new:0:1000"
          "DS:r_cache_usage:GAUGE:$no_time_new:0:10000000000"
          "DS:w_cache_usage:GAUGE:$no_time_new:0:10000000000"
          "DS:total_usage:GAUGE:$no_time_new:0:10000000000"
          "DS:res1:GAUGE:$no_time_new:0:10000000000"
          "DS:res2:GAUGE:$no_time_new:0:10000000000"
	  "RRA:AVERAGE:0.5:1:$five_mins_sample"
	  "RRA:AVERAGE:0.5:12:$one_hour_sample"
	  "RRA:AVERAGE:0.5:72:$five_hours_sample"
	  "RRA:AVERAGE:0.5:288:$one_day_sample"
      );
      last;
    };
   }
   my  $mode = 0644;   chmod $mode, "$rrd";

   if (! Xorux_lib::create_check ("file: $rrd, $five_mins_sample, $one_hour_sample, $five_hours_sample, $one_day_sample") ) {
      # $one_minute_sample is avoided here
      main::error ("create_rrd err : unable to create $rrd (filesystem is full?) at ".__FILE__.": line ".__LINE__);
      RRDp::end;
      RRDp::start "$rrdtool";
      return 1;
   }
   return 0;
  }
  return 2; # the rrdtool file already exist
}

# workaround for situation when during LPM move
# those counters appears all 0 on the targed systems what causes
# huge peak in the graph

sub data_check
{
  my $ent = shift;
  my $cap = shift;
  my $uncap = shift;


  if ( ! $ent eq '' ) {
   if ( ! $cap eq '' ) {
    if (  ! $uncap eq '' ) {
      if ( $ent == 0 && $cap == 0 && $uncap == 0) {
        return 1;
      }
    }
   }
  }
  return 0;
}

sub touch
{
  my $version="$ENV{version}";
  my $basedir = $ENV{INPUTDIR};
  my $new_change="$basedir/tmp/$version-run";
  my $host = $ENV{STORAGE_NAME};
  my $DEBUG = $ENV{DEBUG};


  if ( $host eq '' ) {
    $host="na";
  }

  if ( ! -f $new_change ) {
   `touch $new_change`; # say install_html.sh that there was any change
   print "touch          : $host $new_change\n" if $DEBUG ;
  }

  return 0
}


sub load_retentions
{
  my $step=shift;
  my $act_time=shift;
  my $basedir = $ENV{INPUTDIR};

  # standards
  # note this is set up once more  on the top of the file
  $five_mins_sample=25920; # 90 days
  $one_hour_sample=4320;   # 180 days
  $five_hours_sample=1734; # 361 days , in fact 6 hours
  $one_day_sample=1080;    # ~ 3 years

  if ( ! -f "$basedir/etc/retention.cfg" ) {
    # standard retentions in place
    return 0;
  }

  # extra retentions are specifiled in $basedir/etc/retention.cfg
  open(FH, "< $basedir/etc/retention.cfg") || main::error ("Can't read from: $basedir/etc/retention.cfg: $! ".__FILE__.":".__LINE__) && return 0;
  my @lines = <FH>;
  foreach my $line (@lines) {
    chomp ($line);
    if ( $line =~ m/^5min/ ) {
      (my $trash, $five_mins_sample) = split(/:/,$line);
    }
    if ( $line =~ m/^60min/ ) {
      (my $trash, $one_hour_sample) = split(/:/,$line);
    }
    if ( $line =~ m/^300min/ ) {
      (my $trash, $five_hours_sample) = split(/:/,$line);
    }
    if ( $line =~ m/^1440min/ ) {
      (my $trash, $one_day_sample) = split(/:/,$line);
    }
  }

  close (FH);


  # question is how this would work with 5mins step????
  # it would need definitelly some change
  $step = $step / 60;
  $five_mins_sample = $five_mins_sample / $step;
  $one_hour_sample = $one_hour_sample / $step;
  $five_hours_sample = $five_hours_sample / $step;
  $one_day_sample = $one_day_sample / $step;

  return 1;
}

# load capacity usage of ranks (once a day into *.rrc)
sub load_rank_capacity {
  my ($st_type,$wrkdir,$host,$type,$time,$DEBUG,$act_time,$rank_cfg_id_tmp,$pool_cfg_id_tmp,$rank_capacity_tot_tmp,$rank_capacity_used_tmp) = @_;
  my @rank_cfg_id = @{$rank_cfg_id_tmp};
  my @pool_cfg_id = @{$pool_cfg_id_tmp};
  my @rank_capacity_tot = @{$rank_capacity_tot_tmp};
  my @rank_capacity_used = @{$rank_capacity_used_tmp};
  my $step = 86400; # daily
  my $no_time = 2 * $step;

  my $indx = 0;
  my $wrong = 0;
  my $wrong_text = "";

  # Put on the last time possition "0000"!!! --> for smoth updates
  substr($time,6,4,"0000");

  foreach my $r_id (@rank_cfg_id) {
    #print "$rank_cfg_id[$indx]:$pool_cfg_id[$indx]:$rank_capacity_tot[$indx]:$rank_capacity_used[$indx]\n";
    if ( $rank_capacity_tot[$indx] eq '' || $rank_capacity_used[$indx] eq '' ) {
      $wrong_text = $rank_cfg_id[$indx].$pool_cfg_id[$indx];
      next; # something wrong
    }

    my $rrd = "$wrkdir/$host/$type/$rank_cfg_id[$indx]-$pool_cfg_id[$indx]\.rrc";

    #create rrd db if necessary
    if ( create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type."capacity",$st_type) == 1 ) {
      return 2; # leave uit if any error during RRDTool file creation to keep data
    }

    # find out last record in the db
    # as this makes it slowly to test it each time then it is done
    # once per a lpar for whole load and saved into the array
    my $last_rec = 0;
    eval {
      RRDp::cmd qq(last "$rrd" );
      $last_rec = RRDp::read;    
    };
    if ($@) {
      rrd_error($@,$rrd);
      next;
    }
    chomp ($$last_rec);
    my $ltime = $$last_rec;
    $ltime = $ltime + 86400;
    substr($ltime,6,4,"0000");

    if ( isdigit($time) && isdigit ($ltime) && $time > ($ltime + 86000) ) {
      # when rrd db has been created then load data immedistally
      RRDp::cmd qq(update "$rrd" $time:$rank_capacity_tot[$indx]:$rank_capacity_used[$indx]);
      my $answer = RRDp::read; 
    }
    $indx++;
  }

  if ( $wrong == 1 ) {
    main::error ("Rank capacity load error: $wrong_text ".__FILE__.":".__LINE__);
  }

  return 0;
}
sub isdigit
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

  if (length($digit_work) == 0) {
    # is a number
    return 1;
  }

  # NOT a number
  return 0;
}


###################################################
#  SWIZ section : SVC/Storwize
###################################################

sub load_data_svc_all {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, my $st_type) = @_;

  print "updating RRD   : $host:$st_type\n" if $DEBUG ;

  #
  # at first config files like svc01_svcconf_20130904_115351.out
  #

  my $perf_string = "svcconf";
  opendir(DIR, "$wrkdir/$host") || main::error ("directory does not exists : $wrkdir/$host ".__FILE__.":".__LINE__) && return 0;

  my @files_unsorted = grep(/$host\_$perf_string\_20.*out/,readdir(DIR));
  my @files = sort { lc $a cmp lc $b } @files_unsorted;
  closedir(DIR);

  my $in_exist = 0;

  foreach my $file (@files) {
    chomp($file);
    if ( $file =~ m/-tmp$/ ) {
      next; it is not finised inpud data file
    }
    $in_exist = 1;
    my $in_file = "$wrkdir/$host/$file";

    my $ret = load_data_svc_conf ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type);

    if ( $ret == 0 && $KEEP_OUT_FILES == 0 ) {
      unlink ($in_file);  # delete already processed file
      print "remove used    : $host:$in_file\n" if $DEBUG ;
    }

    # It must be called here otherwise HOST info wouild not work
    # once a day there is created svcconfig backup, every other 5minutes small config files without host info
    # it is here to do not overwrite small config info the complete one
    my $type_nick = "HOST";
    LoadDataModule::load_nicks ($type_nick,$wrkdir,$host,$act_time,$st_type,$DEBUG);
  }

  if ( $in_exist == 0 ) {
    print "config file    : $host: no new config input file found\n" if $DEBUG ;
  }

  #
  # now data files like svc01_svcperf_20130904_115351.out
  #

  $perf_string = "svcperf";
  opendir(DIR, "$wrkdir/$host") || main::error ("directory does not exists : $wrkdir/$host  ".__FILE__.":".__LINE__) && return 0;

  @files_unsorted = grep(/$host\_$perf_string\_20.*/,readdir(DIR));
  @files = sort { lc $a cmp lc $b } @files_unsorted;
  closedir(DIR);

  $in_exist = 0;

  foreach my $file (@files) {
    chomp($file);
    if ( $file =~ m/-tmp$/ ) {
      next; it is not finised inpud data file
    }
    $in_exist = 1;
    my $in_file = "$wrkdir/$host/$file";

    my $ret = load_data_svc_perf ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type);

    if ( $ret == 0 && $KEEP_OUT_FILES == 0 ) {
      unlink ($in_file);  # delete already processed file
      print "remove used    : $host:$in_file\n" if $DEBUG ;
    }

    if ( $ret == 2 ) {
      last; # RRD create issue, skip everything until it is resolved (usually caused by full filesystem)
    }
  }

  if ( $in_exist == 0 ) {
    #main::error ("$host: NOTE: no new input files, exiting data load");
    return 1;
  }

  return 0;
}

sub load_data_svc_conf  {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type) = @_;
  my $counter=0;
  my $counter_ins=0;
  my $act_time_u = time();
  my $ltime=localtime($act_time_u);
  my $cfg_load_data_ok = 0; # it is updated when there is found any mdisk, if 0 then something wrong and do not replace config.html

  print "updating RRD   : $host:$in_file\n" if $DEBUG ;
  my $pool_file = "$wrkdir/$host/pool.cfg";
  my $mdisk_file = "$wrkdir/$host/mdisk.cfg";
  my $config_file = "$wrkdir/$host/config.html";
  my $pool_file_write = 0; # true if any write there 
  my $config_file_write = 0; # true if any write there 
  open(FH, "< $in_file") || main::error ("Can't open $in_file : $! ".__FILE__.":".__LINE__) && return 0;
  open(FM, "> $mdisk_file-tmp") || main::error ("Can't open $mdisk_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
  open(FHW, "> $pool_file-tmp") || main::error ("Can't open $pool_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
  open(FCFG, "> $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
  print FCFG "<HTML> <HEAD> <TITLE>STOR2RRD</TITLE> </HEAD> 
	<BODY BGCOLOR=#D3D2D2 TEXT=#000000 LINK=#0000FF VLINK= #000080 ALINK=#FF0000 > 
        <HR><CENTER><B>System overview:</B>(it is generated once a day, last run : $ltime)</CENTER><HR><PRE>\n";

  my @lines = <FH>;
  my $line = "";

  my @pool_name = "";
  my $pool_name_indx = 0;
  my $cfg_print = 1;
  my $mdisk_cfg_processing = 0;

  foreach $line (@lines) {
    #print "$line";
    chomp ($line);

    # print config file
    print FCFG "$line\n";
    $counter_ins++;

    if ( $line =~ m/Managed Disk Level Configuration/ ) {
      $mdisk_cfg_processing = 1;
      next;
    }

    if ( $line =~ m/Configuration/ ) {
      $mdisk_cfg_processing = 0;
    }

    if ($mdisk_cfg_processing) {
      $line =~ s/^0x//;

      if ( $line =~ m/^$/ || $line =~ m/---/ || $line =~ m/^mdisk_id/ ) {
        next; # some trash like "---"
      }

      $cfg_load_data_ok = 1;

      # create an array with mapping table between mdisk and pools
      # mdisk_id,id,name,status,mode,mdisk_grp_id,mdisk_grp_name,capacity,ctrl_LUN_#,controller_name,UID,tier
      (my $mdisk_id, my $id, my $mdisk_name, my $status, my $mode, my $pool_cfg_id_item, my $pool_name_cfg_item) = split(/,/,$line);
      #print "009 $mdisk_cfg_id[$mdisk_cfg_indx] $pool_cfg_id[$mdisk_cfg_indx]\n";
      #print "009 $line\n";

      print FM "$mdisk_id:$mdisk_name\n";
     
      if ( ! defined ($pool_cfg_id_item) || $pool_cfg_id_item eq '' || ! isdigit($pool_cfg_id_item) || $pool_cfg_id_item =~ m/\./ ) {
        next;
      }

      # save actual pool cfg
      my $found = -1;
      foreach my $pool_item (@pool_name) {
        if ( $pool_item =~ m/^$pool_name_cfg_item$/  && ! $pool_name_cfg_item eq '' ) {
          $found = $pool_cfg_id_item;
          last;
        }
      }
      if ( $found == -1 ) {
        $pool_name[$pool_name_indx] = $pool_name_cfg_item;
        $pool_name_indx++;
        print FHW "$pool_cfg_id_item:$pool_name_cfg_item\n";
      }
    }
  }  # foreach

  close (FHW);
  close (FM);
  print FCFG "</pre></body></html>\n";
  close (FCFG);

  if ($counter_ins) {
    print "cfg processed  : $host cfg rows: $counter_ins\n" if $DEBUG ;
  }

  # check if cfg section has been in the input file and pools have been found, if so then replace pool.cfg by pool.cfg-tmp
  if ( ! -f "$pool_file-tmp" ) {
    main::error ("$pool_file-tmp does not exist ".__FILE__.":".__LINE__);
  }
  else {
    open(FHR, "< $pool_file-tmp") || main::error ("Can't open $pool_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
    @lines = <FHR>;
    close(FHR); 
    my @lines_write = sort { (split ':', $a)[0] <=> (split ':', $b)[0] } @lines; #numeric sorting 
  
    foreach $line (@lines) {
      # mean there is at least one row, --> replace
      if ( ! defined($line) || $line eq '' ) {
        next;
      }
      open(FHR, "> $pool_file") || main::error ("Can't open $pool_file : $! ".__FILE__.":".__LINE__) && return 0;
      foreach my $line_write (@lines_write) {
        print FHR "$line_write";
        #print "$line_write";
      }
      close (FHR);
      print "cfg pool found : $pool_file-tmp --> $pool_file\n" if $DEBUG ;
      unlink ("$pool_file-tmp");
      last;
    }
  }

  # check if mdisk.cfg-tmp has any rows, then replace it and sort it out
  if ( ! -f "$mdisk_file-tmp" ) {
    main::error ("$mdisk_file-tmp does not exist ".__FILE__.":".__LINE__);
  }
  else {
    open(FHR, "< $mdisk_file-tmp") || main::error ("Can't open $mdisk_file-tmp : $! ".__FILE__.":".__LINE__) && return 0;
    @lines = <FHR>;
    close(FHR); 
    my @lines_write = sort { (split ':', $a)[0] <=> (split ':', $b)[0] } @lines; #numeric sorting 
  
    foreach $line (@lines) {
      # mean there is at least one row, --> replace
      open(FHR, "> $mdisk_file") || main::error ("Can't open $mdisk_file : $! ".__FILE__.":".__LINE__) && return 0;
      foreach my $line_write (@lines_write) {
        print FHR "$line_write";
        #print "$line_write";
      }
      close (FHR);
      print "cfg mdisk found: $mdisk_file-tmp --> $mdisk_file\n" if $DEBUG ;
      unlink ("$mdisk_file-tmp");
      last;
    }
  }

  # same as above for config.html
  if ( $cfg_load_data_ok == 1 ) {
    if ( ! -f "$config_file-tmp" ) {
      main::error ("$config_file-tmp does not exist ".__FILE__.":".__LINE__);
    }
    else {
      open(FCFGR, "< $config_file-tmp") || main::error ("Can't open $config_file-tmp: $! ".__FILE__.":".__LINE__) && return 0;
      @lines = <FCFGR>;
      close(FCFGR); 
      my $cfg_section = 0;
      foreach $line (@lines) {
        chomp ($line);
        if ( $line =~ m/Pool Level/ || $line =~ m/Drive Level/ ||$line =~ m/Node Level/ ||$line =~ m/Port Level/ || $line =~ m/Managed Disk Level/ || $line =~ m/Volume Level/ ) {
          # the file must contain all 6 sections
          $cfg_section++;
        }
      }
  
      if ($cfg_section == 6) {
        print "cfg found      : $config_file-tmp --> $config_file\n" if $DEBUG ;
      }
      else {
        if ( $cfg_section > 0 ) {
          main::error ("problem with config file number of sections: $cfg_section ".__FILE__.":".__LINE__);
        }
        else {
          print "cfg not found  : no config in this data file\n" if $DEBUG ;
        }
      }
      if ( -f "$config_file-tmp" ) {
        rename ("$config_file-tmp","$config_file"); # rename it anyway even if some problem
      }
    }
  }

  close(FH); 
  return 0;
}

sub load_data_svc_perf  {
  my ($host, $wrkdir, $webdir, $act_time, $step, $DEBUG, $no_time, $in_file, $st_type) = @_;
  my @mdisk_capacity_tot = "";
  my @mdisk_capacity_used = "";
  my $counter_ins=0;
  my $last_rec = "";
  my $rrd ="";
  my $time = "";
  my $t = "";
  my $type = "NA";
  my $t1 = "";
  my $t2 = "";
  my $t3 = "";
  my $t4 = "";
  my $t5 = "";
  my $t6 = "";
  my $t7 = "";
  my $t8 = "";
  my $t9 = "";
  my $t10 = "";
  my $t11 = "";
  my $t12 = "";
  my $act_time_u = time();
  my $ltime=localtime($act_time_u);
  my $cfg_load_data_ok = 0; # it is updated when there is found any mdisk, if 0 then something wrong and do not replace config.html
  my $data_error_first = 0;

  print "updating RRD   : $host:$in_file\n" if $DEBUG ;
  my $pool_file_write = 0; # true if any write there 
  my $config_file_write = 0; # true if any write there 
  open(FH, "< $in_file") || main::error ("Can't open $in_file : $! ".__FILE__.":".__LINE__) && return 0;

  my @lines = <FH>;
  my $line = "";

  my @mdisk_cfg_id = "";
  my @pool_cfg_id = "";
  my $mdisk_cfg_processing = 0;
  my $mdisk_cfg_indx = 0;
  my @pool_name = "";
  my @pool_name_id = "";
  my $pool_name_indx = 0;
  my $port_type_once = 0;
  my $volume_cache_once = 0;
  my $error_once = 0;

  # pool fron-end data from volume data
  my @pool_read = "";
  my @pool_write = "";
  my @pool_io_read = "";
  my @pool_io_write = "";
  my @pool_resp_r = "";
  my @pool_resp_w = "";
  my @pool_ids = "";
  my $pool_time = 0;
  my $pool_ltime = 0;

  #$DEBUG=2;

  foreach $line (@lines) {
    #print "$line";
    chomp ($line);


    if ( $line =~ m/Pool Capacity Statistics/ ) {
      $type = "POOLcap";
      next;
    }
    if ( $line =~ m/Volume Cache Level Statistics/ ) {
      $type = "VOLUMECache";
      next;
    }

    if ( $line =~ m/Level Statistics/ ) {
      $data_error_first = 0;
      (my $type_temp, my $trash) = split(/ /,$line);
      if ( $type_temp =~ m/Managed/ ) {
        $type = "RANK"; #  Managed --> RANK conversion (mdisk --> rank)
      }
      else {
        $type = uc($type_temp);
      }
      next;
    }
    
    if ( $line =~ m/Interval End:/ ) {
      $line =~ s/	//g;
      $line =~ s/Interval End:     //g;
      $line =~ s/GMT.*//g;
      (my $trash1, my $trash2, my $date, my $time_only) = split(/ /,$line);
      $time = str2time($line);
      if ( isdigit ($time) == 0 ) {
        $type = "NA"; # clear out type when empty line
        main::error("no corret time format: $line : $time ".__FILE__.":".__LINE__);
      }
      print "003 $line - $time\n" if $DEBUG == 3;
      next;
    }
     
    if ( $line =~ m/^$/ ) {
      $type = "NA"; # clear out type when empty line
      if ( $pool_time > 0 ) {
        # insert summed pool data based on volume front-end data, it must be even at the enf of that foreach as volumes normally ends the perf file
        if ( $pool_time > $pool_ltime ) {
           $pool_ltime = pool_sum_insert($wrkdir,$step,$DEBUG,$host,$no_time,$act_time,$st_type,$pool_time,$pool_ltime,\@pool_read,\@pool_write,\@pool_io_read,\@pool_io_write,\@pool_resp_r,\@pool_resp_w,\@pool_ids);
        }
        # reinitialize structures
        @pool_ids  = "";
        @pool_read = "";
        @pool_write = "";
        @pool_io_read = "";
        @pool_io_write = "";
        @pool_resp_r = "";
        @pool_resp_w = "";
        $pool_time = 0;
      }
      next;
    }

    if ( $line =~ /^name,id/ || $line =~ m/^	Interval/ || $line =~ m/^-----------/ || $line =~ m/^Node,Time/ || $line =~ m/^Node,cfav/ || $line =~ m/^CPU Core,Time/ || $line =~ m/^Port,Time/ || $line =~ m/^Drive,Time/ || $line =~ m/^Managed Disk ID,Time/ || $line =~ m/^Volume ID,Time/ ) {
      # avoid other trash
      next;
    }

    # Port
    ########################

    if ( $type =~ m/^PORT$/ ){
      print "000 $line\n" if $DEBUG == 3;
      # Port statistics
      (my $name,my $t1,my $t2,my $write_io,my $read_io,my $io_rate,my $write,my $read,my $data_rate,my $t10,my $t11,my $t12,my $t13,my $t14,my $t15,my $t16,my $t17,my $t18,my $t19,my $t20,my $t21,my $t22,my $t23,my $t24,my $t25,my $t26,my $t27,my $t28,my $t29,my $t30,my $t31,my $t32,my $t33,my $t34,my $t35,my $t36,my $t37,my $t38,my $t39,my $t40,my $t41,my $t42,my $t43,my $t44,my $port_type_text)=split(/,/,$line);
      #Port,Time,Interval (s),Port Send IO Rate (IO/s),Port Receive IO Rate (IO/s),Total Port IO Rate (IO/s),Port Send Data Rate (KB/s),Port Receive Data Rate (KB/s)
      #,TotalPort Data Rate (KB/s),Port Send Transfer Size (kB),Port Receive Transfer Size (kB),Overall Port Transfer Size (kB),Port to Host Send IO Rate (IO/s),
      #Port to Host Receive IO Rate (IO/s),Overall Port to Host IO Rate (IO/s),Port to Host Send Data Rate (KB/s),Port to Host Receive Data Rate (KB/s),
      #Overall Port to Host Data Rate (KB/s),Port to Controller Send IO Rate (IO/s),Port to Controller Receive IO Rate (IO/s),Overall Port to Controller IO Rate (IO/s),
      #Port to Controller Send Data Rate (KB/s),Port to Controller Receive Data Rate (KB/s),Overall Port to Controller Data Rate (KB/s),
      #Port to Local Node Send IO Rate (IO/s),Port to Local Node Receive IO Rate (IO/s),Overall Port to Local Node IO Rate (IO/s),Port to Local Node Send Data Rate (KB/s),
      #Port to Local Node Receive Data Rate (KB/s),Overall Port to Local Node Data Rate (KB/s),Port to Remote Node Send IO Rate (IO/s),
      #Port to Remote Node Receive IO Rate (IO/s),Overall Port to Remote Node IO Rate (IO/s),Port to Remote Node Send DataRate (KB/s),
      #Port to Remote Node Receive Data Rate (KB/s),Overall Port to Reomte Node Data Rate (KB/s),Link Failure,Loss of Synch,Loss of Signal,Primitive Sequence Protocol Error,
      #Invalid Transmission Word Count,Invalid CRC Count,Zero b2b (%),Node,Port type,WWPN,FC WWPN,FCoE WWPN,iSCSI IQN,

      #node1_p01,2013-09-04 11:49:19,300,1.25,800.21,801.46,20091.62,10011.64,30103.26,16073.30,12.51,8042.90,0.00,798.96,798.96,20091.62,10011.64,30103.26,0.00,0.00,0.00,
      #0.00,0.00,0.00,1.25,1.25,1.25,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0,0,0,0,0,0,7870,node1,FC,0x5005076802105e40,0x5005076802105e40,,,

      # type : FC / iSCSI / SAS (PCIe)
      my $port_type = 3; # default unknown port type
      if ( ! defined($port_type_text) || $port_type_text eq '' ) {
        if ( $port_type_once == 0 ) {
          main::error ("$host: unknown port type text: $name : $port_type_text : $line ".__FILE__.":".__LINE__);
          $port_type_once = 1;
        }
        next;
      }
      if ( $port_type_text =~ m/^FC$/    ) { $port_type = 0; }
      if ( $port_type_text =~ m/^PCIe$/  ) { $port_type = 1; }
      if ( $port_type_text =~ m/^SAS$/   ) { $port_type = 1; }
      if ( $port_type_text =~ m/^iSCSI$/ ) { $port_type = 2; }
      if ( $port_type_text =~ m/^IPREP$/ ) { $port_type = 4; }
      # IPREP addition ...  replikaci pro asynchronní remote copy.

      if ( $port_type == 3 && $port_type_once == 0 ) {
        # unknown port type detected, print error message just once
        main::error ("$host: unknown port type: $name : $port_type_text : $line ".__FILE__.":".__LINE__);
        $port_type_once = 1;
      }

      #print "001 PORT $name - $write_io - $read_io - $io_rate - $write - $read - $data_rate - type:$port_type:$port_type_text\n";
      print "001 PORT $name - $write_io - $read_io - $io_rate - $write - $read - $data_rate - type:$port_type\n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/$type/$name\.rrd";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }
      #print "001 $rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type\n" if $DEBUG == 3;

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@port_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $port_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $port_name[$l_count] = $rrd;
	  $port_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          #print "005: $name: $ltime - $l_count : $rrd : $port_name[$l_count] - $port_time[$l_count]\n" if $DEBUG == 3;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $port_time[$l_count] = $time;
        $counter_ins++;
        my $resp_t = -1; # not available yet, could be in the next release
        if ( ! defined($read_io) || $read_io eq '' ) {
          $read_io = -1;
        }
        if ( ! defined($read) || $read eq '' ) {
          $read = -1;
        }
        if ( ! defined($write_io) || $write_io eq '' ) {
          $write_io = -1;
        }
        if ( ! defined($write) || $write eq '' ) {
          $write = -1;
        }
        if ( ! defined($resp_t) || $resp_t eq '' ) {
          $resp_t = -1;
        }
        if ( ! defined($io_rate) || $io_rate eq '' ) {
          $io_rate = -1;
        }
        if ( ! defined($data_rate) || $data_rate eq '' ) {
          $data_rate = -1;
        }
        if ( ! defined($port_type) || $port_type eq '' ) {
          $port_type = -1;
        }
        print "004: PORT $time:$write_io:$read_io:$io_rate:$data_rate:$resp_t:$read:$write\n" if $DEBUG == 3;
        if ( ! isdigit($write_io) || ! isdigit($read_io) || ! isdigit($io_rate) || ! isdigit($data_rate) || ! isdigit($resp_t) || ! isdigit($read) ||
             ! isdigit($write) || ! isdigit($port_type) ) {
          if ( $data_error_first == 0 ) {
            main::error("data error in PORT: $time:$write_io:$read_io:$io_rate:$data_rate:$resp_t:$read:$write:$port_type - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$write_io:$read_io:$io_rate:$data_rate:$resp_t:$read:$write:$port_type);
        my $answer = RRDp::read; 

	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
      }
    }

    # RANK == mdisk in SWIZ terminology
    ########################

    if ( $type =~ m/^RANK$/ ){
      print "100 $line\n" if $DEBUG == 3;
      # Rank statistics
      (my $name, $t1, $t2, my $read_io, my $write_io, my $total_io, my $read, my $write, my $total, $t7, $t8, $t9, my $resp_t_r, my $resp_t_w,$t3,$t4,$t5,$t6,$t10,$t11,$t12, my $pool_id) = split(/,/,$line);

      #Managed Disk ID,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),
      #Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Backend Read Response Time (ms),Backend Write Response Time (ms),
      #Overall Backend Response Time (ms),Backend Read Queue Time (ms),Backend Write Queue Time (ms),Overall Backend Queue Time (ms),Peak Read Response Time (ms),
      #Peak Write Response Time(ms),Managed Disk Name,Managed DiskGroup ID,Managed Disk Group Name,Controller ID,Controller Name,Controller WWNN,Controller LUN (Decimal),
      #Controller LUN (Hex),Preferred WWPN,Quorum Index,Tier
      #0000,2013-09-04 11:49:19,300,233.91,20.48,254.40,21633.12,3689.96,25323.08,92.48,180.14,136.31,1.33,11.71,2.17,0.00,0.00,0.00,1.50,41.95,mdisk1,0,PRDSK1_SAS_600,
      # 0,,,0,,,0,generic_hdd,

      # SWIZ has a pool_id directly in each row!!!, DS8K must translate it from the table ...
      if ( ! defined($pool_id) || $pool_id eq '' || ! isdigit($pool_id) || $pool_id =~ m/\./ ) {
        if ( $error_once == 0 ) {
          if ( defined($pool_id) && $pool_id eq '' ) {
            next; # it is a RANK without a pool assigment, skip it quietly ...
          }
          main::error("Wrong pool_id for : $host:$type:$name : $pool_id : the error is reported only once per a run : $line ".__FILE__.":".__LINE__);
          $error_once++;
        }
        next; # something wrong
      }
      $rrd = "$wrkdir/$host/$type/$name-P$pool_id\.rrd";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type)  == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@mdisk_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $mdisk_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $mdisk_name[$l_count] = $rrd;
	  $mdisk_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          print "005: $ltime - $l_count\n" if $DEBUG == 3;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $mdisk_time[$l_count] = $time;
        $counter_ins++;
        if ( ! defined($read_io) || $read_io eq '' ) {
          $read_io = -1;
        }
        if ( ! defined($read) || $read eq '' ) {
          $read = -1;
        }
        if ( ! defined($write_io) || $write_io eq '' ) {
          $write_io = -1;
        }
        if ( ! defined($write) || $write eq '' ) {
          $write = -1;
        }
        if ( ! defined($resp_t_r) || $resp_t_r eq '' ) {
          $resp_t_r = -1;
        }
        if ( ! defined($resp_t_w) || $resp_t_w eq '' ) {
          $resp_t_w = -1;
        }
        print "104: MDISK $time:$read_io:$write_io:$read:$write:$resp_t_r,$resp_t_w\n" if $DEBUG == 3;
        if ( ! isdigit($read_io) || ! isdigit($write_io) || ! isdigit($read) || ! isdigit($write) || ! isdigit($resp_t_r) || ! isdigit($resp_t_w) ) {
          if ( $data_error_first == 0 ) {
            main::error("data error in RANK: $time:$read_io:$write_io:$read:$write:$resp_t_r:$resp_t_w - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$read_io:$write_io:$read:$write:$resp_t_r:$resp_t_w);
        my $answer = RRDp::read; 

	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
      }
    }


    # Volume
    ########################

    if ( $type =~ m/^VOLUME$/ ){
      print "000 $line\n" if $DEBUG == 3;
      # Volume statistics
      (my $name,my $t1,my $t2,my $io_read,my $io_write,my $total_io,my $read,my $write,my $total,my $t3,my $t4,my $t5,my $resp_t_r,my $resp_t_w,my $t6,my $t7,
       my $t8,my $t9,my $t10,my $t11,my $t12,my $t13,my $t14,my $t15,my $pool_id_vol,my $pool_name) = split(/,/,$line);

      #Volume ID,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),
      #Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Read Response Time (ms),Write Response Time (ms),Overall Response Time (ms),
      #Peak Read Response Time (ms),Peak Write Response Time (ms),Host Delay (assuming that all host delay is writes) (ms),Host Delay (assuming that host delay is 
      # evenly spread between read and writes) (ms),Read Hits,Write Hits,Data Read (KB),Data Written (KB),Volume (Vdisk) Name,Managed Disk Group ID,
      #Managed Disk Group Name,IO Group ID,IO Group Name,Remote Copy relationship ID,Remote Copy relationship name,Remote Copy Change Volume relationship,
      #FlashCopy map ID,FlashCopy map name,FlashCopy map count,Copy Count,Space Efficient Copy Count,Cache state,Easy Tier On/Off,Easy Tier Status,Preferred Node ID,
      #Capacity (TB),Real Capacity (TB),Used Capacity (TB),Auto Expand,Grain Size,Throttle Unit,Throttle Rate,UDID (for HPUX)

      #0000,2013-09-04 11:49:19,300,0.10,0.74,0.84,0.05,3.07,3.12,0.50,4.13,2.31,0.83,0.26,0.55,0.00,0.00,0.00,0.00,30.00,223.00,15.00,920.00,A3201023rvg,0,
      # PRDSK1_SAS_600,0,io_grp0,0,,no,0,,0,1,0,not_empty,,,,53687091200.00,0,0,0,0,,,,

      if ( ! defined ($name) || $name eq '' || ! isdigit($name) || $name =~ m/\./ ) {
        next;
      }

      my $cap = -1;
      my $cap_real = -1;
      my $cap_used = -1;
      #my $cache_tot = -1;
      #my $cache_write_usage = -1;
      #my $cache_read_hits = -1;
      #my $cache_write_hits = -1;

      print "001 VOL $name - $io_read - $io_write - $resp_t_r - $resp_t_w - $read - $write\n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/$type/$name\.rrd";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@vol_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $vol_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $vol_name[$l_count] = $rrd;
	  $vol_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
          #print "005: $name: $ltime - $l_count : $rrd : $port_name[$l_count] - $port_time[$l_count]\n" if $DEBUG == 3;
      }

      #print "last : $ltime actuall: $time\n";
      # Update only latest data
      if ( defined ($time) && isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $vol_time[$l_count] = $time;
        $counter_ins++;
        if ( ! defined($io_read) || $io_read eq '' ) {
          $io_read = -1;
        }
        if ( ! defined($read) || $read eq '' ) {
          $read = -1;
        }
        if ( ! defined($io_write) || $io_write eq '' ) {
          $io_write = -1;
        }
        if ( ! defined($write) || $write eq '' ) {
          $write = -1;
        }
        if ( ! defined($resp_t_r) || $resp_t_r eq '' ) {
          $resp_t_r = -1;
        }
        if ( ! defined($resp_t_w) || $resp_t_w eq '' ) {
          $resp_t_w = -1;
        }
        if ( ! defined($cap) || $cap eq '' ) {
          $cap = -1;
        }
        if ( ! defined($cap_real) || $cap_real eq '' ) {
          $cap_real = -1;
        }
        if ( ! defined($cap_used) || $cap_used eq '' ) {
          $cap_used = -1;
        }
        print "004: VOL $time:$io_read:$io_write:$resp_t_r:$resp_t_w:$read:$write:$cap:$cap_real:$cap_used\n" if $DEBUG == 3;
        #print "004: VOL $time:$io_read:$io_write:$resp_t_r:$resp_t_w:$read:$write:$cap:$cap_real:$cap_used\n";
        if ( ! isdigit($io_read) || ! isdigit($io_write) || ! isdigit($resp_t_r) || ! isdigit($resp_t_w) || ! isdigit($read) || ! isdigit($write) ||
             ! isdigit($cap) || ! isdigit($cap_real) || ! isdigit($cap_used)) {
          if ( $data_error_first == 0 ) {
            main::error("data error in VOLUME $time:$io_read:$io_write:$resp_t_r:$resp_t_w:$read:$write:$cap:$cap_real:$cap_used - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$io_read:$io_write:$resp_t_r:$resp_t_w:$read:$write:$cap:$cap_real:$cap_used);
        my $answer = RRDp::read; 

        # keep volume front-end data summ per pool and save it at the end
        #print "099 $pool_id_vol \n";
        if ( defined($pool_id_vol) ) { # this does not work here if pool_id = 0, why?? " && ! $pool_id eq '' "
              # does not do isdigit as there might be 2 ids separated by a space (some mirror copies)
              my $pool_id_multi = 0;
              if ( $pool_id_vol =~ m/ / ) {
                $pool_id_multi = 1;
              }
              #print "900 $pool_id_vol : $pool_id_multi\n";
              foreach my $pool_id_act (split(/ +/,$pool_id_vol)) {
                #print "910 $pool_id_vol : $pool_id_multi : $pool_id_act \n";
                if ( isdigit($pool_id_act) == 0 ) { 
                  next;
                }
                if ( ! defined $pool_read[$pool_id_act]      || $pool_read[$pool_id_act] eq '' )    { $pool_read[$pool_id_act] = 0; }
                if ( ! defined $pool_write[$pool_id_act]     || $pool_write[$pool_id_act] eq '' )   { $pool_write[$pool_id_act] = 0; }
                if ( ! defined $pool_io_read[$pool_id_act]   || $pool_io_read[$pool_id_act] eq '' ) { $pool_io_read[$pool_id_act] = 0; }
                if ( ! defined $pool_io_write[$pool_id_act]  || $pool_io_write[$pool_id_act] eq '' ){ $pool_io_write[$pool_id_act] = 0; }
                if ( ! defined $pool_resp_r[$pool_id_act]    || $pool_resp_r[$pool_id_act] eq '' )  { $pool_resp_r[$pool_id_act] = 0; }
                if ( ! defined $pool_resp_w[$pool_id_act]    || $pool_resp_w[$pool_id_act] eq '' )  { $pool_resp_w[$pool_id_act] = 0; }
                if ( $pool_id_multi == 1 ) {
                  # the volume belongs to 2 pools, some kind of mirror ??
                  # read is half of each, write 100% each
                  #print "98 $pool_id_act : $pool_id_multi : $read $io_read\n";
                  $read = $read / 2;
                  $io_read = $io_read / 2;
                  # $resp_t_r should stay as it is
                  #print "99 $pool_id_act : $pool_id_multi : $read $io_read\n";
                }
                $pool_read[$pool_id_act] += $read;
                $pool_write[$pool_id_act] += $write;
                $pool_io_read[$pool_id_act] += $io_read;
                $pool_io_write[$pool_id_act] += $io_write;
     
                # convert resp time to acumulated time and after all summing devide it by number of IOs
                $pool_resp_r[$pool_id_act] += $resp_t_r * $io_read;
                $pool_resp_w[$pool_id_act] += $resp_t_w * $io_write;
                $pool_time = $time;
                $pool_ids[$pool_id_act] = $pool_id_act;
                #print "100 $pool_id_vol : $pool_id_act : $pool_read[$pool_id_act] $pool_read[$pool_id_act],$pool_write[$pool_id_act],$pool_io_read[$pool_id_act],$pool_io_write[$pool_id_act]\n";
             }
        }
      }
    }

    # Drives
    ########################

    if ( $type =~ m/^DRIVE$/ ){
      print "000 DRIV $line\n" if $DEBUG == 3;
      # Port statistics
      (my $name, my $t1, my $t2, my $io_read, my $io_write, my $total_io, my $read, my $write, my $total, $t3,$t4,$t5, my $resp_t_r, my $resp_t_w) = split(/,/,$line);

      #Volume ID,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),
      #Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Read Response Time (ms),Write Response Time (ms) ....

      #0000,2013-09-04 11:54:19,300,152.89,392.26,545.15,7166.40,12149.28,19315.68,46.87,30.97,38.92,1.95,3.93,3.38,2.92,13.00,10.17,8.35,8.18,11,12,0,,7,
      # mdisk7,,,,,,0,,,,0,0,299462819840.00,0.27,

      if ( ! defined ($name) || $name eq '' || ! isdigit($name) || $name =~ m/\./ ) {
        next;
      }
      print "001 DRIV $name - $io_read - $io_write - $read - $write - $resp_t_r - $resp_t_w\n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/$type/$name\.rrd";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@drive_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $drive_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $drive_name[$l_count] = $rrd;
	  $drive_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
      }
      #print "008 $rrd : $ltime : $time : $found : $l_count \n";

      print "002 DRIV $name - $io_read - $io_write - $read - $write - $resp_t_r - $resp_t_w\n : $time > $ltime" if $DEBUG == 3;
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $drive_time[$l_count] = $time;
        $counter_ins++;
        if ( ! defined($io_read) || $io_read eq '' ) {
          $io_read = -1;
        }
        if ( ! defined($read) || $read eq '' ) {
          $read = -1;
        }
        if ( ! defined($io_write) || $io_write eq '' ) {
          $io_write = -1;
        }
        if ( ! defined($write) || $write eq '' ) {
          $write = -1;
        }
        if ( ! defined($resp_t_r) || $resp_t_r eq '' ) {
          $resp_t_r = -1;
        }
        if ( ! defined($resp_t_w) || $resp_t_w eq '' ) {
          $resp_t_w = -1;
        }
        print "004: DRIV $time:$io_read:$io_write:$read:$write:$resp_t_r:$resp_t_w\n" if $DEBUG == 3;
        if ( ! isdigit($io_read) || ! isdigit($io_write) || ! isdigit($read) || ! isdigit($write) || ! isdigit($resp_t_r) || ! isdigit($resp_t_w) ) {
          if ( $data_error_first == 0 ) {
            main::error("data error in DRIVE: $time:$io_read:$io_write:$read:$write:$resp_t_r:$resp_t_w - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$io_read:$io_write:$read:$write:$resp_t_r:$resp_t_w);
        my $answer = RRDp::read; 
	# to avoid a bug on HMC when it sometimes reports 2 different values for the same time!!
	#$port_time[$l_count] = $t;
      }
    }

    # CPU-Node
    ########################

    if ( $type =~ m/^CPU-NODE$/ ){
      print "000 $line\n" if $DEBUG == 3;
      # Port statistics
      (my $name, my $t1, my $t2, my $cpu_bussy, my $cpu_lim, my $cpu_sys, my $cpu_compress) = split(/,/,$line);

      # Node,Time,Interval,CPU Busy,CPU Limited,CPU Utilization - System,CPU Utilization - Compression,
      # node1,2014-09-01 11:39:43,300,21.224,0.000,21.224,0.006,

      print "001 CPU $name - $cpu_bussy - $cpu_sys - $cpu_compress\n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/$type/$name\.rrd";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@cpun_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $cpun_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $cpun_name[$l_count] = $rrd;
	  $cpun_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $cpun_time[$l_count] = $time;
        $counter_ins++;
        if ( ! defined($cpu_bussy) || $cpu_bussy eq '' ) {
          $cpu_bussy = -1;
        }
        if ( ! defined($cpu_lim) || $cpu_lim eq '' ) {
          $cpu_lim = -1;
        }
        if ( ! defined($cpu_sys) || $cpu_sys eq '' ) {
          $cpu_sys = -1;
        }
        if ( ! defined($cpu_compress) || $cpu_compress eq '' ) {
          $cpu_compress = -1;
        }
        print "004 CPU NODE $cpu_bussy $cpu_lim $cpu_sys $cpu_compress\n" if $DEBUG == 3;
        if ( ! isdigit($cpu_bussy) || ! isdigit($cpu_lim) || ! isdigit($cpu_sys) || ! isdigit($cpu_compress) ) {
          if ( $data_error_first == 0 ) {
            main::error("data error in CPU NODE:$time:$cpu_bussy:$cpu_lim:$cpu_sys:$cpu_compress - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$cpu_bussy:$cpu_lim:$cpu_sys:$cpu_compress);
        my $answer = RRDp::read; 
      }
    }

    # CPU-Core
    ########################

    if ( $type =~ m/^CPU-CORE$/ ){
      print "000 $line\n" if $DEBUG == 3;
      # Port statistics
      (my $name, my $t1, my $t2, my $node, my $id, my $sys, my $compress) = split(/,/,$line);

      #CPU Core,Time,Interval,Node,CPU Core ID,CPU Utilization - System,CPU Utilization - Compression,

      #node1_core00,2013-09-04 11:54:19,300,node1,0,6.77,0.00,
      #node1_core01,2013-09-04 11:54:19,300,node1,1,8.90,0.00,

      print "001 CPU $name - $sys - $compress\n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/$type/$name\.rrd";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@cpuc_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $cpuc_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $cpuc_name[$l_count] = $rrd;
	  $cpuc_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $cpuc_time[$l_count] = $time;
        $counter_ins++;
        if ( ! defined($sys) || $sys eq '' ) {
          $sys = -1;
        }
        if ( ! defined($compress) || $compress eq '' ) {
          $compress = -1;
        }
        print "004 CPU $name - $sys - $compress\n" if $DEBUG == 3;
        if ( ! isdigit($sys) || ! isdigit($compress) ) {
          if ( $data_error_first == 0 ) {
            main::error("data error in CPU: $time:$sys:$compress - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$sys:$compress);
        my $answer = RRDp::read; 
      }
    }

    # Pool capacity
    ########################

    if ( $type =~ m/^POOLcap$/ ){
      print "000 $line\n" if $DEBUG == 3;
      # Port capacity statistics
      (my $name,my $id,my $t9,my $t1,my $t2,my $total,my $t3,my $free,my $virt,my $used,my $real,my $t4,my $t5,my $t6,my $t7,my $t8, my $t14,
       my $tier0cap, my $tier0free, my $t10, my $t11, my $tier1cap, my $tier1free,my $t12, my $t13, my $tier2cap, my $tier2free) = split(/,/,$line);

       #name,id,status,mdisk count,volume count,capacity (TB),extent size,free capacity (TB),virtual capacity (TB),used capacity (TB),real capacity (TB),
       #overallocation,warning (%),easy tier,easytier status,TIER-0 type,TIER-0 mdisk count,TIER-0 capacity (TB),TIER-0 free capacity (TB),TIER-1 type,
       #TIER-1 mdisk count,TIER-1 capacity (TB),TIER-1 free capacity (TB),TIER-2 type,TIER-2 mdisk count,TIER-2 capacity (TB),TIER-2 free capacity (TB),
       #compression active,compression virtual capacity (TB),compression compressed capacity (TB),compression uncompressed capacity (TB)

       #XXXXXX_SAS_300,2,online,2,14,2.450,256,0.700,1.750,1.750,1.750,71,80,auto,active,generic_ssd,1,0.272,0.000,generic_hdd,1,2.177,0.700,,0,0.000,0.000,no,0.000,0.000,0.000,

      if ( ! defined ($id) || $id eq '' || ! isdigit($id) || $id =~ m/\./ ) {
        next; # to be save against cooruptions in the input file!!!
      }

      print "001 POOL cap : $name - $id - $total - $free - $virt - $used - $real \n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/POOL/$id-cap\.rrd";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@pool_cap_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $pool_cap_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $pool_cap_name[$l_count] = $rrd;
	  $pool_cap_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $pool_cap_time[$l_count] = $time;
        $counter_ins++;
        if ( ! defined($total) || $total eq '' ) {
          $total = -1;
        }
        if ( ! defined($free) || $free eq '' ) {
          $free = -1;
        }
        if ( ! defined($virt) || $virt eq '' ) {
          $virt = -1;
        }
        if ( ! defined($used) || $used eq '' ) {
          $used = -1;
        }
        if ( ! defined($real) || $real eq '' ) {
          $real = -1;
        }
        if ( ! defined($tier0cap) || $tier0cap eq '' ) {
          $tier0cap = -1;
        }
        if ( ! defined($tier0free) || $tier0free eq '' ) {
          $tier0free = -1;
        }
        if ( ! defined($tier1cap) || $tier1cap eq '' ) {
          $tier1cap = -1;
        }
        if ( ! defined($tier1free) || $tier1free eq '' ) {
          $tier1free = -1;
        }
        if ( ! defined($tier2cap) || $tier2cap eq '' ) {
          $tier2cap = -1;
        }
        if ( ! defined($tier2free) || $tier2free eq '' ) {
          $tier2free = -1;
        }
        print "004 POOL cap : $name - $id - $total - $free - $virt - $used - $real TIERS: $tier0cap:$tier0free $tier1cap:$tier1free $tier2cap:$tier2free\n" if $DEBUG == 3;
        if ( ! isdigit($total) || ! isdigit($free) || ! isdigit($virt) || ! isdigit($used) || ! isdigit($real) || ! isdigit($tier0cap) ||
             ! isdigit($tier0free) || ! isdigit($tier1cap) || ! isdigit($tier1free) || ! isdigit($tier2cap) || ! isdigit($tier2free) ) {
          if ( $data_error_first == 0 ) {
            main::error("data error in POOL cap: $time:$total:$free:$virt:$used:$real:$tier0cap:$tier0free:$tier1cap:$tier1free:$tier2cap:$tier2free - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$total:$free:$virt:$used:$real:$tier0cap:$tier0free:$tier1cap:$tier1free:$tier2cap:$tier2free);
        my $answer = RRDp::read; 
      }
    }

    # Volume cache 
    ########################

    if ( $type =~ m/^VOLUMECache$/ ){
      print "000 $line\n" if $DEBUG == 3;
      # Port capacity statistics
      (my $id, my $t1, my $t2, my $t3, my $rcache_hit, my $wcache_hit,my $rcache_usage, my $wcache_usage, my $totcache_usage) = split(/,/,$line);

      # Volume ID,Time,Interval (s),Volume (Vdisk) Name,Cache read hits (%),Cache write hits (%),Read cache usage (kB),Write cache usage (kB),Total cache usage (kB),
      #  Cache data prestaged (kB/s),Cache data destaged (kB/s),Cache read hits (%),Cache read hits on prestaged data (%),Cache write hits on dirty data (%),
      #  Cache writes in Flush Through mode (kB/s),Cachewrites in Write Through mode (kB/s),Cache writes in Fast Write mode (kB/s),
      #  Cache writes in Fast Write mode that were written in Write Through mode due to the lack of memory (kB/s),

      #0000,2013-10-17 21:01:52,300,XXXXX00vg,30.742,36.165,2708,0,2708,5.760,27.253,30.742,25.442,36.165,0.000,0.000,42.693,0.000,

      if ( ! defined ($id) || $id eq '' || ! isdigit($id) || $id =~ m/\./ ) {
        next;
      }

      print "001 VOLUMECache: $id - $rcache_hit - $wcache_hit - $rcache_usage - $wcache_usage - $totcache_usage \n" if $DEBUG == 3;
      $rrd = "$wrkdir/$host/VOLUME/$id\.rrc";

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      my $l;
      my $l_count = 0;
      my $found = -1;
      my $ltime;
      foreach $l (@volume_cache_name) {
        if ($l =~ m/^$rrd$/ ) {
          $found = $l_count;		
          last;
        }
       $l_count++;
      }
      if ( $found > -1) {
        $ltime = $volume_cache_time[$found];
      }
      else {
  	  # find out last record in the db
	  # as this makes it slowly to test it each time then it is done
	  # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;    
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
	  chomp ($$last_rec);
	  chomp ($$last_rec);
	  $volume_cache_name[$l_count] = $rrd;
	  $volume_cache_time[$l_count] = $$last_rec;
          $ltime = $$last_rec;
      }
      #print "009 $found : $ltime : $rrd : $volume_cache_name[$l_count] : $volume_cache_time[$l_count]\n";

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $ltime ) {
        $volume_cache_time[$l_count] = $time;
        $counter_ins++;
        print "004 VOLUMECache: $id - $rcache_hit - $wcache_hit - $rcache_usage - $wcache_usage - $totcache_usage - $time\n" if $DEBUG == 3;
        my $reserve1 = -1; # to get NaN there
        my $reserve2 = -1;
        if ( ! defined($rcache_hit) || $rcache_hit eq '' ) {
          $rcache_hit = -1;
        }
        if ( ! defined($wcache_hit) || $wcache_hit eq '' ) {
          $wcache_hit = -1;
        }
        if ( ! defined($rcache_usage) || $rcache_usage eq '' ) {
          $rcache_usage = -1;
        }
        if ( ! defined($wcache_usage) || $wcache_usage eq '' ) {
          $wcache_usage = -1;
        }
        if ( ! defined($totcache_usage) || $totcache_usage eq '' ) {
          $totcache_usage = -1;
        }
        #print "005 VOLUMECache: $id - $rcache_hit - $wcache_hit - $rcache_usage - $wcache_usage - $totcache_usage - $time\n";
        if ( ! isdigit($rcache_hit) || ! isdigit($wcache_hit) || ! isdigit($rcache_usage) || ! isdigit($wcache_usage) || ! isdigit($totcache_usage) || 
             ! isdigit($reserve1) || ! isdigit($reserve2) ) {
          if ( $data_error_first == 0 ) {
            main::error("data error in VOLUMECache: $time:$rcache_hit:$wcache_hit:$rcache_usage:$wcache_usage:$totcache_usage:$reserve1:$reserve2 - $line ".__FILE__.":".__LINE__);
            $data_error_first = 1;
            $counter_ins--;
          }
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$rcache_hit:$wcache_hit:$rcache_usage:$wcache_usage:$totcache_usage:$reserve1:$reserve2);
        my $answer = RRDp::read; 
      }
    }

    # Node Cache
    ########################

    if ( $type =~ m/NODE-CACHE/ ){
      print "000 $type: $line \n" if $DEBUG == 3;
      next; # not implemented so far
    }
  }  # foreach

  # insert summed pool data based on volume front-end data, it must be even at the enf of that foreach as volumes normally ends the perf file
  if ( $pool_time > $pool_ltime ) {
    pool_sum_insert($wrkdir,$step,$DEBUG,$host,$no_time,$act_time,$st_type,$pool_time,$pool_ltime,\@pool_read,\@pool_write,\@pool_io_read,\@pool_io_write,\@pool_resp_r,\@pool_resp_w,\@pool_ids);
  }


  if ($counter_ins) {
    print "inserted       : $host $counter_ins record(s)\n" if $DEBUG ;
  }

  # write down timestamp of last record , not for daily avg from HMC
  open(FHLT, "> $wrkdir/$host/last_rec") || main::error ("Can't open $wrkdir/$host/last_rec : $! ".__FILE__.":".__LINE__) && return 0;
  print FHLT "$time";
  close(FHLT);

  close(FH); 
  return 0;
}

sub rrd_error
{
  my $err_text = shift;
  my $rrd_file = shift;
  my $basedir = $ENV{INPUTDIR};
  my $tmpdir = "$basedir/tmp";
  if (defined $ENV{TMPDIR_STOR}) {
    $tmpdir = $ENV{TMPDIR_STOR};
  }

  chomp ($err_text);

  if ( ! -f "$rrd_file" ) {
    return 0;
  }

  if ( $err_text =~ m/ERROR:/ ) {
    # copy of the corrupted file into "save" place and remove the original one
    copy ("$rrd_file","$tmpdir/") || main::error("Cannot: cp $rrd_file $tmpdir/: $! ".__FILE__.":".__LINE__);
    unlink("$rrd_file") || main::error("Cannot rm $rrd_file : $! ".__FILE__.":".__LINE__);
    main::error("$err_text, moving it into: $tmpdir/ ".__FILE__.":".__LINE__);
  }
  else {
    main::error("$err_text ".__FILE__.":".__LINE__);
  }
  return 0;
}

# check if RANK already does not exist under different POOL ID, if so then rename it and do not create a new rrd file
sub rename_only
{ 
  my $rrd = shift;
  my $host = shift;
  my $DEBUG = shift;

  my $rrd_find = $rrd;
  $rrd_find =~ s/-P[0-9][0-9]*\.rrd/-P\*\.rrd/;  # preparing search string

  my $rank_found_file = "";
  my $rank_found_time = 0;
  foreach my $file (<$rrd_find*>) {
    if ( $file !~ m/-P[0-9][0-9]*\.rrd/ ) {
      next; # exlude 0001-P.rrd --> ranks without valid pool ID
    }
    my $file_time = (stat("$file"))[9];
    if ( $file_time > $rank_found_time ) {
      # if more old rank files the select the most recent
      $rank_found_time = $file_time;
      $rank_found_file = $file;
    }
  }

  if ($rank_found_time > 0 ) {
    # rename it
    print "RANK rename    : $host $rank_found_file --> $rrd\n" if $DEBUG ;
    if ( -f "$rank_found_file" ) {
      rename("$rank_found_file","$rrd") || main::error(" Cannot mv $rank_found_file $rrd: $!".__FILE__.":".__LINE__) && return 0;
    }
    return 1;
  }
  return 0;
}

sub pool_sum_insert
{
  my ($wrkdir,$step,$DEBUG,$host,$no_time,$act_time,$st_type,$time,$ltime,$read_tmp,$write_tmp,$io_read_tmp,$io_write_tmp,$resp_r_tmp,$resp_w_tmp,$pool_ids_tmp) = @_;

  my @pool_ids = @{$pool_ids_tmp};
  my @read = @{$read_tmp};
  my @write = @{$write_tmp};
  my @io_read = @{$io_read_tmp};
  my @io_write = @{$io_write_tmp};
  my @resp_t_r = @{$resp_r_tmp};
  my @resp_t_w = @{$resp_w_tmp};
  my $type = "POOL";
  my $last_rec = $ltime;
  my $count = 0;

  print "POOL front-end : $host\n" if $DEBUG ;

  foreach my $pool_id (@pool_ids) {
      if ( ! defined($pool_id) || $pool_id eq '' ) {
        next; # there is a gap in pool id row, no problem at all ...
      }
      # pool by pool
      if ( ! defined($read[$pool_id]) || $read[$pool_id] eq '' || ! isdigit($read[$pool_id]) ) {
        $read[$pool_id] = -1;
      }
      if ( ! defined($write[$pool_id]) || $write[$pool_id] eq '' || ! isdigit($write[$pool_id]) ) {
        $write[$pool_id] = -1;
      }
      if ( ! defined($io_read[$pool_id]) || $io_read[$pool_id] eq '' || ! isdigit($io_read[$pool_id]) ) {
        $io_read[$pool_id] = -1;
      }
      if ( ! defined($io_write[$pool_id]) || $io_write[$pool_id] eq '' || ! isdigit($io_write[$pool_id]) ) {
        $io_write[$pool_id] = -1;
      }
      if ( ! defined($resp_t_r[$pool_id]) || $resp_t_r[$pool_id] eq '' || ! isdigit($resp_t_r[$pool_id]) ) {
        $resp_t_r[$pool_id] = -1;
      }
      if ( ! defined($resp_t_w[$pool_id]) || $resp_t_w[$pool_id] eq '' || ! isdigit($resp_t_w[$pool_id]) ) {
        $resp_t_w[$pool_id] = -1;
      }

      if ( $io_read[$pool_id] != 0 ) {
        $resp_t_r[$pool_id] = $resp_t_r[$pool_id] / $io_read[$pool_id];
      }
      else {
        $resp_t_r[$pool_id] = 0;
      }
      if ( $io_write[$pool_id] != 0 ) {
        $resp_t_w[$pool_id] = $resp_t_w[$pool_id] / $io_write[$pool_id];
      }
      else {
        $resp_t_w[$pool_id] = 0;
      }
      my $rrd = "$wrkdir/$host/$type/$pool_id\.rrd"; 

      #create rrd db if necessary
      if (create_rrd($rrd,$time,$step,$DEBUG,$host,$no_time,$act_time,$type,$st_type) == 1 ) {
        return 2; # leave uit if any error during RRDTool file creation to keep data
      }

      if ( $ltime == 0 ) {
          # find out last record in the db
          # as this makes it slowly to test it each time then it is done
          # once per a lpar for whole load and saved into the array
          eval {
            RRDp::cmd qq(last "$rrd" );
            $last_rec = RRDp::read;
          };
          if ($@) {
            rrd_error($@,$rrd);
            next;
          }
          chomp ($$last_rec);
      }

      #print "last : $ltime $$last_rec  actuall: $t\n";
      # Update only latest data
      if ( isdigit($time) && isdigit ($ltime) && $time > $$last_rec ) {
        #print "004: pool_id:$pool_id - $time:$io_read[$pool_id]:$io_write[$pool_id]:$read[$pool_id]:$write[$pool_id]:$resp_t_r[$pool_id]:$resp_t_w[$pool_id]\n";
        if ( ! isdigit($read[$pool_id]) || ! isdigit($write[$pool_id]) || ! isdigit($io_read[$pool_id]) || ! isdigit($io_write[$pool_id]) || 
             ! isdigit($resp_t_r[$pool_id]) || ! isdigit($resp_t_w[$pool_id]) ) {
          main::error("data error in POOL front-end: $time:$read[$pool_id]:$write[$pool_id]:$io_read[$pool_id]:$io_write[$pool_id]:$resp_t_r[$pool_id]:$resp_t_w[$pool_id]");
          next;
        }
        RRDp::cmd qq(update "$rrd" $time:$read[$pool_id]:$write[$pool_id]:$io_read[$pool_id]:$io_write[$pool_id]:$resp_t_r[$pool_id]:$resp_t_w[$pool_id]);
        my $answer = RRDp::read;
        $ltime = $time if ! $$answer;
        $count++;
      }
      #print "003 --$pool_id-- $read[$pool_id] - $write[$pool_id] - $io_read[$pool_id] - $io_write[$pool_id] - $resp_t_r[$pool_id] - $resp_t_w[$pool_id]\n";
  }
  print "POOL front-end : $host inserted: $count\n" if $DEBUG ;

  return $ltime;
}


# It loads volumes nicks from config.html and sort them out and save them into VOLUME/volumes.cfg

sub load_nicks
{
  my $subsystem = shift; # volume, host
  my $wrkdir = shift;
  my $host = shift;
  my $act_time = shift;
  my $st_type = shift;
  my $DEBUG = shift;

  my @vol_nicks = "";
  my @vol_id = "";

  if ( defined $ENV{DEMO} && ($ENV{DEMO} == 1)) {
   print "\n";
   print "DEMO is set, do not update por create volumes.cfg and hosts.cfg\n";
   print "\n";
   return 1; # skip it on the demo site
  }


  print "load nicks     : $host\n" if $DEBUG ;
  open(FHN, "< $wrkdir/$host/config.html") || main::error ("$host: Can't open $wrkdir/$host/config.html (fresh install or upgrade?, then it is ok): $! ".__FILE__.":".__LINE__) && return 0;

  my @lines = <FHN>;
  my @lines_valid = "";

  my $line = "";
  my $found = 0;
  my $indx = 0;

  # host search strings
  my $search_head = "host_id,";
  my $search_head_1 = "host_id,";
  if ( $subsystem =~ m/VOLUME/ ) {
    $search_head = "Volume ID,"; # DS8k
    $search_head_1 = "volume_id,"; # storwize
  }

  foreach $line (@lines) {
    chomp ($line);
    if ( $line =~ m/^$search_head/ || $line =~ m/^$search_head_1/) {
      $found = 1;
      next;
    }
    if ( $found == 0 ) {
      next;
    }
    if ( $found == 1 ) {
      if ( $line eq '' || $line =~ m/<\/html>/ || $line =~ m/Level Configuration/ || $line =~ m/------------------/ ) {
        last;
      }
    }
    $lines_valid[$indx] = $line;
    $indx++;
  }
  close (FHN);

  if ($indx == 0 && $subsystem !~ m/HOST/ ) {
    # host info is loaded once a day!!!
    main::error("Problem with configuration load, no $subsystem has been found, is there really exist one? : $wrkdir/$host/config.html ".__FILE__.":".__LINE__);
    return 0; # ignore the rest as there is not really volume cfg
  }

  # sort per nicks
  @lines_valid = sort { (split ',', $a)[2] cmp (split ',', $b)[2] } @lines_valid;
  $found = 0;
  $indx = 0;
  my $vols = 0;

  my @host_nicks = "";
  my @host_id = 0;

  foreach $line (@lines_valid) {
    chomp ($line);

    $vols++;
    if ( $line eq '' ) {
      next;
    }

    my $id = -1;
    my $nick = "na";
    my $ids = "";
    ($id, my $sn, $nick, my $t1, my $t2, my $t3, my $t4, $ids) = split(/,/,$line);
    # DS8K
    # Volume ID,Volume SN,Volume Nickname,LSS Number,Volume Number,Volume Size,Volume Type
    # 0x0000,IBM.2107-75ANM81/0000,INPH10,0x00,0x00,1.000000,FB 512
    # SVC
    # volume_id,id,name,IO_group_id,IO_group_name,status,mdisk_grp_id,mdisk_grp_name,capacity,type,FC_id,FC_name,RC_id,RC_name,
    #    vdisk_UID,fc_map_count,copy_count,fast_write_state,se_copy_count, RC_change,compressed_copy_count
    # 0000,0,A3105005rvg,0,io_grp0,online,1,PMDSK1_SAS_600,128849018880,striped,,,,,600507680280827CA800000000000000,0,1,empty,0,no,0
    # DS5K
    # ,,ASRV11LPAR7,,,,,60080e500018469e00000f2d4d885cf0 60080e500018450a0000aed84dccba79 

    #host_id,id,name,port_count,iogrp_count,status,WWPN,Volume IDs,Volume Names
    #0002,2,pmnim1,2,4,online,10000000C9FD5FF4 10000000C9FD3784,57 58 59 60,pmnim1bvg1 pmnim1bvg2 pmnim1bvg3 pmnim1bvg4


    if ( ! defined($nick) ) {
      next; # somehing strange ...
    }

    if ( $subsystem =~ m/HOST/ ) {
      if ( $nick eq '' ) {
        next; # somehing strange ...
      }
      if ( ! defined($ids) ) {
        $ids = "";
      }
      $ids =~ s/ 0x/ /g; # filter hexa prefix
      $ids =~ s/^0x//;   # filter hexa prefix
      $host_nicks[$indx] = $nick;
      $host_id[$indx] = $ids;
      $indx++;
    }

    if ( $subsystem =~ m/VOLUME/ ) {
      if ( ! defined($id) || $id eq '' ) {
        next; # somehing strange ...
      }
      if ( $nick eq '' ) {
        $nick = $id;
      }

      if ( $vol_nicks[$indx] eq '' ) {
        # only for the first run!
        $vol_nicks[$indx] = $nick;
        $vol_id[$indx] = $id.";";
        next;
      }
    

      if ( $vol_nicks[$indx] =~ m/^$nick/ ) {
        $vol_id[$indx] .= $id.";";
      }
      else {
        $indx++;
        $vol_nicks[$indx] = $nick;
        $vol_id[$indx] = $id.";";
        #print "$vol_nicks[$indx] $vol_id[$indx] \n";
      }
    }
  }

  # save old structure, in install-html.sh make a diff and when anything diff then run install-html.sh
  # convert the string to lowercase
  my $subsystem_low = lc $subsystem;

  my $subsystem_file = $subsystem_low."s.cfg";
  copy ("$wrkdir/$host/$subsystem/$subsystem_file","$wrkdir/$host/$subsystem/$subsystem_file-old");
    
  # save structured and grouped volumes per their nick
  open(FHW, "> $wrkdir/$host/$subsystem/$subsystem_file-act") || main::error ("$host: Can't open $wrkdir/$host/$subsystem/$subsystem_file-act: $! ".__FILE__.":".__LINE__) && return 0;
  $indx = 0;
  if ( $subsystem =~ m/VOLUME/ ) {
    @host_nicks = @vol_nicks;
  }

  foreach $line (@host_nicks) {
    if ( $line eq '' ) {
      next;
    }
    if ( $subsystem =~ m/VOLUME/ ) {
      print FHW "$line : $vol_id[$indx] \n";
    }
    else {
      print FHW "$line : $host_id[$indx] \n";
    }
    $indx++;
  }
  close (FHW);

  if ( $indx ==  0 ) {
    return 1; # nothing has been found, it could be for HOST info which is downloaded just once a day
  }

  unlink ("$wrkdir/$host/$subsystem/$subsystem_file");
  if ( -f "$wrkdir/$host/$subsystem/$subsystem_file-act" ) {
    rename ("$wrkdir/$host/$subsystem/$subsystem_file-act","$wrkdir/$host/$subsystem/$subsystem_file");
  }
  print "loaded nicks   : $host $indx ($subsystem_low: $vols) \n" if $DEBUG ;

  my $diff = compare("$wrkdir/$host/$subsystem/$subsystem_file","$wrkdir/$host/$subsystem/$subsystem_file-old");

  if ( $diff > 0 ) {
     print "$subsystem_low cfg changed: $diff \n" if $DEBUG ;
     LoadDataModule::touch ();
  }

  return 0;
}

return 1;

