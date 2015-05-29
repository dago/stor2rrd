#!/usr/bin/perl -w
#
# v0.2.9

# Modules
use strict;
use Storable;
use Data::Dumper;
use Date::Parse;

# Options and their default value
my $wbemcli_cmd    = "/usr/bin/wbemcli";
my $storname;                   # XIV storage alias
my $xivip;                      # XIV host name (IP address)
my $xivuser        = "info";    # XIV user name
my $xivpwd         = "";        # XIV user password
my $mininterval    = 300;       # minimal interval time for data collection (sec)
my $dir            = "..";      # Data directory

my $debug          = 0;         # Debug mode 0:off, 1:on
my $debug_full     = 0;         # Debug mode 0:off, 1:on

if (defined $ENV{WBEMCLI_CMD} && -f $ENV{WBEMCLI_CMD}) {
  $wbemcli_cmd = $ENV{WBEMCLI_CMD};
}
if ( ! -f $wbemcli_cmd ) {
  $wbemcli_cmd = "/opt/freeware/bin/wbemcli";
}
if ( ! -f $wbemcli_cmd ) {
  $wbemcli_cmd = "/usr/local/bin/wbemcli";
}

my $bindir = $ENV{BINDIR};
if (defined $ENV{STORAGE_NAME}) {
	$storname = $ENV{STORAGE_NAME};
} else {
	print("xivperf.pl: XIV storage name alias is required.\n");
	exit(1);
}
if (defined $ENV{XIV_IP}) {
	$xivip = $ENV{XIV_IP};
} else {
	print("xivperf.pl: XIV host name or IP address is required.\n");
	exit(1);
}
if (defined $ENV{XIV_USER}) { $xivuser	= $ENV{XIV_USER} }
if (defined $ENV{XIV_PASSWD}) { $xivpwd = $ENV{XIV_PASSWD} }
if (defined $ENV{XIV_DIR}) { $dir = $ENV{XIV_DIR} }
if (defined $ENV{DEBUG}) { $debug = $ENV{DEBUG} }
if (defined $ENV{DEBUG_FULL}) { $debug_full = $ENV{DEBUG_FULL} }

my $tmpdir = "$dir/";       # Directory for temporary files

my $out_perf_file;          #
my $out_conf_file;          #
my $cacheFile = $tmpdir."cache.file";



my @RAW_COUNTERS = ('StatisticTime', 'KBytesRead', 'KBytesWritten', 'KBytesTransferred', 'ReadIOs', 'WriteIOs', 'TotalIOs', 'IOTimeCounter', 'ReadIOTimeCounter', 'WriteIOTimeCounter');
my @VOLUME_COUNTERS = ('ReadRateKB', 'WriteRateKB', 'TotalRateKB', 'ReadIORate', 'WriteIORate', 'TotalIORate', 'ReadIOTime', 'WriteIOTime', 'ReadIOPct');

my $storage;
my $cache;
my $data;
my $config;
my $tzoffset;

sub message {
	my $msg = shift;
	my $tm = localtime();
	print("INFO ".$tm." xivperf.pl: ".$msg."\n");
}

sub warning {
	my ($msg,$rc) = @_;
	my $tm = localtime();
	print STDERR ("WARNING ".$tm." xivperf.pl: ".$msg."\n");
}

sub error {
	my ($msg,$rc) = @_;
	my $tm = localtime();
	print STDERR ("ERROR ".$tm." xivperf.pl: ".$msg."\n");
}

sub wbemcli {
	my ($op, $objpath) = @_;
	`$wbemcli_cmd -noverify $op $objpath`;
}


sub wbemclinl {
	my ($op, $objpath) = @_;
	`$wbemcli_cmd -noverify -nl $op $objpath`;
}

