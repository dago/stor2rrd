#!/usr/bin/perl
#
# svcconfig.pl
#
# v0.3.6

# Modules
use strict;
use Data::Dumper;
use Storable;
use Date::Parse;

#use XML::Simple;
my $bindir = $ENV{BINDIR};
require "$bindir/xml.pl"; # it replaces above line and fixes an issue on Perl 5.10.1 on AIX 7100-00-06-1216

# Oprions and their default values
my $storage;                    # SVC/Storwize V7000 alias
my $svc;                        # SVC/Storwize V7000 cluster host name (IP address)
my $user        = "admin";      # SVC/Storwize V7000 user name
my $key         = "";           # SSH key filename
my $dir         = "..";         # Data directory

my $debug       = 0;            # Debug mode 0:off, 1:on
my $fullcfgint	= 86400;	# Full Config Interval (sec) ... 24H = 86400

if (defined $ENV{STORAGE_NAME}) {
	$storage= $ENV{STORAGE_NAME};
} else {
	message("svcconfig.pl: SVC/Storwize V7000 storage name alias is required.");
	exit(1);
}
if (defined $ENV{SVC_IP}) {
	$svc= $ENV{SVC_IP};
} else {
	message("svcconfig.pl: SVC/Storwize V7000 host name or IP address is required.");
	exit(1);
}
if (defined $ENV{SVC_USER}) { $user	= $ENV{SVC_USER} }
if (defined $ENV{SVC_KEY}) { $key = $ENV{SVC_KEY} }
if (defined $ENV{SVC_DIR}) { $dir = $ENV{SVC_DIR} }
if (defined $ENV{DEBUG}) { $debug = $ENV{DEBUG} }

# Main process

