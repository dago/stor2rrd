#!/usr/bin/perl
#
# svcperf.pl
#
# v0.2.11

# Changes:
# Move svc log to ./logs directory 
# Add Volume Cache Statistic
# Add CPU Node Statistic
# enhanced ssh&scp about  -q -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey
# Remove perf. data file and exiting after falied retrieve or retrieve invalid data.
# Remove perf. data file and exiting after failed upload IOSTAT file.
# Remove old perf. data file after restart svcperf.pl.
# Add new tier name specification in iostats.

# Modules
use strict;
use Storable qw(retrieve store);
use Data::Dumper;
use Date::Parse;

#use XML::Simple;
my $bindir = $ENV{BINDIR};
require "$bindir/xml.pl"; # it replaces above line and fixes an issue on Perl 5.10.1 on AIX 7100-00-06-1216

# Constant
use constant SVCPRF101W => 101;
use constant SVCPRF102W => 102;
use constant SVCPRF103W => 103;
use constant SVCPRF104W => 104;
use constant SVCPRF105W => 105;
use constant SVCPRF106W => 106;
use constant SVCPRF107W => 107;
use constant SVCPRF108W => 108;
use constant SVCPRF109W => 109;
use constant SVCPRF110E => 110;
use constant SVCPRF111E => 111;
use constant SVCPRF112E => 112;
use constant SVCPRF113E => 113;
use constant SVCPRF114E => 114;
use constant SVCPRF115E => 115;
use constant SVCPRF116E => 116;
use constant SVCPRF117E => 117;
use constant SVCPRF118E => 118;
use constant SVCPRF119E => 119;


# Options and their default value
my $storage;                    # SVC/Storwize V7000 alias
my $svc;                        # SVC/Storwize V7000 cluster host name (IP address)
my $user        = "admin";      # SVC/Storwize V7000 user name
my $key         = "";           # SSH key filename
my $interval    = 1;            # interval time for data collection
my $dir         = "..";         # Data directory

my $debug       = 0;            # Debug mode 0:off, 1:on

if (defined $ENV{STORAGE_NAME}) {
	$storage= $ENV{STORAGE_NAME};
} else {
	message("svcperf.pl: SVC/Storwize V7000 storage name alias is required.");
	exit(1);
}
if (defined $ENV{SVC_IP}) {
	$svc= $ENV{SVC_IP};
} else {
	message("svcperf.pl: SVC/Storwize V7000 host name or IP address is required.");
	exit(1);
}
if (defined $ENV{SVC_USER}) { $user	= $ENV{SVC_USER} }
if (defined $ENV{SVC_KEY}) { $key = $ENV{SVC_KEY} }
if (defined $ENV{SVC_INTERVAL}) { $interval = $ENV{SVC_INTERVAL} }
if (defined $ENV{SVC_DIR}) { $dir = $ENV{SVC_DIR} }
if (defined $ENV{DEBUG}) { $debug = $ENV{DEBUG} }

# Global variables with their value
my $ssh;
my $scp;
if("x$key" eq "x") {            # with default keyfile (.ssh/id_rsa)
	$ssh = "ssh  -q -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey $user\@$svc";
	$scp = "scp  -q -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey $user\@$svc:/dumps/iostats/";
} else {                        # with keyfile
	$ssh = "ssh  -q -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey -i $key $user\@$svc";
	$scp = "scp  -q -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey -i $key  $user\@$svc:/dumps/iostats/";
}

my $iosdir = "$dir/iostats/";   # Directory for iostats files
my $tmpdir = "$dir/";       # Directory for temporary files

# Global variables
my $terminate_pgm;
my $iostatsdumps_name;                                  # SVC, Storwize V7000 dependent
my ($node, $front_panel_id, @stats_files, $stats_file); # Current scan data
my (@Nn_last, @Nm_last, @Nv_last, @Nd_last);            # Last scan data
my ($command, $ret);

my $cfg_ref;
my $fullcfg_ref;
my %last_data; my $last_data_ref = \%last_data;
my %prev_data; my $prev_data_ref = \%prev_data;
my %drive_accum; my $drive_accum = \%drive_accum;
my %mdisk_accum; my $mdisk_accum = \%mdisk_accum;
my %vdisk_accum; my $vdisk_accum = \%vdisk_accum;
my %vdiskcache_accum; my $vdiskcache_accum = \%vdiskcache_accum;
my %port_accum; my $port_accum = \%port_accum;
my %cpunode_accum; my $cpunode_accum = \%cpunode_accum;
my %cpucore_accum; my $cpucore_accum = \%cpucore_accum;
my %nodenode_accum; my $nodenode_accum = \%nodenode_accum;
my %nodecache_accum; my $nodecache_accum = \%nodecache_accum;
my %node_accum; my $node_accum = \%node_accum;
my %mdiskgrp_cap; my $mdiskgrp_cap = \%mdiskgrp_cap;

# Main process

