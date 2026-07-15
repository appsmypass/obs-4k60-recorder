@echo off
title Game Recorder - status
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\GameRec.ps1" status
echo. & pause
