# SnapRAID Made Simple
Batch script to simplify maintenance and daily notification of SnapRAID for Windows 10 and adjacent versions. It is being placed here in the hopes that it will be useful to others. This implementation is intended to harden against drive failures. 

The original script was written by Quaraxkad and was found on Source Forge: https://sourceforge.net/p/snapraid/discussion/1677233/thread/c7ec47b8/

Since finding it in 2017 I have modified it quite a bit and added more features.

I personally pair SnapRAID with DrivePool in order to seemlessly use a single protected drive day-to-day. This is not necessary to leverage this script, however.

## Preconditions:
- Install SnapRAID and configure it for your setup

## Installation/Usage:
- Add the following files to your SnapRAID folder: 
  - snapraid_simple.bat, 
  - mailsend.exe, 
  - rxrepl.exe, 
  - MailFooter.txt, 
  - MailHeader.txt, 
  - date.exe (optional), and 
  - findstr.exe (optional)
- (optional) Create a CritialServicesStop.bat file
- Create a folder titled "log" in your SnapRAID folder
- Open Task Scheduler, and Add new task in Task Scheduler to run "snapraid_simple.bat" daily at a convenient time for you
- Modify snapraid_simple.bat and set the Config: parameters to your liking

## Setting the Config parameters:
- emailto - email name to appear in to line
- emailfrom - email name to appear in to line
- mailuser - email account username
- mailpass - email account password (or pass phrase)
- srpath - path to SnapRAID folder (e.g. C:\Snapraid)
- delthresh - delete threshold (default 1000 files); exceed this number to stop with error
- errthresh - error threshold (default 10 errors); exceed this number to stop with error

_Note: When setting the parameters above there shall be no quote marks or spaces, and shall immediately follow an = sign separating the parameter title; e.g. an email to none@yo.biz would appear as emailto=none@yo.biz_

_Note 2: Gmail requires an "App Password" in order to send emails, and the username does not require "@gmail.com" at the end. Google "Gmail App Password" to learn more about setting this up for a Google account._

## Intended/Standard Behavior:
This script is designed to run daily by task scheduler. It is best to run this during a low access time period. Mine runs at 3AM daily.

- If files are changed during the process SnapRAID will report that the Sync is incomplete/at 99%. This is not a practical problem as future syncs will capture any files that were modified/missed.
- It will perform a number of checks and SnapRAID maintenance, then provide an email with the results. 
- If an error is found, it will attempt to repair and send those results via email. Note: fix calls are always simulated first.
- If a disk error is found, a batch file will be run to disable services (if desired). This is intended to minimize changes to remaining disks to improve recoverability/preserve data integrity until you can run a fix.
- If the number of deleted files exeeds the user specified threshold, it will stop and provide an email update. 
- If the number of errors exeeds the user specified threshold, it will stop and provide an email update. 
- If SnapRAID is already running when the script starts, it will cancel and email.

Logs will be created at each step and saved in a /log/ folder. These logs will be stripped of unneeded lines to minimize file size and ease of navigation later.

## Standard Maintenace Steps:
These are the steps in order that are performed when running the script.
1) Check if SnapRAID is running
2) Run Diff
3) Check for Deleted files threshold
4) Run Sync
5) Run Scrub of new files
6) Run Scrub of oldest 3% (~1 month full cycle time)
7) Run Touch to correct zeroed timestamps
8) Run Status
9) Check if Fix Needed
10) Mail results

## Command Line Arguments
There are 3 command line arguments which may be helpful.
```
snapraid_simple.bat skipdel
```
This skips the deleted file threshold check, which is handy if you deleted an old Windows 95 game with a lot of individual assets.

```
snapraid_simple.bat skipdiff
```
This skips the Diff check, meaning it will not look for signs that files have been changed before scrubbing. If a file has been intentionally modified, this option may give you an error.

```
snapraid_simple.bat skipscrub
```
This skips the scrubbing routines.

## Summary Emails:
The email subject will summarize the number of errors/warnings/files (as applicable). E.g.

> SnapRAID Status GOOD (sync:0)(scrub1:0)(scrub2:0)(status:0)(warn:0)(danger:0) (REM:22)(ADD:30)(T:24)
- Summary email will be html formatted with a fixed-width font
- Message begins with SnapRAID Status
- Disk Smart Data will follow

A sample email can be found in the [file MailMessage.log](MailMessage.log).

## Additional Notes:
- The amount that is scrubbed is currently set to 3% per day. This could be modified by changing "-p 3" argument under the :RunScrubO section. I may modify this to be a user parameter in the future.
- MailMessage.log has been provided as an example of what will be sent daily.