# Display options
print("
svcperf.pl: Starts with the following options ...
\tSVC/Storwize V7000 cluster name alias:   $storage
\tSVC/Storwize V7000 cluster host name:    $svc
\tInterval:                                $interval
\tDirectory for iostats files:             $iosdir
\tDirectory for temporary files:           $tmpdir
\tDebug:                                   $debug
");

# Examine system name
my $svc_name;
my $lssystem = &LsSystem();
#my $line_LSSYSTEM = `$ssh svcinfo lssystem -delim : | grep '^name:'`;
#if($debug) {print("The svcinfo lssystem command output: $line_LSSYSTEM");}
#if ( $line_LSSYSTEM =~ /^\s*name:([\w -.]+)$/ ) {
#    $svc_name = $1;
#}
if ( defined $lssystem->{'name'} ) {
	$svc_name = $lssystem->{'name'};
}
if($svc_name eq "x") {
    message("svcperf.pl: Cannot get system name.");
    exit 1;
}
if($debug) {message("svcperf.pl: System name    : $svc_name");}
# Set filenames
my $logfile = $tmpdir . "../../logs/" . $storage . ".svcperf.log";	# log file
my $tmp_perf_file = $tmpdir . $storage . "_svcperf.data";	# 
my $out_perf_file;
my $tmp_conf_file;
my $tmp_conf_full_file = ${storage}."_svcconf.datafull";
# Create log file
$ret = system("echo svcperf.pl started at >> $logfile 2>&1");
if($ret) {message("svcperf.pl: Cannot create/write a log file $logfile"); exit (1);}
system("date >> $logfile 2>&1");
# Handling signals
$SIG{'INT'} = 'CtrlC';

# Change STOUT buffer attribute
$| = 1;	# disable STDOUT buffer

# Examine H/W type and Set iostats dumps file name
my $line_LSNODE = `$ssh svcinfo lsnode -nohdr -delim :`;
#if($debug) {print("The svcinfo lsnode command output: $line_LSNODE");}
my @field_LSNODE = split(':', $line_LSNODE);
if($field_LSNODE[2]) {				# SVC = UPS_serial_number
	$iostatsdumps_name = "front_panel_id";	# SVC iostats dumps file name
	if($debug) {message("svcperf.pl: H/W type, iostats dumps file name (SVC): $iostatsdumps_name.");}
} else {					# Storwize V7000 = UPS_serial_number is blank
	$iostatsdumps_name = "dump_name";	# Storwize V7000 iostats dumps file name
	if($debug) {message("svcperf.pl: H/W type, iostats dumps file name (Storwize V7000): $iostatsdumps_name.");}
}

# Clear SVC/Storwize V7000 iostats files
foreach my $line_LSNODE (`$ssh svcinfo lsnode -nohdr -delim :`) {
	#if($debug) {message("The svcinfo lsnode command output: $line_LSNODE");}
	my @field_LSNODE = split(':', $line_LSNODE);
	system("$ssh svctask cleardumps -prefix /dumps/iostats $field_LSNODE[0]");
	if($debug) {message("svcperf.pl: Clear iostas files: node $field_LSNODE[1]\n");}
}

# Start SVC/Storwize V7000 iostats collection
if($debug) {message("svcperf.pl: Statistics collection: ".$lssystem->{'statistics_status'}." - Interval: ".$lssystem->{'statistics_frequency'});}
if ( $lssystem->{'statistics_frequency'} != $interval ) {
	system ("$ssh svctask startstats -interval $interval") ;
	if($debug) {message("svcperf.pl: Start statistics collection: interval $interval");}
}
$terminate_pgm = 0;

# Remove old performance data file
if ( -r $tmp_perf_file ) {
	if($debug) {message("svcperf.pl: Remove old performance data file: $tmp_perf_file.")};
	system("rm -f " . $tmp_perf_file );
}

# main loop
while(1){

	system("echo Get data at >> $logfile 2>&1");
	system("date >> $logfile 2>&1");

	# Scan all nodes and get performance data
	foreach my $line_LSNODE (`$ssh svcinfo lsnode -nohdr -delim :`) {
		#if($debug) {message("svcperf.pl: The svcinfo lsnode command output: $line_LSNODE");}
		my @field_LSNODE = split(':', $line_LSNODE);
		# Check none configuration nodes
		if($field_LSNODE[7] =~ "no") {
			$node = $field_LSNODE[0];
			if($debug) {message("svcperf.pl: None-configuration node: $node");}
			&ID_front_panel();
			&List_iostats_create();
			&List_iostats_copy();
		# Check configuration node
		} else {
			$node = $field_LSNODE[0];
			if($debug) {message("svcperf.pl: Configuration node: $node");}
			&ID_front_panel();
			&List_iostats_create();
			&List_iostats_get();
		}
	}

    # Check latest data validity
    my @last_nodes = keys(%{$last_data_ref->{svc_node}});
    if ( scalar(@last_nodes) == 0 ) { 
        if($debug) { message("svcperf.pl: Last data is not valid. Continue.")};
        next;
    }
    if ( not defined $last_data_ref->{svc_node}->{$last_nodes[0]}->{timestamp} || "x$last_data_ref->{svc_drive}->{$last_nodes[0]}->{timestamp}" eq "x" ) {
        if($debug) { message("svcperf.pl: Last data is not valid. Continue.")};
        next;
    }
	# Chech if exist previous data
	if ( not -r $tmp_perf_file ) {
		if($debug) {message("svcperf.pl: No previous data. Store data to file: $tmp_perf_file.\n Continue.")};
		#store($last_data_ref, $tmp_perf_file);
		if ( ! defined store($last_data_ref, $tmp_perf_file) ) {
			message("svcperf.pl: ERROR: Store data to file $tmp_perf_file failed.");
			system("rm -f " . $tmp_perf_file );
			exit SVCPRF110E;
		}
		next;
	}
	
	# Retrive previous data from temporary file
	$prev_data_ref = retrieve($tmp_perf_file);
	if ( ! defined $prev_data_ref ) {
		message("svcperf.pl: Retrieve data from file $tmp_perf_file failed.");
		system("rm -f " . $tmp_perf_file );
		exit SVCPRF112E;
		#exit 1;
	}
    # Check previous data validity
    my @prev_nodes = keys(%{$prev_data_ref->{svc_node}});
    if ( scalar(@prev_nodes) == 0 ) { 
        if($debug) { message("svcperf.pl: Previous data is not valid. Exiting.")};
		system("rm -f " . $tmp_perf_file );
		exit SVCPRF115E;
        #next;
    }
    if ( not defined $prev_data_ref->{svc_node}->{$prev_nodes[0]}->{timestamp} || "x$prev_data_ref->{svc_drive}->{$prev_nodes[0]}->{timestamp}" eq "x" ) {
        if($debug) { message("svcperf.pl: Previous data is not valid. Exiting.")};
		system("rm -f " . $tmp_perf_file );
		exit SVCPRF116E;
        #next;
    }
    #
    my $prev_time = str2time($prev_data_ref->{svc_node}->{$prev_nodes[0]}->{timestamp});
    my $last_time = str2time($last_data_ref->{svc_node}->{$last_nodes[0]}->{timestamp});

    if ( $last_time < $prev_time ) {
        if($debug) { message("svcperf.pl: Previous data is not valid. Exiting.")};
		system("rm -f " . $tmp_perf_file );
		exit SVCPRF117E;
    }
    if ( $last_time == $prev_time ) {
        if($debug) { message("svcperf.pl: No new data. Continue.")};
        next;
    }
	# Set output filename
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($last_time);
    $year += 1900;
    $mon++;
    my $date = sprintf("%4d%2.2d%2.2d",$year,$mon,$mday);
    my $time = sprintf("%2.2d%2.2d%2.2d",$hour,$min,$sec);
    $out_perf_file = $tmpdir . $storage . "_svcperf_" . $date . "_" . $time . ".out";
	if($debug) {message("svcperf.pl: Performance Output Filename: $out_perf_file")};

	# Get Latest Config Data
	$tmp_conf_file = &GetConfigFilename();
	if($debug) {message("svcperf.pl: Config Filename: " . $tmpdir . $tmp_conf_file)};
	if (! defined $tmp_conf_file || ! -r $tmpdir . $tmp_conf_file ) {
		message("svcperf.pl: Config File not found");
		exit SVCPRF114E;
	}

	$cfg_ref = retrieve($tmpdir . $tmp_conf_file);
	if ( ! defined $cfg_ref ) {
		message("svcperf.pl: Retrieve data from file $tmp_conf_file failed.");
		system("rm -f " . $tmp_conf_file );
		exit SVCPRF114E;
		#exit 1;
	}
    # Check configuration data validity
    if (! scalar(%{$cfg_ref}) ) { 
        if($debug) { message("svcperf.pl: Configuration data is not valid. Exiting.")};
		system("rm -f " . $tmp_conf_file );
		exit SVCPRF119E;
    }
        # Read Full Config Data 
        if ( -r $tmpdir . $tmp_conf_full_file ) {
	        $fullcfg_ref = retrieve($tmpdir . $tmp_conf_full_file);
        }

	if($debug) {message("svcperf.pl: Configuration and Previous performance data is valid. Continue.")};
	
	# Get Capacity data
	&GetCapacityData();
	# Count performance data
	$ret = &CountPerfData();
	if($ret) { 
		message("svcperf.pl: WARNING: Latest data is not valid. Continue.");
		next;
	}
		
	if($debug) {message("svcperf.pl: Store actual data to file: $tmp_perf_file.")};
	#store($last_data_ref, $tmp_perf_file) or die("svcperf.pl: Store data to file $tmp_perf_file failed.\n");
	if ( ! defined store($last_data_ref, $tmp_perf_file) ) {
		message("svcperf.pl: ERROR: Store data to file $tmp_perf_file failed.");
		system("rm -f " . $tmp_perf_file );
		exit SVCPRF111E;
	}
	
} continue {
	# Clear Accumulated Data
	&ClearAccumData();
	
	# Wait about 60 seconds
	for(my $i = 0; $i < 20; $i++) {
		# Terminate program?
		if($terminate_pgm){
			if($debug) {message("svcperf.pl: Exitting");}
			exit(0);
		}
		sleep (3);
	}
}

sub message {
	my $msg = shift;
	my $tm = localtime();
	print($tm.": ".$msg."\n");
}

sub LsSystem {
	my $line;
	my $delim = ":";
	my %cfg;
	my $cmd = $ssh . " svcinfo lssystem -delim " . $delim;
	if ($debug) {message("svcperf.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcperf.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^(\w+)$delim(.*)$/) {   # system
			$cfg{$1} = $2;
		}
	}
	close(CMDOUT);
	return(\%cfg);
}


sub ID_front_panel {

	# Create $front_panel_id
	foreach my $line_LSNODEVPD (`$ssh svcinfo lsnodevpd -delim : $node`) {
		#if($debug) {print("The svcinfo lsnodevpd command output: $line_LSNODEVPD");}
		my @field_LSNODEVPD = split (':', $line_LSNODEVPD);
		if($field_LSNODEVPD[0] =~ $iostatsdumps_name) {
			if($debug) {message("svcperf.pl: Check: $field_LSNODEVPD[1]");}
			$front_panel_id = $field_LSNODEVPD[1];
			chomp($front_panel_id);
			if($debug) {message("svcperf.pl: Front panel ID: $front_panel_id");}
		}
	}
}


sub List_iostats_create {

	# create local node's I/O stats file list array (@stats_files)
	foreach my $line_LSIOSTATSDUMPS (`$ssh svcinfo lsiostatsdumps -nohdr -delim : $node`) {
		#if($debug) {print("The svcinfo lsiostatsdumps command output: $line_LSIOSTATSDUMPS");}
		my @field_LSIOSTATSDUMPS = split(':', $line_LSIOSTATSDUMPS);
		chomp($field_LSIOSTATSDUMPS[1]);
		if(index($field_LSIOSTATSDUMPS[1], $front_panel_id) > 0) {
			unshift(@stats_files, $field_LSIOSTATSDUMPS[1]);
		}
	}
	@stats_files = sort(@stats_files);
	if($debug) {message("svcperf.pl: I/O statistics log files: @stats_files");}
}

sub List_iostats_copy {

	# Scan all (Node, VDisk, MDisk, Drive) stats files
	while(defined($stats_file = shift(@stats_files))) {

		# Handle Node stats file
		if(not defined $Nn_last[$node]) { $Nn_last[$node] = "" }
		if($stats_file =~ m/Nn/ && $stats_file gt $Nn_last[$node]) {
			$command = $ssh . " svctask cpdumps -prefix /dumps/iostats/" . $stats_file .  " " . $node;
			cmd_exec();
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nn_last[$node] = $stats_file;
		}

		# Handle VDisk stats file
		if(not defined $Nv_last[$node]) { $Nv_last[$node] = "" }
		if($stats_file =~ m/Nv/ && $stats_file gt $Nv_last[$node]) {
			$command = $ssh . " svctask cpdumps -prefix /dumps/iostats/" . $stats_file .  " " . $node;
			cmd_exec();
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nv_last[$node] = $stats_file;
		}

		# Handle MDisk stats file
		if(not defined $Nm_last[$node]) { $Nm_last[$node] = "" }
		if($stats_file =~ m/Nm/ && $stats_file gt $Nm_last[$node]) {
			$command = $ssh . " svctask cpdumps -prefix /dumps/iostats/" . $stats_file .  " " . $node;
			cmd_exec();
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nm_last[$node] = $stats_file;
		}

		# Handle Drive stats file
		if(not defined $Nd_last[$node]) { $Nd_last[$node] = "" }
		if($stats_file =~ m/Nd/ && $stats_file gt $Nd_last[$node]) {
			$command = $ssh . " svctask cpdumps -prefix /dumps/iostats/" . $stats_file .  " " . $node;
			cmd_exec();
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nd_last[$node] = $stats_file;
		}
	}
}

sub List_iostats_get {

	# Scan all (Node, VDisk, MDisk, Drive) stats files
	while(defined($stats_file = shift(@stats_files))) {

		# Handle Node stats file
		if(not defined $Nn_last[$node]) { $Nn_last[$node] = "" }
		if($stats_file =~ m/Nn/ && $stats_file gt $Nn_last[$node]) {
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nn_last[$node] = $stats_file;
		}

		# Handle VDisk stats file
		if(not defined $Nv_last[$node]) { $Nv_last[$node] = "" }
		if($stats_file =~ m/Nv/ && $stats_file gt $Nv_last[$node]) {
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nv_last[$node] = $stats_file;
		}

		# Handle MDisk stats file
		if(not defined $Nm_last[$node]) { $Nm_last[$node] = "" }
		if($stats_file =~ m/Nm/ && $stats_file gt $Nm_last[$node]) {
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nm_last[$node] = $stats_file;
		}

		# Handle Drive stats file
		if(not defined $Nd_last[$node]) { $Nd_last[$node] = "" }
		if($stats_file =~ m/Nd/ && $stats_file gt $Nd_last[$node]) {
			$command = "$scp$stats_file $iosdir";
			#cmd_exec();
			if (! defined cmd_exec() ) {
				message("svcperf.pl: Upload IOSTAT file $stats_file failed.");
				system("rm -f " . $tmp_perf_file );
				exit SVCPRF118E;
			}
			&Data_insert();
			$Nd_last[$node] = $stats_file;
		}
	}
}

sub cmd_exec {
	$ret = 1;
        my $count = 0; # let it run only 5 times ( 10 x 80 sec timeout in ssh = 800secs)
	while($ret && !$terminate_pgm) {
                $count++;
		$ret = system("$command >> $logfile 2>&1");
		if($ret && $count < 10) {
                   message("svcperf.pl: Retry $command");
                   next;
                }
		if($ret && $count == 10) {
                   message("svcperf.pl: Failed: $command : too many attempts : $count");
                   return undef;
                   last;
                }
	}
	return $ret;
}

sub Data_insert {
	my $xmlfile = $iosdir . $stats_file;
	my $simple = XML::Simple->new(keyattr => [], ForceArray => 1);
	my $xmldata = $simple->XMLin($xmlfile);
	
	my %record; my $record_ref = \%record;

	# Create common part
	my $comkeys = "";
	my $comvalues = "";
	while((my $key, my $value) = each %{$xmldata}) {
		if(($key !~ m/^x/s) && ($value !~ m/^ARRAY/s) && ($value !~ m/^HASH/s)) {
			$comkeys = $comkeys . ", " . $key;
			$comvalues = $comvalues . ", '" .  $value . "'";
		}
	}
	$comkeys =~ s/^, //g;
	$comvalues =~ s/^, //g;

	# Nn XML file
	if($stats_file =~ m/^Nn/s) {
		# parse node data
        $last_data_ref->{svc_node}->{$xmldata->{'id'}}=$xmldata;
	}
	# Nv XML file
	if($stats_file =~ m/^Nv/s) {
		# parse vdsk data
        $last_data_ref->{svc_vdsk}->{$xmldata->{'id'}}=$xmldata;
	}
	# Nm XML file
	if($stats_file =~ m/^Nm/s) {
		# parse mdsk data
        $last_data_ref->{svc_mdsk}->{$xmldata->{'id'}}=$xmldata;
	}
	# Nd XML file
	if($stats_file =~ m/^Nd/s) {
		# parse drive data
        $last_data_ref->{svc_drive}->{$xmldata->{'id'}}=$xmldata;
	}

	# Print stats file and remove (if not debug mode)
	system("echo $stats_file >> $logfile 2>&1");
	#if(!($debug)) {
	#	system("rm -f $iosdir" . $stats_file);
	#}

}

###############################################################################
#
# CountPerfData
#
# 1. Variable $last_ref and $prev_ref contains data that need to be processed.
#
###############################################################################

sub CountPerfData {
	my ($last_ref,$prev_ref) = @_;
	my $ret = 0; my $rflag = 0;
	my @prev_nodes = keys(%{$prev_data_ref->{svc_node}});
	my @last_nodes = keys(%{$last_data_ref->{svc_node}});
	if($debug) { message("svcperf.pl: Node list: ".join(" ",@last_nodes)."\n")};
	if($debug) { message("svcperf.pl: Previos data time: ".$prev_data_ref->{svc_node}->{$prev_nodes[0]}->{timestamp}."\n")};
	if($debug) { message("svcperf.pl: Last data time:    ".$last_data_ref->{svc_node}->{$last_nodes[0]}->{timestamp}."\n")};
	# Open output file
	open (PERFOUT,">>${out_perf_file}.tmp") || die "Couldn't open file ${out_perf_file}.tmp.";

	# Count and print data
	if($debug) { print("CPUNodeStatistics - "); }
	if( &CPUNodeStatistics()   ) { $rflag = 1; }
	if($debug) { print("CPUCoreStatistics - "); }
	if( &CPUCoreStatistics()   ) { $rflag = 1; }
	if($debug) { print("NodeNodeStatistics - "); }
	if( &NodeNodeStatistics()  ) { $rflag = 1; }
	if($debug) { print("PortStatistics - "); }
	if( &PortStatistics()      ) { $rflag = 1; }
	if($debug) { print("DriveStatistics - "); }
	if( &DriveStatistics()     ) { $rflag = 1; }
	if($debug) { print("MDiskStatistics - "); }
	if( &MDiskStatistics()     ) { $rflag = 1; }
	if($debug) { print("VDiskStatistics - "); }
	if( &VDiskStatistics()     ) { $rflag = 1; }
	if($debug) { print("NodeCacheStatistics - "); }
	if( &NodeCacheStatistics() ) { $rflag = 1; }
	if($debug) { print("VDiskCacheStatistics - "); }
	if( &VDiskCacheStatistics()) { $rflag = 1; }
	if($debug) { print("MDiskGroupCapacityStatistics - "); }
	if( &MDiskGroupCapacityStatistics() ) { $rflag = 1; }
	if($debug) { print("DONE\n"); }
	# Invalid data - close and remove output file
	if ( $rflag ) {
		close (PERFOUT);
		system("rm ${out_perf_file}.tmp");
		return SVCPRF108W;
	}
	# Close output file
	close (PERFOUT);
    $ret = system("mv ${out_perf_file}.tmp ${out_perf_file}");
    if ($ret) { die "Couldn't rename file ${out_perf_file}.tmp." };
}

###############################################################################
#
# NodeNodeStatistics
#
# 1. Called by CountData
#
###############################################################################

sub NodeNodeStatistics {
	# Node to Node Level Statistics
	#	Interval Start:   2012-04-25 11:01:00 GMT+01:00
	#   Interval End:     2012-04-25 11:06:00 GMT+01:00
	#   Interval Length:  300 seconds
    #---------------------
    my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nNode to Node Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_node}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_node}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for Node to Node Level Statistic. Time: $ltm. Node: $node.\n";
			return SVCPRF101W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_node}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_node}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_node}->{$node}->{node}};
		my $ldata_ref = \@{$last_data_ref->{svc_node}->{$node}->{node}};

		my $reclist = &GetNodeNodeList($pdata_ref);
		foreach my $rec (@{$reclist}) {
			my $precdata_ref = 0; my $lrecdata_ref = 0;
			$precdata_ref = &GetNodeNodeData($rec,$pdata_ref);
			$lrecdata_ref = &GetNodeNodeData($rec,$ldata_ref);
                        if ( $precdata_ref == 0 || $lrecdata_ref == 0 ) {
                            print "svcperf.pl: WARNING: Data for Node $rec not valid. Continue.\n";
                            next;
                        }
			&NodeNodeDiff($lrecdata_ref,$precdata_ref,$int,$node,$szunit,$tmunit,$l_time);
		}
	}
	&NodeNodePrint();
	return 0;
}

