package InnopacTelnet;

# Export records from an Innvoative Interface ILS using telnet emulation
#
# @author David Walker
# @copyright 2010 California State University
#
# This code is based in part on the work of Alan Crump at Colorado State University
#
# @version $Id: InnopacTelnet.pm 90 2011-02-03 17:38:38Z dwalker@calstate.edu $
# @link http://code.google.com/p/shrew/
# @license http://www.gnu.org/licenses/

use strict;
use Carp;
use Cwd;
use IO::Pty();
use Net::FTP;
use Net::SFTP::Foreign;
use Net::Telnet;


######################
#                    #
#  PUBLIC FUNCTIONS  #
#                    #
######################


#
# Constructor
#
# @param string $hostname = the hostname of the innovative server
# @param string $login = the username to connect with via telnet
# @param string $password = the password to connect with via telnet
# @param $internal_initials = the initials (username) to use inside the system
# @param $internal_password = the password to use inside the system
# @param string $ftp_host = the hostname of the ftp server to which you will send the files
# @param string $ftp_username = the username on the ftp site
# @param string $ftp_password = the password on the ftp site
#

sub new 
{
	my ( $class, $hostname, $login, $password, $internal_initials, $internal_password, 
		$ftp_host, $ftp_username, $ftp_password ) = @_;

	# ensure required params
	
	if ( $hostname eq undef )
	{
		confess("you must specify a host for the innovative server");
	}

	if ( $login eq undef )
	{
		confess("you must specify a telnet username to login to the innovative server");
	}

	if ( $password eq undef )
	{
		confess("you must specify a telnet password to login to the innovative server");
	}

	if ( $internal_initials eq undef )
	{
		confess("you must specify initials (internal username) to use on the innovative server");
	}

	if ( $internal_password eq undef )
	{
		confess("you must specify an internal password to use on the innovative server");
	}

	if ( $ftp_host eq undef )
	{
		confess("you must specify an ftp host to where you will ftp the records");
	}
	
	if ( $ftp_username eq undef )
	{
		confess("you must specify a username for the ftp server");
	}
	
	if ( $ftp_password eq undef )
	{
		confess("you must specify a password for the ftp server");
	}
	
	# make 'em properties
	
	my $self = {
		'hostname' => $hostname,
		'login' => $login,
		'password' => $password,
		'internal_initials' => $internal_initials,
		'internal_password' => $internal_password,
		'ftp_host' => $ftp_host,
		'ftp_username' => $ftp_username,
		'ftp_password' => $ftp_password,
		
		'log_to' => undef, # where to send log messages (screen, file, etc)
		'telnet_log' => undef, # whether we are outputting Net::Telnet logs
		'log_path' => undef, # directory where to stick logs
		'last_bib_record' => 0, # last id for bib records
		'internal_name' => '000automated', # internal name of files on the server
		'ssh' => 0, # whether to use ssh
		'sftp' => 0, # whether to use sftp on download
		'expunged_records' => {}, # list of expunged records 
		'review_file_size' => 0, # the actual size of our review file
		'exceeded' => 0 # whether we've exceeded file size limit
	};
		
	bless($self, $class);

	return $self;
}


#
# Export all bibliographic records (and attached item records) out of the Innovative system
#
# @param string $local_path = (optional) the local path (directory) where to move the file after it's been ftp'd
# @param int $chunks = (optional) will export records in incremental groups, with this number of records per group
#
# @return int = total number of records exported
#

sub exportRecords()
{
	my ( $self, $local_path, $chunks, $no_export ) = @_;
	
	my $start = 1000000; # this is always the first bib record in the database
	my $stop = 0; # boolean, when to stop exporting
	my $total = 0; # records exported per batch export
	my $grand_total = 0; # total number of all records exported
	my $x = 1;  # for export file name	
	my $end = -1; # as long as this is -1 it means the whole database
	my $gone_over = 0; # how many times have we gone over
	
	# we've set to export in batches
	
	if ( $chunks ne undef )
	{
		# remove any non-digits entered in the number
	
		$chunks =~ s/\D//g;
		$end = $start + $chunks;
	}
	
	# keep creating, exporting, and (optionally) downloading records in groupings until we reach the end
	
	while ($stop != 1 )
	{
		my $export_filename = "full.marc";
		
		if ( $chunks ne undef )
		{	
			$export_filename = "full-$x.marc";
		}
		
		eval # let's try it
		{
			# create a marc file
				
			$total = $self->createMarcByRange($start, $end);
			
			# unless we've been told not to export or we didn't get any records . . .
			
			if ( $no_export eq undef && $total > 0)
			{
				# ftp it off the innovative server
						
				$self->ftpFile($export_filename, $total);
					
				# download the file from the (remote) ftp server to here, removing it from the ftp location
				
				if ( $local_path ne undef )
				{
					$self->downloadFile($export_filename, $local_path);
				}
			}
		};
		
		if ( $@ ) # got an error
		{
			# was it for exceeding the file size limit?
			
			if ( $self->{'exceeded'} == 1 ) # yup
			{
				$self->{'exceeded'} == 0; # reset the error
				$gone_over++; # count these occurances
				
				# try a new export, this time with a smaller amount
				
				if ( $gone_over == 5 || $gone_over > 8 ) # we seem to be decreasing frequently, so ...
				{
					$chunks = $chunks - 10000; # decrease for every pass from here on out
				}
				else # just reduce this pass
				{
					if ( $end - $start - 10000 == 0) # wow, way low if we are below 10,000
					{
						$end = $end - 5000;
					}
					else
					{
						$end = $end - 10000;
					}
					
				}
				
				if ( $chunks eq undef || $chunks > 100000 || $gone_over > 10 || $end <= $start)
				{
					# uh oh, either we were asked to (a) do the whole database, or 
					# (b) in large chunks, or (c) have tried to auto-reduce too many time, or 
					# (d) something has gone really, really wrong, so best to just die and 
					# let the user set this to a better amount
					
					confess("Exceeded export file size limit, please set \$chunks to smaller amount than '$chunks'.");
				}
			}
			else  # nope, something else, so choke
			{
				die $@;
			}
			
			$self->log("Exceeded export file size limit, trying again with smaller grouping.\n");
		}
		else
		{
			# this is the end, my friend
			
			if ( $end == -1 || $end >= $self->{'last_bib_record'} )
			{
				$stop = 1;
			}
			
			$grand_total += $total; # add it to the grand total
			
			# increment for next pass through
			
			$x++;
			$start = $end + 1;
			$end = $end + $chunks;
		}
	}
	
	return $grand_total;
}