sub enumStorage {
	my $elementClass = shift;
	my %storage;
	my $timeout = $ENV{SAMPLE_RATE};
	if ( $timeout eq '' ) {
    	$timeout = 900;
	} else {
    	$timeout = $timeout * 3;
	}
	eval {
		# Set alarm
    	my $act_time = localtime();
    	local $SIG{ALRM} = sub { die("$act_time: died in SIG ALRM");};
    	alarm($timeout);

		# Get Element Storage
		my $objectPath = "https://".$xivuser.":".$xivpwd."@".$xivip.":5989/root/ibm:".$elementClass;
		if ($debug_full) {message("+$wbemcli_cmd -noverify -nl ei ".$objectPath."."); }
		for my $line ( &wbemclinl("ei",$objectPath) ) {
			chomp($line);
			if(not $line =~ /=/) {next;}
			my @a = split("=",$line);
			if ( $a[0] ) {
				if ( $a[0] =~ /^-(.*)$/ ) { $a[0] = $1; }
				if ( $a[1] ) { $a[1] =~ s/"//g; }
				$storage{$a[0]} = $a[1];
			}
		}
		# end of alarm
    	alarm(0);
	};
	if ($@) {
    	if ($@ =~ /died in SIG ALRM/) {
        	error("command timed out after : $timeout seconds");
        	exit (1);
    	}
	}

	return \%storage;
}

sub enumNames {
	my $elementClass = shift;
	my %names;
	my $timeout = $ENV{SAMPLE_RATE};
	if ( $timeout eq '' ) {
    	$timeout = 900;
	} else {
    	$timeout = $timeout * 3;
	}
	eval {
		# Set alarm
    	my $act_time = localtime();
    	local $SIG{ALRM} = sub {die "$act_time: died in SIG ALRM";};
    	alarm($timeout);

		# Get Element Names
		my $objectPath = "https://".$xivuser.":".$xivpwd."@".$xivip.":5989/root/ibm:".$elementClass;
		if ($debug_full) {message("+$wbemcli_cmd -noverify ei ".$objectPath."."); }
		for my $line ( &wbemcli("ei",$objectPath) ) {
			chomp($line);
			my @a = split(",",$line);
			my $id; my $name;
			foreach my $elem ( @a ) {
				if    ( $elem =~ /^InstanceID="([-:.\w]*)"$/    ) { $id = $1; }
				elsif ( $elem =~ /^ElementName="([-.\w]+)"$/ ) { $name = $1; }
			}
			if ( $id ) {
				$names{$id} = $name;
			}
		}
		# end of alarm
    	alarm(0);
	};
	if ($@) {
    	if ($@ =~ /died in SIG ALRM/) {
        	error("command timed out after : $timeout seconds");
        	exit (1);
    	}
	}
	return \%names;
}

sub enumStats {
	my $elementClass = shift;
	my @stats;
	my $timeout = $ENV{SAMPLE_RATE};
	if ( $timeout eq '' ) {
    	$timeout = 900;
	} else {
    	$timeout = $timeout * 3;
	}
	eval {
		# Set alarm
    	my $act_time = localtime();
    	local $SIG{ALRM} = sub {die "$act_time: died in SIG ALRM";};
    	alarm($timeout);
		# Get Element Statistics
		my $objectPath = "https://".$xivuser.":".$xivpwd."@".$xivip.":5989/root/ibm:".$elementClass;
		if ($debug_full) {message("+$wbemcli_cmd -noverify ei ".$objectPath."."); }
		for my $line ( &wbemcli("ei",$objectPath) ) {
			chomp($line);
			my @a = split(",",$line);
			my $id; my $name; my %st;
			foreach my $elem ( @a ) {
				if    ( $elem =~ /^(\w+)="(.*)"$/ ) { $st{$1} = $2; }
				elsif ( $elem =~ /^(\w+)=(.*)$/ ) { $st{$1} = $2; }
			}
			if ( $st{'InstanceID'} ) {
				push( @stats, \%st );
			}
		}
		# end of alarm
    	alarm(0);
	};
	if ($@) {
    	if ($@ =~ /died in SIG ALRM/) {
       		error("command timed out after : $timeout seconds");
	       	exit (1);
    	}
	}
	return \@stats;
}

sub calculateStats {
	my ($old_counters, $new_counters) = @_;
	# Calculate perf statistic values from raw counters
	my %stats = ();
	my $interval = 0;

	# check that we have timestamp in cached sample
	if ( $old_counters->{'storage_timestamp'} ) {
		$interval = $new_counters->{'storage_timestamp'} - $old_counters->{'storage_timestamp'};

	    if ( $interval ) {
    	 	my $deltaReadKB  = $new_counters->{'KBytesRead'} - $old_counters->{'KBytesRead'};
     		my $deltaWriteKB = $new_counters->{'KBytesWritten'} - $old_counters->{'KBytesWritten'};
     		my $deltaTotalKB = $new_counters->{'KBytesTransferred'} - $old_counters->{'KBytesTransferred'};
     		my $deltaReadIO  = $new_counters->{'ReadIOs'} - $old_counters->{'ReadIOs'};
     		my $deltaWriteIO = $new_counters->{'WriteIOs'} - $old_counters->{'WriteIOs'};
     		my $deltaTotalIO = $new_counters->{'TotalIOs'} - $old_counters->{'TotalIOs'};
     		my $deltaReadIOTimeCounter = $new_counters->{'ReadIOTimeCounter'} - $old_counters->{'ReadIOTimeCounter'};
     		my $deltaWriteIOTimeCounter = $new_counters->{'WriteIOTimeCounter'} - $old_counters->{'WriteIOTimeCounter'};

     		$stats{'ReadRateKB'}  = $deltaReadKB  / $interval;
     		$stats{'WriteRateKB'} = $deltaWriteKB / $interval;
     		$stats{'TotalRateKB'} = $deltaTotalKB / $interval;
     		$stats{'ReadIORate'}  = $deltaReadIO  / $interval;
     		$stats{'WriteIORate'} = $deltaWriteIO / $interval;
     		$stats{'TotalIORate'} = $deltaTotalIO / $interval;

     		if ($deltaReadIO > 0 && $deltaReadIOTimeCounter > 0) {
        		$stats{'ReadIOTime'} = $deltaReadIOTimeCounter / $deltaReadIO;
     		} else {
     			$stats{'ReadIOTime'} = 0;
     		}
     		if ($deltaWriteIO > 0 && $deltaWriteIOTimeCounter > 0) {
       			$stats{'WriteIOTime'} = $deltaWriteIOTimeCounter / $deltaWriteIO;
     		} else {
     			$stats{'WriteIOTime'} = 0;
     		}
     		if ($deltaTotalIO > 0 && $deltaReadIO > 0) {
       			$stats{'ReadIOPct'} = $deltaReadIO / $deltaTotalIO * 100;
     		} else {
     			$stats{'ReadIOPct'} = 0;
     		}
     		$stats{'Interval'} = $interval;
    	} else {
     		&error("Interval between samples is 0, skipping.");
    	}
	} else {
    	&error("No storage timestamp in previous sample, skipping." );
	}
	return \%stats;
}

sub collectStats {
	my ($elementType, $elementClass, $statisticsClass, $elementCounters) = @_;
	my $server_epoch;
	my $retry_cnt = 5;
	my $element = &enumElement($elementClass);
	if (not defined $element ) {
		&error("Read volume configuration data failed. Exiting.");
		exit(1);
	}
	if (scalar(keys %{$element}) == 0) {
		&error("Zero number of volumes. Read volume configuration data failed. Exiting.");
		exit(1);
	}
	if($debug) { &message("Number of volumes = ".scalar(keys %{$element})."."); }
	$config->{$elementType} = $element;
	#
	while ( $retry_cnt ) {
		my $stats = &enumStats($statisticsClass);
		if($debug) { print("R#".$retry_cnt.":"); }
		# Save time of statistic data creation 
		$server_epoch = time();
		foreach my $stat ( @{$stats} ) {
			my $elementID;
			#IBM.2812-7811577-98714500010
			if ( $element->{$stat->{'InstanceID'}}->{'DeviceID'} =~ /IBM.\d{4}-\w{7}-(.*)/ ) {
			#my $elementID = $element->{$stat->{'InstanceID'}}->{'DeviceID'};
			$elementID = $1;
			}
			my $elementName = $element->{$stat->{'InstanceID'}}->{'ElementName'};
			if (! defined $stat->{'StatisticTime'} ) {
				if($debug) { print("e\n"); }
				if($debug) { &warning("Statistic Time is not found in input data."); }
				last;
			}
			my $storage_epoch =	&str2time(&isotime($stat->{'StatisticTime'}));
			if (! defined $storage_epoch ) {
				if($debug) { print("E\n"); }
				if($debug) { &warning("Storage epoch time is not parsed. Statistic Time = ".$stat->{'StatisticTime'}." ISO Time: ".&isotime($stat->{'StatisticTime'})."."); }
				last;
			}
			#if($debug) {&message("Statistic Time = ".$stat->{'StatisticTime'}.". Timestamp = ".$storage_epoch."."); }
			#if($debug) {&message("Local Time = ".localtime($storage_epoch)."."); }
			# Prepare current samples 
			my %newcacheElem; my $new_raw_counters = \%newcacheElem;
			#my $cacheKey = sprintf("%s.%s.%s",$storage->{'Name'},$elementType,$elementName);
			my $cacheKey = sprintf("%s.%s.%s",$storage->{'Name'},$elementType,$elementID);
			foreach my $countType ( @RAW_COUNTERS ) {
				if ( $countType ) { $new_raw_counters->{$countType} = $stat->{$countType}; }
			}
			$new_raw_counters->{'storage_timestamp'} = sprintf("%d",$storage_epoch);
			$new_raw_counters->{'server_timestamp'} = $server_epoch;
			$new_raw_counters->{'name'} = $elementName;
			# Get previous samples from cache
			my $calc_flag = 0;
			my $cached_raw_counters;
			if ( exists( $cache->{$cacheKey} ) ) {
				$cached_raw_counters = $cache->{$cacheKey};
				if (! defined $cached_raw_counters->{'storage_timestamp'} ) {
					if($debug) { print("e"); }
					#&warning("No timestamp in cached data, skipping.");
				} else {
					if ( $storage_epoch == $cached_raw_counters->{'storage_timestamp'} ) {
						&warning("Same sample: ".$cacheKey." = ".$stat->{'StatisticTime'}.", skipping.");
						$retry_cnt = 0;
						if($debug) { print("=\n"); }
						last;
					} elsif ( $new_raw_counters->{'storage_timestamp'} - $cached_raw_counters->{'storage_timestamp'} < $mininterval ) {
						my $int = $new_raw_counters->{'storage_timestamp'} - $cached_raw_counters->{'storage_timestamp'};
						&message("Short interval ".$int." second, waiting\n",);
						$retry_cnt--;
						if($debug) { print("<\n"); }
						sleep 30;
						last;
					} else {
						# Both samples ok -> calculate
						$calc_flag = 1;
						if($debug_full) { print("*"); }
					}
				}
			} else {
				# No data for element in cache
				if($debug) { print("."); }
			}
			# Done - Get previous samples from cache
			$retry_cnt = 0;
			# Save current samples to cache
			$cache->{$cacheKey} = $new_raw_counters;
			# calculate statistics
			if ( $calc_flag ) {
		    	my $stat_values = &calculateStats($cached_raw_counters, $new_raw_counters);
 		   		#
	 		   	$stat_values->{'ID'} = $new_raw_counters->{'InstanceID'};
		   		$stat_values->{'Name'} = $elementName;
		    	$stat_values->{'Type'} = $elementType;
		    	$stat_values->{'Time'} = &epoch2isotime($cached_raw_counters->{'server_timestamp'}, $tzoffset);
		    	$stat_values->{'Timestamp'} = $cached_raw_counters->{'server_timestamp'};
    			$data->{$elementType}->{$stat->{'InstanceID'}} = $stat_values;
		    	$data->{'IntervalStartTime'} = $cached_raw_counters->{'server_timestamp'};
    			$data->{'IntervalEndTime'} = $new_raw_counters->{'server_timestamp'};
				if ( defined $cached_raw_counters->{'storage_timestamp'} ) {
	    			$data->{'Interval'} = $new_raw_counters->{'storage_timestamp'} - $cached_raw_counters->{'storage_timestamp'};
				}
			}
		}
		# Done all elements in statistic data
		if($debug) { print("\n"); }
	}
}

sub writeStats {
	if(! defined $data->{'IntervalEndTime'} ) {
		return;
	}
	# Open output file
	$out_perf_file = $tmpdir . $storname . "_xivperf_" . &fileextTime($data->{'IntervalEndTime'}) . ".out";
	open (PERFOUT,">>${out_perf_file}.tmp") || die "Couldn't open file ${out_perf_file}.tmp.";
	#
	my $elementType = shift;
	if ( $elementType eq "volume" ) {
		&writeVolumeStats;
	}
	close(PERFOUT);
}

sub writeVolumeStats {
	#
	print PERFOUT "\nVolume Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",&epoch2isotime($data->{'IntervalStartTime'},$tzoffset),"\n" if ( defined $data->{'IntervalStartTime'} );
	print PERFOUT "\tInterval End:     ",&epoch2isotime($data->{'IntervalEndTime'},$tzoffset),"\n" if ( defined $data->{'IntervalEndTime'});
	print PERFOUT "\tInterval Length:  ",$data->{'Interval'}," seconds\n" if ( defined $data->{'Interval'} );
	print PERFOUT "---------------------\n";
	#
	# Volume ID,Time,Interval (s),
	# Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),
	# Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),
	# Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),
	# Read Response Time (ms),Write Response Time (ms),Overall Response Time (ms),
	# Peak Read Response Time (ms),Peak Write Response Time (ms),
	# Host Delay (assuming that all host delay is writes) (ms),Host Delay (assuming that host delay is evenly spread between read and writes) (ms),
	# Read Hits,Write Hits,Data Read (KB),Data Written (KB),
	# Volume (Vdisk) Name,Managed Disk Group ID,Managed Disk Group Name,IO Group ID,IO Group Name,
	# Remote Copy relationship ID,Remote Copy relationship name,Remote Copy Change Volume relationship,
	# FlashCopy map ID,FlashCopy map name,FlashCopy map count,
	# Copy Count,Space Efficient Copy Count,Cache state,Easy Tier On/Off,Easy Tier Status,
	# Preferred Node ID,Capacity (TB),Real Capacity (TB),Used Capacity (TB),
	# Auto Expand,Grain Size,Throttle Unit,Throttle Rate,UDID (for HPUX),
	#
	print PERFOUT "Volume ID,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Read Response Time (ms),Write Response Time (ms),Overall Response Time (ms),Peak Read Response Time (ms),Peak Write Response Time (ms),,,Read Hits,Write Hits,Data Read (KB),Data Written (KB),Volume Name,Pool ID,Pool Name,,,,,,,,,,,,,,,,,,,,,,,Source Volume Name\n";
	my @disks = keys(%{$data->{'volume'}});
	foreach my $dsk (sort (@disks)) {
		my $p = $data->{'volume'}->{$dsk};
		my $id;
		my $poolid;
		my $rts = 0; my $wts = 0; my $tts = 0;
		if (! defined $p->{'ReadRateKB'} && ! defined $p->{'ReadIORate'} && ! defined $p->{'ReadIOTime'} ) { last; }
		$rts = $p->{'ReadRateKB'} / $p->{'ReadIORate'} if ( $p->{'ReadIORate'} > 0 );
		$wts = $p->{'WriteRateKB'} / $p->{'WriteIORate'} if ( $p->{'WriteIORate'} > 0 );
		$tts = $p->{'TotalRateKB'} / $p->{'TotalIORate'} if ( $p->{'TotalIORate'} > 0 );
		if ( $dsk =~ /^IBM\.\d{4}\-\d+\-(\w+)$/ ) { $id = $1; }

		printf PERFOUT ("%s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,,,,,,,,,%s,%s,%s,,,,,,,,,,,,,,,,,,,,,,,%s\n",
			$id,$p->{'Time'},$p->{'Interval'},
			$p->{'ReadIORate'},$p->{'WriteIORate'},$p->{'TotalIORate'},
			$p->{'ReadRateKB'},$p->{'WriteRateKB'},$p->{'TotalRateKB'},
			$rts,$wts,$tts, # Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),
			$p->{'ReadIOTime'}/1000,$p->{'WriteIOTime'}/1000,0,
			$p->{'Name'},$p->{'PoolID'},$p->{'PoolName'},$p->{'SourceVolumeName'}
			);
	}

}

sub writeConf {
	# Open output file
	if(! defined $data->{'IntervalEndTime'} ) {
		return;
	}
	$out_conf_file = $tmpdir . $storname . "_xivconf_" . &fileextTime($data->{'IntervalEndTime'}) . ".out";
	open (PERFOUT,">>${out_conf_file}.tmp") || die "Couldn't open file ${out_perf_file}.tmp.";
	#
	my $elementType = shift;
	&writeSystemConf if ( $elementType eq "system" );
	&writePoolConf if ( $elementType eq "pool" );
	&writeVolumeConf if ( $elementType eq "volume" );
	close(PERFOUT);
}

sub writeSystemConf {
	print PERFOUT "\nConfiguration Data\n------------------\n";
	print PERFOUT "\tMachine Name:".$config->{'system'}->{'Name'}."\t\n";
	print PERFOUT "\tMachine Type:\t\n";
	print PERFOUT "\tModel Number:\t\n";
	print PERFOUT "\tMachine Serial:\t\n";
	print PERFOUT "\tCode Level:".$config->{'system'}->{'CodeLevel'}."\t\n";
	print PERFOUT "\n";
}

sub writePoolConf {
	print PERFOUT "\nPool Level Configuration\n------------------------\n";
	print PERFOUT "name,id,status,mdisk_count,vdisk_count,capacity,extent_size,free_capacity,virtual_capacity,used_capacity,real_capacity,overallocation,warning,easy_tier,easy_tier_status,compression_active,compression_virtual_capacity,compression_compressed_capacity,compression_uncompressed_capacity\n";
	foreach my $elem ( sort (keys( %{$config->{'pool'}} ) ) ) {
		my $d = $config->{'pool'}->{$elem};
		my $id;
		if ( $d->{'PoolID'} =~ /.*VP(\w+)$/ ) { $id = $1; }
		printf PERFOUT ("%s,%s,%s,,,%.3f,,%.3f,\n",$d->{'ElementName'},
		       $id,$d->{'Status'},&ConvSizeUnits("GB",$d->{'HardSize'}),
		       &ConvSizeUnits("GB",$d->{'RemainingManagedSpace'}));
	}

}

sub writeVolumeConf {
	print PERFOUT "\nVolume Level Configuration\n--------------------------\n";
	print PERFOUT "volume_id,id,name,,,,pool_id,pool_name,capacity,,,,,,vdisk_UID,,,,,,\n";
	foreach my $elem ( sort (keys( %{$config->{'volume'}} ) ) ) {
		my $d = $config->{'volume'}->{$elem};
		my $pelm = "IBMTSDS:".$d->{'SystemName'}."-VP".$d->{'Pool'};
		my $pname = $config->{"pool"}->{$pelm}->{'ElementName'};
		my $id;
		if ( $d->{'DeviceID'} =~ /.*\-(\w+)\s*$/ ) { $id = $1; }
		printf PERFOUT ("%s,%s,%s,,,,%s,%s,%.3f,,,,,,%s,,,,,,\n",$id,$d->{'DeviceID'},$d->{'ElementName'},
			$d->{'Pool'},$pname,&ConvSizeUnits("GB",$d->{'Size'}),$d->{'Name'},
		);
	}

}

sub collectConf {
	my ($elementType, $elementClass) = @_;
	my $element = &enumElement($elementClass);
	if (not defined $element ) {
		&error("Read pool data failed. Exiting.");
		exit(1);
	}
	if (scalar(keys %{$element}) == 0) {
		&error("Zero number of pools. Read pool data failed. Exiting.")
	}
	if($debug) { &message("Number of Pools = ".scalar(keys %{$element})."."); }
	$config->{$elementType} = $element;
}

sub enumElement {
	my $elementClass = shift;
	my %data;
	my $timeout = $ENV{SAMPLE_RATE};
	if ( $timeout eq '' ) {
    	$timeout = 900;
	} else {
    	$timeout = $timeout * 3;
	}
	eval {
		# Set alarm
    	my $act_time = localtime();
    	local $SIG{ALRM} = sub {die "$act_time: died in SIG ALRM";};
    	alarm($timeout);
		# Get Element Statistics
		my $objectPath = "https://".$xivuser.":".$xivpwd."@".$xivip.":5989/root/ibm:".$elementClass;
		if ($debug_full) {message("+$wbemcli_cmd -noverify ei ".$objectPath."."); }
		for my $line ( &wbemcli("ei",$objectPath) ) {
			chomp($line);
			my @a = split(",",$line);
			my $id; my $name; my %st;
			foreach my $elem ( @a ) {
				if    ( $elem =~ /^InstanceID="([-:.\w]*)"$/    ) { $id = $1; $st{'InstanceID'} = $1; }
				elsif ( $elem =~ /^DeviceID="([-:.\w]*)"$/    ) { $id = $1; $st{'DeviceID'} = $1; }
				elsif ( $elem =~ /^(\w+)="(.*)"$/ ) { $st{$1} = $2; }
				elsif ( $elem =~ /^(\w+)=(.*)$/ ) { $st{$1} = $2; }
			}
			if ( $id ) {
				$data{$id} = \%st;
			}
		}
		# end of alarm
    	alarm(0);
	};
	if ($@) {
    	if ($@ =~ /died in SIG ALRM/) {
        	error("command timed out after : $timeout seconds");
        	exit (1);
    	}
	}
	return \%data;
}


sub insertPoolName {
	foreach my $velm ( keys %{$data->{'volume'}} ) {
		my $poolid = $config->{'volume'}->{$velm}->{'Pool'};
		# Insert 'SourceVolumeName'
		$data->{"volume"}->{$velm}->{'SourceVolumeName'} = $config->{'volume'}->{$velm}->{'SourceVolumeName'};
		# Insert 'PoolID','PoolName'
		foreach my $pelm ( keys %{$config->{"pool"}} ) {
			if ( $pelm =~ /.*VP${poolid}$/ ) {
				$data->{"volume"}->{$velm}->{'PoolID'} = $poolid;
				$data->{"volume"}->{$velm}->{'PoolName'} = $config->{"pool"}->{$pelm}->{'ElementName'};
			}
		}
	}
}


sub fileextTime {
	my $t = shift;
	if (! defined $t ) { return "NA"; }
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
    my $y = $year + 1900;
    my $m = $mon + 1;
	return sprintf("%d%02d%02d_%02d%02d",$y,$m,$mday,$hour,$min,$sec);
}

sub isotime {
	my $t = shift;
	if ( $t =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2}).(\d{6})([\+-])(\d+)$/ ) {
		my $tmod = $9 % 60;
		use integer;
		my $tdiv = $9 / 60;
		no integer; 
		my $tz = sprintf("%04d",($tdiv * 100) + $tmod );
		return sprintf("%d:%02d:%02dT%02d:%02d:%02d.%06d%s%s",$1,$2,$3,$4,$5,$6,$7,$8,$tz);
	}
}