# Display parameters
if ($debug) {
	message("
svcconfig.pl starts with the following parameters ...
\tSVC/Storwize V7000 cluster name:      $storage
\tSVC cluster host name:                $svc
\tSVC admin user name:                  $user
\tSVC admin user SSH key filename:      $key
\tBase Directory for output files:      $dir
\tDebug:                                $debug
");
}

#
my $fullcfgflg = 0; 
my $cfgdata;
my %cfg; my $cfg_ref = \%cfg;
my %fullcfg; my $fullcfg_ref = \%fullcfg;
my %prevcfg; my $prevcfg_ref = \%prevcfg;
my $ssh;
my $scp;
if("x$key" eq "x") {	# with default keyfile (.ssh/id_rsa)
	$ssh = "ssh $user\@$svc";
	$scp = "scp $user\@$svc:/tmp/svc.config.backup.xml";
} else {		        # 
	$ssh = "ssh -i $key $user\@$svc";
	$scp = "scp -i $key  $user\@$svc:/tmp/svc.config.backup.xml";
}

# Date and Time 
my $local_time = localtime(time);
my $local_epoch = str2time($local_time);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon++;
my $date = sprintf("%4d%2.2d%2.2d",$year,$mon,$mday);
my $time = sprintf("%2.2d%2.2d%2.2d",$hour,$min,$sec);
$cfg_ref->{date} = sprintf("%2.2d.%2.2d.%4d",$mday,$mon,$year)." ".sprintf("%2.2d:%2.2d:%2.2d",$hour,$min,$sec); 
# Get Latest Config Data
my $tmp_conf_file = &GetConfigFilename();
if($debug) {message("svcconfig.pl: Config Filename: " . $dir . "/" . $tmp_conf_file)};

if ( defined $tmp_conf_file ) {
	if ( -r $dir . "/" . $tmp_conf_file ) {
		$prevcfg_ref = retrieve($dir . "/" . $tmp_conf_file);
		if ( ! defined $prevcfg_ref ) {
			message("svcconfig.pl: Retrieve data from file $tmp_conf_file failed.");
			system("rm -f ".$dir."/".$tmp_conf_file );
			$fullcfgflg = 1;
		} elsif (! scalar(%{$prevcfg_ref}) ) { 
			if($debug) { message("svcconfig.pl: Previous configuration data is not valid.")};
			system("rm -f ".$dir."/".$tmp_conf_file );
			$fullcfgflg = 1;
		} elsif (! defined $prevcfg_ref->{'fullcfg_epoch'} ) {
			if($debug) { message("svcconfig.pl: Full Config Epoch is not find in previous data.")};
			$fullcfgflg = 1;
		} elsif ( $local_epoch - $prevcfg_ref->{'fullcfg_epoch'} >= $fullcfgint ) {
			$fullcfgflg = 1;
			if($debug) {
				message("svcconfig.pl: Full Config Time = ".localtime($prevcfg_ref->{'fullcfg_epoch'})." - epoch = ".$prevcfg_ref->{'fullcfg_epoch'});
				my $diff = $local_epoch - $prevcfg_ref->{'fullcfg_epoch'};
				message("svcconfig.pl: Full Config Interval = ".$diff);

			}
		} else {
			if($debug) {
				message("svcconfig.pl: Full Config Time = ".localtime($prevcfg_ref->{'fullcfg_epoch'})." - epoch = ".$prevcfg_ref->{'fullcfg_epoch'});
				my $diff = $local_epoch - $prevcfg_ref->{'fullcfg_epoch'};
				message("svcconfig.pl: Full Config Interval = ".$diff);
			}
		}
	} else {
		$fullcfgflg = 1;
		system("rm -f ".$dir."/".$tmp_conf_file );
	}
} else {
	$fullcfgflg = 1;
}
	


# Get SVC/Storwize Code Level
my $codelevel = &GetCodeLevel();
if ( ! defined $codelevel ) {
        die("svcconfig.pl: ERROR: Cannot get SVC/Storwize code level. Exiting.\n");
}
my $codevrmn = $codelevel->{'version'} * 1000000 + $codelevel->{'release'} * 10000 + $codelevel->{'major'} * 100 + $codelevel->{'minor'};
if ( $codevrmn >= 6040000 && $codevrmn <= 7010001 ) {
	# Command svcconfig backup failed with error message
	# CMMVC6202E This command can only be run by the superuser.
    # Suggested Fixes
	# 7.1.0.2  IC90824  Configuration backup could only be run by superuser
	&InsertDataCli();
} else {
	if ( $fullcfgflg ) {
		# Get SVC configuration file (XML file) from SVC cluster
		if ($debug) { message("svcconfig.pl: $ssh svcconfig backup"); }
		system("$ssh svcconfig backup 2>/dev/null >/dev/null") == 0 or die("svcconfig.pl: ERROR: Command \"$ssh svcconfig backup\" failed.\n");
		if ($debug) { message("svcconfig.pl: $scp $dir"); }
		system("$scp $dir") == 0 or die("svcconfig.pl: ERROR: Command \"$scp $dir\" failed.\n");
		$cfgdata = &ReadConfigFile();
		&InsertDataXml();
	} else {
		&InsertDataCli();
	}
}
# Define configurations file name
my $svc_name = $cfg_ref->{svc_system}->{name};
$tmp_conf_file = $dir . "/" . $storage . "_svcconf_". $date . "_" . $time . ".data";
my $tmp_conf_full_file = $dir . "/" . $storage . "_svcconf".".datafull";
my $out_conf_file = $dir . "/" . $storage . "_svcconf_". $date . "_" . $time . ".out";

&StoreData();
&RetriveData();

&PrintData();

exit();

sub message {
	my $msg = shift;
	my $tm = localtime();
	print($tm.": ".$msg."\n");
}

sub GetCodeLevel {
	my $line;
	my $delim = ":";
	my %c;
	my $cmd = $ssh . " svcinfo lssystem -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	# code_level:7.3.0.7 (build 97.5.1410080000)
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^\s*code_level$delim(\d+).(\d+).(\d+).(\d+)\s+\(build\s+.*\)\s*$/) {   
			$c{version} = $1;
			$c{release} = $2;
			$c{major} = $3;
			$c{minor} = $4;
			$c{build} = $5;
			close(CMDOUT);
			return(\%c);
		}
	}
	close(CMDOUT);
	return(undef);
}

sub GetConfigFilename {
    my @a;
    foreach my $line_LS (`ls $dir`) {
        chomp($line_LS);
        # Select Config Data file
        if( $line_LS =~ /^${storage}_svcconf_\d+_\d+.data$/ ) {
            push(@a,$line_LS);
        }
    }
    my @b = sort @a;
    return(pop @b);
}

sub ReadConfigFile {
	my $xmlfile = $dir."/"."svc.config.backup.xml";
	my $simple = XML::Simple->new(keyattr => [], ForceArray => 1);
	my $xmldata = $simple->XMLin($xmlfile);
	my $data = $xmldata->{'object'};
	return $data;
}

sub InsertDataCli {
	# Save time of full config.
	if ( $fullcfgflg ) {
		$cfg_ref->{'fullcfg_epoch'} = $local_epoch;
		if($debug) { message("svcconfig.pl: Insert Full Config Epoch ".$cfg_ref->{'fullcfg_epoch'}." to config data.")};
	} else {
		$cfg_ref->{'fullcfg_epoch'} = $prevcfg_ref->{'fullcfg_epoch'};
		if($debug) { message("svcconfig.pl: Insert Full Config Epoch ".$cfg_ref->{'fullcfg_epoch'}." to config data.")};
	}
	&GetSystemDataCli();
	&GetNodeDataCli();
	&GetEnclosureDataCli();
	&GetPortfcDataCli();
	&GetDriveDataCli();
	&GetMdiskDataCli();
	&GetMdiskGrpDataCli();
	&GetVdiskDataCli();
}