#
# Export bibliographic records (and attached item records) modified TODAY
#
# Creates two marc files of records, one containing records whose item records have been modified today, 
# the other where the bibliographic record itself has been modified.
#
# @param string $local_path = (optional) the local path (directory) where to move the file after it's been ftp'd
# @param int $bib_only = (optional) set to '1' to export only the bib records
# @param int $min = (optional) minimum size the review file should be, if none exists, defaults to 5000
#
# @return array = total number of records exported, total in item modified export, total in bib modified export)
#

sub exportRecordsModifiedToday()
{
	my ( $self, $local_path, $bib_only, $min ) = @_;
	
	my $grand_total = 0; # total number of all records exported
	my $item_export = 0; # number of records in item modified export
	my $bib_export = 0; # number of records in bib modified export

	# we're actually searching for records modified AFTER yesterday
	
	my @time = localtime( time() - ( 24 * 60 * 60 ) );
	my $day = $time[3];
	my $month = $time[4] + 1;
	my $year = $time[5] + 1900;
	
	# get records whose attached item records have been modified today

	if ( $bib_only eq undef )
	{
		$item_export = $self->exportRecordsModifiedAfter('i', $year, $month, $day, "modified-i.marc", $local_path, undef, $min);
	}
	
	# get records where the bibliographic data has been modified today
	
	$bib_export = $self->exportRecordsModifiedAfter('b', $year, $month, $day, "modified-b.marc", $local_path, undef, $min);
	
	$grand_total = $item_export + $bib_export;
	
	return ($grand_total, $item_export, $bib_export);
}


#
# Export bibliographic records (and attached item records) modified AFTER the supplied date
#
# @param char $type = modified date based on which record? ('i' = item or 'b' = bibliographic)
# @param int $year = year 
# @param int $month = month 
# @param int $day = day of the month
# @param string $export_filename = (optional) the name to call the exported file
# @param string $local_path = (optional) the local path (directory) where to move the file after it's been ftp'd
# @param int $bcode = (optional) limit search to bcode3 type
# @param int $min = (optional) minimum size the review file should be, if none exists, defaults to 5000
#
# @return int = total number of records exported
#

sub exportRecordsModifiedAfter()
{
	my ( $self, $type, $year, $month, $day, $export_filename, $local_path, $bcode, $min ) = @_;
	
	if ( $export_filename eq undef )
	{
		$export_filename = "modified-$type.marc";
	}
	
	my $done = 0;
	my $search_total = 0;
	
	# keep trying this until we have a search that includes all modified records
		
	while ( $done == 0 )
	{
		# search for records modified since this date

		$search_total = $self->searchForRecordsModifiedSince($type, $year, $month, $day, $bcode, $min);
		
		# check to make sure we haven't hit the limit
		
		# we check the property review_file_size since that was the actual
		# size of the review file, which may be bigger than $min 
		
		if ( $search_total < $self->{'review_file_size'} )
		{
			$done = 1; # we're good
		}
		else
		{
			# dang, we hit the limit, so there are actually more modified files
			# than our review file could hold
		
			$min = $self->{'review_file_size'};
		
			$self->log("Found $search_total, need to try again with larger review file.");
			
			# double the limit and try this again
			
			$min = $min * 2;
		}
	}
	
	if ( $search_total > 0 )
	{
		# create a marc file from those search results
			
		my $total = $self->createMarcFromReviewFile();
		
		# ftp it off the innovative server
		
		$self->ftpFile($export_filename, $search_total);
		
		# now download the file from the (remote) ftp server to a local directory 
		
		if ( $local_path ne undef )
		{
			$self->downloadFile($export_filename, $local_path);
		}
	
		return $total;
	}
	else
	{
		return 0;
	}
}

#
# Create a file of bibliographic records expunged (i.e., permanently deleted) from the system
#
# File contains lines composed of the bibliographic ID and the date deleted (separated by a comma).
# Supplying year, month, and day will cause this function to only look for records expunged on or 
# after that date.  You may supply the whole date or only the year or only the year and month.
#
# @param string $local_path = where to create the file (include file name)
# @param int $year = year (optional) year in which the record was deleted
# @param int $month = month (optional) month in which the record was deleted
# @param int $day = day of the month (optional) day in which record was deleted
# @param int $chunks = (optional) will export records in incremental groups, with this number of records per group
#
# @return array = total number of records exported, total in item modified export, total in bib modified export)
#

sub getExpungedRecords()
{
	my ( $self, $local_path, $year, $month, $day, $chunks ) = @_;
	
	$self->log("\n\nChecking for expunged records\n\n");
	
	# date check & normalization
		
	if ( $day ne undef )
	{	
		if ( $year eq undef || $month eq undef )
		{
			confess("you must specify a year and month if you supply a day");
		}
		
		$day = sprintf("%02d", $day);
	}

	if ( $month ne undef )
	{
		if ( $year eq undef )
		{
			confess("you must specify a year if you supply a month");
		}
		
		$month = sprintf("%02d", $month);
	}
	
	if ( $year ne undef )
	{
		if ( length($year) != 4  )
		{
			confess("you must specify a four digit year, you supplied '$year'");
		}
	}
	
	my $date_supplied = $year . $month . $day;
	my $date_length = length($date_supplied);
	
	# do the full database dump, but don't actually export the file(s)
	# we can do this in one pass regardless of file size limits
	
	$self->exportRecords($local_path, $chunks, 0 );
	
	# just need to go back and delete the file after we're done
	
	$self->deleteExportFile();
	
	# now take the records that were listed as 'deleted' during the export
	# and export them to a file

	open FILE, ">$local_path" or confess "could not open $local_path to write expunged records";
	
	my $x = 0;
		
	foreach my $key (keys %{$self->{'expunged_records'}})
	{
		my $date = $self->{'expunged_records'}->{$key};
						
		# but the user supplied a date, so make sure this 
		# record was deleted on or after that one
		
		if ( $date_length  > 0 )
		{
			# to compare, we'll convert the date to just a number (e.g., 20101105)
		
			my $date_check = $date;
			$date_check =~ s/\D//g;
			
			# then reduce it to only the month and/or year if 
			# that was the only date part(s) supplied
		
			my $date_compare = substr($date_check,0,$date_length);
			
			# too old
		
			if (  $date_compare < $date_supplied )
			{
				next;
			}
		}
	
		print FILE "$key\n";
		$x++;
	}
	
	close FILE;
	
	return $x;
}


