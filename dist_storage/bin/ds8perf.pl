#!/usr/bin/perl
#
# ds8perf.pl
# version 0.31
# March 23, 2013    ... expansion of logical disk statistics
# March 28, 2013    ... repair statistics Logical Disk
# April 25, 2013    ... diversification of the output array configuration (rank, volume, host)
# April 29, 2013    ... alarm handling when calling DSCL
# April 30, 2013    ... Adding a separate log output to a file
# April 30, 2013    ... adjust the output control Reports
# May 01, 2013      ... adjust the output control Reports
# May 02, 2013      ... fix the time zones
# May 06, 2013      ... repair first run
# May 07, 2013      ... location correction script file offline elements
# May 20, 2013      ... detected error condition DSCL
# May 22, 2013      ... repair of alarm
# January 16, 2014  ... Detection of incomplete data
# January 20, 2014  ... fix date to epoch conversion

use strict;
use Data::Dumper;
use Date::Parse;
use Storable;
#
#
my $DEBUG = $ENV{DEBUG};
my $inputdir = $ENV{INPUTDIR};
my $ds8_user = $ENV{STORAGE_USER};
my $ds8_clidir = $ENV{DS8_CLIDIR};
my $ds8_hmc1 = $ENV{DS8_HMC1};
my $ds8_hmc2 = $ENV{DS8_HMC2};
my $ds8_name = $ENV{STORAGE_NAME};
my $ds8_devid = $ENV{DS8_DEVID};
my $ds8_outfile = $ENV{DS8_OUTFILE};
#
my $ds8_protocol = 0; my $ds8_protocolfile;
$ds8_protocol = $ENV{DS8_PROTOCOL} if (defined $ENV{DS8_PROTOCOL});
$ds8_protocolfile = $ENV{DS8_PROTOCOLFILE} if (defined $ENV{DS8_PROTOCOLFILE});
# -PH
$ds8_outfile .= "-tmp"; # work with a temp file until it does not finish


# Set filenames
my $ds8_perf_script = "${inputdir}/tmp/${ds8_name}.ds8perf.scr";
my $ds8_conf_script = "${inputdir}/tmp/${ds8_name}.ds8conf.scr";
my $tmp_perf_file = "${inputdir}/tmp/${ds8_name}.ds8perf.tmp";
my $tmp_conf_file = "${inputdir}/tmp/${ds8_name}.ds8conf.tmp";
my $tmp_conf_first = "${inputdir}/tmp/${ds8_name}.ds8conf.first.tmp";

# Save current time. Outputs from the DSCLI have a time off the storage. Is not usually synchronized using NTP.
my $local_time = localtime();
my $local_epoch = str2time($local_time);
my %time_record;
$time_record{'local_time'} = $local_time;
$time_record{'local_epoch'} = $local_epoch;

message("Start.") if ($DEBUG);
# Data Collection Header Information
# 
my $config;
#if ( ! -f $ds8_outfile || ! -f $tmp_conf_file ) {
if ( once_a_day ($tmp_conf_file) || ! -f $tmp_conf_file ) {
	message("Proces storage configuration.") if ($DEBUG);
	confscript();
	ds8config();
	perfscript();
	message("Proces storage configuration. Done.") if ($DEBUG);
} elsif ( -f $tmp_conf_first ) {
	message("Proces storage configuration 2 pass. ") if ($DEBUG);
	unlink $tmp_conf_first;
	ds8config();
	message("Proces storage configuration. Done.") if ($DEBUG);
}

message("Proces storage performance data.") if ($DEBUG);

my $line;
my $id;
my $record_ref;
my %data;
my $data_ref = \%data;
my $timeout = $ENV{SAMPLE_RATE};

if ( $timeout eq '' ) {
    $timeout = 900;
} else {
    $timeout = $timeout * 3;
}
# set alarm on first SSH command to make sure it does not hang
eval {
    my $act_time = localtime();
    local $SIG{ALRM} = sub {die "$act_time: died in SIG ALRM";};
    alarm($timeout);

    # Launching DSCLI script - performace
    my $dscli_cmd;
    if ( $ds8_hmc2 ) {
	$dscli_cmd = ${ds8_clidir}."/dscli -hmc1 ".$ds8_hmc1." -hmc2 ".$ds8_hmc2." -user ".$ds8_user." -script ".$ds8_perf_script;
    } else {
	$dscli_cmd = ${ds8_clidir}."/dscli -hmc1 ".$ds8_hmc1." -user ".$ds8_user." -script ".$ds8_perf_script;
    }
    #message(" +".$dscli_cmd) if ($DEBUG);
    open (DSCLI,"$dscli_cmd 2>&1 |") || die "DSCLI command failed. Exiting.";

    $data_ref->{TIME} = \%time_record;

    while ($line = <DSCLI>) {
	chomp ($line);
	if ( $line =~ /^ID\s+(.*)$/) {
		$id = $1;
		
		my %record;
		$record_ref = \%record;
		$record_ref->{'ID'} = $id;

		# First entry in record.
	    # Resolve type of record (RANK | IOPORT | VOLUME).
	    # Create new data structure for record
	} elsif ( $line =~ /^timewrite\s+\(SCSI\)\s+(\d+)$/) {
		# Last entry 
		$record_ref->{'scsi_timewrite'} = $1;
		my $id = $record_ref->{'ID'};
		$data_ref->{$id} = $record_ref;
	} elsif ( $line =~ /^(\w+)\s+\(PPRC\)\s+(\d+)$/ ) {
		$record_ref->{'pprc_'.$1} = $2;
	} elsif ( $line =~ /^(\w+)\s+\(SCSI\)\s+(\d+)$/ ) {
		$record_ref->{'scsi_'.$1} = $2;
	} elsif ( $line =~ /^(\w+)\s+\(FICON\/ESCON\)\s+(\d+)$/ ) {
		$record_ref->{'ficon_'.$1} = $2;
	} elsif ( $line =~ /^timewrite\s+(\d+)$/) {
		# Last entry 
		$record_ref->{'timewrite'} = $1;
		my $id = $record_ref->{'ID'};
		$data_ref->{$id} = $record_ref;
	} elsif ( $line =~ /^Date\s+(.*)$/) {
		$record_ref->{'Date'} = $1;
		$record_ref->{'Epoch'} = str2time_ntz($1);
	} elsif ( $line =~ /^(\w+)\s+(\d+)$/ ) {
		$record_ref->{$1} = $2;
        } elsif ( $line =~ /^CMMCI\d{4}[WE]\s+.*|^CMU[A-Z]\d{5}[WE]\s+.*/ ) {
                error("$line");
                error("Proces storage performance data. Exiting.");
                exit(1);
	}
    }
    close(DSCLI);


    # end of alarm
    alarm (0);
};

if ($@) {
    if ($@ =~ /died in SIG ALRM/) {
        my $act_time = localtime();
        error("command timed out after : $timeout seconds");
        exit (0);
    }
}

if ( not -r $tmp_perf_file ) {
	message("No previous data. Store actual data and exit.") if ($DEBUG);
	store \%data, $tmp_perf_file;
        # First pass 
	open(TMP,">$tmp_conf_first") || die "Cannot create file $tmp_conf_first. Exiting.";
	print TMP ($local_time);
	close(TMP);
        # move the output file from temp to final name, this makes thatb ready for further processing
        my $ds8_outfile_finall = $ENV{DS8_OUTFILE};
        rename $ds8_outfile, $ds8_outfile_finall;
	exit 0;
}

$config = retrieve($tmp_conf_file);
if ( ! defined $config ) {
	error("Retrieve data from file $tmp_conf_file failed.");
	exit 1;
}
my $prev_ref = retrieve($tmp_perf_file);
if ( ! defined $config ) {
	error("Retrieve data from file $tmp_perf_file failed.");
	exit 1;
}

message("Store actual data.") if ($DEBUG);
store(\%data, $tmp_perf_file) or error("Store data to file $tmp_perf_file failed.");

# Count performance data
perf_out(\%data,$prev_ref);

# -PH
# move the output file from temp to final name, this makes thatb ready for further processing
my $ds8_outfile_finall = $ENV{DS8_OUTFILE};
rename $ds8_outfile, $ds8_outfile_finall;

message ("Proces storage performance data. Done.") if ($DEBUG);
exit 0;





# perf_out - Perform the calculation of statistics for interval and writes the output to a file
#
sub perf_out {
	# ID,byteread,bytewrit,Reads,Writes,timeread,timewrite,dataencrypted
	my ($curr_ref,$prev_ref) = @_;
	my %data; my %date;
	my @id; my $c_ref; my $p_ref;
	my @elem = sort keys( %{$curr_ref});
	
	open (PERFOUT,">>$ds8_outfile") || die "Couldn't open file $ds8_outfile.";
	open (PROTOCOL,">>$ds8_protocolfile") || die "Couldn't open file $ds8_protocolfile." if ( $ds8_protocol );
	
	message ("Time: ".epoch2datestr( ($curr_ref->{TIME})->{local_epoch} )) if ($DEBUG);
	# Port Level Statistics
        port_statistics($curr_ref,$prev_ref);
	rank_statistics($curr_ref,$prev_ref);
	volume_statistics($curr_ref,$prev_ref);

	close (PERFOUT);
	close (PROTOCOL) if ( $ds8_protocol );
	
}

