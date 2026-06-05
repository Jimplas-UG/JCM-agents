@echo off
set LOG=C:\logs\jcm\daily-briefing-telegram.log
set ROOT=C:\jcm-project
set BACKEND=%ROOT%\backend
set PY=%BACKEND%\.venv\Scripts\python.exe
echo %date% %time% [primary-bat] start >> "%LOG%"
if not exist "%PY%" (echo %date% %time% ERROR: venv missing >> "%LOG%" & exit /b 1)
if not exist "%ROOT%\.env" (echo %date% %time% ERROR: .env missing >> "%LOG%" & exit /b 1)
copy /Y "%ROOT%\.env" "%BACKEND%\.env" >nul
cd /d "%BACKEND%"
"%PY%" -m app.workers.daily_briefing_job --force >> "%LOG%" 2>&1
set EC=%ERRORLEVEL%
echo %date% %time% [primary-bat] exit %EC% >> "%LOG%"
exit /b %EC%
