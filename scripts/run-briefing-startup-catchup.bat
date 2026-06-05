@echo off
for /f "tokens=1-2 delims=:" %%a in ("%time%") do set HOUR=%%a
set /a HOUR=1%HOUR% - 100
if %HOUR% LSS 9 exit /b 0
call C:\jcm\scripts\run-briefing-backup.bat
