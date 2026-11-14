@echo off
chcp 65001 >nul
cd /d "%~dp0.."
"C:\Users\19453\.dsh\dsh-runtimes\dsh-next-primary-runtime\dependencies\python\python.exe" tools\socket_editor.py
pause