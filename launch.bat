@echo off
title WinInit - Windows Initialization Script
color 0A
mode con: cols=120 lines=9999

:: ============================================================================
:: WinInit Launcher - Auto-Elevate + Center Window
:: Double-click this file to start. That's it.
:: ============================================================================

:: --- Auto-elevate to Administrator ---
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs -ArgumentList '%~dp0'"
    exit /b
)

:: --- Center window and set full height ---
powershell -NoProfile -Command ^
    "Add-Type @'`n"^
    "using System; using System.Runtime.InteropServices;`n"^
    "public class Win { [DllImport(\"user32.dll\")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int h2, bool r);`n"^
    "[DllImport(\"kernel32.dll\")] public static extern IntPtr GetConsoleWindow();`n"^
    "[DllImport(\"user32.dll\")] public static extern bool GetWindowRect(IntPtr h, out RECT r);`n"^
    "[DllImport(\"user32.dll\")] public static extern int GetSystemMetrics(int i);`n"^
    "public struct RECT { public int L, T, R, B; } }`n"^
    "'@;`n"^
    "$h=[Win]::GetConsoleWindow(); $r=[Win+RECT]::new(); [Win]::GetWindowRect($h,[ref]$r)|Out-Null;`n"^
    "$sw=[Win]::GetSystemMetrics(0); $sh=[Win]::GetSystemMetrics(1);`n"^
    "$w=$r.R-$r.L; if($w -lt 960){$w=960}; $x=($sw-$w)/2; $y=0;`n"^
    "[Win]::MoveWindow($h,$x,$y,$w,$sh-40,$true)|Out-Null"

cls
echo.
echo   WinInit - Windows Initialization ^& Customization
echo   Running as Administrator
echo.
echo  [*] Starting in 3 seconds... Press Ctrl+C to abort.
echo.
timeout /t 3 /nobreak >nul

:: --- Launch the main orchestrator ---
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0init.ps1"
popd

echo.
echo   WinInit Complete! A reboot is recommended to apply all changes.
echo   Press any key to close this window.
echo.
pause