sub GetNodeNodeList {
	my ($p_ref) = @_;
	my $d;
	foreach my $a (@{$p_ref}) {
		push(@{$d},$a->{id});
	}
	return $d;
}

sub GetNodeNodeData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d eq $a->{id} ) {
			return \%{$a}; 
		}
	}
}

sub NodeNodeDiff {
	my ($l,$p,$int,$node,$szu,$tmu,$tm) = @_;
	my ($ro,$wo,$rb,$wb,$rops,$wops,$rbps,$wbps,$rl,$wl,$xl);
	#
	my %a; $nodenode_accum{$node."_".$p->{cluster}."_".$p->{id}} = \%a;
	my @keylist = keys(%{$p});
	foreach my $var (@keylist) {
		if ($var eq "cluster" or $var eq "cluster_id" or $var eq "type_id" or $var eq "id" or
		    $var eq "node_id" ) { 
		    	if (defined $l->{$var}) { $a{$var} = $l->{$var}; } else { $a{$var} = ""; } 
		    	next;
		}
		if (defined $l->{$var} && defined $p->{$var}) { $a{$var} = DiffCalc($l->{$var},$p->{$var},"Node: ".$node." var: ".$var); } else { $a{$var} = 0; }
	}
	$a{time} = $tm; $a{interval} = $int; $a{node} = $node;
	$a{timeunit} = $tmu; $a{sizeunit} = $szu;
}

sub NodeNodePrint {
	# Node,Time,Interval (s),
	# Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),
	# Read Data Rate (KB/s),Write Data Rate,Total Data Rate,
	# Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),
	# Receive latency excluding inbound queue time (ms),Send latency excluding outbound queue time (ms),Overall latency excluding queue time (ms),
	# Receive latency including inbound queue time (ms),Send latency including outbound queue time (ms),Overall latency including queue time (ms),
	# Node,Remote Cluster,Remote Node,
	print PERFOUT "Node,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Receive latency excluding inbound queue time (ms),Send latency excluding outbound queue time (ms),Overall latency excluding queue time (ms),Receive latency including inbound queue time (ms),Send latency including outbound queue time (ms),Overall latency including queue time (ms),Node,Remote Cluster,Remote Node,\n";
	my @idlist = keys(%{$nodenode_accum});
	foreach my $id (sort (@idlist)) {
		my ($rtpo,$wtpo,$repo,$wepo,$rqpo,$wqpo);
		my $p = $nodenode_accum->{$id};
		#
		if ($p->{ro} > 0) { 
			$rtpo = $p->{rb}*$p->{sizeunit}/1024/$p->{ro};
			$repo = $p->{re}*$p->{sizeunit}/$p->{ro};
			$rqpo = $p->{rq}*$p->{sizeunit}/$p->{ro};
		} else { 
			$rtpo = 0; $repo = 0; $rqpo = 0;
		}
		if ($p->{wo} > 0) { 
			$wtpo = $p->{wb}*$p->{sizeunit}/1024/$p->{wo};
			$wepo = $p->{we}*$p->{sizeunit}/$p->{wo};
			$wqpo = $p->{wq}*$p->{sizeunit}/$p->{wo};
		} else { 
			$wtpo = 0; $wepo = 0; $wqpo = 0;
		}
		printf PERFOUT ("%s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s,%s,%s,\n",
			$id,$p->{time},$p->{interval},
			$p->{ro}/$p->{interval},$p->{wo}/$p->{interval},($p->{ro}+$p->{wo})/$p->{interval},
			$p->{rb}*$p->{sizeunit}/1024/$p->{interval}, $p->{wb}*$p->{sizeunit}/1024/$p->{interval},($p->{rb}+$p->{wb})*$p->{sizeunit}/1024/$p->{interval},
			$rtpo,$wtpo,($rtpo + $wtpo)/2,
			$repo,$wepo,($repo + $wepo)/2,
			$rqpo,$wqpo,($rqpo + $wqpo)/2,
			$p->{node},$p->{cluster},$p->{id},
			);
	}
	
}

###############################################################################
#
# NodeCacheStatistics
#
# 1. Called by CountData
#
###############################################################################

sub NodeCacheStatistics {
	# Node Cache Level Statistics
	#	Interval Start:   2012-04-25 11:01:00 GMT+01:00
	#   Interval End:     2012-04-25 11:06:00 GMT+01:00
	#   Interval Length:  300 seconds
    #---------------------
    my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nNode Cache Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_node}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_node}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for Node Cache Level Statistic. Time: $ltm. Node: $node.\n";
			return SVCPRF102W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_node}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_node}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_node}->{$node}->{cache}};
		my $ldata_ref = \@{$last_data_ref->{svc_node}->{$node}->{cache}};
		&NodeCacheDiff($ldata_ref->[0],$pdata_ref->[0],$int,$node,$szunit,$tmunit,$l_time);
	}
	&NodeCachePrint();
	return 0;
}

sub NodeCacheDiff {
	my ($l,$p,$int,$node,$szu,$tmu,$tm) = @_;
	my ($ro,$wo,$rb,$wb,$rops,$wops,$rbps,$wbps,$rl,$wl,$xl);
	#
	my %a; $nodecache_accum{$node} = \%a;
	#my @keylist = keys(%{$p});
	foreach my $var ( qw(cfav cfcn cfmn cfmx dlav dlcn dlmn dlmx drll dtav dtcn dtmn dtmx gcll mll plav plcn plmn plmx slav slcn slmn slmx taav tacn tamn tamx tlav tlcn tlmn tlmx wcfav wcfcn wcfmn wcfmx) ) {
		if (defined $l->{$var}) { $a{$var} = $l->{$var}; } else { $a{$var} = 0; }
	}
	$a{time} = $tm; $a{interval} = $int; $a{node} = $node;
	$a{timeunit} = $tmu; $a{sizeunit} = $szu;
}

sub NodeCachePrint {
	# Node,Time,Interval (s),
	# cvb = Total cache usage (byte),cmb = Write cache usage (byte), 
	
	my @idlist = keys(%{$nodecache_accum});
	my @hdr = qw(time interval cfav cfcn cfmn cfmx dlav dlcn dlmn dlmx drll dtav dtcn dtmn dtmx gcll mll plav plcn plmn plmx slav slcn slmn slmx taav tacn tamn tamx tlav tlcn tlmn tlmx wcfav wcfcn wcfmn wcfmx);
	print PERFOUT "Node,",join(',',@hdr),"\n";
	foreach my $id (sort (@idlist)) {
		my ($rtpo,$wtpo,$repo,$wepo,$rqpo,$wqpo);
		my $p = $nodecache_accum->{$id};
		#
		print PERFOUT ($id,",");
		foreach my $h (@hdr) {
			print PERFOUT ($p->{$h},",");
		}
		print PERFOUT ("\n");
	}
	
}

###############################################################################
#
# DriveStatistics
#
# 1. Called by CountData
#
###############################################################################

sub DriveStatistics {
	# Drive Level Statistics
	my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_drive}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_drive}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nDrive Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_drive}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_drive}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for Drive Level Statistic. Time: $ltm. Node: $node.\n";
			return SVCPRF103W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_drive}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_drive}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_drive}->{$node}->{mdsk}};
		my $ldata_ref = \@{$last_data_ref->{svc_drive}->{$node}->{mdsk}};

		my $drives = &GetDriveList($pdata_ref);
		foreach my $rec (@{$drives}) {
			my $precdata_ref = 0; my $lrecdata_ref = 0;
			$precdata_ref = &GetDriveData($rec,$pdata_ref);
			$lrecdata_ref = &GetDriveData($rec,$ldata_ref);
                        if ( $precdata_ref == 0 || $lrecdata_ref == 0 ) {
                            print "svcperf.pl: WARNING: Data for Drive $rec not valid. Continue.\n";
                            next;
                        }
			&DriveDiff($lrecdata_ref,$precdata_ref,$int,$szunit,$tmunit,$l_time);
		}
	}
	&DrivePrint();
	return 0;
}

sub GetSizeUnits {
	my $unit = shift;
	if ( not defined $unit ) {
		print "svcperf.pl: WARNING: Size Units is not defined.Use defalt value 512B. Continue.\n";
		return 512;
	}
	if ($unit eq "1B") { return 1; }
	elsif ($unit eq "512B") { return 512; }
	elsif ($unit eq "1K") { return 1024; }
	elsif ($unit eq "1M") { return 1024 * 1024; }
	elsif ($unit eq "1G") { return 1024 * 1024 * 1024; }
}

sub GetTimeUnits {
	my $unit = shift;
	# msec
	return $unit;
}


