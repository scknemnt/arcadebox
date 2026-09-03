@echo off
cd /d "%~dp0"
where py >nul 2>&1 && py -3 backend\arcadebox.py && goto :eof
python backend\arcadebox.py
