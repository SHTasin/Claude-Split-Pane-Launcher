@echo off
:: Launch-ClaudeCode.bat -- double-click to run
:: Must be in the SAME folder as Launch-ClaudeCode.ps1

set "PS=%~dp0Launch-ClaudeCode.ps1"
set "VBS=%TEMP%\RunHidden_%RANDOM%.vbs"

if not exist "%PS%" (
    echo ERROR: Cannot find Launch-ClaudeCode.ps1 next to this .bat file.
    pause
    exit /b 1
)

:: Write a tiny VBScript to launch PowerShell with no visible window
echo Set sh = CreateObject("WScript.Shell") > "%VBS%"
echo sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%PS%""", 0, False >> "%VBS%"
echo Set sh = Nothing >> "%VBS%"

wscript.exe "%VBS%"
del "%VBS%" 2>nul