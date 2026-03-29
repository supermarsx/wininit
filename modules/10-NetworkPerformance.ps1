# Module: 10 - Network & Performance Tuning
# Nagle, paging executive, SSD, memory compression, standby memory, IRPStackSize

Write-Section "Network & Performance Tuning"

# --- 10a. Disable Nagle Algorithm (lower latency) ---
Write-Log "Disabling Nagle algorithm on all interfaces..."
$netInterfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
foreach ($iface in $netInterfaces) {
    Set-ItemProperty -Path $iface.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $iface.PSPath -Name "TCPNoDelay"      -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $iface.PSPath -Name "TcpDelAckTicks"  -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Log "Nagle algorithm disabled on all network interfaces" "OK"

# --- 10b. Disable Paging Executive (keep kernel in RAM) ---
Write-Log "Disabling paging executive (keep kernel in RAM)..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" `
    -Name "DisablePagingExecutive" -Value 1 -Type DWord
Write-Log "Paging executive disabled - kernel stays in RAM" "OK"

# --- 10c. SSD Optimizations ---
Write-Log "Applying SSD optimizations..."
# Disable last access timestamp updates (reduces write overhead)
fsutil behavior set disablelastaccess 1 >$null 2>&1
# Disable 8.3 short filename creation (reduces NTFS overhead)
fsutil behavior set disable8dot3 1 >$null 2>&1
# Ensure TRIM is enabled
fsutil behavior set disabledeletenotify 0 >$null 2>&1
Write-Log "SSD optimizations applied (last access off, 8.3 names off, TRIM on)" "OK"

# --- 10d. Disable Memory Compression ---
Write-Log "Disabling memory compression..."
Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue 3>$null | Out-Null
Write-Log "Memory compression disabled (saves CPU, use if 16GB+ RAM)" "OK"

# --- 10e. Clear Standby Memory on Threshold ---
Write-Log "Configuring standby memory clearing..."
# Set large system cache to let the OS manage standby more aggressively
$MemMgmtPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $MemMgmtPath -Name "LargeSystemCache" -Value 1 -Type DWord
# Create a scheduled task that clears standby list when free RAM < 1GB
# Uses a PowerShell command that flushes working sets
$clearMemAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
-NoProfile -WindowStyle Hidden -Command "&{
    `$freeGB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
    if (`$freeGB -lt 1) {
        Get-Process | Where-Object { `$_.WorkingSet64 -gt 100MB -and `$_.ProcessName -ne 'explorer' } | ForEach-Object {
            [System.Diagnostics.Process]::GetProcessById(`$_.Id).MinWorkingSet = [IntPtr]::new(-1)
        }
        [System.GC]::Collect()
    }
}"
"@
$clearMemTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
$clearMemPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "WinInit-ClearStandbyMemory" `
    -Action $clearMemAction -Trigger $clearMemTrigger -Principal $clearMemPrincipal `
    -Description "Clears standby memory when free RAM drops below 1GB" `
    -Force -ErrorAction SilentlyContinue 3>$null | Out-Null
Write-Log "Standby memory clearing task registered (runs every 10 min)" "OK"

# --- 10f. Increase IRPStackSize (network throughput) ---
Write-Log "Increasing IRPStackSize..."
$TcpipParams = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
Set-ItemProperty -Path $TcpipParams -Name "IRPStackSize" -Value 32 -Type DWord
Write-Log "IRPStackSize set to 32 (improved network throughput)" "OK"

Write-Log "Module 10-NetworkPerformance completed" "OK"

