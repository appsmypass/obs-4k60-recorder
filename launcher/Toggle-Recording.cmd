@echo off
title Game Recorder - toggle
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\GameRec.ps1" toggle
echo. & pause