sub port_statistics {
	my ($curr_ref,$prev_ref) = @_;
	my @id; my $c_ref; my $p_ref;

	# Port Level Statistics
	#	Interval Start:   2012-04-25 11:01:00 GMT+01:00
	#   Interval End:     2012-04-25 11:06:00 GMT+01:00
	#   Interval Length:  300 seconds
    #---------------------
    #Port ID,Speed (Gbps),I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,FB Read I/Os,FB Write I/Os,FB KBs Read,FB KBs Written,FB Accum Read Time,FB Accum Write Time,CKD Read I/Os,CKD Write I/Os,CKD KBs Read,CKD KBs Written,CKD Accum Read Time,CKD Accum Write Time,PPRC Receive I/Os,PPRC Send I/Os,PPRC KBs Received,PPRC KBs Sent,PPRC Accum Recv Time,PPRC Accum Send Time,Interval Length
    #0x30,4.0,14.489708805207625,1161.809116011045,80.1816745684695,0.504487917146145,26,4319,262.144,348127.232,0.0,2192.0,0,0,0.0,0.0,0,0,0,0,0.0,0.0,0,0,299.868
    #0x31,4.0,858.6378006322782,52915.203756319446,61.62692082430344,0.28839745531657074,216527,40951,1.398276096E7,1884815.36,57728.0,16528.0,0,0,0.0,0.0,0,0,0,0,0.0,0.0,0,0,299.868
	#
	my @elem = sort keys( %{$curr_ref});
	$p_ref = $prev_ref->{TIME};
	$c_ref = $curr_ref->{TIME};
    # 
	print PERFOUT "\nPort Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",epoch2datestr( $p_ref->{local_epoch} ),"\n";
	print PERFOUT "\tInterval End:     ",epoch2datestr( $c_ref->{local_epoch} ),"\n";
	print PERFOUT "\tInterval Length:  ",$c_ref->{local_epoch} - $p_ref->{local_epoch}," seconds\n";
	print PERFOUT "---------------------\n";
	print PERFOUT "Port ID,Speed (Gbps),I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,FB Read I/Os,FB Write I/Os,FB KBs Read,FB KBs Written,FB Accum Read Time,FB Accum Write Time,CKD Read I/Os,CKD Write I/Os,CKD KBs Read,CKD KBs Written,CKD Accum Read Time,CKD Accum Write Time,PPRC Receive I/Os,PPRC Send I/Os,PPRC KBs Received,PPRC KBs Sent,PPRC Accum Recv Time,PPRC Accum Send Time,Interval Length\n";
    # Protocol
    if ( $ds8_protocol ) {
	    print PROTOCOL "\nPort Level Statistics\n";
	    print PROTOCOL "\tInterval Start:   ",epoch2datestr( $p_ref->{local_epoch} ),"\n";
	    print PROTOCOL "\tInterval End:     ",epoch2datestr( $c_ref->{local_epoch} ),"\n";
	    print PROTOCOL "\tInterval Length:  ",$c_ref->{local_epoch} - $p_ref->{local_epoch}," seconds\n";
	    print PROTOCOL "---------------------\n";
	    print PROTOCOL "Port ID,Speed (Gbps),I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,FB Read I/Os,FB Write I/Os,FB KBs Read,FB KBs Written,FB Accum Read Time,FB Accum Write Time,CKD Read I/Os,CKD Write I/Os,CKD KBs Read,CKD KBs Written,CKD Accum Read Time,CKD Accum Write Time,PPRC Receive I/Os,PPRC Send I/Os,PPRC KBs Received,PPRC KBs Sent,PPRC Accum Recv Time,PPRC Accum Send Time,Interval Length\n";
    }
	
	foreach my $id ( @elem ) {
		if ( $id =~ /^I(\d+)/ ) {
			my $ioprt = $1;
                        #message ("DBG: Port: $id");
			if ( not ref($curr_ref->{$id}) ) {
				message ("Incomplete data detected for Port ".$id.". Latest data missing.");
				return;
			}
			if ( not ref($prev_ref->{$id}) ) {
				message ("Incomplete data detected for Port ".$id.". Previous data missing.");
				return;
			}
			if ( not defined( ($curr_ref->{$id})->{Epoch} ) ) {
				message ("Incomplete data detected for Port ".$id.". Latest data missing or corrupted.");
				return;
			}
			if ( not defined( ($prev_ref->{$id})->{Epoch} ) ) {
				message ("Incomplete data detected for Port ".$id.". Previous data missing or corrupted.");
				return;
			}
			my $iorate = port_iorate($curr_ref->{$id},$prev_ref->{$id});
			my $dtrate = port_dtrate($curr_ref->{$id},$prev_ref->{$id});
			my $xfsize = port_xfsize($curr_ref->{$id},$prev_ref->{$id});
			my $rstime = port_rstime($curr_ref->{$id},$prev_ref->{$id});
			my ($fcp_ioread,$fcp_iowrite,$fcp_dtread,$fcp_dtwrite,$fcp_tmread,$fcp_tmwrite) = port_fcp($curr_ref->{$id},$prev_ref->{$id});
			my ($ckd_ioread,$ckd_iowrite,$ckd_dtread,$ckd_dtwrite,$ckd_tmread,$ckd_tmwrite) = port_ckd($curr_ref->{$id},$prev_ref->{$id});
			my ($pprc_ioread,$pprc_iowrite,$pprc_dtread,$pprc_dtwrite,$pprc_tmread,$pprc_tmwrite) = port_pprc($curr_ref->{$id},$prev_ref->{$id});
			my $interval = ($curr_ref->{$id})->{Epoch} - ($prev_ref->{$id})->{Epoch};
			printf PERFOUT ("0x%04d,%.1f,%f,%f,%f,%f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",$ioprt,"4.0",
			        $iorate,$dtrate,$xfsize,$rstime,
			        $fcp_ioread,$fcp_iowrite,$fcp_dtread,$fcp_dtwrite,$fcp_tmread,$fcp_tmwrite,
			        $ckd_ioread,$ckd_iowrite,$ckd_dtread,$ckd_dtwrite,$ckd_tmread,$ckd_tmwrite,
			        $pprc_ioread,$pprc_iowrite,$pprc_dtread,$pprc_dtwrite,$pprc_tmread,$pprc_tmwrite,
			        $interval);
			printf PROTOCOL ("0x%04d,%.1f,%f,%f,%f,%f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",$ioprt,"4.0",
			        $iorate,$dtrate,$xfsize,$rstime,
			        $fcp_ioread,$fcp_iowrite,$fcp_dtread,$fcp_dtwrite,$fcp_tmread,$fcp_tmwrite,
			        $ckd_ioread,$ckd_iowrite,$ckd_dtread,$ckd_dtwrite,$ckd_tmread,$ckd_tmwrite,
			        $pprc_ioread,$pprc_iowrite,$pprc_dtread,$pprc_dtwrite,$pprc_tmread,$pprc_tmwrite,
			        $interval) if ($ds8_protocol);
		}
	}
}

# port_iorate
# Averge I/O rate (ops per second) - all operations
sub port_iorate {
	my ($c,$p) = @_;
	my $diff; my $io; my $int;
	$int = $c->{Epoch} - $p->{Epoch}; #print "Interval: $int\n";
	$diff = $c->{scsi_Reads} - $p->{scsi_Reads}; $io = $diff;
	$diff = $c->{ficon_Reads} - $p->{ficon_Reads}; $io = $io + $diff;
	$diff = $c->{pprc_Reads} - $p->{pprc_Reads}; $io = $io + $diff;
	$diff = $c->{scsi_Writes} - $p->{scsi_Writes}; $io = $io + $diff;
	$diff = $c->{ficon_Writes} - $p->{ficon_Writes}; $io = $io + $diff;
	$diff = $c->{pprc_Writes} - $p->{pprc_Writes}; $io = $io + $diff;
	return $io / $int if $int != 0;
	return 0;
}

# port_dtrate
# Averge data rate (KBs per second) - all operations
# DSCLI byteread - value is based on increments of 128kB - 128000 bytes
sub port_dtrate {
	my ($c,$p) = @_;
	my $diff; my $dt; my $int;
	$int = $c->{Epoch} - $p->{Epoch}; #print "Interval: $int\n";
	$diff = $c->{scsi_byteread} - $p->{scsi_byteread}; $dt = $diff;
	$diff = $c->{ficon_byteread} - $p->{ficon_byteread}; $dt = $dt + $diff;
	$diff = $c->{pprc_byteread} - $p->{pprc_byteread}; $dt = $dt + $diff;
	$diff = $c->{scsi_bytewrit} - $p->{scsi_bytewrit}; $dt = $dt + $diff;
	$diff = $c->{ficon_bytewrit} - $p->{ficon_bytewrit}; $dt = $dt + $diff;
	$diff = $c->{pprc_bytewrit} - $p->{pprc_bytewrit}; $dt = $dt + $diff;
	return $dt * 128 / $int if $int != 0;
	return 0;
}


# port_xtsize
# Averge transfer size per I/O (KBs) - all operations
sub port_xfsize {
	my ($c,$p) = @_;
	my $diff; my $io; my $dt;
	# pocet io operaci 
	$diff = $c->{scsi_Reads} - $p->{scsi_Reads}; $io = $diff;
	$diff = $c->{ficon_Reads} - $p->{ficon_Reads}; $io = $io + $diff;
	$diff = $c->{pprc_Reads} - $p->{pprc_Reads}; $io = $io + $diff;
	$diff = $c->{scsi_Writes} - $p->{scsi_Writes}; $io = $io + $diff;
	$diff = $c->{ficon_Writes} - $p->{ficon_Writes}; $io = $io + $diff;
	$diff = $c->{pprc_Writes} - $p->{pprc_Writes}; $io = $io + $diff;
    # pocet bloku
	$diff = $c->{scsi_byteread} - $p->{scsi_byteread}; $dt = $diff;
	$diff = $c->{ficon_byteread} - $p->{ficon_byteread}; $dt = $dt + $diff;
	$diff = $c->{pprc_byteread} - $p->{pprc_byteread}; $dt = $dt + $diff;
	$diff = $c->{scsi_bytewrit} - $p->{scsi_bytewrit}; $dt = $dt + $diff;
	$diff = $c->{ficon_bytewrit} - $p->{ficon_bytewrit}; $dt = $dt + $diff;
	$diff = $c->{pprc_bytewrit} - $p->{pprc_bytewrit}; $dt = $dt + $diff;
	return $dt * 128 / $io if $io != 0;
	return 0;
}