#
# Download a file from the (remote) FTP server to a local directory, file will be deleted from FTP location
#
# @param string $ftp_file = the name of the file to download
# @param string $local_path = the local directory where the file should be put
#

sub downloadFile()
{
	my ( $self, $ftp_file, $local_path ) = @_;

	$self->log("downloading '$ftp_file' from " . $self->{'ftp_host'} . " . . . ");

	if ( $self->{'sftp'} == 1 )
	{
		my $sftp = Net::SFTP::Foreign->new(
			'host' => $self->{'ftp_host'},
			'user' => $self->{'ftp_username'},
			'password' => $self->{'ftp_password'}
			)
			or confess("cannot connect to ftp server");

		$sftp->get($ftp_file, "$local_path/$ftp_file")
			or confess("file transfer failed: " . $sftp->error);
		
		$sftp->remove($ftp_file)
			or confess("file delete failed: " . $sftp->error);
		
	}
	else
	{	
		my $ftp = Net::FTP->new($self->{'ftp_host'})
			or confess("cannot connect to ftp server");

		$ftp->login($self->{'ftp_username'},$self->{'ftp_password'});
		$ftp->get($ftp_file, "$local_path/$ftp_file");
		$ftp->delete($ftp_file);
		$ftp->quit();
	}
	
	$self->log("done!\n");
}



##############################
#                            #
#  PRIVATE: BASIC FUNCTIONS  #
#                            #
##############################



#
# Initialize the telnet object and connect to the server
#
# @return object = telnet object
#

sub initialize()
{
	my ( $self ) = @_;

	my $prompt = '/. ?$|.?$/i';
	my $ts = "";

	if ( $self->{'ssh'} == 1 )
	{
		## SSH

		# start ssh program

		$self->log("spawning ssh program . . . ");

		my $pty = $self->spawnSSH($self->{'hostname'}, $self->{'login'});

		$self->log("done.\n");

		# create a Net::Telnet object to perform I/O on ssh's tty.

		$ts = new Net::Telnet (
			-fhopen => $pty,
			-prompt => $prompt,
			-telnetmode => 0,
			-cmd_remove_mode => 1,
			-output_record_separator => "\r"
			);

		# generate log files, if told to do so

		if ( $self->{'telnet_log'} == 1 )
		{
			$ts->input_log($self->{'log_path'} . "telnet_input.log");
			$ts->output_log($self->{'log_path'} . "telnet_output.log");
		}

		# connect
		
		$self->log("connecting to " . $self->{'hostname'} . " . . . ");

		# save ssh key if need be

		my $savekey = $ts->waitfor(
			-match => '/RSA key fingerprint/i',
			-errmode => "return"
			);
			
		if ( $savekey != undef )
		{
			$self->log("\n\t need to save key, saving . . . ");
			$ts->print("yes");
		}
		
		# login to remote host

		$ts->waitfor(
			-match => '/password: ?$/i',
			-errmode => "return"
			)
			or confess("problem connecting to host: ", $ts->lastline);

		$ts->print($self->{'password'});

		$ts->waitfor(
			-match => $ts->prompt,
			-errmode => "return"
			)
			or confess("login failed: ", $ts->lastline);
	}
	else
	{
		## TELNET

		$ts = new Net::Telnet();
		$ts->timeout(20);
		$ts->prompt($prompt);

		# generate log files, if told to do so
		
		if ( $self->{'telnet_log'} == 1 )
		{
			$ts->input_log($self->{'log_path'} . "telnet_input.log");
			$ts->output_log($self->{'log_path'} . "telnet_output.log");
		}

		# open telnet session
	
		$self->log("connecting to " . $self->{'hostname'} . " . . . ");
	
		$ts->open($self->{'hostname'});

		# login to remote host
	
		$ts->login(
			Name => $self->{'login'},
			Password => $self->{'password'},
			Prompt => $prompt
			)
			or confess("problem connecting to host: ", $ts->lastline);
	}


	$ts->max_buffer_length(2048000000);
	
	$self->log("done!\n");

	# now check to see if we are being asked to pick a terminal

	my $terminal = $ts->waitfor( 
		Match => "/MAIN MENU/i", 
		Errmode => "return",
		Timeout => 20
		);

	if ( $terminal != 1  )
	{
		$self->log("Looks like we need to choose a terminal. Choosing 'V' VT100 . . . ");

		$ts->put("v");
		$ts->put("y"); # confirm?
		sleep(3);

		$self->log("done!\n");
	}
	
	return $ts;
}


#
# Spawn the ssh process so telnet object can use a secure connection
#
# @return object = pty object
#

sub spawnSSH()
{
	my( $self, $hostname, $login) = @_;
	my( $pid, $pty, $tty, $tty_fd );

	## create a new pseudo terminal.

	$pty = new IO::Pty or confess $!;

        ## execute the program in another process

        unless ($pid = fork) 
	{  
		# child process

		confess "problem spawning program: $!\n" unless defined $pid;

		## disassociate process from existing controlling terminal.

		use POSIX();
		POSIX::setsid or confess "setsid failed: $!";

		## associate process with a new controlling terminal.

		$tty = $pty->slave;
		$pty->make_slave_controlling_terminal();
		$tty_fd = $tty->fileno;
		close $pty;

		## make stdio use the new controlling terminal

		open STDIN, "<&$tty_fd" or confess $!;
		open STDOUT, ">&$tty_fd" or confess $!;
		open STDERR, ">&STDOUT" or confess $!;
		close $tty;

		## execute requested program.

		exec "ssh -l $login $hostname" or confess "problem executing ssl command\n";
        }

        return $pty;
}


