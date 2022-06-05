@ECHO off

REM Pulled from https://sourceforge.net/p/snapraid/discussion/1677233/thread/c7ec47b8/
REM and heavily modified to add functionality

REM Changelog
REM 2017.09.17 Added function to check if disk has failed, modify email, and stop critical services by running "CriticalServicesStop.bat"
REM 2017.07.03 Added html header/footer, and monospace/Courier New as font; added common MAILSEND function
REM previous Added auto fix function when errors found less than threshold; added auto run for "Touch" function


:Config
REM If password has a &, escape it with ^. So pass&word = pass^&word.
SET emailto=someuser@gmail.com
SET emailfrom=someuser@gmail.com
SET mailuser=someuser
SET mailpass=somePasswordOrAppPass
SET srpath=C:\Snapraid_11.0
SET delthresh=1000
SET errthresh=10

CHCP 65001 > nul

REM Set date regardless of region settings
SETLOCAL EnableDelayedExpansion
for /f "tokens=*" %%i in ('date.exe +"%%Y-%%m-%%d"') do set nDate=%%i

REM alternate date method:
REM FOR /f %%a IN ('wmic path win32_localtime get /format:list ^| findstr "="') DO (set %%a)
REM SET "formattedMonth=0%month%"
REM SET "formattedDay=0%day%"
REM SET nDate=%year%-!formattedMonth:~-2!-!formattedDay:~-2!

REM Default/initial parameters
SET fixhasrun="FALSE"
SET syncresult=0
SET scrubnresult=0
SET scruboresult=0
SET statusresult=0
SET statuswarn=0
SET statusdanger=0
SET diskfatal=0
SET fixerrors=0

SET param=%~1
IF NOT "%param%"=="" (
 IF "%param%"=="skipdel" (
  ECHO Skipping deleted file threshold check...
 ) ELSE IF "%param%"=="skipdiff" (
  ECHO Skipping diff check...
 ) ELSE IF "%param%"=="skipscrub" (
  ECHO Skipping scrub routine...
 ) ELSE (
  ECHO.
  ECHO skipdel = skips deleted files threshold check.
  ECHO skipdiff = skips diff check ^(and delete threshold^).
  ECHO skipscrub = skips scrub routine^(s^).
  EXIT /b
 )
)


:CheckRunning
MD %srpath%\log\
tasklist /FI "IMAGENAME eq snapraid.exe" 2>NUL | find /I /N "snapraid.exe">NUL
IF NOT "%ERRORLEVEL%"=="0" goto RunDiff
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
ECHO Can not run task because snapraid.exe instance exists
ECHO Can not run task because snapraid.exe instance exists > "%srpath%\log\%atimestamp%_sync.log" 2>&1
mailsend -smtp "smtp.gmail.com" -starttls -port 587 -auth -t "%emailto%" +cc +bc -f "%emailfrom%" -sub "SnapRAID Already Running at Triggered Time" -M "empty" -user "%mailuser%" -pass "%mailpass%"
EXIT /B 555

