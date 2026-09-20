@echo off
title Game Recorder - close OBS
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\GameRec.ps1" quit
timeout /t 3 >nul