#
# Makes a menu selection; checks for the option first and 
# performs any login that may occur
#
# @param object $ts = the telnet object
# @param string $cmd = the letter option to choose
# @param string $message = the option name (or main part thereof) for check
# @param int $force = (optional) go ahead and force the command anyway, sometimes this is necessary
#

sub choose()
{
	my ( $self, $ts, $cmd, $message, $force ) = @_; 

	$self->log("choosing $cmd > $message . . . ");

	if ( $force eq undef )
	{
		# make sure its on the screen before we chose it or else we could be lost
	
		my ($prematch, $match) = $ts->waitfor( Match => "/$cmd > $message/i", Errmode => "return" );

		# didn't find it

		if ( $match eq undef )
		{
			# see if system is using a non-standard menu value
			
			my ($prematch_second, $match_second) = $ts->waitfor( 
				Match => "/[A-Z,0-9]{1} > $message/i", 
				Errmode => "return" );
						
			# nothing at all? time to croak baby!
			
			if ( $match_second eq undef )
			{
				 confess("Couldn't find '$message' on this screen!");
			}
			elsif ( $match_second =~/([A-Z,0-9]{1}) > /i )
			{
				$cmd = $1;
				$self->log("\n looks like it's actually $cmd > $message . . . ");
			}
		}
	}

	$ts->put($cmd);
	$self->log("done!\n");
	$self->checkForPassword($ts);
}


#
# Check if we are being prompted for a password, in which case supply internal credentials
#
# @param object $ts = the telnet object
#

sub checkForPassword()
{
	my ( $self, $ts ) = @_; 

	# check if we are being prompted for a password

	my $password = $ts->waitfor( Match => "/Password required/i", Errmode => "return" );

	if ( $password == 1 )
	{
		# supply credentials
	
		$self->log("We need to login?  Okay, supplying initials . . . ");
	
		$ts->print($self->{'internal_initials'});
		$ts->print($self->{'internal_password'});
		
		sleep(3);
		
		$self->log("done!\n");

		# check to make sure it worked

		my $bad_username = $ts->waitfor( Match => "/You are not in the list/i", Errmode => "return", Timeout => 1 );

		if ( $bad_username == 1 )
		{
			confess("invalid initials for internal credentials");
		}

		my $bad_password = $ts->waitfor( Match => "/Invalid password/i", Errmode => "return", Timeout => 1 );

		if ( $bad_password == 1 )
		{
			confess("invalid password for internal credentials");
		}

		my $not_authorized = $ts->waitfor( Match => "/You are not authorized/i", Errmode => "return", Timeout => 1 );

		if ( $not_authorized == 1 )
		{
			confess("internal user is not authorized to use this function");
		}
	}
}

#
# Log info
#
# @param string $message = message to log
# @param int $stamp = (optional) set to '1' to add a timestamp before the message
#

sub log()
{
	my ( $self, $message, $stamp ) = @_;

	# let's add a timestamp

	if ( $stamp == 1 )
	{
		my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = localtime(time);
		my $timestamp = sprintf( "%4d-%02d-%02d %02d:%02d:%02d\n", $year+1900,$mon+1,$mday,$hour,$min,$sec);

		$message = $timestamp . $message;
	}

	# output it
	
	if ( $self->{'log_to'} eq "screen" )
	{
		print $message;
	}
	elsif ( $self->{'log_to'} eq "file" )
	{
		my $file = $self->{'log_path'} . "action.log" ;
		
		# append message
		
		open FILE, ">>$file" or confess "could not open $file for logging";
		print FILE $message;
		close FILE;
	}
}


#
# Locate and extract the number of a file in a list, either a
# review file or a marc file
#
# @param object $ts = the telnet object
# @param string $file = name of the file
# @param int $ret = (optional) set this to a value to not throw exception if no file found
#
# @return string = number of the file
#

sub findFileInList()
{
	my ( $self, $ts, $file, $ret  ) = @_;

	my $stop = 0; # boolean to stop
	my $x = 0; # so we don't go in endless loop
	my $list_id; # the review file number
	
	# locate our review file
	
	$self->log("locating the file '$file' . . . ");
	
	# innovative now presents us with a list of files, and asked to choose
	# the number of our file; we'll cycle thru the list until we find ours
	
	my $pattern = "([0-9]{1,3}) \> $file";
	
	while ( $stop == 0 && $x < 20)
	{
		my ($prematch, $match) = $ts->waitfor(
			Match => "/$pattern/i", 
			Errmode => "return",
			Timeout => 2
			);
			
		if ( $match =~ m/$pattern/ ) # we got it
		{
			$list_id = $1; # grab just the number
			$stop = 1; # exit loop
		}
		else
		{
			$ts->put("f"); # didn't see it, so move forward in the list
		}
		
		$x++;
	}
	
	# whoops, it ain't here, yo! & we've been told it should be
	
	if ( $list_id eq undef && $ret eq undef )
	{
		confess("could not find '$file' in list");
	}
	
	$self->log("it's number '$list_id'\n");
	
	return $list_id;
}



###########################################
#                                         #
#  PRIVATE: MARC FILE & EXPORT FUNCTIONS  #
#                                         #
###########################################



#
# Commands to 'send' records (that is, dump them into a marc file for export)
#
# @param object $ts = the telnet object
#
# @return int = number of records found
#

sub sendRecordsToMarcFile()
{
	my ( $self, $ts, $chunks ) = @_;

	# start sending records from database into the marc file

	$self->choose($ts, "S", "START sending records");

	# wait for it to finish
		
	my $done = 0;
	my $rec = 0;
	
	while ( $done == 0  )
	{
		my $line = $ts->getline( Errmode => "return",timeout => 20 );
				
		# found a record

		if ( $line =~ m/b[0-9]{7}/i )
		{
			$rec++;		
		}

		# found an expunged record 
		
		if ( $line =~ m/Record (b[0-9]{8,9}) deleted on ([0-9]{2})-([0-9]{2})-([0-9]{4})/i )
		{
			# add them in, but flip the date around
		
			$self->{'expunged_records'}->{$1} = "$4-$3-$2";
		}
		
		if ( $rec % 1000 == 0 )
		{
			$self->log("\t $rec records examined for output\n");	
		}

		# no new line, so we are done
		
		if ( $line eq undef )
		{
			$done = 1;
		}
	}
	
	$self->log("Checking number of records added to file . . . ");
	
	# check to make sure we are really done
	
	$ts->waitfor('/RECORD CONVERSION STATISTICS/i');

	# scrape the number of records exported

	$ts->waitfor('/output records/'); # after this	
	my ($numRecs) = $ts->waitfor('/Number of errors/'); #but before this
	$numRecs =~ m/([0-9]{1,10})/; # get the number
	$numRecs = $1;
	
	$self->log("done!\n");
	
	$self->log("$numRecs records dumped to MARC file!\n");
	
	return $numRecs;
}


