@echo off
title Game Recorder - stop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\GameRec.ps1" stop
echo. & pause