:RunDiff
IF "%param%"=="skipdiff" GOTO RunSync
ECHO Running diff check
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid diff -v > "%srpath%\log\%atimestamp%_diff.log" 2>&1
REM Save tail 9 rows to temp file (large files may not be parsed correctly by rxrepl
FOR /f %%i in ('find /v /c "" ^< "%srpath%\log\%atimestamp%_diff.log"') DO SET /a lines=%%i
SET /a startLine=%lines% - 9
more /e +%startLine% "%srpath%\log\%atimestamp%_diff.log" > "%srpath%\temp.txt"
REM Pull added/rem from temp.txt
rxrepl -f "%srpath%\temp.txt" -o "%srpath%\removed.cnt" --no-backup --no-bom -i -s ".*?(\d+) removed\r\n.*" -r "\1"
rxrepl -f "%srpath%\temp.txt" -o "%srpath%\added.cnt" --no-backup --no-bom -i -s ".*?(\d+) added\r\n.*" -r "\1"
SET /p intrem=<"%srpath%\removed.cnt"
SET /p intadd=<"%srpath%\added.cnt"
DEL "%srpath%\temp.txt"
DEL "%srpath%\removed.cnt"
DEL "%srpath%\added.cnt"
REM Trim log file
rxrepl -f "%srpath%\log\%atimestamp%_diff.log" -a --no-backup --no-bom -i -s "Excluding file '.*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_diff.log" -a --no-backup --no-bom -i -s "WARNING! Ignoring special '.*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_diff.log" -a --no-backup --no-bom -i -s "WARNING! Ignoring special 'system-directory' file .*?\r\n" -r ""

:CheckRemoved
IF "%param%"=="skipdel" GOTO RunSync
IF %intrem% GTR %delthresh% (
mailsend -smtp "smtp.gmail.com" -starttls -port 587 -auth -t "%emailto%" +cc +bc -f "%emailfrom%" -sub "SnapRAID not running: %intrem% files removed." -M "%atimestamp%. %intrem% removed. %intadd% added." -user "%mailuser%" -pass "%mailpass%"
EXIT /B 999
)

:RunSync
ECHO Running sync
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid sync -v --test-io-cache=32 > "%srpath%\log\%atimestamp%_sync.log" 2>&1
SET syncresult=%ERRORLEVEL%
rxrepl -f "%srpath%\log\%atimestamp%_sync.log" -a --no-backup --no-bom -i -s "\d+\%%,\s+\d+\sMB.*?\r\n" -r ""
REM Trim log file
rxrepl -f "%srpath%\log\%atimestamp%_sync.log" -a --no-backup --no-bom -i -s "Excluding file '.*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_sync.log" -a --no-backup --no-bom -i -s "WARNING! Ignoring special '.*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_sync.log" -a --no-backup --no-bom -i -s "Saving state .*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_sync.log" -a --no-backup --no-bom -i -s "Verifying .*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_diff.log" -a --no-backup --no-bom -i -s "WARNING! Ignoring special 'system-directory' file .*?\r\n" -r ""


:RunScrubN
IF "%param%"=="skipscrub" GOTO RunStatus
ECHO Running scrub of new data
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid scrub -p new -v --test-io-cache=32 > "%srpath%\log\%atimestamp%_scrub1.log" 2>&1
SET scrubnresult=%ERRORLEVEL%
rxrepl -f "%srpath%\log\%atimestamp%_scrub1.log" -a --no-backup --no-bom -i -s "\d+\%%,\s+\d+\sMB.*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_scrub1.log" -a --no-backup --no-bom -i -s "Saving state .*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_scrub1.log" -a --no-backup --no-bom -i -s "Verifying .*?\r\n" -r ""


:RunScrubO
IF "%param%"=="skipscrub" GOTO RunStatus
ECHO Running scrub of oldest 3%%
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid scrub -p 3 -v --test-io-cache=32 > "%srpath%\log\%atimestamp%_scrub2.log" 2>&1
SET scruboresult=%ERRORLEVEL%
rxrepl -f "%srpath%\log\%atimestamp%_scrub2.log" -a --no-backup --no-bom -i -s "\d+\%%,\s+\d+\sMB.*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_scrub2.log" -a --no-backup --no-bom -i -s "Saving state .*?\r\n" -r ""
rxrepl -f "%srpath%\log\%atimestamp%_scrub2.log" -a --no-backup --no-bom -i -s "Verifying .*?\r\n" -r ""


:RunTouch
ECHO Running Touch
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid touch -v >> "%srpath%\log\%atimestamp%_touch.log" 2>&1

SET touchsuccess=0
For /F "delims=:" %%N in ('findstr /N "touch " ^< "%srpath%\log\%atimestamp%_touch.log"') DO SET /A touchsuccess+=1
SET toucherror=0
For /F "delims=:" %%N in ('findstr /N "Error " ^< "%srpath%\log\%atimestamp%_touch.log"') DO SET /A toucherror+=1
SET /A touchtotal=%touchsuccess%+%toucherror%
SET touchresult=%touchsuccess%


:RunStatus
ECHO Running Status
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid status -v >> "%srpath%\log\%atimestamp%_status.log" 2>&1
SET statusresult=%ERRORLEVEL%


:CheckStatusLog
SET statuswarn=0
findstr /m "WARNING" "%srpath%\log\%atimestamp%_status.log"
IF %ERRORLEVEL%==0 (
SET statuswarn=1
)

SET statusdanger=0
findstr /m "DANGER" "%srpath%\log\%atimestamp%_status.log"
IF %ERRORLEVEL%==0 (
SET statusdanger=1
)

SET statusgood=GOOD
SET needfix="FALSE"
IF NOT %syncresult%==0 ( 
 SET statusgood=ERROR 
 IF %errthresh% GTR %syncresult% SET needfix="TRUE"
 )
IF NOT %scrubnresult%==0 (
 SET statusgood=ERROR 
 IF %errthresh% GTR %scrubnresult% SET needfix="TRUE"
 )
IF NOT %scruboresult%==0 (
 SET statusgood=ERROR 
 IF %errthresh% GTR %scruboresult% SET needfix="TRUE"
 )
IF NOT %statusresult%==0 (
 SET statusgood=ERROR 
 IF %errthresh% GTR %statusresult% SET needfix="TRUE"
 )
IF NOT %statuswarn%==0 (
 REM Warnings do not necessarily require fixing
 REM SET statusgood=ERROR 
 REM IF %errthresh% GTR %statuswarn% SET needfix="TRUE"
 )
IF NOT %statusdanger%==0 (
 SET statusgood=ERROR 
 IF %errthresh% GTR %statusdanger% SET needfix="TRUE"
 )
 
SET statusstring=(sync:%syncresult%)(scrub1:%scrubnresult%)(scrub2:%scruboresult%)(status:%statusresult%)(warn:%statuswarn%)(danger:%statusdanger%)
SET diffstring=(REM:%intrem%)(ADD:%intadd%)(T:%touchresult%)

REM Add Status line to top of log
ECHO SnapRAID Status %statusgood% %statusstring% %diffstring% >"%srpath%\log\%atimestamp%_status.log.new"
type "%srpath%\log\%atimestamp%_status.log" >>"%srpath%\log\%atimestamp%_status.log.new"
move /y "%srpath%\log\%atimestamp%_status.log.new" "%srpath%\log\%atimestamp%_status.log"

REM Add SMART data to bottom of log
snapraid smart >> "%srpath%\log\%atimestamp%_status.log"

REM Add Error Fix message to log if fix has run
IF %fixhasrun%=="TRUE" (
 ECHO %fixmsg% >"%srpath%\log\%atimestamp%_status.log.new"
 type "%srpath%\log\%atimestamp%_status.log" >>"%srpath%\log\%atimestamp%_status.log.new"
 move /y "%srpath%\log\%atimestamp%_status.log.new" "%srpath%\log\%atimestamp%_status.log"
 
 SET MessageFile=%srpath%\log\%atimestamp%_status.log
 Call:MAILSEND
 
 EXIT /B 0
)

REM Fix errors if errthresh met
IF %needfix%=="TRUE" (
 ECHO FixErrors in progress >"%srpath%\log\%atimestamp%_status.log.new"
 type "%srpath%\log\%atimestamp%_status.log" >>"%srpath%\log\%atimestamp%_status.log.new"
 move /y "%srpath%\log\%atimestamp%_status.log.new" "%srpath%\log\%atimestamp%_status.log"
 
 SET MessageFile=%srpath%\log\%atimestamp%_status.log
 Call:MAILSEND
 
 GOTO FixErrors
)

REM Normal exit
SET MessageFile=%srpath%\log\%atimestamp%_status.log
Call:MAILSEND
EXIT /B 0

:FixErrors
IF %fixhasrun%=="TRUE" (
 REM Fix has run and was unable to recover
 ECHO Exiting fixhasrun
 EXIT /B 999
)

REM Write log for files with error (simulate fix)
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid check -e -l "%srpath%\log\%atimestamp%_fix_test.log"
rxrepl -f "%srpath%\log\%atimestamp%_fix_test.log" -a --no-backup --no-bom -i -s "msg:verbose: Excluding link '.*?\r\n" -r ""
IF %ERRORLEVEL%==0 (
 REM No issue/errors found
)
IF %ERRORLEVEL% GTR 0 (
 SET fixerrors=%ERRORLEVEL%
)
REM Look for missing disks -> fatal error
SET diskfatal=0
For /F "delims=:" %%N in ('findstr /N "msg:fatal: Error accessing 'disk' '" ^< "%srpath%\log\%atimestamp%_fix_test.log"') DO SET /A diskfatal+=1

REM Fix errors on bad blocks
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid -e fix > "%srpath%\log\%atimestamp%_fix.log" 2>&1
SET unfixerrors=%ERRORLEVEL%
IF %ERRORLEVEL%==0 (
 REM Issues/errors fixed
)
IF %ERRORLEVEL% GTR 0 (
 REM Issues/errors unrecoverable
)

REM Scrub for previously bad blocks
SET atimestamp=%nDate%_%time::=;%
SET atimestamp=%atimestamp: =0%
snapraid -p bad scrub > "%srpath%\log\%atimestamp%_fix_confirm.log" 2>&1
IF %ERRORLEVEL%==0 (
 REM Issues/errors fixed
)
IF %ERRORLEVEL% GTR 0 (
 REM Issues/errors unrecoverable
 SET unfixerrors=%ERRORLEVEL%
)
SET /a resolveerrors=%fixerrors%-%unfixerrors%
SET fixmsg=%fixerrors% errors found^; %resolveerrors% errors recovered with %unfixerrors% errors unrecoverable; Full script has been rerun
SET fixhasrun="TRUE"
GOTO RunDiff

:MAILSEND
REM Call common Mailsend

 IF NOT %diskfatal%==0 (
  REM Fatal disk error has occurred!
  REM Stop all critical services
  IF EXIST CriticalServicesStop.bat CriticalServicesStop.bat 

  REM Add services note to message and update %statusgood%
  ECHO Critical Services Stopped >"%srpath%\log\%atimestamp%_status.log.new"
  type "%srpath%\log\%atimestamp%_status.log" >>"%srpath%\log\%atimestamp%_status.log.new"
  move /y "%srpath%\log\%atimestamp%_status.log.new" "%srpath%\log\%atimestamp%_status.log"
  
  SET statusgood=Fatal Disk Error (MissingDisks: %diskfatal%)
 )
  
 REM Attach header/footer to log message
 COPY /y "%srpath%\MailHeader.txt" "%srpath%\MailMessage.log"
 type "%MessageFile%" >>"%srpath%\MailMessage.log"
 type "%srpath%\MailFooter.txt" >>"%srpath%\MailMessage.log"
 COPY /y "%srpath%\MailMessage.log" "%srpath%\log\%atimestamp%_mail_msg.log"
 
 REM Send email 
 mailsend -smtp "smtp.gmail.com" -starttls -port 587 -auth -t "%emailto%" +cc +bc -f "%emailfrom%" -sub "SnapRAID Status %statusgood% %statusstring% %diffstring%" -attach "%srpath%\MailMessage.log",text/html,i -user "%mailuser%" -pass "%mailpass%"

EXIT /B 0






