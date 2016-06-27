#!/usr/bin/perl
#
# Script : check_emc_vnx2.pl - checks the EMC VNX2 SAN arrays
# Author: Julien Lutran <julien@lutran.fr>
#

use strict;
use warnings;
use File::Basename;
use Getopt::Std;
use XML::Simple;
use Data::Dumper;
use Switch;


##########################
#    Global variables    #
##########################

my $naviseccli = "/opt/Navisphere/bin/naviseccli";
my $output = "";
my $state = "OK";
my %options = ();


##########################
#          SUBS          #
##########################

sub Usage {
    print "\nNAME\n\n";
    print "\t",basename($0)," - Shinken monitoring script for EMC VNX2\n\n";
    print "SYNOPSIS\n\n";
    print "\t",basename($0)," -h <ip> -u <username> -p <password> -c <check>\n\n";
    print "ARGUMENTS\n\n";
    print "\t<ip>\t\tSP IP address\n";
    print "\t<username>\tUnisphere username\n";
    print "\t<password>\tUnisphere password\n";
    print "\t<check>\t\tCheck type : disks, enclosures, faults, hotspares, luns, ports, pools\n\n" ;
    exit 1
}

sub runCmd {
    my $args = shift;
    my $error_code = 1;
    my $xml = new XML::Simple;
    my $cmd = `$naviseccli $args`;
    my $dump = $xml->XMLin($cmd);
    my $data = $dump->{'MESSAGE'}->{'SIMPLERSP'}->{'METHODRESPONSE'};
    foreach my $prop (@{$data->{'RETURNVALUE'}->{'VALUE.NAMEDINSTANCE'}->{'INSTANCE'}->{'PROPERTY'}}) {
        if ($prop->{'NAME'} eq 'errorCode') {
            $error_code = $prop->{'VALUE'};
        }
    }
    if ($error_code ne "0") {
        printStatus("UNKNOWN", "No output from $naviseccli");
    } else {
        return ($data);
    }
}

sub printStatus {
    # Nagios exit states
    my %states = (OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3);

    my $state = shift;
    my $output = shift;
    if ($output ne "") { $output =~ s/,\s?$/\.\n/; }
    print $output;
    exit $states{$state};
}

sub checkEnclosure {
    my $cmd = shift;
    my $data = runCmd($cmd);

    foreach my $prop (@{$data->{'PARAMVALUE'}->{'VALUE'}->{'PARAMVALUE'}}) {    
        if ($prop->{'NAME'} =~ /^(.*)\sState$/) {
            my $element = $1;
            my $value = $prop->{'VALUE'};
            if ($value !~ /Present|Valid|N\/A/) {
                $state = "CRITICAL";
                $output .= "$element status : $value,";
            }
        }
    }
    printStatus($state, $output);
}

sub checkCache {
    my $cmd = shift;
    my $data = runCmd($cmd);

    foreach my $prop (@{$data->{'PARAMVALUE'}->{'VALUE'}->{'PARAMVALUE'}}) {
        if ($prop->{'NAME'} =~ /^(.*)\sState$/) {
            my $element = $1;
            my $value = $prop->{'VALUE'};
            if ($value !~ /Enabled/) {
                $state = "CRITICAL";
                $output .= "$element : $value,";
            }
        }
    }
    printStatus($state, $output);
}

sub checkDisk {
    my $cmd = shift;
    my $data = runCmd($cmd);

    my $element;
    foreach my $prop (@{$data->{'PARAMVALUE'}->{'VALUE'}->{'PARAMVALUE'}}) {
        if ($prop->{'NAME'} =~ /^(Bus\s+\d+\s+Enclosure\s+\d+\s+Disk\s+\d+)$/) {
            $element = $1;
        }
        if ($prop->{'NAME'} eq 'State') {
            my $value = $prop->{'VALUE'};
            if ($value !~ /Binding|Empty|Enabled|Expanding|Unbound|Powering Up|Ready|Transitioning/) {
                $state = "CRITICAL";
                $output .= "$element status : $value,";
            }
        }
    }
    printStatus($state, $output);
}

sub checkFaults {
    my $cmd = shift;
    my $data = runCmd($cmd);

    if (ref($data->{'PARAMVALUE'}) eq 'ARRAY') {
        foreach my $prop (@{$data->{'PARAMVALUE'}}) {
            my $name = $prop->{'NAME'};
            my $value = $prop->{'VALUE'};
            next if (($name ne " ") or (ref $value));
            $output .= "$value, ";
            $state = "CRITICAL";
        }
    }
    printStatus($state, $output);
}

