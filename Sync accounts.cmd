@echo off
rem Joins the XNAH data of all your WoW accounts on this PC: characters (Wealth page), ledger, newest prices.
rem Waits until every game window is closed, then merges. Backups go to private\backups.
cd /d "%~dp0"
where node >nul 2>nul || set "PATH=%PATH%;C:\Program Files\nodejs"
node tools\sync-accounts.js --wait
pause
