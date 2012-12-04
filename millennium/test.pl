#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;

use lib 'lib';
use InnopacTelnet;

###############
#   CONFIG    #
###############

# catalog

my $host = "opac.example.edu"; # host name of the innovative system
my $login = ""; # username to login to the system via telnet
my $password = ""; # password for that user
my $internal_initials = ""; # once inside the system, the initials to use
my $internal_password = ""; # password for those initials

# ftp server

my $ftp_host = "ftp.example.edu"; # ftp server you are going to use
my $ftp_username = ""; # username
my $ftp_password = ""; # password

# additional options

my $chunks = undef; # number of records to export per batch (e.g., 50,000) in the full or expunged export
my $expunged_chunks = undef; # the same as above, but specifically for the expunged action; not ususally needed
my $days = 2; # number of days to go back for modified or expunged records


# ssh and sftp

my $use_ssh = 1; # set this to 0 to use plain, old telnet, rather ssh when connecting to the innovative system
my $use_sftp = 0; # set this to 1 to use secure ftp (sftp) when downloading the file from 
                  # the ftp server to the location of this script






###############
#   ACTIONS   #
###############

# set it up

my $catalog = new InnopacTelnet(
	$host, $login, $password, 
	$internal_initials, $internal_password, 
	$ftp_host, $ftp_username, $ftp_password
	);

$catalog->setLogDirectory("log");
$catalog->logTo("screen");
$catalog->logTelnet(1);

if ( $use_ssh == 1 )
{
	$catalog->useSSH();
}

if ( $use_sftp == 1 )
{
	$catalog->useSFTP();
}

# command line tells us which action to perform

my $action = "";
GetOptions ('action=s' => \$action);

# date

my @time = localtime( time() - ( $days * 24 * 60 * 60 ) ); # how many days ago
my $day = $time[3];
my $month = $time[4] + 1;
my $year = $time[5] + 1900;

# let's do it!

if ( $action eq "full" )
{
	# get all records
	
	$catalog->exportRecords("data/", $chunks);

}
elsif ( $action eq "today" )
{
	# get bib records modified after this day
	
	$catalog->exportRecordsModifiedAfter('b', $year, $month, $day, undef, "data/");
}
elsif ( $action eq "expunged" )
{
	# get expunged records
	
	$catalog->getExpungedRecords("data/expunged.txt", $year, $month, $day, $expunged_chunks);
}
else
{
	print "supply paramater: --action=full or --action=today or --action=expunged";
}	