# port_rstime
# Averge response time (miliseconds per I/O) - all operations
# DSCLI timeread - value is based on increments of 16 milliseconds
sub port_rstime {
	my ($c,$p) = @_;
	my $diff; my $time; my $io;
	# pocet io operaci 
	$diff = $c->{scsi_Reads} - $p->{scsi_Reads}; $io = $diff;
	$diff = $c->{ficon_Reads} - $p->{ficon_Reads}; $io = $io + $diff;
	$diff = $c->{pprc_Reads} - $p->{pprc_Reads}; $io = $io + $diff;
	$diff = $c->{scsi_Writes} - $p->{scsi_Writes}; $io = $io + $diff;
	$diff = $c->{ficon_Writes} - $p->{ficon_Writes}; $io = $io + $diff;
	$diff = $c->{pprc_Writes} - $p->{pprc_Writes}; $io = $io + $diff;
    # pocet 16ms intervalu
	$diff = $c->{scsi_timeread} - $p->{scsi_timeread}; $time = $diff;
	$diff = $c->{ficon_timeread} - $p->{ficon_timeread}; $time = $time + $diff;
	$diff = $c->{pprc_timeread} - $p->{pprc_timeread}; $time = $time + $diff;
	$diff = $c->{scsi_timewrite} - $p->{scsi_timewrite}; $time = $time + $diff;
	$diff = $c->{ficon_timewrite} - $p->{ficon_timewrite}; $time = $time + $diff;
	$diff = $c->{pprc_timewrite} - $p->{pprc_timewrite}; $time = $time + $diff;
	return $time * 16 / $io if $io != 0;
	return 0;
}

# port_fcp
# FCP operations:
# Read I/Os, Write I/Os, KBs Read, KBs Written, Accum Read Time, Accum Write Time,
sub port_fcp {
	my ($c,$p) = @_;
	#my $ior; my $iow; my $dtr; my $dtw;
	my ($ior,$iow,$dtr,$dtw,$tmr,$tmw);
	$ior = $c->{scsi_Reads} - $p->{scsi_Reads};
	$iow = $c->{scsi_Writes} - $p->{scsi_Writes};
	$dtr = $c->{scsi_byteread} - $p->{scsi_byteread};
	$dtw = $c->{scsi_bytewrit} - $p->{scsi_bytewrit};
	$tmr = $c->{scsi_timeread} - $p->{scsi_timeread};
	$tmw = $c->{scsi_timewrite} - $p->{scsi_timewrite};
	return ($ior,$iow,$dtr*128,$dtw*128,$tmr*16,$tmw*16);
}

# port_ckd
# CKD operations:
# Read I/Os, Write I/Os, KBs Read, KBs Written, Accum Read Time, Accum Write Time,
sub port_ckd {
	my ($c,$p) = @_;
	#my $ior; my $iow; my $dtr; my $dtw;
	my ($ior,$iow,$dtr,$dtw,$tmr,$tmw);
	$ior = $c->{ficon_Reads} - $p->{ficon_Reads};
	$iow = $c->{ficon_Writes} - $p->{ficon_Writes};
	$dtr = $c->{ficon_byteread} - $p->{ficon_byteread};
	$dtw = $c->{ficon_bytewrit} - $p->{ficon_bytewrit};
	$tmr = $c->{ficon_timeread} - $p->{ficon_timeread};
	$tmw = $c->{ficon_timewrite} - $p->{ficon_timewrite};
	return ($ior,$iow,$dtr*128,$dtw*128,$tmr*16,$tmw*16);
}

# port_pprc
# FCP operations:
# Read I/Os, Write I/Os, KBs Read, KBs Written, Accum Read Time, Accum Write Time,
sub port_pprc {
	my ($c,$p) = @_;
	#my $ior; my $iow; my $dtr; my $dtw;
	my ($ior,$iow,$dtr,$dtw,$tmr,$tmw);
	$ior = $c->{pprc_Reads} - $p->{pprc_Reads};
	$iow = $c->{pprc_Writes} - $p->{pprc_Writes};
	$dtr = $c->{pprc_byteread} - $p->{pprc_byteread};
	$dtw = $c->{pprc_bytewrit} - $p->{pprc_bytewrit};
	$tmr = $c->{pprc_timeread} - $p->{pprc_timeread};
	$tmw = $c->{pprc_timewrite} - $p->{pprc_timewrite};
	return ($ior,$iow,$dtr*128,$dtw*128,$tmr*16,$tmw*16);
}

sub rank_statistics {
	my ($curr_ref,$prev_ref) = @_;
	my @id; my $c_ref; my $p_ref;
    #
	# Rank Level Statistics
    #	Interval Start:   2012-06-01 05:16:00 CEST
    #	Interval End:     2012-06-01 05:26:00 CEST
    #	Interval Length:  600 seconds
    #---------------------
    #Rank ID,RAID Type,Num of Arrays,Read I/O Rate,Write I/O Rate,Read Data Rate,Write Data Rate,Avg Read Xfer Size,Avg Write Xfer Size,Avg Read Resp Time,Avg Write Resp Time,Read I/Os,Write I/Os,KBs Read,KBs Written,Accum Read Time,Accum Write Time,Interval Length
    #0x0,RAID-5,1,0.08000173337088971,7.561830506327637,1.7476645327315425,497.8659337618982,21.845333333333333,65.83934053339212,14.0,74.01190213797663,48,4537,1048.576,298713.088,672,335792,599.987
    #0x1,RAID-5,1,0.36667461128324447,1.788372081395097,15.073606594809554,86.29093630361993,41.108945454545456,48.25110904007456,7.709090909090909,17.714818266542405,220,1073,9043.968,51773.44,1696,19008,599.987
	#
	my @elem = sort keys( %{$curr_ref});
	$p_ref = $prev_ref->{TIME};
	$c_ref = $curr_ref->{TIME};
    # 
	print PERFOUT "\nRank Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",epoch2datestr( $p_ref->{local_epoch} ),"\n";
	print PERFOUT "\tInterval End:     ",epoch2datestr( $c_ref->{local_epoch} ),"\n";
	print PERFOUT "\tInterval Length:  ",$c_ref->{local_epoch} - $p_ref->{local_epoch}," seconds\n";
	print PERFOUT "---------------------\n";
	print PERFOUT "Rank ID,RAID Type,Num of Arrays,Read I/O Rate,Write I/O Rate,Read Data Rate,Write Data Rate,Avg Read Xfer Size,Avg Write Xfer Size,Avg Read Resp Time,Avg Write Resp Time,Read I/Os,Write I/Os,KBs Read,KBs Written,Accum Read Time,Accum Write Time,Interval Length\n";
    # Protocol
    if ($ds8_protocol) {
	    print PROTOCOL "\nRank Level Statistics\n";
	    print PROTOCOL "\tInterval Start:   ",epoch2datestr( $p_ref->{local_epoch} ),"\n";
	    print PROTOCOL "\tInterval End:     ",epoch2datestr( $c_ref->{local_epoch} ),"\n";
	    print PROTOCOL "\tInterval Length:  ",$c_ref->{local_epoch} - $p_ref->{local_epoch}," seconds\n";
	    print PROTOCOL "---------------------\n";
	    print PROTOCOL "Rank ID,RAID Type,Num of Arrays,Read I/O Rate,Write I/O Rate,Read Data Rate,Write Data Rate,Avg Read Xfer Size,Avg Write Xfer Size,Avg Read Resp Time,Avg Write Resp Time,Read I/Os,Write I/Os,KBs Read,KBs Written,Accum Read Time,Accum Write Time,Interval Length\n";
    }
    #
	foreach my $id ( @elem ) {
		if ( $id =~ /^R(\d+)/ ) {
			my $idnum = $1;
                        #message ("DBG: Rank $id");
			if ( not ref($curr_ref->{$id}) ) {
				message ("Incomplete data detected for Rank ".$id.". Latest data missing.");
				return;
			}
			if ( not ref($prev_ref->{$id}) ) {
				message ("Incomplete data detected for Rank ".$id.". Previous data missing.");
				return;
			}
			if ( not defined( ($curr_ref->{$id})->{Epoch} ) ) {
				message ("Incomplete data detected for Rank ".$id.". Latest data missing or corrupted.");
				return;
			}
			if ( not defined( ($prev_ref->{$id})->{Epoch} ) ) {
				message ("Incomplete data detected for Rank ".$id.". Previous data missing or corrupted.");
				return;
			}
			my ($ioreadps,$iowriteps,$dtreadps,$dtwriteps,$xferread,$xferwrite,$rstmread,$rstmwrite)
			                                                        = rank_aver($curr_ref->{$id},$prev_ref->{$id});
			my ($ioread,$iowrite,$dtread,$dtwrite,$tmread,$tmwrite) = rank_oper($curr_ref->{$id},$prev_ref->{$id});
			my $interval = ($curr_ref->{$id})->{Epoch} - ($prev_ref->{$id})->{Epoch};
			my $rtype = ($config->{$id})->{RAIDtype};
			printf PERFOUT ("0x%02d,RAID-%d,1,%f,%f,%f,%f,%f,%f,%f,%f,%d,%d,%d,%d,%d,%d,%d\n",
			        $idnum,$rtype,
			        $ioreadps,$iowriteps,$dtreadps,$dtwriteps,$xferread,$xferwrite,$rstmread,$rstmwrite,
			        $ioread,$iowrite,$dtread,$dtwrite,$tmread,$tmwrite,
			        $interval);
			printf PROTOCOL ("0x%02d,RAID-%d,1,%f,%f,%f,%f,%f,%f,%f,%f,%d,%d,%d,%d,%d,%d,%d\n",
			        $idnum,$rtype,
			        $ioreadps,$iowriteps,$dtreadps,$dtwriteps,$xferread,$xferwrite,$rstmread,$rstmwrite,
			        $ioread,$iowrite,$dtread,$dtwrite,$tmread,$tmwrite,
			        $interval) if ($ds8_protocol);
		}
	}
}