sub GetDriveList {
	my ($p_ref) = @_;
	my $d;
	foreach my $a (@{$p_ref}) {
		push(@{$d},$a->{idx});
	}
	return $d;
}

sub GetDriveData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d == $a->{idx} ) {
			return \%{$a}; 
		}
	}
}

sub DriveDiff {
	my ($l,$p,$int,$szu,$tmu,$tm) = @_;
	my %t;
	my $drv = $p->{idx};
	#
	foreach my $var ( qw(ro wo) ) {
		if (defined $l->{$var} && defined $p->{$var}) { 
			$t{$var} = DiffCalc($l->{$var},$p->{$var},"Drive: ".$drv." var: ".$var); 
			$t{$var."ps"} = $t{$var} / $int;
		} else {
			$t{$var} = 0;
			$t{$var."ps"} = 0;
		}
	}
	#
	foreach my $var ( qw(rb wb) ) {
		if (defined $l->{$var} && defined $p->{$var}) { 
			$t{$var} = DiffCalc($l->{$var},$p->{$var},"Drive: ".$drv." var: ".$var) * $szu; 
			$t{$var."ps"} = $t{$var} / $int;
		} else {
			$t{$var} = 0;
			$t{$var."ps"} = 0;
		}
	}
	#
	foreach my $var ( qw(pre pro pwe pwo) ) {
		if (defined $l->{$var}) { $t{$var} = $l->{$var}; } else { $t{$var} = 0; }
	}
	#
	foreach my $var ( qw(ure urq uwe uwq re we rq wq) ) {
		if (defined $l->{$var} && defined $p->{$var}) { $t{$var} = DiffCalc($l->{$var},$p->{$var},"Drive: ".$drv." var: ".$var); } else { $t{$var} = 0; }
	}
	#
	if ( exists($drive_accum{$drv}) ) {
		my $a = $drive_accum{$drv};
		foreach my $var ( qw(ro wo rb wb rops wops rbps wbps ure urq uwe uwq pre pro pwe pwo re we rq wq) ) {
			$a->{$var} = $a->{$var} + $t{$var};
		}
	} else {
		my %a; $drive_accum{$drv} = \%a;
		$a{time} = $tm; $a{int} = $int;
		foreach my $var ( qw(ro wo rb wb rops wops rbps wbps ure urq uwe uwq pre pro pwe pwo re we rq wq) ) {
			$a{$var} = $t{$var};
		}
	}
}

sub DrivePrint {
	# Drive,Time,Interval (s),
	# Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),
	# Read Data Rate (B/s),Write Data Rate (KB/s),Total Data Rate (B/s),
	# Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),
	# Backend Read Response Time (ms),Backend Write Response Time (ms),Overall Backend Response Time (ms),
	# Backend Read Queue Time (ms),Backend Write Queue Time (ms),Overall Backend Queue Time (ms),
	# Peak Read Response Time (ms),Peak Write Response Time(ms),
	#
	# Enclosure ID,Slot ID,Node ID,Node Name,Mdisk (aka Array) ID,Mdisk (aka Array) Name,
	# Member ID,Vendor,RPM,Product,FRU Part Number,Quorum ID,UID,
	# Firmware Level,FPGA Level,Block Size (bytes),
	# Use,Capacity $BYTES,Capacity $TB
	print PERFOUT "Drive,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Backend Read Response Time (ms),Backend Write Response Time (ms),Overall Backend Response Time (ms),Backend Read Queue Time (ms),Backend Write Queue Time (ms),Overall Backend Queue Time (ms),Peak Read Response Time (ms),Peak Write Response Time(ms),Enclosure ID,Slot ID,Node ID,Node Name,Mdisk (aka Array) ID,Mdisk (aka Array) Name,Member ID,Vendor,RPM,Product,FRU Part Number,Quorum ID,UID,Firmware Level,FPGA Level,Block Size (bytes),Use,Capacity (bytes),Capacity (TB)\n";
	my @drives = keys(%{$drive_accum});
	foreach my $drv (sort { $a <=> $b } (@drives)) {
		my ($rtpo,$wtpo,$repo,$rqpo,$wepo,$wqpo,$oepo,$oqpo,$prepo,$pwepo);
		my $p = $drive_accum->{$drv};
		my $c = $cfg_ref->{svc_drive}->{sprintf("%04d",$drv)};
		if ($p->{ro} > 0) {$rtpo = $p->{rb} / $p->{ro} / 1024;} else {$rtpo = 0;}
		if ($p->{wo} > 0) {$wtpo = $p->{wb} / $p->{wo} / 1024;} else {$wtpo = 0;}
		if ($p->{ro} > 0) {$repo = $p->{re} / $p->{ro}} else {$repo = 0}
		if ($p->{wo} > 0) {$wepo = $p->{we} / $p->{wo}} else {$wepo = 0}
		if (($p->{ro} + $p->{wo}) > 0) {$oepo = ($p->{re} + $p->{we}) / ($p->{ro} + $p->{wo})} else {$oepo = 0}
		if ($p->{ro} > 0) {$rqpo = $p->{rq} / $p->{ro}} else {$rqpo = 0}
		if ($p->{wo} > 0) {$wqpo = $p->{wq} / $p->{wo}} else {$wqpo = 0}
		if (($p->{ro} + $p->{wo}) > 0) {$oqpo = ($p->{rq} + $p->{wq}) / ($p->{ro} + $p->{wo})} else {$oqpo = 0}

		if ($p->{ro} > 0) {$prepo = ($p->{pre} + $p->{pro}) / $p->{ro}} else {$prepo = 0}
		if ($p->{wo} > 0) {$pwepo = ($p->{pwe} + $p->{pwo}) / $p->{wo}} else {$pwepo = 0}

                if ( not defined $c->{node_id} ) { $c->{node_id} = "" };
                if ( not defined $c->{node_name} ) { $c->{node_name} = "" };

                #print STDERR "__DBG__Drive: $drv -- \n";
                #if ($drv == 20) { print STDERR "__DBG__Drive: $drv -- \n",Dumper($p),"\n",Dumper($c),"\n" };

		printf PERFOUT ("%04d,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%s,%.3f,%.3f,\n",
			$drv,$p->{time},$p->{int},
			$p->{rops},$p->{wops},$p->{rops} + $p->{wops},
			$p->{rbps}/1024,$p->{wbps}/1024,($p->{rbps} + $p->{wbps})/1024,
			$rtpo,$wtpo,($rtpo + $wtpo)/2,
			$repo,$wepo,$oepo,
			$rqpo - $repo,$wqpo - $wepo,$oqpo - $oepo,
			$prepo,$pwepo,
			$c->{enclosure_id},$c->{slot_id},$c->{node_id},$c->{node_name},
			$c->{mdisk_id},$c->{mdisk_name},
			$c->{member_id},"","","","","","",	# Vendor,RPM,Product,FRU Part Number,Quorum ID,UID,
			"","",0,                        # Firmware Level,FPGA Level,Block Size (bytes),
			$c->{use},$c->{capacity},$c->{capacity}/1099511627776,	    # Use,Capacity $BYTES,Capacity $TB
			);
	}
	return 0;
}


###############################################################################
#
# MDiskStatistics
#
# 1. Called by CountData
#
###############################################################################
sub MDiskStatistics {
	# Managed Disk Level Statistics
	my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_mdsk}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_mdsk}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nManaged Disk Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_mdsk}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_mdsk}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for Managed Disk Level Statistic. Time: $ltm. Node: $node.\n";
			return SVCPRF104W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_mdsk}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_mdsk}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_mdsk}->{$node}->{mdsk}};
		my $ldata_ref = \@{$last_data_ref->{svc_mdsk}->{$node}->{mdsk}};

		my $disks = &GetMDiskList($pdata_ref);
		foreach my $rec (@{$disks}) {
			my $precdata_ref = 0; my $lrecdata_ref = 0;
			$precdata_ref = &GetMDiskData($rec,$pdata_ref);
			$lrecdata_ref = &GetMDiskData($rec,$ldata_ref);
                        if ( $precdata_ref == 0 || $lrecdata_ref == 0 ) {
                            print "svcperf.pl: WARNING: Data for Managed Disk $rec not valid. Continue.\n";
                            next;
                        }
			&MDiskDiff($lrecdata_ref,$precdata_ref,$int,$szunit,$tmunit,$l_time);
		}
	}
	&MDiskPrint();
	return 0;
}


sub GetMDiskList {
	my ($p_ref) = @_;
	my $d;
	foreach my $a (@{$p_ref}) {
		push(@{$d},$a->{idx});
	}
	return $d;
}

sub GetMDiskData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d == $a->{idx} ) {
			return \%{$a}; 
		}
	}
}

sub MDiskDiff {
	my ($l,$p,$int,$szu,$tmu,$tm) = @_;
	my %t;
	my $dsk = $p->{idx};
	#
	foreach my $var ( qw(ro wo) ) {
		if (defined $l->{$var} && defined $p->{$var}) { 
			$t{$var} = DiffCalc($l->{$var},$p->{$var},"MDisk: ".$dsk." var: ".$var); 
			$t{$var."ps"} = $t{$var} / $int;
		} else {
			$t{$var} = 0;
			$t{$var."ps"} = 0;
		}
	}
	#
	foreach my $var ( qw(rb wb) ) {
		if (defined $l->{$var} && defined $p->{$var}) { 
			$t{$var} = DiffCalc($l->{$var},$p->{$var},"MDisk: ".$dsk." var: ".$var) * $szu; 
			$t{$var."ps"} = $t{$var} / $int;
		} else {
			$t{$var} = 0;
			$t{$var."ps"} = 0;
		}
	}
	#
	foreach my $var ( qw(pre pro pwe pwo) ) {
		if (defined $l->{$var}) { $t{$var} = $l->{$var}; } else { $t{$var} = 0; }
	}
	#
	foreach my $var ( qw(ure urq uwe uwq re we rq wq) ) {
		if (defined $l->{$var} && defined $p->{$var}) { $t{$var} = DiffCalc($l->{$var},$p->{$var},"MDisk: ".$dsk." var: ".$var); } else { $t{$var} = 0; }
	}
	#
	if ( exists($mdisk_accum{$dsk}) ) {
		my $a = $mdisk_accum{$dsk};
		foreach my $var ( qw(ro wo rb wb rops wops rbps wbps ure urq uwe uwq pre pro pwe pwo re we rq wq) ) {
			$a->{$var} = $a->{$var} + $t{$var};
		}
	} else {
		my %a; $mdisk_accum{$dsk} = \%a;
		$a{time} = $tm; $a{int} = $int;
		foreach my $var ( qw(ro wo rb wb rops wops rbps wbps ure urq uwe uwq pre pro pwe pwo re we rq wq) ) {
			$a{$var} = $t{$var};
		}
	}
}

