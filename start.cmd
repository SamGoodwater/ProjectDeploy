@echo off
REM Lance ProjectDeploy sans avertissement Zone.Identifier sur install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
if errorlevel 1 pause
