<#
  Replaces resources\app.asar with the locally built adapter archive.

  This script never stops DeepSeek Harness. If the app is running it asks you to
  quit it and waits, then swaps the archive, verifies the hash, writes the
  installation record and starts the app exactly once.

  The previous version killed every desktop process and was itself terminated by
  that kill, so the copy never ran. Waiting for a manual exit removes that race.

  Exit codes: 0 installed or already installed, 1 failed, 2 unsupported archive.
#>
param(
    [switch]$CheckOnly,
    [int]$WaitSeconds = 900,
    [string]$Exe = "$env:LOCALAPPDATA\Programs\DeepSeek Harness\DeepSeek Harness.exe"
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$exe = $Exe
$resources = Join-Path (Split-Path $exe) 'resources'
$target = Join-Path $resources 'app.asar'
$backup = Join-Path $resources 'app.before-conversation-window-plugin.asar'
$record = Join-Path $resources 'conversation-window-plugin.sha256'
$candidate = Join-Path $root 'build\app.conversation-window.asar'
$staged = Join-Path $resources 'app.conversation-window.pending.asar'
$logFile = Join-Path $root 'build\install-restart.log'
$lockFile = Join-Path $root 'build\install-restart.lock'
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

function Get-AncestorPaths {
    $paths = @()
    $id = $PID
    for ($depth = 0; $depth -lt 12; $depth++) {
        $self = Get-CimInstance Win32_Process -Filter "ProcessId = $id" -ErrorAction SilentlyContinue
        if (!$self -or $self.ParentProcessId -le 0) { break }
        $id = $self.ParentProcessId
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $id" -ErrorAction SilentlyContinue
        if (!$parent) { break }
        $paths += $parent.ExecutablePath
    }
    $paths
}

try {
    Write-Status 'START installer invoked.'
    if (!(Test-Path -LiteralPath $exe)) { throw "Desktop executable not found: $exe" }
    if (!(Test-Path -LiteralPath $target)) { throw "Application archive not found: $target" }
    if (!(Test-Path -LiteralPath $candidate)) { throw 'Build the adapter first: python scripts/build_adapter.py --source "<original app.asar>"' }
    if ((Get-FileDigest $candidate) -ne $patchedHash) { throw 'Built archive does not match the reviewed build; rebuild it instead of patching the hash.' }

    $current = Get-FileDigest $target
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

    if ($CheckOnly) {
        Write-Status "CHECK_OK source and candidate verified, backup ready; app.asar untouched. running_processes=$((Get-DesktopProcesses).Count)"
        exit 0
    }

    if ((Get-AncestorPaths) -contains $exe) {
        throw 'This console is a child of DeepSeek Harness; quitting the app would kill the installer too. Close this window and double-click install-and-restart.cmd in Explorer.'
    }

    if (Test-Path -LiteralPath $lockFile) {
        $owner = (Get-Content -LiteralPath $lockFile -Raw -ErrorAction SilentlyContinue)
        if ($owner) { $owner = $owner.Trim() }
        if ($owner -and (Get-Process -Id $owner -ErrorAction SilentlyContinue)) {
            Write-Status "FAIL another installer (pid $owner) is already waiting; nothing changed."
            exit 3
        }
    }
    Set-Content -LiteralPath $lockFile -Value $PID -Encoding Ascii
    $lockOwned = $true

    if ((Get-DesktopProcesses).Count -gt 0) {
        Write-Status "WAIT DeepSeek Harness is running ($((Get-DesktopProcesses).Count) processes)."
        Write-Status 'WAIT Quit it completely: the window close button only hides it. Use the tray icon > Exit.'
        Write-Status "WAIT Waiting up to $WaitSeconds seconds. Nothing is killed; the archive is replaced only after it exits."
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        while ((Get-DesktopProcesses).Count -gt 0) {
            if ((Get-Date) -gt $deadline) { throw "DeepSeek Harness was still running after $WaitSeconds seconds. Nothing was replaced." }
            Start-Sleep -Milliseconds 700
        }
        Write-Status 'WAIT app exited.'
        Start-Sleep -Seconds 2
    }

    Copy-Item -LiteralPath $candidate -Destination $staged -Force
    if ((Get-FileDigest $staged) -ne $patchedHash) { throw 'Staged copy failed its hash check.' }

    $swapped = $false
    $swapBackup = $target + '.previous.tmp'
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            [System.IO.File]::Replace($staged, $target, $swapBackup, $true)
            if (Test-Path -LiteralPath $swapBackup) { [System.IO.File]::Delete($swapBackup) }
            $swapped = $true
            break
        }
        catch {
            try {
                Move-Item -LiteralPath $staged -Destination $target -Force
                $swapped = $true
                break
            }
            catch {
                Start-Sleep -Seconds 2
            }
        }
    }
    if (!$swapped -or (Get-FileDigest $target) -ne $patchedHash) { throw 'Could not replace app.asar; it is still locked or write-protected.' }

    Set-Content -LiteralPath $record -Value $patchedHash -Encoding Ascii
    if (Test-Path -LiteralPath $staged) { [System.IO.File]::Delete($staged) }
    Write-Status 'STATE adapter installed and verified.'

    Start-Process -FilePath $exe | Out-Null
    Write-Status 'OK DeepSeek Harness started once. Test: right-click a conversation > open in new window.'
    exit 0
}
catch {
    Write-Status "FAIL $($_.Exception.Message)"
    if (Test-Path -LiteralPath $staged) { try { [System.IO.File]::Delete($staged) } catch { } }
    if (Test-Path -LiteralPath $backup) {
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