# rank_aver
# 
sub rank_aver {
	my ($c,$p) = @_;
	my $diff; my $int;
	my ($rio,$wio,$dtr,$dtw,$tmr,$tmw ); 
	$int = $c->{Epoch} - $p->{Epoch};
	$rio = $c->{Reads} - $p->{Reads};
	$wio = $c->{Writes} - $p->{Writes};
	$dtr = $c->{byteread} - $p->{byteread};
	$dtw = $c->{bytewrit} - $p->{bytewrit};
	$tmr = $c->{timeread} - $p->{timeread};
	$tmw = $c->{timewrite} - $p->{timewrite};
	if ( $rio == 0 && $wio == 0 ) {
		return ($rio/$int,$wio/$int,$dtr*128/$int,$dtw*128/$int,0,0,0,0 );
	} elsif ( $rio == 0 ) {
		return ($rio/$int,$wio/$int,$dtr*128/$int,$dtw*128/$int,0,$dtw*128/$wio,0,$tmw*16/$wio );
	} elsif ( $wio == 0 ) {
		return ($rio/$int,$wio/$int,$dtr*128/$int,$dtw*128/$int,$dtr*128/$rio,0,$tmr*16/$rio,0 );
	} else {
		return ($rio/$int,$wio/$int,$dtr*128/$int,$dtw*128/$int,$dtr*128/$rio,$dtw*128/$wio,$tmr*16/$rio,$tmw*16/$wio );
	}
}

# rank_oper
# Operations:
# Read I/Os, Write I/Os, KBs Read, KBs Written, Accum Read Time, Accum Write Time,
sub rank_oper {
	my ($c,$p) = @_;
	my ($ior,$iow,$dtr,$dtw,$tmr,$tmw);
	$ior = $c->{Reads} - $p->{Reads};
	$iow = $c->{Writes} - $p->{Writes};
	$dtr = $c->{byteread} - $p->{byteread};
	$dtw = $c->{bytewrit} - $p->{bytewrit};
	$tmr = $c->{timeread} - $p->{timeread};
	$tmw = $c->{timewrite} - $p->{timewrite};
	return ($ior,$iow,$dtr*128,$dtw*128,$tmr*16,$tmw*16);
}


sub volume_statistics {
	my ($curr_ref,$prev_ref) = @_;
	my @id; my $c_ref; my $p_ref;
    #
	# Volume Level Statistics
    #	Interval Start:   2012-06-01 05:16:00 CEST
    #	Interval End:     2012-06-01 05:26:00 CEST
    #	Interval Length:  600 seconds
    #-----------------------
    #Volume ID,I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,Delayed I/O Perc,Total Hit Perc,Read Hit Perc,Write Hit Perc,Non-seq Read I/Os,Non-seq Write I/Os,Seq Read I/Os,Seq Write I/Os,Non-seq Read Hits,Non-seq Write Hits,Seq Read Hits,Seq Write Hits,KBs Read,KBs Written,Accum Read Time,Accum Write Time,Non-seq Disk->Cache Ops,Seq Disk->Cache Ops,Cache->Disk Ops,NVS Allocs,Non-seq DFW I/Os,Seq DFW I/Os,NVS Delayed DFW I/Os,Cache Delayed I/Os,Rec Mode Read I/Os,Rec Mode Read Hits,CC/XRC Trks Read,CC/XRC Contam Writes,PPRC Trk Xfers,Quick Write Prom,CFW Read I/Os,CFW Write I/Os,CFW Read Hits,CFW Write Hits,Irreg Trk Acc,Irreg Trk Acc Hits,Backend Read Ops,Backend Write Ops,Backend KBs Read,Backend KBs Written,Backend Accum Read Time,Backend Accum Write Time,ICL Read I/Os,Cache Bypass Write I/Os,Backend Data Xfer Time,Interval Length
    #0x4000,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0,0,0,0,0,0,0,0,0.0,0.0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.0,0.0,0,0,0,0,0,599.457
    #0x4101,0.373613,80.669782,215.917714,4.857142,0.0,100.0,100.0,100.0,170,54,0,0,170,54,0,0,24379.392,23986.176,832,256,0,0,369,54,0,0,0,0,146,146,0,0,0,0,0,0,0,0,0,0,0,19,0.0,23986.176,0,8480,0,0,0,599.55
    #
	my @elem = sort keys( %{$curr_ref});
	$p_ref = $prev_ref->{TIME};
	$c_ref = $curr_ref->{TIME};
    #
	print PERFOUT "\nVolume Level Statistics\n";
	print PERFOUT "\tInterval Start:   ",epoch2datestr( $p_ref->{local_epoch} ),"\n";
	print PERFOUT "\tInterval End:     ",epoch2datestr( $c_ref->{local_epoch} ),"\n";
	print PERFOUT "\tInterval Length:  ",$c_ref->{local_epoch} - $p_ref->{local_epoch}," seconds\n";
	print PERFOUT "-----------------------\n";
	print PERFOUT "Volume ID,I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,Delayed I/O Perc,Total Hit Perc,Read Hit Perc,Write Hit Perc,Non-seq Read I/Os,Non-seq Write I/Os,Seq Read I/Os,Seq Write I/Os,Non-seq Read Hits,Non-seq Write Hits,Seq Read Hits,Seq Write Hits,KBs Read,KBs Written,Accum Read Time,Accum Write Time,Non-seq Disk->Cache Ops,Seq Disk->Cache Ops,Cache->Disk Ops,NVS Allocs,Non-seq DFW I/Os,Seq DFW I/Os,NVS Delayed DFW I/Os,Cache Delayed I/Os,Rec Mode Read I/Os,Rec Mode Read Hits,CC/XRC Trks Read,CC/XRC Contam Writes,PPRC Trk Xfers,Quick Write Prom,CFW Read I/Os,CFW Write I/Os,CFW Read Hits,CFW Write Hits,Irreg Trk Acc,Irreg Trk Acc Hits,Backend Read Ops,Backend Write Ops,Backend KBs Read,Backend KBs Written,Backend Accum Read Time,Backend Accum Write Time,ICL Read I/Os,Cache Bypass Write I/Os,Backend Data Xfer Time,Interval Length,Pool ID\n";
    # Protocol
    if ($ds8_protocol) {
	    print PROTOCOL "\nVolume Level Statistics\n";
	    print PROTOCOL "\tInterval Start:   ",epoch2datestr( $p_ref->{local_epoch} ),"\n";
	    print PROTOCOL "\tInterval End:     ",epoch2datestr( $c_ref->{local_epoch} ),"\n";
	    print PROTOCOL "\tInterval Length:  ",$c_ref->{local_epoch} - $p_ref->{local_epoch}," seconds\n";
	    print PROTOCOL "-----------------------\n";
	    print PROTOCOL "Volume ID,I/O Rate,Data Rate,Avg Xfer Size,Avg Resp Time,Delayed I/O Perc,Total Hit Perc,Read Hit Perc,Write Hit Perc,Non-seq Read I/Os,Non-seq Write I/Os,Seq Read I/Os,Seq Write I/Os,Non-seq Read Hits,Non-seq Write Hits,Seq Read Hits,Seq Write Hits,KBs Read,KBs Written,Accum Read Time,Accum Write Time,Non-seq Disk->Cache Ops,Seq Disk->Cache Ops,Cache->Disk Ops,NVS Allocs,Non-seq DFW I/Os,Seq DFW I/Os,NVS Delayed DFW I/Os,Cache Delayed I/Os,Rec Mode Read I/Os,Rec Mode Read Hits,CC/XRC Trks Read,CC/XRC Contam Writes,PPRC Trk Xfers,Quick Write Prom,CFW Read I/Os,CFW Write I/Os,CFW Read Hits,CFW Write Hits,Irreg Trk Acc,Irreg Trk Acc Hits,Backend Read Ops,Backend Write Ops,Backend KBs Read,Backend KBs Written,Backend Accum Read Time,Backend Accum Write Time,ICL Read I/Os,Cache Bypass Write I/Os,Backend Data Xfer Time,Interval Length,Pool ID\n";
    }
    #
	foreach my $id ( @elem ) {
		if ( $id =~ /^([0-9a-fA-F]{4})/ ) {
			my $poolid;
			my $volid = $1;
                        #message ("DBG: Volume $id");
			if ( not ref($curr_ref->{$id}) ) {
				message ("Incomplete data detected for Volume ".$id.". Latest data missing.");
				return;
			}
			if ( not ref($prev_ref->{$id}) ) {
				message ("Incomplete data detected for Volume ".$id.". Previous data missing.");
				return;
			}
			if ( not defined( ($curr_ref->{$id})->{Epoch} ) ) {
				message ("Incomplete data detected for Volume ".$id.". Latest data missing or corrupted.");
				return;
			}
			if ( not defined( ($prev_ref->{$id})->{Epoch} ) ) {
				message ("Incomplete data detected for Volume ".$id.". Previous data missing or corrupted.");
				return;
			}
			if( not ref($config->{$id}) ) {
				$poolid = "";
			} else {
				$poolid = ($config->{$id})->{"extpool"};
			}
			my $iorate = volume_iorate($curr_ref->{$id},$prev_ref->{$id});
			my $dtrate = volume_dtrate($curr_ref->{$id},$prev_ref->{$id});
			my $xfsize = volume_xfsize($curr_ref->{$id},$prev_ref->{$id});
			my $rstime = volume_rstime($curr_ref->{$id},$prev_ref->{$id});
			my ($dlioperc,$tothitperc,$readhitperc,$writehitperc) = volume_percent($curr_ref->{$id},$prev_ref->{$id});
			my ($normreads,$normwrites,$seqreads,$seqwrites,$normreadhits,$normwritehits,$seqreadhits,$seqwritehits) = volume_stat1($curr_ref->{$id},$prev_ref->{$id});
			my ($datareads,$datawrites,$accreadtm,$accwritetm,$normdasdtrans,$seqdasdtrans,$seqcachetrans) = volume_stat2($curr_ref->{$id},$prev_ref->{$id});
			my ($nvsspallo,$normdfwops,$seqdfwops,$nvsspadel,$cachspdelay,$recmoreadops,$recmoreadhits) = volume_stat3($curr_ref->{$id},$prev_ref->{$id});
			my ($xrctrkreads,$xrccontamwrts,$pprctrks,$qwriteprots,$cfwreadreqs,$cfwwritereqs,$cfwreadhits,$cfwwritehits) = volume_stat4($curr_ref->{$id},$prev_ref->{$id});
			my ($ckdirtrkac,$ckdirtrkhits,$phread,$phwrite,$phbyteread,$phbytewrite,$timephread,$timephwrite) = volume_stat5($curr_ref->{$id},$prev_ref->{$id});
			my ($inbcachload,$bypasscach,$timelowifact) = volume_stat6($curr_ref->{$id},$prev_ref->{$id});
			my $interval = ($curr_ref->{$id})->{Epoch} - ($prev_ref->{$id})->{Epoch};
			printf PERFOUT ("0x%04s,%f,%f,%f,%f,%f,%f,%f,%f,%d,%d,%d,%d,%d,%d,%d,%d,%f,%f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%f,%f,%d,%d,%d,%d,%d,%d,%s\n",$volid,
			        $iorate,$dtrate,$xfsize,$rstime,
			        $dlioperc,$tothitperc,$readhitperc,$writehitperc,
			        $normreads,$normwrites,$seqreads,$seqwrites,$normreadhits,$normwritehits,$seqreadhits,$seqwritehits,
			        $datareads,$datawrites,$accreadtm,$accwritetm,$normdasdtrans,$seqdasdtrans,$seqcachetrans,
			        $nvsspallo,$normdfwops,$seqdfwops,$nvsspadel,$cachspdelay,$recmoreadops,$recmoreadhits,
			        $xrctrkreads,$xrccontamwrts,$pprctrks,$qwriteprots,$cfwreadreqs,$cfwwritereqs,$cfwreadhits,$cfwwritehits,
			        $ckdirtrkac,$ckdirtrkhits,$phread,$phwrite,$phbyteread,$phbytewrite,$timephread,$timephwrite,
			        $inbcachload,$bypasscach,$timelowifact,
			        $interval,$poolid);
			printf PROTOCOL ("0x%04s,%f,%f,%f,%f,%f,%f,%f,%f,%d,%d,%d,%d,%d,%d,%d,%d,%f,%f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%f,%f,%d,%d,%d,%d,%d,%d,%s\n",$volid,
			        $iorate,$dtrate,$xfsize,$rstime,
			        $dlioperc,$tothitperc,$readhitperc,$writehitperc,
			        $normreads,$normwrites,$seqreads,$seqwrites,$normreadhits,$normwritehits,$seqreadhits,$seqwritehits,
			        $datareads,$datawrites,$accreadtm,$accwritetm,$normdasdtrans,$seqdasdtrans,$seqcachetrans,
			        $nvsspallo,$normdfwops,$seqdfwops,$nvsspadel,$cachspdelay,$recmoreadops,$recmoreadhits,
			        $xrctrkreads,$xrccontamwrts,$pprctrks,$qwriteprots,$cfwreadreqs,$cfwwritereqs,$cfwreadhits,$cfwwritehits,
			        $ckdirtrkac,$ckdirtrkhits,$phread,$phwrite,$phbyteread,$phbytewrite,$timephread,$timephwrite,
			        $inbcachload,$bypasscach,$timelowifact,
			        $interval,$poolid) if ( $ds8_protocol );
		}
	}
}