sub MDiskPrint {
	# Managed Disk,Time,Interval (s),
	# Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),
	# Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),
	# Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),
	# Backend Read Response Time (ms),Backend Write Response Time (ms),Overall Backend Response Time (ms),
	# Backend Read Queue Time (ms),Backend Write Queue Time (ms),Overall Backend Queue Time (ms),
	# Peak Read Response Time (ms),Peak Write Response Time(ms),
	#
	# Managed Disk Name,Managed Disk Group ID,Managed Disk Group Name,
	# Controller ID,Controller Name,Controller WWNN,Controller LUN (Decimal),Controller LUN (Hex),
	# Preferred WWPN,Quorum Index,Tier
	print PERFOUT "Managed Disk ID,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Backend Read Response Time (ms),Backend Write Response Time (ms),Overall Backend Response Time (ms),Backend Read Queue Time (ms),Backend Write Queue Time (ms),Overall Backend Queue Time (ms),Peak Read Response Time (ms),Peak Write Response Time(ms),Managed Disk Name,Managed Disk Group ID,Managed Disk Group Name,Controller ID,Controller Name,Controller WWNN,Controller LUN (Decimal),Controller LUN (Hex),Preferred WWPN,Quorum Index,Tier\n";

	my @disks = keys(%{$mdisk_accum});
	foreach my $dsk (sort { $a <=> $b } (@disks)) {
		my ($rtpo,$wtpo,$repo,$rqpo,$wepo,$wqpo,$oepo,$oqpo,$prepo,$pwepo);
		my $p = $mdisk_accum->{$dsk};
		my $c = $cfg_ref->{svc_mdsk}->{sprintf("%04d",$dsk)};
		if ($p->{ro} > 0) {$rtpo = $p->{rb} / $p->{ro} / 1024;} else {$rtpo = 0;}
		if ($p->{wo} > 0) {$wtpo = $p->{wb} / $p->{wo} / 1024;} else {$wtpo = 0;}
		if ($p->{ro} > 0) {$repo = $p->{re} / $p->{ro}} else {$repo = 0}
		if ($p->{wo} > 0) {$wepo = $p->{we} / $p->{wo}} else {$wepo = 0}
		if (($p->{ro} + $p->{wo}) > 0) {$oepo = ($p->{re} + $p->{we}) / ($p->{ro} + $p->{wo})} else {$oepo = 0}
		if ($p->{ro} > 0) {$rqpo = $p->{rq} / $p->{ro}} else {$rqpo = 0}
		if ($p->{wo} > 0) {$wqpo = $p->{wq} / $p->{wo}} else {$wqpo = 0}
		if (($p->{ro} + $p->{wo}) > 0) {$oqpo = ($p->{rq} + $p->{wq}) / ($p->{ro} + $p->{wo})} else {$oqpo = 0}

		if ($p->{ro} > 0) {$prepo = ($p->{pre} + $p->{pro}) / $p->{ro}} else {$prepo = 0}
		if ($p->{wo} > 0) {$pwepo = ($p->{pwe} + $p->{pwo}) / $p->{wo}} else {$pwepo = 0}
		

		printf PERFOUT ("%04d,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%s,\n",
			$dsk,$p->{time},$p->{int},
			$p->{rops},$p->{wops},$p->{rops} + $p->{wops},
			$p->{rbps}/1024,$p->{wbps}/1024,($p->{rbps} + $p->{wbps})/1024,
			$rtpo,$wtpo,($rtpo + $wtpo)/2,
			$repo,$wepo,$oepo,
			$rqpo - $repo,$wqpo - $wepo,$oqpo - $oepo,
			$prepo,$pwepo,
			$c->{name},$c->{mdisk_grp_id},$c->{mdisk_grp_name},
			0,$c->{controller_name},"",$c->{'ctrl_LUN_#'},"",  # Controller ID,Controller WWNN,Controller LUN (Hex),
			"",0,$c->{tier},  # Preferred WWPN,Quorum Index,
	
			);
	}
}


###############################################################################
#
# VDiskStatistics
#
# 1. Called by CountData
#
###############################################################################
sub VDiskStatistics {
	my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_vdsk}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_vdsk}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nVolume Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_vdsk}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_vdsk}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for Volume Level Statistic. Time: $ltm. Node: $node.\n";
            return SVCPRF105W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_vdsk}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_vdsk}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_vdsk}->{$node}->{vdsk}};
		my $ldata_ref = \@{$last_data_ref->{svc_vdsk}->{$node}->{vdsk}};

		my $disks = &GetVDiskList($pdata_ref);
		foreach my $rec (@{$disks}) {
			my $precdata_ref = 0; my $lrecdata_ref = 0;
			$precdata_ref = &GetVDiskData($rec,$pdata_ref);
			$lrecdata_ref = &GetVDiskData($rec,$ldata_ref);
                        if ( $precdata_ref == 0 || $lrecdata_ref == 0 ) {
                            print "svcperf.pl: WARNING: Data for Volume $rec not valid. Continue.\n";
                            next;
                        }
			&VDiskDiff($lrecdata_ref,$precdata_ref,$int,$szunit,$tmunit,$l_time);
		}
	}
	&VDiskPrint();
	return 0;
}


sub GetVDiskList {
	my ($p_ref) = @_;
	my $d;
	foreach my $a (@{$p_ref}) {
		push(@{$d},$a->{idx});
	}
	return $d;
}

sub GetVDiskData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d == $a->{idx} ) {
			return \%{$a}; 
		}
	}
}

sub VDiskDiff {
	my ($l,$p,$int,$szu,$tmu,$tm) = @_;
	my %t;
	my $dsk = $p->{idx};
	#
	foreach my $var ( qw(rlw wlw) ) {
		if (defined $l->{$var}) { 
			$t{$var} = $l->{$var}; 
		} else {
			$t{$var} = 0;
		}
	}
	#
	foreach my $var ( qw(ro wo) ) {
		if (defined $l->{$var} && defined $p->{$var}) { 
			$t{$var} = DiffCalc($l->{$var},$p->{$var},"Volume: ".$dsk." var: ".$var); 
			$t{$var . "ps"} = $t{$var} / $int;
		} else {
			$t{$var} = 0;
			$t{$var . "ps"} = 0;
		}
	}
	#
	foreach my $var ( qw(rb wb) ) {
		if (defined $l->{$var} && defined $p->{$var}) { 
			$t{$var} = DiffCalc($l->{$var},$p->{$var},"Volume: ".$dsk." var: ".$var) * $szu; 
			$t{$var . "ps"} = $t{$var} / $int;
		} else {
			$t{$var} = 0;
			$t{$var . "ps"} = 0;
		}
	}
	# Volume perf
	foreach my $var ( qw(rl wl xl) ) {
		if (defined $l->{$var} && defined $p->{$var}) { $t{$var} = DiffCalc($l->{$var},$p->{$var},"Volume: ".$dsk." var: ".$var); } else { $t{$var} = 0; }
	}
	#
	if ( exists($vdisk_accum{$dsk}) ) {
		my $a = $vdisk_accum{$dsk};
		foreach my $var ( qw(ro wo rb wb rops wops rbps wbps rl wl xl rlw wlw) ) {
			$a->{$var} = $a->{$var} + $t{$var};
		}
	} else {
		my %a; $vdisk_accum{$dsk} = \%a;
		$a{time} = $tm; $a{int} = $int;$a{timeunit} = $tmu; $a{sizeunit} = $szu;
		foreach my $var ( qw(ro wo rb wb rops wops rbps wbps rl wl xl rlw wlw) ) {
			$a{$var} = $t{$var};
		}
	}
}

sub VDiskPrint {
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
	print PERFOUT "Volume ID,Time,Interval (s),Read IO Rate (IO/s),Write IO Rate (IO/s),Total IO Rate (IO/s),Read Data Rate (KB/s),Write Data Rate (KB/s),Total Data Rate (KB/s),Read Transfer Size (kB),Write Transfer Size (kB),Overall Transfer Size (kB),Read Response Time (ms),Write Response Time (ms),Overall Response Time (ms),Peak Read Response Time (ms),Peak Write Response Time (ms),Host Delay (assuming that all host delay is writes) (ms),Host Delay (assuming that host delay is evenly spread between read and writes) (ms),Read Hits,Write Hits,Data Read (KB),Data Written (KB),Volume (Vdisk) Name,Managed Disk Group ID,Managed Disk Group Name,IO Group ID,IO Group Name,Remote Copy relationship ID,Remote Copy relationship name,Remote Copy Change Volume relationship,FlashCopy map ID,FlashCopy map name,FlashCopy map count,Copy Count,Space Efficient Copy Count,Cache state,Easy Tier On/Off,Easy Tier Status,Preferred Node ID,Capacity (TB),Real Capacity (TB),Used Capacity (TB),Auto Expand,Grain Size,Throttle Unit,Throttle Rate,UDID (for HPUX),\n";
	my @disks = keys(%{$vdisk_accum});
	foreach my $dsk (sort { $a <=> $b } (@disks)) {
		my ($c,$fc,$rtpo,$wtpo,$rlpo,$wlpo,$xlpo,$olpo,$rlwpo,$wlwpo);
		my $p = $vdisk_accum->{$dsk};
		if ( defined $cfg_ref->{svc_vdsk}->{sprintf("%04d",$dsk)} ) {
			$c = $cfg_ref->{svc_vdsk}->{sprintf("%04d",$dsk)};
		} else {
			%{$c} = ("name" => "","mdisk_grp_id" => "","mdisk_grp_name" => "",
			      "IO_group_id" => "","IO_group_name" => "",
			      "RC_id" => "","RC_name" => "","RC_change" => "",
			      "FC_id" => "","FC_name" => "","fc_map_count" => 0,
			      "copy_count" => 0,"se_copy_count" => 0,"fast_write_state" => "",
			      "capacity" => 0);
		}
		if ( defined $fullcfg_ref->{svc_vdsk}->{sprintf("%04d",$dsk)} ) {
			$fc = $fullcfg_ref->{svc_vdsk}->{sprintf("%04d",$dsk)};
		}
		my @a;
		my @b;
		if ( not defined $c->{mdisk_grp_id} ) {
			if ( defined $c->{"copy_0_mdisk_grp_id"} ) {
			        push(@a,$c->{"copy_0_mdisk_grp_id"});
			}
			if ( defined $c->{"copy_1_mdisk_grp_id"} ) {
				push(@a,$c->{"copy_1_mdisk_grp_id"});
			}
			if ( defined $c->{"copy_0_mdisk_grp_name"} ) {
				push(@b,$c->{"copy_0_mdisk_grp_name"});
			}
			if ( defined $c->{"copy_1_mdisk_grp_name"} ) {
				push(@b,$c->{"copy_1_mdisk_grp_name"});
			}
		        if ( scalar(@a) ) {
			        $c->{mdisk_grp_id} = join(" ",@a);
			        $c->{mdisk_grp_name} = join(" ",@b);
		        } else {
			        $c->{mdisk_grp_id} = "";
			        $c->{mdisk_grp_name} = "";
		        } 
		} elsif ( $c->{mdisk_grp_id} eq "many" ) {
			if ( defined $fc->{"copy_0_mdisk_grp_id"} ) {
				push(@a,$fc->{"copy_0_mdisk_grp_id"});
			}
			if ( defined $fc->{"copy_1_mdisk_grp_id"} ) {
				push(@a,$fc->{"copy_1_mdisk_grp_id"});
			}
			if ( defined $fc->{"copy_0_mdisk_grp_name"} ) {
				push(@b,$fc->{"copy_0_mdisk_grp_name"});
			}
			if ( defined $fc->{"copy_1_mdisk_grp_name"} ) {
				push(@b,$fc->{"copy_1_mdisk_grp_name"});
			}
		        if ( scalar(@a) ) {
			        $c->{mdisk_grp_id} = join(" ",@a);
			        $c->{mdisk_grp_name} = join(" ",@b);
		        } else {
			        $c->{mdisk_grp_id} = "";
			        $c->{mdisk_grp_name} = "";
		        } 
                }

	        if ($p->{ro} > 0) {$rtpo = $p->{rb} / $p->{ro} / 1024;} else {$rtpo = 0;}
		if ($p->{wo} > 0) {$wtpo = $p->{wb} / $p->{wo} / 1024;} else {$wtpo = 0;}
		if ($p->{ro} > 0) {$rlpo = $p->{rl} / $p->{ro}} else {$rlpo = 0}
		if ($p->{wo} > 0) {$wlpo = $p->{wl} / $p->{wo}} else {$wlpo = 0}
		if ($p->{ro} > 0) {$rlwpo = $p->{rlw} / $p->{ro}} else {$rlwpo = 0}
		if ($p->{wo} > 0) {$wlwpo = $p->{wlw} / $p->{wo}} else {$wlwpo = 0}
		#if (($p->{ro} + $p->{wo}) > 0) {$olpo = ($p->{rl} + $p->{wl}) / ($p->{ro} + $p->{wo})} else {$olpo = 0}
		$olpo = ($rlpo + $wlpo)/2;

                #print STDERR "__DBG__: Volume ",$dsk,"\n";
                #if($dsk == 0) {print STDERR "__DBG__:",Dumper($p),"\n",Dumper($c),"\n";}

		printf PERFOUT ("%04d,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%d,%d,%s,%s,%s,%s,%.3f,%d,%d,%d,%d,%s,%d,%s,\n",
			$dsk,$p->{time},$p->{int},
			$p->{rops},$p->{wops},$p->{rops} + $p->{wops},
			$p->{rbps}/1024,$p->{wbps}/1024,($p->{rbps} + $p->{wbps})/1024,
			$rtpo,$wtpo,($rtpo + $wtpo)/2,
			$rlpo,$wlpo,$olpo,
			$rlwpo,$wlwpo,0,0,
			$p->{ro},$p->{wo},$p->{rb}/1024,$p->{wb}/1024,
			$c->{name},$c->{mdisk_grp_id},$c->{mdisk_grp_name},$c->{IO_group_id},$c->{IO_group_name},
			$c->{RC_id},$c->{RC_name},$c->{RC_change},
			$c->{FC_id},$c->{FC_name},$c->{fc_map_count},
			$c->{copy_count},$c->{se_copy_count},$c->{fast_write_state},"","",  # Easy Tier On/Off,Easy Tier Status,
			"",$c->{capacity},0,0,                                # Preferred Node ID,Real Capacity (TB),Used Capacity (TB),
			0,0,"",0,"", 	                                          # Auto Expand,Grain Size,Throttle Unit,Throttle Rate,UDID (for HPUX)
			);
	}
	
}