#
# Commands to move to the 'Output MARC records to another system using FTP' screen
#
# @param object $ts = the telnet object
#

sub moveToExportScreen()
{
	my ( $self, $ts ) = @_; 
	
	$self->choose($ts, "A", "ADDITIONAL system functions");
	$self->choose($ts, "M", "Read\\/write MARC records");
	$self->choose($ts, "M", "Output MARC records");
	
	$self->log("Checking available space . . . ");
	
	# check to see if there is enough space

	my $size_check = $ts->waitfor( 
		Match => "/your files total more than/i", 
		Errmode => "return",
		Timeout => 5
		);
	
	if ( $size_check == 1 )
	{		
		$self->log("Whoops, Innovative server says there isn't enough export file space.\n");
		$self->{'exceeded'} = 1;
		
		$self->log("Attempting to delete any files we created.\n");
		
		$ts->put(" "); # space to continue
		
		# remove it
		
		$self->removeExportFile($ts);
		
		confess("Innovative server says there isn't sufficient export file space.  " .
			"You may need to delete some files there, and/or set \$chunks to smaller size.");
	}
	
	# check to see if there are too many files

	my $number_check = $ts->waitfor( 
		Match => "/remove files until you have at most/i", 
		Errmode => "return",
		Timeout => 2
		);
		
	if ( $number_check == 1 )
	{
		$self->log("Whoops, Innovative server says there are too many files.\n");
		$self->{'exceeded'} = 1;
		
		$self->log("Attempting to delete any files we created.\n");
		
		$ts->put(" "); # space to continue
		
		# remove it
		
		$self->removeExportFile($ts);
		
		confess("Innovative server says there are too many export files.  " .
			"You may need to delete some files.");
	}
	
	$ts->put(" "); # space to get past any warnings, shouldn't hurt
	
	$self->log("done!\n");
}


#
# Connect to the server and delete our export file, if it exists
#


sub deleteExportFile()
{
	my ( $self ) = @_; 
	
	$self->log("\n\n\nGoing back to server to delete export file.\n\n");

	my $ts = $self->initialize();
	
	eval
	{
		$self->moveToExportScreen($ts);
	};
	
	# if we exceeded the file size limit, we've already deleted the file
	
	if ( $@ ) # got an error
	{	
		if ( $self->{'exceeded'} != 1 ) # these are not the droids you're looking for
		{
			die $@;
		}
	}
	else
	{

		$self->removeExportFile($ts); # remove it
	}
	
	# quit out
	
	$self->log("quitting out . . . ");	
	
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put("x"); # exit
	
	$self->log("done!\n");
	
	$ts->close();
}


#
# Common function for removing the export file when the list is available
#
# @param object $ts = the telnet object
#

sub removeExportFile()
{
	my ( $self, $ts ) = @_;

	# locate our file in the list

	my $file = $self->getInternalFileName("out");
	my $list_id = $self->findFileInList($ts, $file);
	
	if ( $list_id ne undef )
	{
		# remove it
		
		$self->log("Removing file . . . ");
		
		# it's either 'R' or 'X', not likely a problem to try both; 
		# we do it this way, since the option is not always on the screen
		
		$ts->put("x"); 		
		$ts->put("r"); 
		
		$ts->put("$list_id\n"); # choose this number
		$ts->put("y"); # yes to confirm
		
		$self->log("done!\n");
	}
}


#
# Commands to move to the 'CREATE file of MARC records' screen, and prepare file for export
#
# @param object $ts = the telnet object
# @param string $file = name to give the export file
#

sub moveToCreateFileScreen()
{
	my ( $self, $ts, $file ) = @_; 

	$self->choose($ts, "C", "CREATE .* records");

	# give the file a name
	
	$self->log("Telling it to use '$file' . . . ");

	$ts->print($file);
	
	$self->log("done!\n");
	
	# overwrite existing file
	# even if the file doesn't exist, this doesn't hurt
	
	$self->log("choosing 'y', overwite existing file . . ");
	
	$ts->put("y"); 
	
	$self->log("done!\n");

	$self->log("now in program, choosing 'y' again, overwite existing file . . ");
	
	$ts->put("y");
	
	$ts->waitfor('/Choose one/i'); #bottom of menu
	
	$self->log("done!\n");
}


#
# FTP a file off of the Innovative server using FTS (file transfer system)
#
# @param string $remote_file = the new name to give the file on export
# @param int $size = (optional) no. of records in the file, helps set export time
#

