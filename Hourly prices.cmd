@echo off
rem Fetches your auction house about once an hour from the game's official web API and hands it to XNAH.
rem Needs your own developer key in private\api.json (see the README). Leave this window open; close it to stop.
title XNAH hourly prices
cd /d "%~dp0"
where node >nul 2>nul || set "PATH=%PATH%;C:\Program Files\nodejs"
node tools\api-fetch.js --watch
pause