# volume_iorate
# Averge I/O rate (ops per second) - all operations
sub volume_iorate {
	my ($c,$p) = @_;
	my $diff; my $io; my $int;
	$int = $c->{Epoch} - $p->{Epoch}; #print "Interval: $int\n";
	$diff = $c->{normrdrqts} - $p->{normrdrqts}; $io = $diff;               # normal non-seq read IO
	$diff = $c->{normwritereq} - $p->{normwritereq}; $io = $io + $diff;     # normal non-seq write IO
	$diff = $c->{seqreadreqs} - $p->{seqreadreqs}; $io = $io + $diff;       # sequential read IO
	$diff = $c->{seqwritereq} - $p->{seqwritereq}; $io = $io + $diff;       # sequential write IO
	$diff = $c->{cachfwrreqs} - $p->{cachfwrreqs}; $io = $io + $diff;       # CFW read IO
	$diff = $c->{cachefwreqs} - $p->{cachefwreqs}; $io = $io + $diff;         # CFW write IO
	return $io / $int if $int != 0;
	return 0;
}


# volume_dtrate
# Averge data rate (KBs per second) - all operations
# DSCLI byteread - value is based on increments of 128kB - 128000 bytes
sub volume_dtrate {
	my ($c,$p) = @_;
	my $diff; my $dt; my $int;
	$int = $c->{Epoch} - $p->{Epoch}; #print "Interval: $int\n";
	$diff = $c->{byteread} - $p->{byteread}; $dt = $diff;
	$diff = $c->{bytewrit} - $p->{bytewrit}; $dt = $dt + $diff;
	return $dt * 128 / $int if $int != 0;
	return 0;
}


# volume_xtsize
# Averge transfer size per I/O (KBs) - all operations
sub volume_xfsize {
	my ($c,$p) = @_;
	my $diff; my $io; my $dt;
	# the number of IO operations
	$diff = $c->{normrdrqts} - $p->{normrdrqts}; $io = $diff;               # normal non-seq read IO
	$diff = $c->{normwritereq} - $p->{normwritereq}; $io = $io + $diff;     # normal non-seq write IO
	$diff = $c->{seqreadreqs} - $p->{seqreadreqs}; $io = $io + $diff;       # sequential read IO
	$diff = $c->{seqwritereq} - $p->{seqwritereq}; $io = $io + $diff;       # sequential write IO
	$diff = $c->{cachfwrreqs} - $p->{cachfwrreqs}; $io = $io + $diff;       # CFW read IO
	$diff = $c->{cachefwreqs} - $p->{cachefwreqs}; $io = $io + $diff;         # CFW write IO
    # the number of block
	$diff = $c->{byteread} - $p->{byteread}; $dt = $diff;
	$diff = $c->{bytewrit} - $p->{bytewrit}; $dt = $dt + $diff;
	return $dt * 128 / $io if $io != 0;
	return 0;
}

# volume_rstime
# Averge response time (miliseconds per I/O) - all operations
# DSCLI timeread - value is based on increments of 16 milliseconds
sub volume_rstime {
	my ($c,$p) = @_;
	my $diff; my $time; my $io;
	# the number of IO operations
	$diff = $c->{normrdrqts} - $p->{normrdrqts}; $io = $diff;               # normal non-seq read IO
	$diff = $c->{normwritereq} - $p->{normwritereq}; $io = $io + $diff;     # normal non-seq write IO
	$diff = $c->{seqreadreqs} - $p->{seqreadreqs}; $io = $io + $diff;       # sequential read IO
	$diff = $c->{seqwritereq} - $p->{seqwritereq}; $io = $io + $diff;       # sequential write IO
	$diff = $c->{cachfwrreqs} - $p->{cachfwrreqs}; $io = $io + $diff;       # CFW read IO
	$diff = $c->{cachefwreqs} - $p->{cachefwreqs}; $io = $io + $diff;         # CFW write IO
    # the number of 16ms intervals
	$diff = $c->{timeread} - $p->{timeread}; $time = $diff;
	$diff = $c->{timewrite} - $p->{timewrite}; $time = $time + $diff;
	return $time * 16 / $io if $io != 0;
	return 0;
}

