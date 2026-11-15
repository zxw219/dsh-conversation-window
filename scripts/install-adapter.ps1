<#
  Installs or removes the conversation-window adapter in resources\app.asar.

  One script for both directions:
    (default)  install  - swap in build\app.conversation-window.asar
    -Restore   rollback - put the original archive back

  It never stops DeepSeek Harness. When the app is running it prints WAIT and
  waits for a manual exit (tray > Exit), because app.asar is locked while the
  desktop runs. The archive is replaced atomically, verified, recorded, and the
  app is started exactly once afterwards. Every state goes to
  build\install-adapter.log.

  Exit codes: 0 done or nothing to do, 1 failed, 2 unsupported archive, 3 locked.
#>
param(
    [string]$Resources = "$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources",
    [switch]$Restore,
    [switch]$CheckOnly,
    [int]$WaitSeconds = 900
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
try { $resourcesPath = (Resolve-Path -LiteralPath $Resources).Path }
catch { Write-Output "FAIL resources directory not found: $Resources"; exit 1 }
$exe = Join-Path (Split-Path $resourcesPath -Parent) 'DeepSeek Harness.exe'
$target = Join-Path $resourcesPath 'app.asar'
$backup = Join-Path $resourcesPath 'app.before-conversation-window-plugin.asar'
$record = Join-Path $resourcesPath 'conversation-window-plugin.sha256'
$candidate = Join-Path $root 'build\app.conversation-window.asar'
$staged = Join-Path $resourcesPath 'app.conversation-window.pending.asar'
$logFile = Join-Path $root 'build\install-adapter.log'
$lockFile = Join-Path $root 'build\install-adapter.lock'
$lockOwned = $false

$originalHash = '14CFD81C9135BF0AFB89417543C94F9ECFE09266574452A9B106890C698725AE'
$patchedHash = 'EE66AA50B281CD0E32C4B1EC3B359F6C7528F6CD5BAA57541E6C83E17CB04EC0'

function Get-FileDigest([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Write-Status([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Output $line
    try {
        $directory = Split-Path $logFile -Parent
        if (!(Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        [System.IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
    catch { }
}

function Get-DesktopProcesses {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -eq $exe })
}

function Assert-OutsideDesktop {
    $id = $PID
    for ($depth = 0; $depth -lt 12; $depth++) {
        $self = Get-CimInstance Win32_Process -Filter "ProcessId = $id" -ErrorAction SilentlyContinue
        if (!$self -or $self.ParentProcessId -le 0) { return }
        $id = $self.ParentProcessId
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $id" -ErrorAction SilentlyContinue
        if (!$parent) { return }
        if ($parent.ExecutablePath -eq $exe) {
            throw 'This console is a child of DeepSeek Harness; quitting the app would kill the script. Double-click install-and-restart.cmd in Explorer instead.'
        }
    }
}

function Wait-ForDesktopExit {
    $running = (Get-DesktopProcesses).Count
    if ($running -eq 0) { return }
    Write-Status "WAIT DeepSeek Harness is running ($running processes)."
    Write-Status 'WAIT Quit it completely: the close button only hides it, use the tray icon > Exit.'
    Write-Status "WAIT Waiting up to $WaitSeconds seconds. Nothing is killed; the archive changes only after it exits."
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-DesktopProcesses).Count -gt 0) {
        if ((Get-Date) -gt $deadline) { throw "DeepSeek Harness was still running after $WaitSeconds seconds. Nothing was changed." }
        Start-Sleep -Milliseconds 700
    }
    Write-Status 'WAIT app exited.'
    Start-Sleep -Seconds 2
}

function Set-Archive([string]$Source, [string]$Expected) {
    $swapBackup = $target + '.previous.tmp'
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            [System.IO.File]::Replace($Source, $target, $swapBackup, $true)
            if (Test-Path -LiteralPath $swapBackup) { [System.IO.File]::Delete($swapBackup) }
            break
        }
        catch {
            try {
                Copy-Item -LiteralPath $Source -Destination $target -Force
                break
            }
            catch {
                if ($attempt -eq 6) { throw 'Could not replace app.asar; it is still locked or write-protected.' }
                Start-Sleep -Seconds 2
            }
        }
    }
    if ((Get-FileDigest $target) -ne $Expected) { throw 'Replaced archive failed its hash check.' }
}

try {
    Write-Status ("START mode={0} resources={1}" -f $(if ($Restore) { 'restore' } else { 'install' }), $resourcesPath)
    if (!(Test-Path -LiteralPath $target)) { throw "Application archive not found: $target" }

    $current = Get-FileDigest $target

    if ($Restore) {
        if (!(Test-Path -LiteralPath $backup)) { throw "Original backup missing: $backup" }
        if ((Get-FileDigest $backup) -ne $originalHash) { throw 'Backup does not match the original archive; inspect it before restoring.' }
        if (!(Test-Path -LiteralPath $record)) { throw 'Installation record missing; cannot confirm what is installed.' }
        $recorded = (Get-Content -LiteralPath $record -Raw).Trim()
        if ($current -eq $originalHash) {
            Write-Status 'STATE archive is already the original; nothing to do.'
            exit 0
        }
        if ($current -ne $recorded) { throw 'Archive changed after installation; refusing to overwrite a newer application. Use the official installer.' }
    }
    else {
        if (!(Test-Path -LiteralPath $candidate)) { throw 'Build the adapter first: python scripts/build_adapter.py' }
        if ((Get-FileDigest $candidate) -ne $patchedHash) { throw 'Built archive does not match the reviewed build; rebuild it instead of editing the hash.' }
        if ($current -eq $patchedHash) {
            Write-Status 'STATE adapter already installed; nothing to do.'
            exit 0
        }
        if ($current -ne $originalHash) {
            Write-Status "FAIL unsupported app.asar hash: $current"
            exit 2
        }
        if (Test-Path -LiteralPath $backup) {
            if ((Get-FileDigest $backup) -ne $originalHash) { throw 'Existing backup does not match the original archive; inspect it before reinstalling.' }
            Write-Status 'STATE original backup verified.'
        }
        else {
            Copy-Item -LiteralPath $target -Destination $backup
            if ((Get-FileDigest $backup) -ne $originalHash) { throw 'Backup copy failed verification.' }
            Write-Status 'STATE original backup created.'
        }
    }

    if ($CheckOnly) {
        Write-Status ("CHECK_OK ready; archive untouched; running_processes={0}" -f (Get-DesktopProcesses).Count)
        exit 0
    }

    Assert-OutsideDesktop

    if (Test-Path -LiteralPath $lockFile) {
        $owner = (Get-Content -LiteralPath $lockFile -Raw -ErrorAction SilentlyContinue)
        if ($owner) { $owner = $owner.Trim() }
        if ($owner -and (Get-Process -Id $owner -ErrorAction SilentlyContinue)) {
            Write-Status "FAIL another run (pid $owner) is already waiting; nothing changed."
            exit 3
        }
    }
    Set-Content -LiteralPath $lockFile -Value $PID -Encoding Ascii
    $lockOwned = $true

    Wait-ForDesktopExit

    if ($Restore) {
        Copy-Item -LiteralPath $backup -Destination $staged -Force
        if ((Get-FileDigest $staged) -ne $originalHash) { throw 'Staged original copy failed its hash check.' }
        Set-Archive $staged $originalHash
        if (Test-Path -LiteralPath $staged) { [System.IO.File]::Delete($staged) }
        if (Test-Path -LiteralPath $record) { [System.IO.File]::Delete($record) }
        Write-Status 'STATE original archive restored; installation record removed.'
    }
    else {
        Copy-Item -LiteralPath $candidate -Destination $staged -Force
        if ((Get-FileDigest $staged) -ne $patchedHash) { throw 'Staged copy failed its hash check.' }
        Set-Archive $staged $patchedHash
        if (Test-Path -LiteralPath $staged) { [System.IO.File]::Delete($staged) }
        Set-Content -LiteralPath $record -Value $patchedHash -Encoding Ascii
        Write-Status 'STATE adapter installed and verified.'
    }

    Start-Process -FilePath $exe | Out-Null
    Write-Status 'OK DeepSeek Harness started once.'
    exit 0
}
catch {
    Write-Status "FAIL $($_.Exception.Message)"
    if (Test-Path -LiteralPath $staged) { try { [System.IO.File]::Delete($staged) } catch { } }
    if (!$Restore -and (Test-Path -LiteralPath $backup)) {
        $targetHash = if (Test-Path -LiteralPath $target) { Get-FileDigest $target } else { '' }
        $known = @($originalHash, $patchedHash, '')
        if ((Get-FileDigest $backup) -eq $originalHash -and $known -notcontains $targetHash) {
            Copy-Item -LiteralPath $backup -Destination $target -Force
            Write-Status 'ROLLBACK original archive restored from backup.'
        }
    }
    exit 1
}
finally {
    if ($lockOwned -and (Test-Path -LiteralPath $lockFile)) {
        Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
    }
}