###############################################################################
#
# VDiskCacheStatistics
#
# 1. Called by CountData
#
###############################################################################
sub VDiskCacheStatistics {
	my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_vdsk}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_vdsk}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nVolume Cache Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_vdsk}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_vdsk}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for Volume Cache Level Statistic. Time: $ltm. Node: $node.\n";
            return SVCPRF105W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_vdsk}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_vdsk}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_vdsk}->{$node}->{vdsk}};
		my $ldata_ref = \@{$last_data_ref->{svc_vdsk}->{$node}->{vdsk}};

		my $disks = &GetVDiskCacheList($pdata_ref);
		foreach my $rec (@{$disks}) {
			my $precdata_ref = 0; my $lrecdata_ref = 0;
			$precdata_ref = &GetVDiskCacheData($rec,$pdata_ref);
			$lrecdata_ref = &GetVDiskCacheData($rec,$ldata_ref);
                        if ( $precdata_ref == 0 || $lrecdata_ref == 0 ) {
                            print "svcperf.pl: WARNING: Data for Volume $rec not valid. Continue.\n";
                            next;
                        }
			&VDiskCacheDiff($lrecdata_ref,$precdata_ref,$int,$szunit,$tmunit,$l_time);
		}
	}
	&VDiskCachePrint();
	return 0;
}


sub GetVDiskCacheList {
	my ($p_ref) = @_;
	my $d;
	foreach my $a (@{$p_ref}) {
		push(@{$d},$a->{idx});
	}
	return $d;
}

sub GetVDiskCacheData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d == $a->{idx} ) {
			return \%{$a}; 
		}
	}
}

sub VDiskCacheDiff {
	my ($l,$p,$int,$szu,$tmu,$tm) = @_;
	my %t;
	my $dsk = $p->{idx};
	# Volume cache perf
	foreach my $var ( qw(cv cm) ) {
		if (defined $l->{$var}) { $t{$var} = $l->{$var}; } else { $t{$var} = 0; }
	}
	#
	foreach my $var ( qw(ctps ctds ctrhs ctrhps ctrs ctwhs ctws ctwfts ctwwts ctwfws ctwfwshs) ) {
		if (defined $l->{$var} && defined $p->{$var}) { $t{$var} = DiffCalc($l->{$var},$p->{$var},"VolumeCache: ".$dsk." var: ".$var); } else { $t{$var} = 0; }
	}
	#
	if ( exists($vdiskcache_accum{$dsk}) ) {
		my $a = $vdiskcache_accum{$dsk};
		foreach my $var ( qw(cv cm ctps ctds ctrhs ctrhps ctrs ctwhs ctws ctwfts ctwwts ctwfws ctwfwshs) ) {
			$a->{$var} = $a->{$var} + $t{$var};
		}
	} else {
		my %a; $vdiskcache_accum{$dsk} = \%a;
		$a{time} = $tm; $a{int} = $int;$a{timeunit} = $tmu; $a{sizeunit} = $szu;
		foreach my $var ( qw(cv cm ctps ctds ctrhs ctrhps ctrs ctwhs ctws ctwfts ctwwts ctwfws ctwfwshs) ) {
			$a{$var} = $t{$var};
		}
	}
}

sub VDiskCachePrint {
	#
	print PERFOUT "Volume ID,Time,Interval (s),Volume (Vdisk) Name,Cache read hits (%),Cache write hits (%),Read cache usage (kB),Write cache usage (kB),Total cache usage (kB),Cache data prestaged (kB/s),Cache data destaged (kB/s),Cache read hits (%),Cache read hits on prestaged data (%),Cache write hits on dirty data (%),Cache writes in Flush Through mode (kB/s),Cache writes in Write Through mode (kB/s),Cache writes in Fast Write mode (kB/s),Cache writes in Fast Write mode that were written in Write Through mode due to the lack of memory (kB/s),\n";
	  	  
	my @disks = keys(%{$vdisk_accum});
	foreach my $dsk (sort { $a <=> $b } (@disks)) {
		my ($c,$rtpo,$wtpo,$rlpo,$wlpo,$xlpo,$olpo);
		my $p = $vdiskcache_accum->{$dsk};
		if ( defined $cfg_ref->{svc_vdsk}->{sprintf("%04d",$dsk)} ) {
			$c = $cfg_ref->{svc_vdsk}->{sprintf("%04d",$dsk)};
		} else {
			%{$c} = ("name" => "");
		}
		# Cache
		$p->{cvb} = $p->{cv} * $p->{sizeunit};
		$p->{cmb} = $p->{cm} * $p->{sizeunit};
		$p->{ctpps} = $p->{ctps} * $p->{sizeunit} / $p->{int};
		$p->{ctdps} = $p->{ctds} * $p->{sizeunit} / $p->{int};
		if ($p->{ctrs} > 0)  { $p->{ctrhr} = $p->{ctrhs} * 100 / $p->{ctrs};   } else { $p->{ctrhr} = 0; }
		if ($p->{ctrs} > 0) { $p->{ctrhrp} = $p->{ctrhps} * 100 / $p->{ctrs}; } else { $p->{ctrhrp} = 0; }
		if ($p->{ctws} > 0)  { $p->{ctwhr} = $p->{ctwhs} * 100 / $p->{ctws};   } else { $p->{ctwhr} = 0; }
		$p->{ctwftps} = $p->{ctwfts} * $p->{sizeunit} / $p->{int};
		$p->{ctwwtps} = $p->{ctwwts} * $p->{sizeunit} / $p->{int};
		$p->{ctwfwps} = $p->{ctwfws} * $p->{sizeunit} / $p->{int};
		$p->{ctwfwshps} = $p->{ctwfwshs} * $p->{sizeunit} / $p->{int};

                #print STDERR "__DBG__: Volume ",$dsk,"\n";
                #if($dsk == 0) {print STDERR "__DBG__:",Dumper($p),"\n",Dumper($c),"\n";}

		printf PERFOUT ("%04d,%s,%d,%s,%.3f,%.3f,%d,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,\n",
			# Volume ID,Time,Interval (s),
			$dsk,$p->{time},$p->{int},
			# Volume (Vdisk) Name,
			$c->{name},
			# Cache read hits (%),Cache write hits (%),
			$p->{ctrhr},$p->{ctwhr},
			# Read cache usage (kB),Write cache usage (kB),Total cache usage (kB)
			ConvSizeUnits("KB",$p->{cvb} - $p->{cmb}),ConvSizeUnits("KB",$p->{cmb}),ConvSizeUnits("KB",$p->{cvb}),
			# Cache data prestaged (kB/s),Cache data destaged (kB/s),
			ConvSizeUnits("KB",$p->{ctpps}),ConvSizeUnits("KB",$p->{ctdps}),
			# Cache read hits (%),Cache read hits on prestaged data (%),Cache write hits on dirty data (%),
			$p->{ctrhr},$p->{ctrhrp},$p->{ctwhr},
			# Cache writes in Flush Through mode (kB/s),Cache writes in Write Through mode (kB/s),
			ConvSizeUnits("KB",$p->{ctwftps}),ConvSizeUnits("KB",$p->{ctwwtps}),
			# Cache writes in Fast Write mode (kB/s),Cache writes in Fast Write mode that were written in Write Through mode due to the lack of memory (kB/s)
			ConvSizeUnits("KB",$p->{ctwfwps}),ConvSizeUnits("KB",$p->{ctwfwshps}),
			);
	}
	
}



###############################################################################
#
# PortStatistics
#
# 1. Called by CountData
#
###############################################################################
sub PortStatistics {
    my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nPort Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_node}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_node}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for Port Level Statistic. Time: $ltm. Node: $node.\n";
			return SVCPRF106W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_node}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_node}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_node}->{$node}->{port}};
		my $ldata_ref = \@{$last_data_ref->{svc_node}->{$node}->{port}};

		my $ports = &GetPortList($pdata_ref);
		foreach my $rec (@{$ports}) {
			my $precdata_ref = 0; my $lrecdata_ref = 0;
			$precdata_ref = &GetPortData($rec,$pdata_ref);
			$lrecdata_ref = &GetPortData($rec,$ldata_ref);
                        if ( $precdata_ref == 0 || $lrecdata_ref == 0 ) {
                            print "svcperf.pl: WARNING: Data for Port $rec not valid. Continue.\n";
                            next;
                        }
			&PortDiff($lrecdata_ref,$precdata_ref,$int,$node,$szunit,$tmunit,$l_time);
		}
	}
	&PortPrint();
	return 0;
}


sub GetPortList {
	my ($p_ref) = @_;
	my $d;
	foreach my $a (@{$p_ref}) {
		push(@{$d},$a->{id});
	}
	return $d;
}

sub GetPortData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d == $a->{id} ) {
			return \%{$a}; 
		}
	}
}

sub PortDiff {
	my ($l,$p,$int,$node,$szu,$tmu,$tm) = @_;
	my ($ro,$wo,$rb,$wb,$rops,$wops,$rbps,$wbps,$rl,$wl,$xl);
	my $prt = $p->{id};
	#
	
	my %a = ('bbcz',0,'icrc',0,'itw',0,'lf',0,'lsi',0,'lsy',0,'pspe',0);
	$port_accum{$node."_p".sprintf("%02d",$prt)} = \%a;

	foreach my $var ( qw(cet het lnet rmet cer her lner rmer cbt hbt lnbt rmbt cbr hbr lnbr rmbr lf lsy lsi pspe itw icrc bbcz) ) {
		if (defined $l->{$var} && defined $p->{$var}) { 
			$a{$var} = DiffCalc($l->{$var},$p->{$var},"Port: ".$prt." var: ".$var); 
		} else { 
			$a{$var} = 0;
		}
	}
	#
	foreach my $var ( qw(node type wwpn fc_wwpn fcoe_wwpn iqn) ) {
		if (defined $l->{$var} && defined $p->{$var}) { $a{$var} = $l->{$var}; } else { $a{$var} = ""; }
	}
	#
	$a{time} = $tm; $a{interval} = $int; $a{node} = $node;
	$a{timeunit} = $tmu; $a{sizeunit} = $szu;
}