sub checkPort {
    my $cmd = shift;
    my $data = runCmd($cmd);

    my $element;
    foreach my $prop (@{$data->{'PARAMVALUE'}->{'VALUE'}->{'PARAMVALUE'}}) {
        if ($prop->{'NAME'} =~ /^(\S+)\.([a|b]\d)$/) {
            $element = $2;
        }
        my $name = $prop->{'NAME'};
        my $value = $prop->{'VALUE'};
        if ($name =~ /Port Status/ and $value !~ /Online/) {
            $state = "CRITICAL";
            $output .= "$element status : $value,";
        }
    }
    printStatus($state, $output);
}

sub checkStoragePool {
    my $cmd = shift;
    my $data = runCmd($cmd);

    my $element;
    foreach my $prop (@{$data->{'PARAMVALUE'}}) {
        if ($prop->{'NAME'} =~ /^Pool\sName$/) {
            $element = $prop->{'VALUE'};
        }
        my $name = $prop->{'NAME'};
        my $value = $prop->{'VALUE'};
        if ($name =~ /^State$/ and $value !~ /Ready/) {
            $state = "CRITICAL";
            $output .= "Pool $element state : $value,";
        }
        if ($name =~ /^Percent\sFull$/ and $value > 90 and $state ne "CRITICAL") {
            $state = "WARNING";
            $output .= "Pool $element is $value % full,";
        }
    }
    printStatus($state, $output);
}

sub checkLuns {
    my $cmd = shift;
    my $data = runCmd($cmd);

    my ($luns, $id);
    foreach my $prop (@{$data->{'PARAMVALUE'}->{'VALUE'}->{'PARAMVALUE'}}) {
        my $name = $prop->{'NAME'};
        if ($name =~ /^LOGICAL\sUNIT\sNUMBER/) { $id = $prop->{'VALUE'}; }
        if ($name =~ /^Name$/) { $luns->{$id}->{'name'} = $prop->{'VALUE'}; }
        if ($name =~ /^Current\sOwner/) { $luns->{$id}->{'owner'} = $prop->{'VALUE'}; }
        if ($name =~ /^Default\sOwner/) { $luns->{$id}->{'default'} = $prop->{'VALUE'}; }
        if ($name =~ /^Current\sState/) { $luns->{$id}->{'state'} = $prop->{'VALUE'}; }
        if ($name =~ /^Is\sPrivate/) { $luns->{$id}->{'isprivate'} = $prop->{'VALUE'}; }
    }
    foreach my $id ( sort keys %$luns ) {
        my $name = $luns->{$id}->{'name'};
        my $owner = $luns->{$id}->{'owner'};
        my $default = $luns->{$id}->{'default'};
        my $state = $luns->{$id}->{'state'};
        my $isprivate = $luns->{$id}->{'isprivate'};
        next if $isprivate eq 'Yes';
        if ($state ne "Ready") {
            $state = "CRITICAL";
            $output .= "Lun $name state is $state,";
        }
        if ($owner ne $default and $state ne "CRITICAL") {
            $state = "WARNING";
            $output .= "Lun $name trespassed,";
        }
    }
    printStatus($state, $output);
}

sub checkHotSpare {
    my $cmd = shift;
    my $data = runCmd($cmd);

    my @lines = split /\n/, $data->{'PARAMVALUE'}->{'VALUE'};
    my ($id, $disk_type, $unused);
    foreach my $line (@lines) {
        if ($line =~ /^Policy\sID:\s+(\d+)$/) { $id = $1; }
        if ($line =~ /^Disk\sType:\s+(.*)$/) { $disk_type = $1; }
        if ($line =~ /^Unused\sdisks\sfor\shot\sspares:\s+(\d+)$/) {
            if ($1 eq "0") {
                $state = "CRITICAL";
                $output .= "No more hotspare disks for policy $id ($disk_type),";
            }
        }
    }
    printStatus($state, $output);
}


############
##  MAIN  ##
############

getopts("h:u:p:c:",\%options);
if ( not defined $options{h} or not defined $options{u} or not defined $options{p} ) { Usage; }

$naviseccli .= " -Xml -np -User $options{u} -Password $options{p} -Scope 0 -h $options{h} ";

switch ($options{c}) {
    case "cache"        { checkCache("cache -sp -info -state") }
    case "disks"        { checkDisk("getdisk -state") }
    case "enclosures"   { checkEnclosure("getcrus") }
    case "faults"       { checkFaults("faults -list") }
    case "hotspares"    { checkHotSpare("hotsparepolicy -list") }
    case "luns"         { checkLuns("lun -list -state -owner -default -isPrivate") }
    case "ports"        { checkPort("port -list -sp") }
    case "pools"        { checkStoragePool("storagepool -list -state -prcntFull") }
    else                { Usage }
}
