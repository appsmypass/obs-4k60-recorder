@echo off
title Game Recorder - one-time setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Setup-OBS.ps1"
echo. & pause