sub DiffCalc {
	my ($l,$p,$m) = @_;
	my $res;
	if ( $l >= $p ) {
		$res = $l - $p;
	} else {
		$res = $l;
		print ("svcperf.pl: WARNING: $m - Negative difference occured (prev = $p, last = $l).\n");
	}
	return($res);
}

sub PortPrint {
	# Port,Time,Interval (s),
	# Port Send IO Rate (IO/s),Port Receive IO Rate (IO/s),Total Port IO Rate (IO/s),
	# Port Send Data Rate (KB/s),Port Receive Data Rate (KB/s),Total Port Data Rate (KB/s),
	# Port Send Transfer Size (kB),Port Receive Transfer Size (kB),Overall Port Transfer Size (kB),
	# Port to Host Send IO Rate (IO/s),Port to Host Receive IO Rate (IO/s),Overall Port to Host IO Rate (IO/s),
	# Port to Host Send Data Rate (KB/s),Port to Host Receive Data Rate (KB/s),Overall Port to Host Data Rate (KB/s),
	# Port to Controller Send IO Rate (IO/s),Port to Controller Receive IO Rate (IO/s),Overall Port to Controller IO Rate (IO/s),
	# Port to Controller Send Data Rate (KB/s),Port to Controller Receive Data Rate (KB/s),Overall Port to Controller Data Rate (KB/s),
	# Port to Local Node Send IO Rate (IO/s),Port to Local Node Receive IO Rate (IO/s),Overall Port to Local Node IO Rate (IO/s),
	# Port to Local Node Send Data Rate (KB/s),Port to Local Node Receive Data Rate (KB/s),Overall Port to Local Node Data Rate (KB/s),
	# Port to Remote Node Send IO Rate (IO/s),Port to Remote Node Receive IO Rate (IO/s),Overall Port to Remote Node IO Rate (IO/s),
	# Port to Remote Node Send Data Rate (KB/s),Port to Remote Node Receive Data Rate (KB/s),Overall Port to Reomte Node Data Rate (KB/s),
	# Link Failure,Loss of Synch,Loss of Signal,Primitive Sequence Protocol Error,Invalid Transmission Word Count,Invalid CRC Count,Zero b2b (%)
	print PERFOUT "Port,Time,Interval (s),Port Send IO Rate (IO/s),Port Receive IO Rate (IO/s),Total Port IO Rate (IO/s),Port Send Data Rate (KB/s),Port Receive Data Rate (KB/s),Total Port Data Rate (KB/s),Port Send Transfer Size (kB),Port Receive Transfer Size (kB),Overall Port Transfer Size (kB),Port to Host Send IO Rate (IO/s),Port to Host Receive IO Rate (IO/s),Overall Port to Host IO Rate (IO/s),Port to Host Send Data Rate (KB/s),Port to Host Receive Data Rate (KB/s),Overall Port to Host Data Rate (KB/s),Port to Controller Send IO Rate (IO/s),Port to Controller Receive IO Rate (IO/s),Overall Port to Controller IO Rate (IO/s),Port to Controller Send Data Rate (KB/s),Port to Controller Receive Data Rate (KB/s),Overall Port to Controller Data Rate (KB/s),Port to Local Node Send IO Rate (IO/s),Port to Local Node Receive IO Rate (IO/s),Overall Port to Local Node IO Rate (IO/s),Port to Local Node Send Data Rate (KB/s),Port to Local Node Receive Data Rate (KB/s),Overall Port to Local Node Data Rate (KB/s),Port to Remote Node Send IO Rate (IO/s),Port to Remote Node Receive IO Rate (IO/s),Overall Port to Remote Node IO Rate (IO/s),Port to Remote Node Send Data Rate (KB/s),Port to Remote Node Receive Data Rate (KB/s),Overall Port to Reomte Node Data Rate (KB/s),Link Failure,Loss of Synch,Loss of Signal,Primitive Sequence Protocol Error,Invalid Transmission Word Count,Invalid CRC Count,Zero b2b (%),Node,Port type,WWPN,FC WWPN,FCoE WWPN,iSCSI IQN,\n";
	my @ports = keys(%{$port_accum});
	foreach my $prt (sort (@ports)) {
		my ($et,$etps,$er,$erps,$bt,$btps,$br,$brps,$ttps,$trps) = (0,0,0,0,0,0,0,0,0,0);
		my $p = $port_accum->{$prt};
		#
		$et = ($p->{cet} + $p->{het} + $p->{lnet} + $p->{rmet});
		$etps =  $et / $p->{interval};                                           # Send IO Rate (IO/s);
		$er = ($p->{cer} + $p->{her} + $p->{lner} + $p->{rmer});
		$erps = $er / $p->{interval};                                            # Receive IO Rate (IO/s)
		$bt = ($p->{cbt} + $p->{hbt} + $p->{lnbt} + $p->{rmbt}) * $p->{sizeunit};
		$btps = $bt / 1024 / $p->{interval};                                  # Send Data Rate (KB/s)
		$br = ($p->{cbr} + $p->{hbr} + $p->{lnbr} + $p->{rmbr}) * $p->{sizeunit};
		$brps = $br / 1024 / $p->{interval};                                  # Receive Data Rate (KB/s)
		if ($et > 0) { $ttps = $bt / 1024 / $et } else { $ttps = 0 }                       # Send Transfer Size (kB)
		if ($er > 0) { $trps = $br / 1024 / $er } else { $trps = 0 }                       # Receive Transfer Size (kB)
		
		printf PERFOUT ("%s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s,\n",
			$prt,$p->{time},$p->{interval},
			$etps,$erps,$etps + $erps,
			$btps,$brps,$btps + $brps,
			$ttps,$trps,($ttps + $trps)/2,
			$p->{het}/$p->{interval},$p->{her}/$p->{interval},($p->{het}+$p->{her})/$p->{interval},
			$p->{hbt}*$p->{sizeunit}/1024/$p->{interval}, $p->{hbr}*$p->{sizeunit}/1024/$p->{interval},($p->{hbt}+$p->{hbr})*$p->{sizeunit}/1024/$p->{interval},
			$p->{cet}/$p->{interval},$p->{cer}/$p->{interval},($p->{cet}+$p->{cer})/$p->{interval},
			$p->{cbt}*$p->{sizeunit}/1024/$p->{interval}, $p->{cbr}*$p->{sizeunit}/1024/$p->{interval},($p->{cbt}+$p->{cbr})*$p->{sizeunit}/1024/$p->{interval},
			$p->{lnet}/$p->{interval},$p->{lner}/$p->{interval},($p->{lnet}+$p->{lner})/$p->{interval},
			$p->{lnbt}*$p->{sizeunit}/1024/$p->{interval}, $p->{lnbr}*$p->{sizeunit}/1024/$p->{interval},($p->{lnbt}+$p->{lnbr})*$p->{sizeunit}/1024/$p->{interval},
			$p->{rmet}/$p->{interval},$p->{rmer}/$p->{interval},($p->{rmet}+$p->{rmer})/$p->{interval},
			$p->{rmbt}*$p->{sizeunit}/1024/$p->{interval}, $p->{rmbr}*$p->{sizeunit}/1024/$p->{interval},($p->{rmbt}+$p->{rmbr})*$p->{sizeunit}/1024/$p->{interval},
			$p->{lf},$p->{lsy},$p->{lsi},$p->{pspe},$p->{itw},$p->{icrc},$p->{bbcz},
			$p->{node},$p->{type},$p->{wwpn},$p->{fc_wwpn},$p->{fcoe_wwpn},$p->{iqn},
			);
	}
	
}

###############################################################################
#
# CPUNodeStatistics
#
# 1. Called by CountData
#
###############################################################################
sub CPUNodeStatistics {
    my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nCPU-Node Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_node}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_node}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for CPU-Node Level Statistic. Time: $ltm. Node: $node.\n";
			return SVCPRF109W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_node}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_node}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_node}->{$node}->{cpu}};
		my $ldata_ref = \@{$last_data_ref->{svc_node}->{$node}->{cpu}};

		&CPUNodeDiff($ldata_ref->[0],$pdata_ref->[0],$int,$node,$szunit,$tmunit,$l_time);
	}
	&CPUNodePrint();
	return 0;
}


sub GetCPUNodeData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d == $a->{id} ) {
			return \%{$a}; 
		}
	}
}

sub CPUNodeDiff {
	my ($l,$p,$int,$node,$szu,$tmu,$tm) = @_;
	#
	my %a; $cpunode_accum{$node} = \%a;
	my @keylist = keys(%{$p});
	foreach my $var (@keylist) {
		if (($l->{$var} - $p->{$var}) >= 0) {$a{$var} = $l->{$var} - $p->{$var};} else {$a{$var} = $l->{$var};}
	}
	$a{time} = $tm; $a{interval} = $int; $a{node} = $node;
	$a{timeunit} = $tmu; $a{sizeunit} = $szu;
}

sub CPUNodePrint {
	# CPU Core,Time,Interval,
	# Node,CPU Core ID,
	# CPU Utilization - System $PCENT,CPU Utilization - Compression $PCENT,
	print PERFOUT "Node,Time,Interval,CPU Busy,CPU Limited,CPU Utilization - System,CPU Utilization - Compression,\n";
	my @nodes = keys(%{$cpunode_accum});
	foreach my $nod (sort (@nodes)) {
		my ($ttps,$trps);
		my $p = $cpunode_accum->{$nod};
		#
		printf PERFOUT ("%s,%s,%d,%.3f,%.3f,%.3f,%.3f,\n",
			$nod,$p->{time},$p->{interval},
			$p->{busy}/$p->{interval}/10,$p->{limited}/$p->{interval}/10,
			$p->{system}/$p->{interval}/10,$p->{comp}/$p->{interval}/10,
			);
	}
	
}

###############################################################################
#
# CPUCoreStatistics
#
# 1. Called by CountData
#
###############################################################################
sub CPUCoreStatistics {
    my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nCPU-Core Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	#
	foreach my $node (sort(@nodes)) {
		my $ptm = $prev_data_ref->{svc_node}->{$node}->{timestamp};
		my $ltm = $last_data_ref->{svc_node}->{$node}->{timestamp};
		my $int = str2time($ltm) - str2time($ptm);
		if ($int <= 0) {
			print "svcperf.pl: WARNING: Interval lengt is <= 0 for CPU-Core Level Statistic. Time: $ltm. Node: $node.\n";
			return SVCPRF107W;
		}
		my $szunit = &GetSizeUnits($prev_data_ref->{svc_node}->{$node}->{sizeUnits});
		my $tmunit = &GetTimeUnits($prev_data_ref->{svc_node}->{$node}->{timeUnits});
		my $pdata_ref = \@{$prev_data_ref->{svc_node}->{$node}->{cpu_core}};
		my $ldata_ref = \@{$last_data_ref->{svc_node}->{$node}->{cpu_core}};

		my $cores = &GetCPUCoreList($pdata_ref);
		foreach my $rec (@{$cores}) {
			my $precdata_ref = 0; my $lrecdata_ref = 0;
			$precdata_ref = &GetCPUCoreData($rec,$pdata_ref);
			$lrecdata_ref = &GetCPUCoreData($rec,$ldata_ref);
                        if ( $precdata_ref == 0 || $lrecdata_ref == 0 ) {
                            print "svcperf.pl: WARNING: Data for CPU-Core $rec not valid. Continue.\n";
                            next;
                        }
			&CPUCoreDiff($lrecdata_ref,$precdata_ref,$int,$node,$szunit,$tmunit,$l_time);
		}
	}
	&CPUCorePrint();
	return 0;
}