# volume_percent
# dlioperc - Delayed IO Percentage 
# 
sub volume_percent {
	my ($c,$p) = @_;
	my $time; my $diff; my $rio; my $wio; my $rht; my $wht; my $div;
	# Delayed IO Percentage - NVSspadel/(normwriteops + seqwriteops)
	my $dlioperc = 0;
	$div = ($c->{normwriteops} - $p->{normwriteops}) + ($c->{seqwriteops} - $p->{seqwriteops});
	$dlioperc = $c->{NVSspadel} - $p->{NVSspadel} if $div != 0;
	# Total Hit Percentage - (normrdhits + normwritehits + seqreadhits + seqwritehits + cachfwrhits + cachfwhits)/total io * 100
	my $tothitperc = 0; my $readhitperc = 0; my $writehitperc = 0;
	# read io
	$diff = $c->{normrdrqts} - $p->{normrdrqts}; $rio = $diff;         
	$diff = $c->{seqreadreqs} - $p->{seqreadreqs}; $rio = $rio + $diff;
	$diff = $c->{cachfwrreqs} - $p->{cachfwrreqs}; $rio = $rio + $diff;
	# write io
	$diff = $c->{normwritereq} - $p->{normwritereq}; $wio = $diff;
	$diff = $c->{seqwritereq} - $p->{seqwritereq}; $wio = $wio + $diff; 
	$diff = $c->{cachefwreqs} - $p->{cachefwreqs}; $wio = $wio + $diff; 
	# read hits
	$diff = $c->{normrdhits} - $p->{normrdhits}; $rht = $diff;           
	$diff = $c->{seqreadhits} - $p->{seqreadhits}; $rht = $rht + $diff; 
	$diff = $c->{cachfwrhits} - $p->{cachfwrhits}; $rht = $rht + $diff; 
	# write hits
	$diff = $c->{normwritehits} - $p->{normwritehits}; $wht = $diff;
	$diff = $c->{seqwritehits} - $p->{seqwritehits}; $wht = $wht + $diff; 
	$diff = $c->{cachfwhits} - $p->{cachfwhits}; $wht = $wht + $diff;  
	$tothitperc = 100 * ($rht + $wht) / ($rio + $wio) if $rio + $wio != 0;
	$readhitperc = 100 * $rht / $rio if $rio != 0;
	$writehitperc = 100 * $wht / $wio if $wio != 0;
	#
	return ($dlioperc,$tothitperc,$readhitperc,$writehitperc);
}

# volume_stat1
# 
sub volume_stat1 {
	my ($c,$p) = @_;
	my $normreads = $c->{normrdrqts} - $p->{normrdrqts};                # Non-seq Read IOs
	my $normwrites = $c->{normwritereq} - $p->{normwritereq};           # Non-seq Write IOs
	my $seqreads = $c->{seqreadreqs} - $p->{seqreadreqs};               # Seq Read IOs
	my $seqwrites = $c->{seqwritereq} - $p->{seqwritereq};              # Seq Write IOs
	#
	my $normreadhits = $c->{normrdhits} - $p->{normrdhits};            # Non-seq Read Hits
	my $normwritehits = $c->{normwritehits} - $p->{normwritehits};      # Non-seq Write Hits
	my $seqreadhits = $c->{seqreadhits} - $p->{seqreadhits};            # Seq Read Hits
	my $seqwritehits = $c->{seqwritehits} - $p->{seqwritehits};         # Seq Write Hits
	#
	return ($normreads,$normwrites,$seqreads,$seqwrites,$normreadhits,$normwritehits,$seqreadhits,$seqwritehits);
}

# volume_stat2
# 
sub volume_stat2 {
	my ($c,$p) = @_;
	my $datareads = ( $c->{byteread} - $p->{byteread} ) * 128;          # KBs Read
	my $datawrites = ( $c->{bytewrit} - $p->{bytewrit} ) * 128;         # KBs Write
	#
	my $accreadtm = ( $c->{timeread} - $p->{timeread} ) * 16;           # Accum Read Time
	my $accwritetm = ( $c->{timewrite} - $p->{timewrite} ) * 16;        # Accum Write Time
	#
	my $normdasdtrans = $c->{DASDtrans} - $p->{DASDtrans};              # Non-seq Disk->Cache Ops
	my $seqdasdtrans = $c->{seqDASDtrans} - $p->{seqDASDtrans};         # Seq Disk->Cache Ops
	my $seqcachetrans = $c->{cachetrans} - $p->{cachetrans};             # Cache->Disk Ops
	#
	return ($datareads,$datawrites,$accreadtm,$accwritetm,$normdasdtrans,$seqdasdtrans,$seqcachetrans);
}
	
# volume_stat3
# 
sub volume_stat3 {
	my ($c,$p) = @_;
	my $nvsspallo = $c->{NVSspallo} - $p->{NVSspallo};           # NVS Allocs
	my $normdfwops = $c->{normwriteops} - $p->{normwriteops};    # Non-seq DFW IOs
	my $seqdfwops = $c->{seqwriteops} - $p->{seqwriteops};       # Seq DFW IOs
	my $nvsspadel = $c->{NVSspadel} - $p->{NVSspadel};           # NVS Delayed DFW IOs
	my $cachspdelay = $c->{cachspdelay} - $p->{cachspdelay};       # Cache Delayed IOs
	my $recmoreadops = $c->{recmoreads} - $p->{recmoreads};      # Record Mode Read IOs
	my $recmoreadhits = $recmoreadops - ( $c->{reccachemis} - $p->{reccachemis} );   # Record Mode Read Hits
	#
	return ($nvsspallo,$normdfwops,$seqdfwops,$nvsspadel,$cachspdelay,$recmoreadops,$recmoreadhits);
}

# volume_stat4
# 
sub volume_stat4 {
	my ($c,$p) = @_;
	my $xrctrkreads = $c->{sfiletrkreads} - $p->{sfiletrkreads}; # CC/XRC Trks Read
	my $xrccontamwrts = $c->{contamwrts} - $p->{contamwrts};     # CC/XRC Contam Writes
	my $pprctrks = $c->{PPRCtrks} - $p->{PPRCtrks};              # PPRC Trk Xfers
	my $qwriteprots = $c->{qwriteprots} - $p->{qwriteprots};     # Quick Write Prom
	my $cfwreadreqs = $c->{cachefwreqs} - $p->{cachefwreqs};       # CFW Read IOs
	my $cfwwritereqs = $c->{cachfwrreqs} - $p->{cachfwrreqs};    # CFW Write IOs
	my $cfwreadhits = $c->{cachfwhits} - $p->{cachfwhits};       # CFW Read Hits
	my $cfwwritehits = $c->{cachfwrhits} - $p->{cachfwrhits};    # CFW Write Hits
	#
	return ($xrctrkreads,$xrccontamwrts,$pprctrks,$qwriteprots,$cfwreadreqs,$cfwwritereqs,$cfwreadhits,$cfwwritehits);
}


# volume_stat5
# 
sub volume_stat5 {
	my ($c,$p) = @_;
	my $ckdirtrkac = $c->{CKDirtrkac} - $p->{CKDirtrkac};                 # CKD Irreg Trk Acc
	my $ckdirtrkhits = $c->{CKDirtrkhits} - $p->{CKDirtrkhits};           # CKD Irreg Trk Acc Hits
	my $phread = $c->{phread} - $p->{phread};                             # Backend Read Ops
	my $phwrite = $c->{phwrite} - $p->{phwrite};                          # Backend Write Ops
	my $phbyteread = ( $c->{phbyteread} - $p->{phbyteread} ) * 128;       # Backend KBs Read
	my $phbytewrite = ( $c->{phbytewrite} - $p->{phbytewrite} ) * 128;      # Backend KBs Write
	my $timephread = ( $c->{timephread} - $p->{timephread} ) * 16;        # Backend Accum Read Time
	my $timephwrite = ( $c->{timephwrite} - $p->{timephwrite} ) * 16;     # Backend Accum Write Time
	#
	return ($ckdirtrkac,$ckdirtrkhits,$phread,$phwrite,$phbyteread,$phbytewrite,$timephread,$timephwrite);
}

# volume_stat6
# 
sub volume_stat6 {
	my ($c,$p) = @_;
	my $inbcachload = $c->{inbcachload} - $p->{inbcachload};              # ICL ReadIOs
	my $bypasscach = $c->{bypasscach} - $p->{bypasscach};                 # Cache Bypass Write IOs
	my $timelowifact = $c->{timelowifact} - $p->{timelowifact};           # Backend Data Xfer Time 
	#
	return ($inbcachload,$bypasscach,$timelowifact);
}



sub epoch2datestr {
    # Vystup: 2012-04-25 09:50:00 GMT+01:00
    my $tm = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($tm);
    my $y = $year + 1900;
    my $m = $mon + 1;
    my $tz = tzoffset();
    my $str = sprintf("%4s-%02s-%02s %02s:%02s:%02s %s",$y,$m,$mday,$hour,$min,$sec,$tz);
    return($str);
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
    return sprintf("%s%s%02d:00","GMT",$sign,$tzo);
}


