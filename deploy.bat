@echo off
call flutter build web
if errorlevel 1 exit /b 1
if exist site\app rmdir /s /q site\app
xcopy /e /i /y build\web site\app
echo Done. Now run git add, commit and push.