sub InsertDataXml {
	# Save time of full config.
	if ( $fullcfgflg ) {
		$cfg_ref->{'fullcfg_epoch'} = $local_epoch;
		if($debug) { message("svcconfig.pl: Insert Full Config Epoch ".$cfg_ref->{'fullcfg_epoch'}." to config data.")};
	} else {
		$cfg_ref->{'fullcfg_epoch'} = $prevcfg_ref->{'fullcfg_epoch'};
		if($debug) { message("svcconfig.pl: Insert Full Config Epoch ".$cfg_ref->{'fullcfg_epoch'}." to config data.")};
	}
	&GetSystemDataXml();
	&GetNodeDataXml();
	&GetEnclosureDataXml();
	&GetPortfcDataXml();
	&GetDriveDataXml();
	&GetMdiskDataXml();
	&GetMdiskGrpDataXml();
	&GetVdiskDataXml();
	&GetVdiskHostMapDataXml();
	&GetHostDataXml();
}

sub StoreData {
	#
    store($cfg_ref, $tmp_conf_file) or die("svcconfig.pl: Store data to file $tmp_conf_file failed.");
    if ( $fullcfgflg ) {
        store($cfg_ref, $tmp_conf_full_file) or die("svcconfig.pl: Store data to file $tmp_conf_file failed.");
    }
}

sub RetriveData {
    if( -r $tmp_conf_full_file ) {
        $fullcfg_ref = retrieve($tmp_conf_full_file);
    }
}

sub PrintData {
	#
	if ($debug) {message("svcconfig.pl: Output file: ${out_conf_file}.tmp.")};
	open(CONFOUT,">${out_conf_file}.tmp") or die("Print data to file ${out_conf_file}.tmp failed.");
	&PrintSystemData();
	&PrintNodeData();
	&PrintEnclosureData();
	&PrintPortfcData();
	&PrintDriveData();
	&PrintMdiskData();
	&PrintMdiskGrpData();
	&PrintVdiskData();
	if ( $fullcfgflg ) {
		&PrintHostData()  if ( $codevrmn < 6400 || $codevrmn > 7101 );
	}
	close(CONFOUT);
	if ($debug) {message("svcconfig.pl: Rename output file to: ${out_conf_file}.")};
	my $ret = system("mv ${out_conf_file}.tmp ${out_conf_file}"); 
	if ($ret) { die("svcconfig.pl: Couldn't rename file ${tmp_conf_file}.tmp .") };
}

# -------------------------------------------------------------------------------------------------
# CLI

sub GetSystemDataCli {
	my $line;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lssystem -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^(\w+)$delim(.*)$/) {   # system
			$cfg_ref->{svc_system}->{$1} = $2;
		}
	}
	close(CMDOUT);
}

sub GetNodeDataCli {
	my $line;
	my @header;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lsnode -bytes -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^id${delim}name${delim}UPS_serial_number.*$/) {   # header
			@header = split(/$delim/,$line);
		} else {
			my %record;
			@record{@header} = split(/$delim/,$line);
			$cfg_ref->{svc_node}->{$record{name}} = \%record;
		}
	}
	close(CMDOUT);
}

sub GetEnclosureDataCli {
	my $line;
	my @header;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lsenclosure -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^id${delim}status${delim}type.*$/) {   # header
			@header = split(/$delim/,$line);
		} else {
			my %record;
			@record{@header} = split(/$delim/,$line);
			$cfg_ref->{svc_enclosure}->{$record{id}} = \%record;
		}
	}
	close(CMDOUT);
}

sub GetPortfcDataCli {
	my $line;
	my @header;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lsportfc -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^id${delim}fc_io_port_id${delim}.*$/) {   # header
			@header = split(/$delim/,$line);
		} else {
			my %record;
			@record{@header} = split(/$delim/,$line);
			my $id = $record{node_name}."_p".sprintf("%02d",$record{port_id});
			$cfg_ref->{svc_portfc}->{$id} = \%record;
		}
	}
	close(CMDOUT);
}

sub GetDriveDataCli {
	my $line;
	my @header;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lsdrive -bytes -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^id${delim}status${delim}.*$/) {   # header
			@header = split(/$delim/,$line);
		} else {
			my %record;
			@record{@header} = split(/$delim/,$line);
			my $id = sprintf("%04d",$record{id});
			$cfg_ref->{svc_drive}->{$id} = \%record;
		}
	}
	close(CMDOUT);
}

sub GetMdiskDataCli {
	my $line;
	my @header;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lsmdisk -bytes -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^id${delim}name${delim}.*$/) {   # header
			@header = split(/$delim/,$line);
		} else {
			my %record;
			@record{@header} = split(/$delim/,$line);
			my $id = sprintf("%04d",$record{id});
			$cfg_ref->{svc_mdsk}->{$id} = \%record;
		}
	}
	close(CMDOUT);
}