sub ftpFile()
{
	my ( $self, $remote_file, $size ) = @_;

	# ensure required params set
	
	if ( $remote_file eq undef )
	{
		confess("you must specify a name for the remote file when exporting marc records");
	}
	
	# use default internal name
	
	my $file = $self->getInternalFileName("out");

	$self->log("\n\n\nExporting file '$file' as '$remote_file'\n\n");
	
	# connect, and move to the export screen
	
	my $ts = $self->initialize();
	$self->moveToExportScreen($ts);
	
	# locate our file in the list
	
	my $list_id = $self->findFileInList($ts, $file);
	
	# select program to send a file out of the system

	$self->choose($ts, "S", "SEND a MARC file to another system using FTS", 1);
	
	# select the file
		
	$ts->waitfor('/Enter file number/i'); # bottom of next menu

	$self->log("choosing file '$list_id' . . . ");
	
	$ts->put($list_id);
	
	$self->log("done!\n");

	# enter ftp host

	$self->log("choosing E > ENTER a host . . . ");

	$ts->put('E');

	$self->log("done!\n");
		
	$self->log("entering '" . $self->{'ftp_host'} . "' . . . ");
	
	$ts->print($self->{'ftp_host'});
	
	$self->log("done!\n");

	sleep(15);

	# check to make sure that worked

	my $host_check = $ts->waitfor( Match => "/Username/i", Errmode => "return" );

	if ( $host_check != 1 )
	{
		confess("couldn't connect to ftp host.");
	}

	# pass in the ftp credentials
	
	$self->log("entering ftp credentials . . . ");
	
	$ts->print($self->{'ftp_username'});
	$ts->print($self->{'ftp_password'});
	
	$self->log("done!\n");

	$ts->waitfor('/Choose one/i'); # bottom of next menu
	
	# select transfer file
	
	$self->choose($ts, "T", "TRANSFER files", 1);
			
	# enter new name for file

	$ts->waitfor('/Enter name of remote file/i'); # top of menu
	
	$self->log("entering '$remote_file' as name of remote file . . . ");

	$ts->print($remote_file);

	$ts->waitfor("/$file/i");
	
	$self->log("done!\n");
	
	# wait for transfer to complete
	
	$self->log("waiting for transfer to complete . . . ");
	
	my $wait = 900; # 15 minutes
	
	# if it's large, we may need to wait longer, 
	# so check it and increase if necessary
	
	if ( $size ne undef )
	{
		my $wait_estimate = int( $size / 660 ); 
		
		if ( $wait_estimate > 900 )
		{
			$wait = $wait_estimate;	
		}
	}
	
	$ts->waitfor(
		Match => "/Choose one/i",
		Timeout => $wait
		);
	
	$self->log("done!\n");
	
	# continue
	
	$self->log("exiting file transfer program . . . ");
	
	$ts->put("c");

	sleep(5);
	
	$self->log("done!\n");

	# quit out
	
	$self->log("quitting out . . . ");	
	
	$ts->put("q"); # quit
	sleep(5);
	$ts->put(" "); # space to continue
	sleep(5);
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	
	$ts->put("x");
	
	$self->log("done!\n");
	
	$ts->close();
}



#####################################
#                                   #
#  PRIVATE: CREATE RANGE FUNCTIONS  #
#                                   #
#####################################



#
# Generate a MARC file on the Innovative server by range of record numbers
#
# @param string $start = (optional) the starting record number ( do not include check digit ; 
#   if left blank, will use the start record in the database)
# @param string $end = (optional) the end record number (do not include check digit ; 
#   if left blank, will use the end record in the database)
# @param string $file = (optional) name to give the MARC file (will use default 'internal' name if left blank)
#
# @return int = number of records sent to marc file
#

sub createMarcByRange()
{
	my ( $self, $start, $end,  $file ) = @_;
	
	# use default internal name if not defined
	
	if ( $file eq undef )
	{
		$file = $self->getInternalFileName("out");
	}
	
	$self->log("\n\n\nCreating file by range ");
	
	if ( $end > 0 )
	{
		 $self->log("($start - $end)");
	}
	else
	{
		$self->log("(the whole database)");
	}
	
	$self->log("\n\n");
	
	# connect, move to export screen, and then to create file screen
	
	my $ts = $self->initialize();
	$self->moveToExportScreen($ts);
	$self->moveToCreateFileScreen($ts, $file);
	
	# create file from a range of records

	$self->choose($ts, "R", "from a RANGE of records", 1);
	
	# get last bib record no. in database if not set already
	
	if ( $self->{'last_bib_record'} == 0 )
	{
		$self->log("determining last bib record in database . . . ");
	
		$ts->waitfor('/Specify records to be output/');
		
		# find range of records specified bibliographic
		
		$ts->waitfor('/BIBLIOGRAPHIC/');
		my ($range) = $ts -> waitfor('/ORDER/'); 
		
		# get y from the phrase "x to y"
		
		my $to = index($range, 'to') + 3;
		$self->{'last_bib_record'} = substr($range,$to,7);  # chop off check digit		
		
		$self->log($self->{'last_bib_record'} . "!\n");
	}
	
	# no explicit end set, so make the end the last record
	
	if ( $end == -1 )
	{
		$end = $self->{'last_bib_record'};
	}
	
	# starting with record no.
	
	# iii records have a check digit at the end, but we always use 'a' instead, 
	# telling the system that we don't know what the check digit is.
	
	if ( $start ne "" )
	{
		$start = substr($start,0,7) . "a";
	}
	
	$self->log("Enter starting record #: $start . . . ");
	
	$ts->print($start);

	$self->log("done!\n");
	
	# make sure we aren't asking for more than is in the database
	
	if ( $end > $self->{'last_bib_record'} )
	{
		$self->log("We've reached the end of the database!\n");
		
		$end = $self->{'last_bib_record'};
	}

	# ending with record no.

	if ( $end ne "" )
	{
		$end = substr($end,0,7) . "a";
	}

	$self->log("Enter ending record # $end . . . ");
		
	$ts->print($end);

	$self->log("done!\n");
	
	# confirm scope (doesn't always ask this, but doesn't hurt to hit 'y' anyway

	$self->log("choosing 'y', in case asked confirm scope . . . ");	

	$ts->put("y");
	
	$self->log("done!\n");


	# confirm range
	
	$self->log("choosing 'y', yes this range is correct . . . ");	

	$ts->put("y");
	
	$self->log("done!\n");

	sleep(5);
	
	# give the send function a range so it can properly set the
	# (potentially long) time
	
	my $range = $end - $start;
	
	# dump the results to a marc file
	
	my $numRecs = $self->sendRecordsToMarcFile($ts,$range);	
	
	# quit out
	
	$self->log("quitting out . . . ");
	
	$ts->put("q"); # quit
	$ts->put(" "); # space to continue
	$ts->put("q"); # quit
	$ts->put(" "); # space to continue
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put("q"); # quit

	$ts->put("x");

	$self->log("done!\n");

	$ts->close();
	
	return $numRecs;
}



####################################
#                                  #
#  PRIVATE: CREATE LIST FUNCTIONS  #
#                                  #
####################################



#
# Run a search for records updated AFTER the supplied date
#
# @param char $type = record type ('i' = item or 'b' = bibliographic)
# @param int $year = year 
# @param int $month = month 
# @param int $day = day of the month
# @param int $bcode = (optional) limit search to bcode3 type
# @param int $min = (optional) minimum size the review file should be, if none exists, defaults to 5000
#

