@echo off
chcp 65001 >nul
title Ninho Monitor - Endereco Fixo
cd /d "%~dp0"
JortanPonte.exe --endereco-fixo
pause