sub InitMdiskGrpRecord {
	my $c = shift;
	$c->{capacity} = 0;
	$c->{free_capacity} = 0;
	$c->{virtual_capacity} = 0;
	$c->{used_capacity} = 0;
	$c->{real_capacity} = 0;
	$c->{tier_0_capacity} = 0;
	$c->{tier_0_free_capacity} = 0;
	$c->{tier_1_capacity} = 0;
	$c->{tier_1_free_capacity} = 0;
	$c->{tier_2_capacity} = 0;
	$c->{tier_2_free_capacity} = 0;
	$c->{compression_active} = "no";
	$c->{compression_virtual_capacity} = 0;
	$c->{compression_compressed_capacity} = 0;
	$c->{compression_uncompressed_capacity} = 0;
}


sub GetMdiskGrpDataCli {
	my $line;
	my @header;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lsmdiskgrp -bytes -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
		if ($line  =~ /^id${delim}name${delim}.*$/) {   # header
			@header = split(/$delim/,$line);
		} else {
			my %record;
			&InitMdiskGrpRecord(\%record);
			@record{@header} = split(/$delim/,$line);
			my $id = $record{name};
			$cfg_ref->{svc_pool}->{$id} = \%record;
		}
	}
	close(CMDOUT);
}

sub GetVdiskDataCli {
	my $line;
	my @header;
	my $delim = ":";
	my $cmd = $ssh . " svcinfo lsvdisk -bytes -delim " . $delim;
	if ($debug) {message("svcconfig.pl: Command: $cmd.")};
	open (CMDOUT,"$cmd |") || die "svcconfig.pl: Command $cmd failed. Exiting.";
	
	while ($line = <CMDOUT>) {
		chomp ($line);
	    if ($line  =~ /^id${delim}name${delim}.*$/) {   # header
			@header = split(/$delim/,$line);
	    } else {
    		my %record;
			@record{@header} = split(/$delim/,$line);
			my $id = sprintf("%04d",$record{id});
			$cfg_ref->{svc_vdsk}->{$id} = \%record;
		}
	}
	close(CMDOUT);
}


# -------------------------------------------------------------------------------------------------
# XML
sub GetSystemDataXml {
	my $p;
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "cluster") {
			$p = $n->{'property'};
		}
	}
	my $tiername;
	foreach my $m ( @{$p} ) {
		if( $m->{'name'} eq "tier" ) {
			$tiername = $m->{'value'};
		} elsif ( $m->{'name'} eq "tier_capacity" ) {
			$cfg_ref->{svc_system}->{$tiername."_".$m->{'name'}} = $m->{'value'};
		} elsif ( $m->{'name'} eq "tier_free_capacity" ) {
			$cfg_ref->{svc_system}->{$tiername."_".$m->{'name'}} = $m->{'value'};
		} else {
			$cfg_ref->{svc_system}->{$m->{'name'}} = $m->{'value'};
		}
	}
	if (! defined $cfg_ref->{svc_system}->{ssd_tier_capacity} ) { $cfg_ref->{svc_system}->{ssd_tier_capacity} = 0; }
	if (! defined $cfg_ref->{svc_system}->{enterprise_tier_capacity} ) { $cfg_ref->{svc_system}->{enterprise_tier_capacity} = 0; }
	if (! defined $cfg_ref->{svc_system}->{nearline_tier_capacity} ) { $cfg_ref->{svc_system}->{nearline_tier_capacity} = 0; }
	if (! defined $cfg_ref->{svc_system}->{ssd_tier_free_capacity} ) { $cfg_ref->{svc_system}->{ssd_tier_free_capacity} = 0; }
	if (! defined $cfg_ref->{svc_system}->{enterprise_tier_free_capacity} ) { $cfg_ref->{svc_system}->{enterprise_tier_free_capacity} = 0; }
	if (! defined $cfg_ref->{svc_system}->{nearline_tier_free_capacity} ) { $cfg_ref->{svc_system}->{nearline_tier_free_capacity} = 0; }

}

sub GetNodeDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "node") {
			my %record;
			foreach my $m ( @{$n->{'property'}} ) {
				$record{$m->{'name'}} = $m->{'value'};
			}
			$cfg_ref->{svc_node}->{$record{name}} = \%record;
		}
	}
}

sub GetEnclosureDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "enclosure") {
			my %record;
			foreach my $m ( @{$n->{'property'}} ) {
				$record{$m->{'name'}} = $m->{'value'};
			}
			$cfg_ref->{svc_enclosure}->{$record{id}} = \%record;
		}
	}
}