sub tzoffset {
    my $sign = "";
    my $t = time();
    my $local_time = localtime($t);
    my $gm_time = gmtime($t);
    my $local = str2time($local_time);
    my $utc = str2time($gm_time);
    my $tzo = (($local - $utc)/3600);
    if( $tzo > 0 ) { $sign = "+"; }
    return sprintf("%s%02d00",$sign,$tzo);
}

sub epoch2isotime {
    # Output: 2015:02:05T19:54:07.000000+0100
    my ($tm,$tz) = @_;	# epoch, TZ offset (+0100)
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($tm);
    my $y = $year + 1900;
    my $m = $mon + 1;
    my $mcs = 0;
    my $str = sprintf("%4d:%02d:%02dT%02d:%02d:%02d.%06d%s",$y,$m,$mday,$hour,$min,$sec,$mcs,$tz);
    return($str);
}

sub ConvSizeUnits {
	my ($unit,$size) = @_;
	if ( $unit eq "KB" ) { return($size / 1024) }
	if ( $unit eq "MB" ) { return($size / 1048576) }
	if ( $unit eq "GB" ) { return($size / 1073741824) }
	if ( $unit eq "TB" ) { return($size / 1099511627776) }
}


# MAIN

&message("Start.");
$storage = &enumStorage("IBMTSDS_StorageSystem");
if (! defined $storage->{'Name'} ) {
	&error("Cannot get storage name. Connection error. Exiting.");
	exit 1;
}
$config->{"system"} = $storage;
&message("Get interval performance data for storage".$storage->{'Name'}.".");
if($debug) { &message("Storage Name: ".$storage->{'Name'}." CodeLevel: ".$storage->{'CodeLevel'}."."); }

# Load cache from file
if ( -r $cacheFile ) {
	if($debug) { message("Read cache file $cacheFile."); };
	$cache = retrieve($cacheFile);
} else {
	my %cache_array; $cache = \%cache_array;
}

$tzoffset = &tzoffset();
&collectConf("pool","IBMTSDS_VirtualPool");
&collectStats("volume","IBMTSDS_SEVolume","IBMTSDS_SEVolumeStatistics",\@VOLUME_COUNTERS);
&insertPoolName();
&writeConf("system");
&writeConf("pool");
&writeConf("volume");
&writeStats("volume");

if($debug) { &message("Store cache file $cacheFile."); }
store($cache, $cacheFile);
&message("Done.");

exit 0;
