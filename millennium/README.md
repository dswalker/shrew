![Shrew](http://xerxes.calstate.edu/images/shrew.gif)

Millennium Harvest Script
=========================

The Shrew Millennium harvest program is essentially a telnet emulator.  It connects to your Innovative system using the old Innopac telnet interface, issues commands to export records -- either the entire database or records that have been added, modified, or deleted since a certain date -- and then instructs the Innovative server to FTP the records to another server, where they can be used for a variety of purposes, including indexing by a discovery service.

1. Set-up
------------

### a. Server requirements

Before you get started, look at the [HarvestRequirements server requirements] for running the script.  That page also covers some required set-up on your Innovative system.

### b. Download the code  

You'll want to grab the [http://code.google.com/p/shrew/downloads/list latest version of the code], and extract it to your desktop.  The .zip file includes two directories, `harvest` and `lookup`.  We'll be using the code in `harvest`.  The `harvest` directory includes a test script (`test.pl`), the main Perl module (`lib/InnopacTelnet.pm`), and some directories for the exported MARC records (`data`) and log files (`log`).

### c. Edit test.pl 

You'll need to open `test.pl` with a text editor, and enter some [HarvestConfig configuration values] for the Innovative and FTP servers, as well as a few optional entries that control the behavior of the script.  

### d. Upload the whole harvest directory to your server

However you want to do that.


Running the script
------------

Jump on a command prompt, telnet to your server, and navigate to your uploaded harvest directory.  We're now going to issue some commands to make sure everything is working.  The test script is set to output its actions to the screen, so you can follow its progress. 

### Full export

To run a full export, issue this command:


  perl test.pl --action=full


The script will connect to your Innovative server and use the By Range Export to export all of your bib records.  Eventually, it should download a file called `full.marc` (or several files, if so configured) to the local `data` directory.

### Incremental export

To run an incremental export, issue this command:


  perl test.pl --action=today


The script will connect to your Innovative server and use Create Lists to find records added or modified over the past couple of days.  It will, by default, attempt to use an empty, unassigned review file of (at least) 5,000 records; if that fills up, however, it will use increasingly larger review files until it can get all modified records.  Eventually, the script will download a file called `modified-b.marc` to the `data` directory.

### Expunged records

To find expunged records (that is, records that have been permanently deleted from the system), issue this command:


  perl test.pl --action=expunged


This will use the By Range Export to locate records deleted over the past couple of days (as with the incremental export, the time frame here is configurable). It will eventually create a file called `expunged.txt` in the `data` directory, with the bibliographic IDs of each deleted record on a new line.


3. Cron jobs
------------

Once everything is working to your satisfaction, you can set-up a cron job to automatically run the above commands each day.  At Cal State, we run the *incremental* export every night, and then once a week do a *full* export, just to make sure everything is kosher.


4. Special handling for discovery systems
------------

  * SolrMarc
  * Summon (coming soon)