sub GetPortfcDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "portfc") {
			my %record;
			foreach my $m ( @{$n->{'property'}} ) {
				$record{$m->{'name'}} = $m->{'value'};
			}
			my $id = $record{node_name}."_id".sprintf("%02d",$record{id})."_p".sprintf("%02d",$record{port_id});
			$cfg_ref->{svc_portfc}->{$id} = \%record;
		}
	}
}

sub GetDriveDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "drive") {
			my %record;
			foreach my $m ( @{$n->{'property'}} ) {
				$record{$m->{'name'}} = $m->{'value'};
			}
			my $id = sprintf("%04d",$record{id});
			$cfg_ref->{svc_drive}->{$id} = \%record;
		}
	}
}

sub GetMdiskDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "mdisk") {
			my %record;
			foreach my $m ( @{$n->{'property'}} ) {
				$record{$m->{'name'}} = $m->{'value'};
			}
			my $id = sprintf("%04d",$record{id});
			$cfg_ref->{svc_mdsk}->{$id} = \%record;
		}
	}
}

sub GetMdiskGrpDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "mdisk_grp") {
			my %record;
			foreach my $m ( @{$n->{'property'}} ) {
				$record{$m->{'name'}} = $m->{'value'};
			}
			my $id = $record{name};
			$cfg_ref->{svc_pool}->{$id} = \%record;
		}
	}
}

sub GetVdiskDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "vdisk") {
			my %record;
#			foreach my $m ( @{$n->{'property'}} ) {
#				$record{$m->{'name'}} = $m->{'value'};
#			}
#			my $id = sprintf("%04d",$record{id});
#			$cfg_ref->{svc_vdsk}->{$id} = \%record;
			my $tiername; my $copyid = 0;
			foreach my $m ( @{$n->{'property'}} ) {
				#$record{$m->{'name'}} = $m->{'value'};
				if( $m->{'name'} eq "copy_id" ) {
					$copyid = $m->{'value'};
				} elsif( $m->{'name'} eq "tier" ) {
					if ( $m->{'value'} =~ /ssd/ ) {
						# SSD
						$tiername = "tier_0";
						$record{"copy_".$copyid."_".$tiername} = $m->{'value'};
					} elsif ( $m->{'value'} =~ /enterprise/ || $m->{'value'} =~ /hdd/ ) {
						# Enterprise
						$tiername = "tier_1";
						$record{"copy_".$copyid."_".$tiername} = $m->{'value'};
					} elsif ( $m->{'value'} =~ /nearline/ || $m->{'value'} =~ /Nearline/ ) {
						# Nearline
						$tiername = "tier_2";
						$record{"copy_".$copyid."_".$tiername} = $m->{'value'};
					} else {
						Message("WARNING: Unknown tiername ".$m->{'value'}.".");
						$tiername = "tier_unknown";
					}
				} elsif ( $m->{'name'} eq "tier_capacity" ) {
					$record{"copy_".$copyid."_".$tiername."_capacity"} = $m->{'value'};
				} elsif ( $m->{'name'} eq "mdisk_grp_id" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "mdisk_grp_name" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "used_capacity" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "real_capacity" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "free_capacity" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "se_copy" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "overallocation" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "compressed_copy" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "uncompressed_used_capacity" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "easy_tier" ) {
					$record{"copy_".$copyid."_".$m->{'name'}} = $m->{'value'};
				} else {
					$record{$m->{'name'}} = $m->{'value'};
				}
			}
			my $id = sprintf("%04d",$record{id});
			$cfg_ref->{svc_vdsk}->{$id} = \%record;
#			$cfg{$id} = \%record;

		}
	}
}

sub GetHostDataXml {
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "host") {
			my %record;
			my $i = 0;
			foreach my $m ( @{$n->{'property'}} ) {
				if ( $m->{'name'} eq "WWPN" ) {
					$record{"FC".$i."_".$m->{'name'}} = $m->{'value'};
					$i++;  
				} elsif ( $m->{'name'} eq "node_logged_in_count" ) {
					$record{"FC".$i."_".$m->{'name'}} = $m->{'value'};
				} elsif ( $m->{'name'} eq "state" ) {
					$record{"FC".$i."_".$m->{'name'}} = $m->{'value'};
				} else {
					$record{$m->{'name'}} = $m->{'value'};
				}
			}
			my $id = sprintf("%04d",$record{id});
			$cfg_ref->{svc_host}->{$id} = \%record;
		}
	}
}

sub GetVdiskHostMapDataXml {
	my @a;
	foreach my $n ( @{$cfgdata} ) {
		if ( $n->{'type'} eq "vdiskhostmap") {
			my %record;
			my $i = 0;
			foreach my $m ( @{$n->{'property'}} ) {
				$record{$m->{'name'}} = $m->{'value'};
			}
			my $id = sprintf("%04d",$record{vdisk_id});
			push(@a,\%record);
		}
	}
	$cfg_ref->{svc_vdiskhostmap} = \@a;
}