sub searchForRecordsModifiedSince()
{
	my ( $self, $type, $year, $month, $day, $bcode, $min ) = @_;
	
	# ensure required params
	
	if ( $type eq undef )
	{
		confess("you must specify the record type: 'i' (item) or 'b' (bibliographic)");
	}
	
	if ( $year eq undef || length($year) != 4 )
	{
		confess("you must specify a four digit year when searching for modified records, you supplied '$year'");
	}

	if ( $month eq undef )
	{
		confess("you must specify a month when searching for modified records");
	}

	if ( $day eq undef )
	{
		confess("you must specify a day when searching for modified records");
	}

	# this just for clarity in the logs

	my $type_display = "bibliographic";
	
	if ( $type eq 'i' )
	{
		$type_display = "item";
	}	
	
	# let's get it started!
	
	$self->log("\n\n\nSearching for $type_display records modified since $year-$month-$day\n\n");

	# connect
	
	my $ts = $self->initialize();
	
	# go to create lists and prepare our review file
	
	$self->prepareReviewFile($ts, $min);
	
	# type of records

	if ( $type eq 'i')
	{
		$self->choose($ts, "I", "ITEM list");

		# select field to search on: 'updated'
		
		$self->log("entering search: \n");
		$self->log("  find item records where 'updated' field is ");
	
		$ts->put("29");	
	}
	elsif ( $type eq 'b')
	{

		$self->choose($ts, "B", "BIBLIOGRAPHIC list");
	
		# select field to search on: 'updated'
		
		$self->log("entering search: \n");
		$self->log("  find bib records where 'updated' field is ");
	
		$ts->put("11");
	}
	
	sleep(2);
	
	# greater than
	
	$self->log(" > ");
	$ts->put(">");
	sleep(1);
	
	# format the date for input

	my $check_pattern = $ts->get();
	
	# is this asking for four year pattern?
	
	if ( $check_pattern !~ m/mo-dy-year/ )
	{
		# nope, so just enter the last two digits of the year
		
		$year = substr($year,-2); 
	}
	
	$day = sprintf("%02d", $day); # day, padded with 0
	$month = sprintf("%02d", $month); # month, padded with 0
	
	$self->log(" '$month-$day-$year' . . . ");
	
	$ts->put($month);
	$ts->put($day);
	$ts->put($year);
			
	if ( $bcode ne undef )
	{
		$self->log("\n AND ");
		$ts->put("a");

		$self->log("bcode 3 = $bcode . . . ");
		
		$ts->put("07");
		$ts->put("=");
		$ts->put($bcode);
	}

	$self->log("done!\n");
	
	my $numRecs = $self->submitSearch($ts);
	
	# quit out
	
	$self->log("quitting out  . . . ");
	
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	sleep(1);
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	
	$ts->put("x");
	
	$self->log("done!\n");
	
	$ts->close();
	
	return $numRecs;
}


#
# Generate a MARC file on the Innovative server from a review file (results of a Create Lists query)
#
# @param string $file = (optional) name to give the MARC file (will use default 'internal' name if left blank)
#
# @return int = number of records sent to marc file
#

sub createMarcFromReviewFile()
{
	my ( $self, $file ) = @_;

	# use default internal name if not defined
	
	if ( $file eq undef )
	{
		$file = $self->getInternalFileName();
	}
	
	$self->log("\n\n\nCreating marc file from review file '$file'\n\n");
	
	# connect, move to export screen, move to create file screen
	
	my $ts = $self->initialize();
	$self->moveToExportScreen($ts);
	$self->moveToCreateFileScreen($ts, $file);
	
	# create file from review file

	$self->choose($ts, "B", "from a BOOLEAN review file");
	
	my $list_id = $self->findFileInList($ts, $file);
	
	# now tell it to use that review file
	
	$self->log("Choosing review file '$list_id' . . . ");
	
	$ts->put($list_id);
	
	$self->log("done!\n");
	
	# dump the results to a marc file
	
	my $numRecs = $self->sendRecordsToMarcFile($ts);

	# quit out
	
	$self->log("quitting out . . . ");
		
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put(" "); # space to continue
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put("q"); # quit
	$ts->put("q"); # quit

	$ts->put("x");

	$self->log("done!\n");

	$ts->close();
	
	return $numRecs;
}


#
# Locate an empty review file (that meets the supplied size criteria)
#
# @param object $ts = the telnet object
# @param int $min = (optional) minimum size the review file should be, defaults to 5000
#
# @return string = number of the review file
#

sub findEmptyReviewFile()
{
	my ( $self, $ts, $min ) = @_;
	
	# set default
	
	if ( $min eq undef )
	{
		$min = 5000;
	}
	
	my $stop = 0; # boolean to stop
	my $x = 0; # so we don't go in endless loop
	my $list_chosen; # the chosen review file number
		
	$self->log("locating an empty review file with at least $min records . . . ");
	
	# we'll cycle thru the list until we find an empty one that meets 
	# our size criteria
	
	my $pattern = "([0-9]{2,3}) \> Empty";
	my %empty_files = ();
	
	while ( $stop == 0 && $x < 30)
	{
		my ($prematch, $match) = $ts->waitfor(
			Match => "/$pattern/i", 
			Errmode => "return",
			Timeout => 2
			);
			
		if ( $match =~ m/$pattern/ ) # we got one
		{			
			my $list_id = $1; # grab the file id
			
			# find size
			
			my ($prematch_size, $size) = $ts->waitfor(
				Match => "/[0-9]{1,3}000/i", 
				Errmode => "return",
				Timeout => 2
				);

			# see if it's of a sufficient size
			
			if ( $size >= $min ) # yup
			{
				$empty_files{$list_id} = $size;
			}
		}
		elsif ( $match eq undef ) # didn't find any on this screen
		{
			$ts->put("f"); # so move forward in the list
		}
		
		$x++;
	}
	
	# put them in ascending order by size, so we try the smaller ones first
	
	foreach my $review_file ( sort { $empty_files{$a} <=> $empty_files{$b} } keys %empty_files )
	{
		# now take the first one that isn't locked
		
		$ts->put($review_file); # enter it
		
		# see if we can create a new file with it
		
		if ( $ts->waitfor(
			Match => "/Create a new file/i", 
			Errmode => "return",
			Timeout => 2
			) )
		{
			# yup, so use this one
			
			$list_chosen = $review_file;
			
			# register the size
			
			$self->{'review_file_size'} = $empty_files{$review_file};
			
			$ts->put("q"); # back out as well
			last; # this is like break
		}
		else
		{
			# nope, but back out so we can 
			# try the next one
			$ts->put("q"); 
		}
	}
	
	# found none, yike
	
	if ( $list_chosen eq undef )
	{
		confess("could not find an empty review file with at least $min records"); 
	}
	
	$self->log("found one, number '$list_chosen', with size of " . $self->{'review_file_size'} . "\n");
		
	return $list_chosen;
}


