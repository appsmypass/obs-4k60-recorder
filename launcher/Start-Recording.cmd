@echo off
title Game Recorder - start
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\GameRec.ps1" start
timeout /t 3 >nul
