@echo off
setlocal
SET batpath=%~dp0
powershell -ExecutionPolicy Bypass -File %batpath%\luksmount.ps1 %*

pause