#
# Move to create lists, locate our review file (or create a new one) and prepare it for searching
#
# @param object $ts = the telnet object
# @param int $min = (optional) minimum size the review file should be, defaults to 5000
#

sub prepareReviewFile()
{
	my ( $self, $ts, $min ) = @_; 

	my $list_id; # id for the review file
	
	$self->choose($ts, "M", "MANAGEMENT information");
	$self->choose($ts, "L", "Create LISTS of records");
	
	$self->log("Clearing any previously used review files.\n");
	
	# see if we already have a previous review file
	
	$list_id = $self->findFileInList($ts, $self->getInternalFileName(), 1 );
	
	# yes we do, so blank it
	
	if ( $list_id ne undef )
	{
		# we found our previous one, so choose that
		
		$self->log("choosing review file '$list_id' . . . ");
		
		$ts->put($list_id);
		
		$self->log("done!\n");
		
		# empty it

		$self->choose($ts, "E", "EMPTY");
	
		# yes, really do empty the review file
		
		$self->log("confirming, yes, empty the file . . . ");
		
		$ts->put("y");
		
		$self->log("done!\n");
		
		# back to list
		
		$self->choose($ts, "Q", "Quit");
	}
	else
	{
		$self->log("couldn't find it.\n");
	}
		
	# back-up
	
	$self->log("Exiting Create Lists and re-entering again.\n");

	$self->choose($ts, "Q", "Quit");		
	$self->choose($ts, "L", "Create LISTS of records");
	
	# look for an empty one
	
	$list_id = $self->findEmptyReviewFile($ts, $min);
	
	# choose that one
	
	$self->log("choosing review file '$list_id' . . . ");
	
	$ts->put($list_id);
	
	$self->log("done!\n");

	# create a new file 
	
	$self->choose($ts, "2", "Create a new file");
}


#
# Submit a search to create lists and return number of records found
#
# @param object $ts = the telnet object
#
# @return int = number of records found
#

sub submitSearch()
{
	my ( $self, $ts ) = @_; 
	
	my $review_file = $self->getInternalFileName();
	
	# start the search

	$self->log("choosing 'S' to start the search . . . ");
	
	$ts->put("s");
		
	$self->log("done!\n");
		
	# give it the same name
	
	$self->log("giving review file name '$review_file' . . . ");
	
	$ts->print($review_file);
	
	$self->log("done!\n");
	
	# now wait for it to report it's done
	
	$self->log("waiting for search to finish . . . ");
	
	my $done = 0;
	my $x = 0;
	my $minutes = 120; # 2 hours, needs to be this long for some of the bigger, slower systems
	
	while ( $done != 1 && $x < $minutes ) 
	{
		$done = $ts->waitfor(Match => '/BOOLEAN SEARCH COMPLETE/', Timeout => 60, Errmode => "return");
		$ts->buffer_empty; # clear the buffer to make this more efficient		
		$x++;
	}
	
	# nada
	
	if ( $done == 0 )
	{
		confess("timed out waiting for search to finish after $minutes minutes");
	}
	
	$self->log("done!\n");
	
	# exit search screen
	
	$self->log("exiting search . . . ");
	
	$ts->put(" "); # space to continue

	$self->log("done!\n");
	
	# scrape the number of records found
	
	# (easier to grab it on this screen, after exiting the search, then on the
	# previous one, even though that was the results screen )
	
	$ts->waitfor('/has/'); # after this
	my ($numRecs) = $ts->waitfor('/records/'); # and before this	
	$numRecs =~ s/ //g; # strip out spaces
	
	$self->log("$numRecs found!\n");
	
	return $numRecs;
}



##################
#                #
#   PROPERTIES   #
#                #
##################



#
# The name used for marc (out) file and review file on the Innovative system
#
# @param string $suffix = add a file extension (e.g., '.out') to the file
#

sub getInternalFileName()
{
	my ( $self, $suffix ) = @_;
	
	my $name = $self->{'internal_name'};
	
	if ( $suffix ne undef )
	{
		$suffix =~ s/\.//g; # remove any periods
		$name .= ".$suffix";
	}
	
	return $name;
}

#
# Change the name used for marc and review files on the Innovative system
#
# @param string $name = the new name
#

sub setInternalFileName()
{
	my ( $self, $name ) = @_;
	$self->{'internal_name'} = $name;
}


#
# Put log files here
#
# @param string $path = path to where to stick the log file
#

sub setLogDirectory()
{
	my ( $self, $path ) = @_;
	
	if ( $path eq undef )
	{
		$path = getcwd; # use current working directory
	}
	
	# make sure the path exists, yo
	
	if (! -d $path)
	{
		confess("'$path' does not exist on the file system, please create it first before setting log directory");
	}
	
	# make sure we've got a trailing slash on this thing
	
	if ( substr($path, -1) ne "/" )
	{
		$path .= "/";
	}
	
	$self->{'log_path'} = $path;
}


#
# Where to put logging info
#
# @param string $location = valid values include 'screen' or 'file'
#

sub logTo()
{
	my ( $self, $location ) = @_;
	
	$self->{'log_to'} = $location;
}


#
# Whether to write out Net::Telnet input/output logs
#
# @param boolean $true = set to 1 to turn on, anything else to turn off
#

sub logTelnet()
{
	my ( $self, $true ) = @_;
	
	$self->{'telnet_log'} = $true;
}


#
# Use SSH when connecting to the Innovative system
#

sub useSSH()
{
	my ( $self ) = @_;
	$self->{'ssh'} = 1;
}


#
# Use SFTP when downloading the file
#

sub useSFTP()
{
	my ( $self ) = @_;
	$self->{'sftp'} = 1;
}



1;