sub ds8config {
    # Launching DSCLI script - storage configuration

    my $line;
    my $id;
    my $record_ref;
    my %data;
    my $data_ref = \%data;
    $config = $data_ref;
    my @storage_hdr = qw(Name ID StorageUnit Model WWNN State ESSNet);
    my @rank_hdr = qw(ID Group State datastate Array RAIDtype extpoolID extpoolnam stgtype exts usedexts encryptgrp);
    my @ioprt_hdr = qw(ID WWPN State Type topo portgrp Speed);
    my @fbvol_hdr = qw(Name ID accstate datastate configstate deviceMTM datatype extpool sam captype cap_2_30B cap_10_9B cap_blocks volgrp reqcap_blocks eam perfgrp resgrp);
    my @hsprt_hdr = qw(Name ID WWPN HostType LBS addrDiscovery Profile portgrp volgrpID atchtopo ESSIOport speed desc);
    my @host_hdr = qw(Name ID Type);
    my $timeout = $ENV{SAMPLE_RATE};

    if ( $timeout eq '' ) {
        $timeout = 900;
    } else {
        $timeout = $timeout * 3;
    }
    # set alarm on first SSH command to make sure it does not hang
    eval {
      my $act_time = localtime();
      local $SIG{ALRM} = sub {die "$act_time: died in SIG ALRM";};
      alarm($timeout);

      my $dscli_cmd;
      if ( $ds8_hmc2 ) {
          $dscli_cmd = ${ds8_clidir}."/dscli -hmc1 ".$ds8_hmc1." -hmc2 ".$ds8_hmc2." -user ".$ds8_user." -script ".$ds8_conf_script;
      } else {
          $dscli_cmd = ${ds8_clidir}."/dscli -hmc1 ".$ds8_hmc1." -user ".$ds8_user." -script ".$ds8_conf_script;
      }
      #message(" +".$dscli_cmd) if ($DEBUG);
      open (DSCLI,"$dscli_cmd 2>&1 |") || die "DSCLI command failed. Exiting.";


      while ($line = <DSCLI>) {
    	chomp ($line);
    	if ( $line =~ /^[\w -.]+:(IBM.\d{4}-\w{7}):.*$/) {   # storage
    		my %record = ();
    		$record_ref = \%record;
            my @values = split(/:/,$line);
    		@record{@storage_hdr} = @values;
    		$id="_CFG_";
            $data_ref->{$id} = $record_ref;
    	} elsif ( $line =~ /^IBM.\d{4}-\w{7}\/(I\d{4}):.*$/) {   # IO Port
    		my %record = ();
    		$record_ref = \%record;
            my @values = split(/:/,$line);
    		@record{@ioprt_hdr} = @values;
    		$id = $1;
            $data_ref->{$id} = $record_ref;
    	} elsif ( $line =~ /^IBM.\d{4}-\w{7}\/(R\d+):.*$/) {   # Rank
    		my %record = ();
    		$record_ref = \%record;
            my @values = split(/:/,$line);
    		@record{@rank_hdr} = @values;
    		$id = $1;
            $data_ref->{$id} = $record_ref;
    	} elsif ( $line =~ /^[\w -.]+:IBM.\d{4}-\w{7}\/([0-9A-Fa-f]{4}):[A-Za-z]+:.*$/) {   # FB Volume
    		my %record = ();
    		$record_ref = \%record;
            my @values = split(/:/,$line);
    		@record{@fbvol_hdr} = @values;
    		$id = $1;
            $data_ref->{$id} = $record_ref;
    	} elsif ( $line =~ /^[\w -.]+:IBM.\d{4}-\w{7}\/([0-9A-Fa-f]{4}):[0-9A-Fa-f]{16}:.*$/) {   # Host Connection Port
    		my %record = ();
    		$record_ref = \%record;
            my @values = split(/:/,$line);
    		@record{@hsprt_hdr} = @values;
    		$id = $1;
            $data_ref->{"H".$id} = $record_ref;
    	} elsif ( $line =~ /^[\w -.]+:IBM.\d{4}-\w{7}\/(V\d+):.*$/) {   # Host
    		$id = $1;
    		if ( $id eq "V10" || $id eq "V20" || $id eq "V30" ) { next; }
    		my %record = ();
    		$record_ref = \%record;
            my @values = split(/:/,$line);
    		@record{@host_hdr} = @values;
            $data_ref->{$id} = $record_ref;
        } elsif ( $line =~ /^CMMCI\d{4}[WE]\s+.*|^CMU[A-Z]\d{5}[WE]\s+.*/ ) {
                error("$line");
                error("Proces storage performance data. Exiting.");
                exit(1);
    	}
      }
    
      close(DSCLI);
    
      # end of alarm
      alarm(0);
    };

    if ($@) {
      if ($@ =~ /died in SIG ALRM/) {
          my $act_time = localtime();
          error("command timed out after : $timeout seconds\n");
          exit (0);
      }
    }

	store $data_ref, $tmp_conf_file or error("Store data to file $tmp_conf_file failed.");
    #print Dumper(\%data);
	open (CONFOUT,">$ds8_outfile") || die "Couldn't open file $ds8_outfile.";
	open (PROTOCOL,">$ds8_protocolfile") || die "Couldn't open file $ds8_protocolfile." if ( $ds8_protocol );
    #Data Collection Header
    data_collection_header($data_ref);
    #Configuration data
    configuration_data($data_ref);
    close(CONFOUT);
    close(PROTOCOL) if ( $ds8_protocol );
}

#Data Collection Header
sub data_collection_header {
	my $d_ref = shift;
	my $r_ref = $d_ref->{'_CFG_'};
	print CONFOUT "\nPerformance Data Collection\n";
	print CONFOUT   "---------------------------\n";
	print CONFOUT "\tDS Device ID:                ",$r_ref->{ID},"\n";
	print CONFOUT "\tData Collection Start:       ",epoch2datestr($local_epoch),"\n";
	print CONFOUT "\tData Collection Frequency:   "," \n";
	print CONFOUT "\tData Collection Duration:    "," \n";
	print CONFOUT "\tPerformance Data Collection Utility version  "," \n";
	print CONFOUT "\n======================================================================\n";
	if ( $ds8_protocol ) {
		print PROTOCOL "\nPerformance Data Collection\n";
		print PROTOCOL   "---------------------------\n";
		print PROTOCOL "\tDS Device ID:                ",$r_ref->{ID},"\n";
		print PROTOCOL "\tData Collection Start:       ",epoch2datestr($local_epoch),"\n";
		print PROTOCOL "\tData Collection Frequency:   "," \n";
		print PROTOCOL "\tData Collection Duration:    "," \n";
		print PROTOCOL "\tIBM Performance Data Collection Utility version  "," \n";
		print PROTOCOL "\n======================================================================\n";
	}
}