# -------------------------------------------------------------------------------------------------

sub PrintSystemData {
	print CONFOUT "\nConfiguration Data\n";
	print CONFOUT   "------------------\n";
	print CONFOUT "\tMachine Name:   ",$cfg_ref->{svc_system}->{name},"\n";
	print CONFOUT "\tMachine Type-Model:  ",&MachineTypeModel,"\n";
	print CONFOUT "\tMachine Serial:      ",&MachineSerial,"\n";
	print CONFOUT "\tCode Level:     ",$cfg_ref->{svc_system}->{code_level},,"\n";
	print CONFOUT "\n";
	print CONFOUT "\tPerformance Statistic Status:    ",$cfg_ref->{svc_system}->{statistics_status},,"\n";
	print CONFOUT "\tPerformance Statistic Frequency: ",$cfg_ref->{svc_system}->{statistics_frequency},,"\n";
	print CONFOUT "\n";
	print CONFOUT "\tDate:           ",$cfg_ref->{date},"\n";
	print CONFOUT "\n";
	print CONFOUT "\tTotal Mdisk Capacity:            ",$cfg_ref->{svc_system}->{total_mdisk_capacity},"\n";
	print CONFOUT "\tSpace in Pools:                  ",$cfg_ref->{svc_system}->{space_in_mdisk_grps},"\n";
	print CONFOUT "\tSpace Allocated to Volumes:      ",$cfg_ref->{svc_system}->{space_allocated_to_vdisks},"\n";
	print CONFOUT "\n";
	print CONFOUT "\tTotal Free_space:                ",$cfg_ref->{svc_system}->{total_free_space},"\n";
	print CONFOUT "\tTotal Used_capacity:             ",$cfg_ref->{svc_system}->{total_used_capacity},"\n";
	print CONFOUT "\tTotal Overallocation:            ",$cfg_ref->{svc_system}->{total_overallocation},"\n";
	print CONFOUT "\tTotal Volume Capacity:           ",$cfg_ref->{svc_system}->{total_vdisk_capacity},"\n";
	print CONFOUT "\tTotal Volumecopy Capacity:       ",$cfg_ref->{svc_system}->{total_vdiskcopy_capacity},"\n";
	print CONFOUT "\tTotal Allocated Extent Capacity: ",$cfg_ref->{svc_system}->{total_allocated_extent_capacity},"\n";
	print CONFOUT "\n";
	if ( defined $cfg_ref->{svc_system}->{ssd_tier_capacity} ) { 
	print CONFOUT "\t                                 Flash  \tEnterprise     \tNearline\n";
	print CONFOUT "\tTier Capacity:                   ",$cfg_ref->{svc_system}->{ssd_tier_capacity},"\t",
	                                                    $cfg_ref->{svc_system}->{enterprise_tier_capacity},"    \t",
	                                                    $cfg_ref->{svc_system}->{nearline_tier_capacity},
	                                                    "\n";
	print CONFOUT "\tTier Free Capacity:              ",$cfg_ref->{svc_system}->{ssd_tier_free_capacity},"\t",
	                                                    $cfg_ref->{svc_system}->{enterprise_tier_free_capacity},"    \t",
	                                                    $cfg_ref->{svc_system}->{nearline_tier_free_capacity},
	                                                    "\n";
	}
	print CONFOUT "\n";
}