sub GetCPUCoreList {
	my ($p_ref) = @_;
	my $d;
	foreach my $a (@{$p_ref}) {
		push(@{$d},$a->{id});
	}
	return $d;
}

sub GetCPUCoreData {
	my ($d,$d_ref) = @_;
	foreach my $a (@{$d_ref}) {
		if ( $d == $a->{id} ) {
			return \%{$a}; 
		}
	}
}

sub CPUCoreDiff {
	my ($l,$p,$int,$node,$szu,$tmu,$tm) = @_;
	my $id = $p->{id};
	#
	
	my %a; $cpucore_accum{$node."_core".sprintf("%02d",$id)} = \%a;
	my @keylist = keys(%{$p});
	foreach my $var (@keylist) {
		if ($var eq "id") { $a{$var} = $l->{$var}; next;}
		if (($l->{$var} - $p->{$var}) >= 0) {$a{$var} = $l->{$var} - $p->{$var};} else {$a{$var} = $l->{$var};}
	}
	$a{time} = $tm; $a{interval} = $int; $a{node} = $node;
	$a{timeunit} = $tmu; $a{sizeunit} = $szu;
}

sub CPUCorePrint {
	# CPU Core,Time,Interval,
	# Node,CPU Core ID,
	# CPU Utilization - System $PCENT,CPU Utilization - Compression $PCENT,
	print PERFOUT "CPU Core,Time,Interval,Node,CPU Core ID,CPU Utilization - System,CPU Utilization - Compression,\n";
	my @cores = keys(%{$cpucore_accum});
	foreach my $cor (sort (@cores)) {
		my ($ttps,$trps);
		my $p = $cpucore_accum->{$cor};
		#
		printf PERFOUT ("%s,%s,%d,%s,%d,%.3f,%.3f,\n",
			$cor,$p->{time},$p->{interval},
			$p->{node},$p->{id},
			$p->{system}/$p->{interval}/10,$p->{comp}/$p->{interval}/1000000,
			);
	}
	
}


###############################################################################
#
# ClearAccumData
#
# 1. Called in main loop
#
###############################################################################
sub ClearAccumData {
	undef %drive_accum;
	undef %mdisk_accum;
	undef %vdisk_accum;
	undef %vdiskcache_accum;
	undef %port_accum;
	undef %cpucore_accum;
	undef %nodenode_accum;
	undef %nodecache_accum;
	undef %node_accum;
	undef %mdiskgrp_cap;
}

###############################################################################
#
# CtrlC
#
# 1. Catch SIGINT
# 2. Ternimate process
#
###############################################################################

sub CtrlC {
	$terminate_pgm = 1;
	print("svcperf.pl: Terminating ...\n");
}

###############################################################################
#
# GetConfigFilename
#
# 1. Return filename of the latest config file
#
###############################################################################
sub GetConfigFilename {
    my @a;
    foreach my $line_LS (`ls $tmpdir`) {
        chomp($line_LS);
        # Select Config Data file
        if( $line_LS =~ /^${storage}_svcconf_\d+_\d+.data$/ ) {
            push(@a,$line_LS);
        }
    }
    my @b = sort @a;
    return(pop @b);
}

###############################################################################
#
# GetCapacityData
#
# 1. Store Capacity data to latest performance data
#
###############################################################################
sub	GetCapacityData {
	#
	&MDiskGroupCapacityData();
}

sub InitMdiskGrpRecord {
        my $c = shift;
        $c->{tier_0} = "ssd";
	$c->{tier_0_mdisk_count} = 0;
        $c->{tier_0_capacity} = 0;
        $c->{tier_0_free_capacity} = 0;
        $c->{tier_1} = "enterprise";
	$c->{tier_1_mdisk_count} = 0;
        $c->{tier_1_capacity} = 0;
        $c->{tier_1_free_capacity} = 0;
        $c->{tier_2} = "nearline";
	$c->{tier_2_mdisk_count} = 0;
        $c->{tier_2_capacity} = 0;
        $c->{tier_2_free_capacity} = 0;
}

sub MDiskGroupCapacityData {
	#
	foreach my $line_LSMDISKGRP (`$ssh svcinfo lsmdiskgrp -nohdr -delim :`) {
		#if($debug) {print("The svcinfo lsmdiskgrp command output: $line_LSMDISKGRP");}
		my @field_LSMDISKGRP = split(':', $line_LSMDISKGRP);
		# 
		my $name = $field_LSMDISKGRP[1];
		if($debug) {print("svcperf.pl: Get capacity data for mdisk group: $name\n");}
		my %rec;
		#%rec = ('tier_0'=>"",'tier_0_mdisk_count'=>0,'tier_0_capacity'=>0,'tier_0_free_capacity'=>0);
		#%rec = ('tier_1'=>"",'tier_1_mdisk_count'=>0,'tier_1_capacity'=>0,'tier_1_free_capacity'=>0);
		#%rec = ('tier_2'=>"",'tier_2_mdisk_count'=>0,'tier_2_capacity'=>0,'tier_2_free_capacity'=>0);
		&InitMdiskGrpRecord(\%rec);
		my $tier_level = 1;
		foreach my $line (`$ssh svcinfo lsmdiskgrp  -bytes -delim : $name`) {
			chomp($line);
			#if($debug) {print("svcperf.pl: The svcinfo lsmdiskgrp $name command output: $line\n");}
			#
			my @a = split(':',$line);
			if ( $a[0] eq "site_id" && ! defined $a[1] ) { 
				$rec{$a[0]} = "";
			} elsif ( $a[0] eq "site_name" && ! defined $a[1] ) {
                                $rec{$a[0]} = "";
                        } elsif ( $a[0] eq "tier" && $a[1] eq "generic_ssd" || $a[1] eq "ssd" ) { # set TIER Level 0
				$tier_level = 0;
				$rec{tier_0} = $a[1];
			} elsif ( $a[0] eq "tier" && $a[1] eq "generic_hdd" || $a[1] eq "enterprise" ) { # set TIER Level 1
				$tier_level = 1;
				$rec{tier_1} = $a[1];
			} elsif ( $a[0] eq "tier" ) { # set TIER Level 2
				$tier_level = 2;
				$rec{tier_2} = $a[1];
			} elsif ( $a[0] eq "tier_mdisk_count" ) {
				$rec{"tier_" . $tier_level . "_mdisk_count"} = $a[1];
			} elsif ( $a[0] eq "tier_capacity" ) {
				$rec{"tier_" . $tier_level . "_capacity"} = $a[1];
			} elsif ( $a[0] eq "tier_free_capacity" ) {
				$rec{"tier_" . $tier_level . "_free_capacity"} = $a[1];
			} else {
				$rec{$a[0]} = $a[1];
			}
		}
		$mdiskgrp_cap->{$name} = \%rec;
	}
}

###############################################################################
#
# MDiskGroupCapacityStatistics
#
# 1. Called by CountData
#
###############################################################################
sub MDiskGroupCapacityStatistics {
	#
	my @nodes = keys(%{$prev_data_ref->{svc_node}});
	#
	my $p_time = $prev_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $l_time = $last_data_ref->{svc_node}->{$nodes[0]}->{timestamp};
	my $interval = str2time($l_time) - str2time($p_time);
	#
	print PERFOUT "\nPool Capacity Statistics\n";
	print PERFOUT "\tInterval Start:   ",$p_time,"\n";
	print PERFOUT "\tInterval End:     ",$l_time,"\n";
	print PERFOUT "\tInterval Length:  ",$interval," seconds\n";
	print PERFOUT "---------------------\n";
	
	print PERFOUT "name,id,status,mdisk count,volume count,capacity (TB),extent size,free capacity (TB),virtual capacity (TB),used capacity (TB),real capacity (TB),overallocation,warning (%),easy tier,easy tier status,TIER-0 type,TIER-0 mdisk count,TIER-0 capacity (TB),TIER-0 free capacity (TB),TIER-1 type,TIER-1 mdisk count,TIER-1 capacity (TB),TIER-1 free capacity (TB),TIER-2 type,TIER-2 mdisk count,TIER-2 capacity (TB),TIER-2 free capacity (TB),compression active,compression virtual capacity (TB),compression compressed capacity (TB),compression uncompressed capacity (TB)\n";
	# id,name,status,mdisk_count,vdisk_count,
	# capacity (TB),extent_size,free_capacity (TB),virtual_capacity (TB),used_capacity (TB),real_capacity (TB),overallocation,warning,
	# easy_tier,easy_tier_status,
	# tier_0,tier_0_mdisk_count,tier_0_capacity,tier_0_free_capacity,
	# tier_1,tier_1_mdisk_count,tier_1_capacity,tier_1_free_capacity,
	# tier_2,tier_2_mdisk_count,tier_2_capacity,tier_2_free_capacity,
	# compression_active,compression_virtual_capacity,compression_compressed_capacity,compression_uncompressed_capacity
	my @hdr = split(',',"name,id,status,mdisk_count,vdisk_count,capacity,extent_size,free_capacity,virtual_capacity,used_capacity,real_capacity,overallocation,warning,easy_tier,easy_tier_status,tier_0,tier_0_mdisk_count,tier_0_capacity,tier_0_free_capacity,tier_1,tier_1_mdisk_count,tier_1_capacity,tier_1_free_capacity,tier_2,tier_2_mdisk_count,tier_2_capacity,tier_2_free_capacity,compression_active,compression_virtual_capacity,compression_compressed_capacity,compression_uncompressed_capacity");

	my @rec = keys(%{$mdiskgrp_cap});
	foreach my $name (sort (@rec)) {
		my $c = $mdiskgrp_cap->{$name};
		printf PERFOUT ("%s,%s,%s,%d,%d,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%d,%d,%s,%s,%s,%d,%.3f,%.3f,%s,%d,%.3f,%.3f,%s,%d,%.3f,%.3f,%s,%.3f,%.3f,%.3f,\n",
			$c->{name},$c->{id},$c->{status},$c->{mdisk_count},$c->{vdisk_count},
			ConvSizeUnits("TB",$c->{capacity}),$c->{extent_size},ConvSizeUnits("TB",$c->{free_capacity}),
			ConvSizeUnits("TB",$c->{virtual_capacity}),ConvSizeUnits("TB",$c->{used_capacity}),
			ConvSizeUnits("TB",$c->{real_capacity}),$c->{overallocation},$c->{warning},
			$c->{easy_tier},$c->{easy_tier_status},
			$c->{tier_0},$c->{tier_0_mdisk_count},ConvSizeUnits("TB",$c->{tier_0_capacity}),ConvSizeUnits("TB",$c->{tier_0_free_capacity}),
			$c->{tier_1},$c->{tier_1_mdisk_count},ConvSizeUnits("TB",$c->{tier_1_capacity}),ConvSizeUnits("TB",$c->{tier_1_free_capacity}),
			$c->{tier_2},$c->{tier_2_mdisk_count},ConvSizeUnits("TB",$c->{tier_2_capacity}),ConvSizeUnits("TB",$c->{tier_2_free_capacity}),
			$c->{compression_active},ConvSizeUnits("TB",$c->{compression_virtual_capacity}),
			ConvSizeUnits("TB",$c->{compression_compressed_capacity}),ConvSizeUnits("TB",$c->{compression_uncompressed_capacity}),
		);
	}
	
}

sub ConvSizeUnits {
	my ($unit,$size) = @_;
	if ( ! defined $size ) { $size = 0; }
	if ( $unit eq "KB" ) { return($size / 1024) }
	if ( $unit eq "MB" ) { return($size / 1048576) }
	if ( $unit eq "GB" ) { return($size / 1073741824) }
        if ( $unit eq "TB" ) { return($size / 1099511627776) }
}