#Configuration data
sub configuration_data {
	my $d_ref = shift;
	my @elem = sort keys( %{$d_ref});
	my $r_ref = $d_ref->{_CFG_};
	my $mtype;
	if ( $r_ref->{ID} =~ /IBM.(\d{4})-\w{7}/ ) {
		$mtype = $1;
	}

	print CONFOUT "\nConfiguration Data\n";
	print CONFOUT   "------------------\n";
	print CONFOUT "\tMachine Type: ",$mtype,"\n";
	print CONFOUT "\tModel Number: ",$r_ref->{Model},"\n";
	print CONFOUT "\tCache Memory: not available at this time.","\n";
	print CONFOUT "\tNVS Memory: not available at this time.","\n";

	print CONFOUT "\nPort Level Configuration\n";
	print CONFOUT   "------------------------\n";
	print CONFOUT "Port ID,Location,Type,Speed (Gbps),WWPN,Topology\n";
	if ( $ds8_protocol ) {
		print PROTOCOL "\nConfiguration Data\n";
		print PROTOCOL   "------------------\n";
		print PROTOCOL "\tMachine Type: ",$mtype,"\n";
		print PROTOCOL "\tModel Number: ",$r_ref->{Model},"\n";
		print PROTOCOL "\tCache Memory: not available at this time.","\n";
		print PROTOCOL "\tNVS Memory: not available at this time.","\n";

		print PROTOCOL "\nPort Level Configuration\n";
		print PROTOCOL   "------------------------\n";
		print PROTOCOL "Port ID,Location,Type,Speed (Gbps),WWPN,Topology\n";
	}
	foreach my $id ( @elem ) {
		$r_ref = $d_ref->{$id};
		#0x230,U1300.001.RJ02302-P1-C4-T0,FC-SW,0,0x5005076304130914,SCSI/FCP
		my $i; my $s;
		if ( $id =~ /^I(\d{4})$/ ) {
			$i = $1;
			$s = $1 if ( $r_ref->{Speed} =~ /^(\d+)\s+Gb\/s$/ );
			printf CONFOUT ("0x%04d,%s,%s,%d,0x%s,%s\n",$i,"",$r_ref->{Type},$s,$r_ref->{WWPN},$r_ref->{topo} );
			printf PROTOCOL ("0x%04d,%s,%s,%d,0x%s,%s\n",$i,"",$r_ref->{Type},$s,$r_ref->{WWPN},$r_ref->{topo} ) if ( $ds8_protocol );
			
		}
	}
	print CONFOUT "\nRank Level Configuration\n";
	print CONFOUT   "------------------------\n";
	print CONFOUT "Rank ID,Pool ID,Extent Type,Capacity,RAID,Num Arrays,Disk RPM,Disk Size,Pool Name,Used Capacity\n";
	if ( $ds8_protocol ) {
		print PROTOCOL "\nRank Level Configuration\n";
		print PROTOCOL   "------------------------\n";
		print PROTOCOL "Rank ID,Pool ID,Extent Type,Capacity,RAID,Num Arrays,Disk RPM,Disk Size,Pool Name,Used Capacity\n";
	}

	foreach my $id ( @elem ) {
		$r_ref = $d_ref->{$id};
		#0x0,IBM.2107-75AZYM2/P0,FB,1698.659565568,RAID-5,1,10000,300.000
		my $i; my $s;
		if ( $id =~ /^R(\d+)$/ ) {
			$i = $1;
			printf CONFOUT ("0x%02d,%s,%s,%d,RAID-%d,1,10000,300.000,%s,%d\n",
			        $i,$r_ref->{extpoolID},$r_ref->{stgtype},$r_ref->{exts},$r_ref->{RAIDtype},$r_ref->{extpoolnam},$r_ref->{usedexts} );
			printf PROTOCOL ("0x%02d,%s,%s,%d,RAID-%d,1,10000,300.000,%s,%d\n",
			        $i,$r_ref->{extpoolID},$r_ref->{stgtype},$r_ref->{exts},$r_ref->{RAIDtype},$r_ref->{extpoolnam},$r_ref->{usedexts} ) if ( $ds8_protocol );
		}
	}
	print CONFOUT "\nVolume Level Configuration\n";
	print CONFOUT   "--------------------------\n";
	print CONFOUT "Volume ID,Volume SN,Volume Nickname,LSS Number,Volume Number,Volume Size,Volume Type,Host Maps,Pool ID\n";
	if ( $ds8_protocol ) {
		print PROTOCOL "\nVolume Level Configuration\n";
		print PROTOCOL   "--------------------------\n";
		print PROTOCOL "Volume ID,Volume SN,Volume Nickname,LSS Number,Volume Number,Volume Size,Volume Type,Host Maps,Pool ID\n";
	}
	foreach my $id ( @elem ) {
		$r_ref = $d_ref->{$id};
		#0x4000,IBM.2107-75AZYM2/4000,BTP_03L024,0x40,0x0,322.123,FB
		my $i; my $lss; my $num;
		if ( $id =~ /^([0-9a-fA-F]\w{3})$/ ) {
			$i = $1;
			if ( $id =~ /^(\w{2})(\w{2})$/ ) { $lss = $1;$num = $2 };
                        my $volgrp = $r_ref->{volgrp};
                        $volgrp =~ s/,/:/;
			printf CONFOUT ("0x%04s,%s,%s,0x%s,0x%s,%f,%s,%s,%s\n",
			        $i,$r_ref->{ID},$r_ref->{Name},$lss,$num,$r_ref->{cap_2_30B},$r_ref->{datatype},$volgrp,$r_ref->{extpool} );
			printf PROTOCOL ("0x%04s,%s,%s,0x%s,0x%s,%f,%s,%s,%s\n",
			        $i,$r_ref->{ID},$r_ref->{Name},$lss,$num,$r_ref->{cap_2_30B},$r_ref->{datatype},$volgrp,$r_ref->{extpool} ) if ( $ds8_protocol );
		}
	}
	print CONFOUT "\nHost Level Configuration\n";
	print CONFOUT   "--------------------------\n";
	print CONFOUT "host_id,id,name,port_count,Type,volume_count,WWPN,Volume IDs,Volume Names\n";
	if ( $ds8_protocol ) {
		print PROTOCOL "\nHost Level Configuration\n";
		print PROTOCOL   "--------------------------\n";
		print PROTOCOL "host_id,id,name,port_count,Type,volume_count,WWPN,Volume IDs,Volume Names\n";
	}
	foreach my $id ( @elem ) {
		$r_ref = $d_ref->{$id};
		#
		my $i; my $lss; my $num;
		if ( $id =~ /^V(\d+)$/ ) {
			$i = $1;
			my $wwpn = &listhostwwpn($d_ref,$r_ref->{'ID'});
			my @a = split(/ /,$wwpn);
			my $pcnt = scalar(@a);
			my $volid = &listvolumeid($d_ref,$r_ref->{'ID'});
			@a = split(/ /,$volid);
			my $vcnt = scalar(@a);
			my $volname = &listvolumename($d_ref,$r_ref->{'ID'});
			printf CONFOUT ("0x%04s,%s,%s,%d,%s,%d,%s,%s,%s,\n",
			        $i,$r_ref->{ID},$r_ref->{Name},$pcnt,$r_ref->{Type},$vcnt,$wwpn,$volid,$volname );
			printf PROTOCOL ("0x%04s,%s,%s,%d,%s,%d,%s,%s,%s,\n",
			        $i,$r_ref->{ID},$r_ref->{Name},$pcnt,$r_ref->{Type},$vcnt,$wwpn,$volid,$volname ) if ( $ds8_protocol );
			
		}
	}

	print CONFOUT "\n======================================================================\n";
	print PROTOCOL "\n======================================================================\n" if ( $ds8_protocol );
}

sub listhostwwpn {
	my ($d_ref,$hstid) = @_;
	my @elem = sort keys( %{$d_ref});
	my @a;
	foreach my $id ( @elem ) {
		my $r_ref = $d_ref->{$id};
		#
		my $i; my $lss; my $num;
		if ( $id =~ /^H([0-9a-fA-F]{4})$/ ) {
			if ( $hstid eq $r_ref->{'volgrpID'} ) {
				push(@a,$r_ref->{'WWPN'});
			}
		}
	}
	if ( scalar(@a) == 0 ) {
		return "";
	} else {
		return(join(" ",@a));
	}
}

sub listvolumeid {
	my ($d_ref,$hstid) = @_;
	my @elem = sort keys( %{$d_ref});
	my @a;
	foreach my $id ( @elem ) {
		my $r_ref = $d_ref->{$id};
		#
		if ( $id =~ /^[0-9a-fA-F]{4}$/ ) {          # FB Volume
			my @z = split(/,/,$r_ref->{'volgrp'});  # Volume in multiple VG
			foreach my $vid ( @z ) {
				if ( $hstid eq $vid ) {
					push(@a,sprintf("0x%04s",$id));
				}
			}
		}
	}
	if ( scalar(@a) == 0 ) {
		return "";
	} else {
		return(join(" ",@a));
	}
}

sub listvolumename {
	my ($d_ref,$hstid) = @_;
	my @elem = sort keys( %{$d_ref});
	my @a;
	foreach my $id ( @elem ) {
		my $r_ref = $d_ref->{$id};
		#
		#
		if ( $id =~ /^[0-9a-fA-F]{4}$/ ) {          # FB Volume
			my @z = split(/,/,$r_ref->{'volgrp'});  # Volume in multiple VG
			foreach my $vgid ( @z ) {
				if ( $hstid eq $vgid ) {
					push(@a,$r_ref->{'Name'});
				}
			}
		}
	}
	if ( scalar(@a) == 0 ) {
		return "";
	} else {
		return(join(" ",@a));
	}
}

sub perfscript {
	my @elem = sort keys( %{$config});
	my $r_ref = $config->{_CFG_};
    my $dev = $r_ref->{ID};

    if ( -f $ds8_perf_script ) {
        unlink($ds8_perf_script);
    }

	open (SCRIPT,">$ds8_perf_script") || die "Couldn't open file $ds8_perf_script.";
	foreach my $id ( @elem ) {
		$r_ref = $config->{$id};
		if ( $id =~ /^(I\d{4})$/ && $r_ref->{'State'} eq "Online" ) {
			print SCRIPT "showioport -dev ",$dev," -metrics ",$1,"\n";
		}
	}
	foreach my $id ( @elem ) {
		$r_ref = $config->{$id};
		if ( $id =~ /^(R\d+)$/ && $r_ref->{'State'} eq "Normal" ) {
			print SCRIPT "showrank -dev ",$dev," -metrics ",$1,"\n";
		}
	}
    foreach my $id ( @elem ) {
		$r_ref = $config->{$id};
		if ( $id =~ /^([0-9A-Fa-f]{4})$/ && $r_ref->{'accstate'} eq "Online"  ) {
			print SCRIPT "showfbvol -dev ",$dev," -metrics ",$1,"\n";
		}
	}
    
    
    close(SCRIPT);
	return 0;
}


sub confscript {
    my $scr = "setoutput -fmt delim -delim : -p off -hdr on -v off -bnr off\n".
              "lssi -fullid ".$ds8_devid."\n".
              "lsioport -dev ".$ds8_devid." -l -fullid\n".
              "lsrank -dev ".$ds8_devid." -l -fullid\n".
              "lsfbvol -dev ".$ds8_devid." -l -fullid\n".
              "lshostconnect -dev ".$ds8_devid." -l -fullid\n".
              "lsvolgrp -dev ".$ds8_devid." -l -fullid\n";

    if ( -f $ds8_conf_script ) {
        unlink($ds8_conf_script);
    }

	open (SCRIPT,">$ds8_conf_script") || die "Couldn't open file $ds8_conf_script.";
    print SCRIPT $scr;
	close (SCRIPT);
}

# returns 1 when next day after modification the file in the argument
# returns 0 when there is not next day
sub once_a_day {
  my $file = shift;

  if ( ! -f $file ) {
    return 0;
  } else {
    my $run_time = (stat("$file"))[9];
    (my $sec,my $min,my $h,my $aday,my $m,my $y,my $wday,my $yday,my $isdst) = localtime(time());
    ($sec,$min,$h,my $png_day,$m,$y,$wday,$yday,$isdst) = localtime($run_time);
    if ( $aday == $png_day ) {
      # If it is the same day then return 0
      return 0;
    }
    else {
       # diff day
       return 1;
    }
  }
}

# error handling
sub error
{
  my $text = shift;
  my $act_time = localtime();
  print STDERR ("ERROR $act_time: ds8perf.pl: $ds8_name: $text\n");
  return 1;
}

# message handling
sub message
{
  my $text = shift;
  my $act_time = localtime();
  print STDERR ("INFO $act_time: ds8perf.pl: $ds8_name: $text\n");
  return 0;
}

# Calculate difference with detection of negative value
sub DiffCalc {
	my ($l,$p,$m) = @_;
	my $res;
	if ( $l >= $p ) {
		$res = $l - $p;
	} else {
		$res = $l;
		message ("$m - Negative difference occured (prev = $p, last = $l).\n");
	}
	return($res);
}

# Convert date and time without TZ
sub str2time_ntz
{
    my $date_time = shift;
    my @a = split(/ /,$date_time);
    return( str2time ($a[0]." ".$a[1]) );
}
