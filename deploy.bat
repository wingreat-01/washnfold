@echo off
cd /d "%~dp0"

echo === Building Flutter web ===
call flutter build web
if errorlevel 1 goto failed

echo === Copying build to site\app ===
if exist site\app rmdir /s /q site\app
xcopy /e /i /y build\web site\app
if errorlevel 1 goto failed

echo.
echo SUCCESS: site\app is updated. Now run git add, commit and push.
pause
exit /b 0

:failed
echo.
echo FAILED: read the error above.
pause
exit /b 1