## Handy Commands:
Aside from the SnapRAID made simple script, you may need to run a recovery of files/folders/disks. Here are a few handy commands I have had to use in the past. 

_You may notice that sometimes logs are created using the SnapRAID built-in function, and sometimes using console piping. If I recall correctly, sometimes the SnapRAID log function leaves out certain message types, while piping with redirection (adding the "2>&1" on the end) will capture all messages that would be displayed in the terminal/console._

* Disk has failed, and a replacement disk has been inserted in its place (lets call it drive D: known as d1 within SnapRAID). We will write a log to see what is and is not recoverable. This will take a long time, so hang on, and review the .log when done for "unrecoverable" issues. This data may be gone forever :( As an aside, recovering all the data is often the easiest option (if possible/practicable for you) as you do not have to verify data is correct after copying what is accessible from the failed drive.
```
snapraid -d d1 -l fixYYYYMMDD.log fix
```

* Retiring old disk and inserting a new disk (lets call them O:\ for old and N:\ for new). 
  - Step 1. copy all of your data to the new disk. Lets use Windows's built-in Robocopy program.
```
robocopy /e /xc /xn /xo O:\ N:\
```

- - Step 2. we need to sync the drives to be correct. You need to modify your snapraid.conf file to remove the old drive O:\ and replace it with N:\. After this we will sync SnapRAID and force it to ignore the drive serial numbers. This step can also be useful when getting the cluster back to functioning after a drive failure. We will pipe the screen to a log file to capture what happens. At this point any file errors present (if any) will become what we see as "good" data.
```
snapraid --force-uuid --force-empty --force-full sync > "buildArray_YYYYMMDD.log" 2>&1
```

* Need to move a disk drive from one number to another within SnapRAID/snapraid.conf. E.g. we need to move d7 to be d8.
  - Step 1. modify your snapraid.conf to reflect the change. We will pipe this to a log file as well.
```
snapraid diff -E -U -v > "diff_YYYYMMDD.log" 2>&1
```

* Bad blocks were found, and need to be manually fixed before moving data to a new drive
  - Step 1. blocks have already been identified during a previous scrub. Let's simulate a fix first.
```
snapraid check -e -l "fixTest_YYYYMMDD.log" 
```

- - Step 2. after reviewing the log and you're satisfied with what can be fixed, let's fix the data. Note: bad physical blocks on the disk should be handled already so you don't have to worry about the known physical bad parts. But, physical errors are like a landslide, and once you see a few pebbles/errors, more are likely to follow quickly. I recommend moving the data as swiftly as possible if more than 1 or 2 errors on the disk. We will pipe this one to a log file.
```
snapraid -e fix > "fix_YYYYMMDD.log" 2>&1
```

## Creating a CritialServicesStop.bat:
_This step is optional. Anything can be performed in this batch, but it must complete in order to continue the script._

In Windows 10 (and prior versions) services may be started and stopped by using the net command.
E.g. "net stop Apache" would stop a service named Apache, and "net start Apache" starts it.

If you wish any services to stop upon a disk error (such as services which would alter data on a protected drive), then create a batch file titled "CriticalServicesStop.bat" and save it in your SnapRAID folder, along with the other files.

## Tips on data integrity:
If your cluster has relatively low value files that are easily replicated, or would be automatically, consider using the "exclude" feature with wildcards within SnapRAID. This can be used to exclude files by type with entire trees, such as _"EXCLUDE \VirtualBox\\*.log"_. Log files and metadata files fall heavily into this low-value category. Other data which is more critical may be unrecoverable because an hourly job updated hundreds of logs or metadata/.nfo files that really don't matter. 

## Binary Depencencies (you need these):
These are programs that are referenced in the batch to perform certain functions. The first two have been posted here for convenience, however feel free to get them from the developers' sites.
### rxrepl.exe
https://sites.google.com/site/regexreplace/
- used to strip log files of unneeded lines/rows

### mailsend.exe
https://github.com/muquit/mailsend
- used to send status emails to you; tested with v1.19

### date.exe
(included with Microsoft Windows; I have a copy added to the SnapRAID folder along with the script)
- used to find date/time regardless of current region

### findstr.exe
(included with Microsoft Windows; I have a copy added to the SnapRAID folder along with the script)
- used to find/count errors and warnings within log files

## Copyright notice:
All software referenced here are property of their respective owners. Any copies posed here are for convenience purposes, and no warranties are expressed or implied...