sub PrintNodeData {
	my $delim = ",";
	# Add product_mtm
	# my @keylist = split(/,/,"id,name,UPS_serial_number,WWNN,status,IO_group_id,IO_group_name,config_node,UPS_unique_id,hardware,iscsi_name,iscsi_alias,panel_name,enclosure_id,canister_id,enclosure_serial_number");
	my @keylist = split(/,/,"id,name,UPS_serial_number,WWNN,status,IO_group_id,IO_group_name,config_node,UPS_unique_id,hardware,iscsi_name,iscsi_alias,panel_name,enclosure_id,canister_id,product_mtm,enclosure_serial_number");
	my $hdrline = join($delim,@keylist);

	print CONFOUT "\nNode Level Configuration\n";
	print CONFOUT   "------------------------\n";
	print CONFOUT $hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_node}});
	foreach my $rec (sort(@reclist)) {
		my @a;
		foreach my $key (@keylist) {
			if ( defined $cfg_ref->{svc_node}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_node}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

sub MachineTypeModel {
	my @a;
	if ( defined $cfg_ref->{svc_enclosure} ) {
		my @reclist = keys(%{$cfg_ref->{svc_enclosure}});
		foreach my $rec (sort(@reclist)) {
			if ( $cfg_ref->{svc_enclosure}->{$rec}->{type} eq "control" ) {
				push(@a,$cfg_ref->{svc_enclosure}->{$rec}->{product_MTM});
			}
		}
	} else {
		my @reclist = keys(%{$cfg_ref->{svc_node}});
		foreach my $rec (sort(@reclist)) {
			if (defined $cfg_ref->{svc_node}->{$rec}->{product_mtm}) {
				push(@a,$cfg_ref->{svc_node}->{$rec}->{product_mtm});
			} else {
				push(@a,"2145-".$cfg_ref->{svc_node}->{$rec}->{hardware});
			}
			
		}
	}
	return(join(",",@a));
}

sub MachineSerial {
	my @a;
	if ( defined $cfg_ref->{svc_enclosure} ) {
		my @reclist = keys(%{$cfg_ref->{svc_enclosure}});
		foreach my $rec (sort(@reclist)) {
			if ( $cfg_ref->{svc_enclosure}->{$rec}->{type} eq "control" ) {
				push(@a,$cfg_ref->{svc_enclosure}->{$rec}->{serial_number});
			}
		}
	} else {
		my @reclist = keys(%{$cfg_ref->{svc_node}});
		foreach my $rec (sort(@reclist)) {
		    if(defined $cfg_ref->{svc_node}->{$rec}->{enclosure_serial_number}) {
			push(@a,$cfg_ref->{svc_node}->{$rec}->{enclosure_serial_number});
                    }
		}
	}
        if ( @a ) {
	    return(join(",",@a));
        } else {
            return;
        }
}

sub PrintEnclosureData {
	if (not defined $cfg_ref->{svc_enclosure} ) { return; }
	my $delim = ",";
	my @keylist = split(/,/,"id,status,type,managed,IO_group_id,IO_group_name,product_MTM,serial_number,total_canisters,online_canisters,total_PSUs,online_PSUs,drive_slots,machine_part_number");
	my $hdrline = join($delim,@keylist);

	print CONFOUT "\nEnclosure Level Configuration(V7000 Series)\n";
	print CONFOUT   "-------------------------------------------\n";
	print CONFOUT $hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_enclosure}});
	foreach my $rec (sort(@reclist)) {
		my @a;
		foreach my $key (@keylist) {
			if ( defined $cfg_ref->{svc_enclosure}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_enclosure}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

sub PrintPortfcData {
	my $delim = ",";
	my @keylist = split(/,/,"id,fc_io_port_id,port_id,type,port_speed,node_id,node_name,WWPN,nportid,status,attachment");
	my $hdrline = join($delim,@keylist);

	print CONFOUT "\nPort Level Configuration - Fribre Channel Ports\n";
	print CONFOUT   "-----------------------------------------------\n";
	print CONFOUT "port_name",$delim,$hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_portfc}});
	foreach my $rec (sort(@reclist)) {
		my @a;
		push(@a,$rec);
		foreach my $key (@keylist) {
			if ( defined $cfg_ref->{svc_portfc}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_portfc}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

sub PrintDriveData {
	my $delim = ",";
	my @keylist = split(/,/,"id,status,error_sequence_number,use,tech_type,capacity,mdisk_id,mdisk_name,member_id,enclosure_id,slot_id,node_id,node_name");
	my $hdrline = join($delim,@keylist);

	print CONFOUT "\nDrive Level Configuration\n";
	print CONFOUT   "------------------------\n";
	print CONFOUT "drive_id",$delim,$hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_drive}});
	foreach my $rec (sort(@reclist)) {
		my @a;
		push(@a,$rec);
		foreach my $key (@keylist) {
			if ( defined $cfg_ref->{svc_drive}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_drive}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

sub PrintMdiskData {
	my $delim = ",";
	my @keylist = split(/,/,"id,name,status,mode,mdisk_grp_id,mdisk_grp_name,capacity,ctrl_LUN_#,controller_name,UID,tier");
	my $hdrline = join($delim,@keylist);

	print CONFOUT "\nManaged Disk Level Configuration\n";
	print CONFOUT   "------------------------\n";
	print CONFOUT "mdisk_id",$delim,$hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_mdsk}});
	foreach my $rec (sort(@reclist)) {
		my @a;
		push(@a,$rec);
		foreach my $key (@keylist) {
			if ( defined $cfg_ref->{svc_mdsk}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_mdsk}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

sub PrintMdiskGrpData {
	my $delim = ",";
	my @keylist = split(/,/,"name,id,status,mdisk_count,vdisk_count,capacity,extent_size,free_capacity,virtual_capacity,used_capacity,real_capacity,overallocation,warning,easy_tier,easy_tier_status,compression_active,compression_virtual_capacity,compression_compressed_capacity,compression_uncompressed_capacity");
	my $hdrline = join($delim,@keylist);

	print CONFOUT "\nPool Level Configuration\n";
	print CONFOUT   "------------------------\n";
	print CONFOUT $hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_pool}});
	foreach my $rec (sort(@reclist)) {
		my @a;
		foreach my $key (@keylist) {
			if ( defined $cfg_ref->{svc_pool}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_pool}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

sub PrintVdiskData {
	my $delim = ",";
	my @keylist = split(/,/,"id,name,IO_group_id,IO_group_name,status,mdisk_grp_id,mdisk_grp_name,capacity,type,FC_id,FC_name,RC_id,RC_name,vdisk_UID,fc_map_count,copy_count,fast_write_state,se_copy_count,RC_change,compressed_copy_count");
	my $hdrline = join($delim,@keylist);

	print CONFOUT "\nVolume Level Configuration\n";
	print CONFOUT   "--------------------------\n";
	print CONFOUT "volume_id",$delim,$hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_vdsk}});
	foreach my $rec (sort(@reclist)) {
		my @a;
		push(@a,$rec);
		foreach my $key (@keylist) {
			if ( $key eq "mdisk_grp_id" or $key eq "mdisk_grp_name") {
				my @b;
				if ( not defined $cfg_ref->{svc_vdsk}->{$rec}->{$key} ) {
					if ( defined $cfg_ref->{svc_vdsk}->{$rec}->{"copy_0_".$key} ) {
						push(@b,$cfg_ref->{svc_vdsk}->{$rec}->{"copy_0_".$key});
					}
					if ( defined $cfg_ref->{svc_vdsk}->{$rec}->{"copy_1_".$key} ) {
						push(@b,$cfg_ref->{svc_vdsk}->{$rec}->{"copy_1_".$key});
					}
				        if ( scalar(@b) ) {
					        push(@a,join(" ",@b));
				        } else {
					        push(@a,"");
				        } 
				} elsif ( $cfg_ref->{svc_vdsk}->{$rec}->{$key} eq "many" ) {
					if ( defined $fullcfg_ref->{svc_vdsk}->{$rec}->{"copy_0_".$key} ) {
						push(@b,$fullcfg_ref->{svc_vdsk}->{$rec}->{"copy_0_".$key});
					}
					if ( defined $fullcfg_ref->{svc_vdsk}->{$rec}->{"copy_1_".$key} ) {
						push(@b,$fullcfg_ref->{svc_vdsk}->{$rec}->{"copy_1_".$key});
					}
				        if ( scalar(@b) ) {
					        push(@a,join(" ",@b));
				        } else {
					        push(@a,"");
				        } 
                                } else {
				        push(@a,$cfg_ref->{svc_vdsk}->{$rec}->{$key});
                                }
			} elsif ( defined $cfg_ref->{svc_vdsk}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_vdsk}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

sub PrintHostData {
	my $delim = ",";
	my @keylist = split(/,/,"id,name,port_count,iogrp_count,status");
	my $hdrline = join($delim,@keylist).$delim."IQN WWPN".$delim."Volume IDs".$delim."Volume Names";

	print CONFOUT "\nHost Level Configuration\n";
	print CONFOUT   "--------------------------\n";
	print CONFOUT "host_id",$delim,$hdrline,"\n";

	my @reclist = keys(%{$cfg_ref->{svc_host}});
	foreach my $rec (sort(@reclist)) {
		my @a; my @w; my @d; my @n;
		push(@a,$rec);
		foreach my $key (@keylist) {
			if ( defined $cfg_ref->{svc_host}->{$rec}->{$key} ) {
				push(@a,$cfg_ref->{svc_host}->{$rec}->{$key});
			} else {
				push(@a,"");
			}
		}
		# Add IQN and WWPNs
		my $i = 0;
		while ( $i < $cfg_ref->{svc_host}->{$rec}->{port_count} ) {
			if ( $cfg_ref->{svc_host}->{$rec}->{'iscsi_name'} ) {
				push(@w,$cfg_ref->{svc_host}->{$rec}->{'iscsi_name'});
			} elsif ( $cfg_ref->{svc_host}->{$rec}->{"FC".$i."_WWPN"} ) {
				push(@w,$cfg_ref->{svc_host}->{$rec}->{"FC".$i."_WWPN"});
			}
			$i++;
		}
		push(@a,join(" ",@w));
		# Add Vdisk IDs
		foreach my $map ( @{$cfg_ref->{svc_vdiskhostmap}} ) {
			if ( $cfg_ref->{svc_host}->{$rec}->{'id'} eq $map->{'host_id'} ) {
				push(@d,$map->{'vdisk_id'})
			}
		}
		@d = sort(@d);
		push(@a,join(" ",@d));
		# Add Vdisk Names
		foreach my $id ( @d ) {
			$id = sprintf("%04d",$id);
			push(@n,$cfg_ref->{svc_vdsk}->{$id}->{'name'});
		}
		push(@a,join(" ",@n));
		print CONFOUT join($delim,@a),"\n";
	}
	print CONFOUT "\n";
}

