param(
    [Parameter(Mandatory=$true)][string]$Resources,
    [switch]$Restore
)
$ErrorActionPreference = 'Stop'
$resourcesPath = (Resolve-Path -LiteralPath $Resources).Path
$target = Join-Path $resourcesPath 'app.asar'
$backup = Join-Path $resourcesPath 'app.before-conversation-window-plugin.asar'
$candidate = Join-Path $PSScriptRoot '..\build\app.conversation-window.asar'
$record = Join-Path $resourcesPath 'conversation-window-plugin.sha256'
if (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) {
    throw 'Exit DeepSeek Harness completely, including its tray icon, before installing or restoring.'
}
if ($Restore) {
    if (!(Test-Path -LiteralPath $backup) -or !(Test-Path -LiteralPath $record)) { throw 'Backup or installation record missing.' }
    $installedHash = (Get-Content -LiteralPath $record -Raw).Trim()
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $installedHash) {
        throw 'Current archive changed after installation; refusing to overwrite an updated application.'
    }
    Copy-Item -LiteralPath $backup -Destination $target -Force
    Write-Output 'Original archive restored. Restart DeepSeek Harness.'
    exit
}
if (!(Test-Path -LiteralPath $candidate)) { throw 'Build the adapter first with scripts/build_adapter.py.' }
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne '5FA8A6B21BCEB8F3E99E30EFA2270EFD0CC773A11E42AA0488F804A64B34E637') {
    throw 'Unsupported or already patched app.asar. Only the inspected original Windows build is supported.'
}
if (Test-Path -LiteralPath $backup) { throw 'Backup already exists; inspect it before reinstalling. Never overwrite a recovery copy.' }
Copy-Item -LiteralPath $target -Destination $backup
$hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
Copy-Item -LiteralPath $candidate -Destination $target -Force
Set-Content -LiteralPath $record -Value $hash -Encoding Ascii
Write-Output 'Experimental desktop adapter installed. Restart, then install the plugin bundle through DSH.'
