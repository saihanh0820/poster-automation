[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectFile,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [ValidateSet('preview', 'a1-150ppi', 'a1-300ppi')][string]$Preset = 'a1-150ppi'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
& (Join-Path $scriptRoot 'validate-project.ps1') -ProjectFile $ProjectFile -Preset $Preset
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $scriptRoot 'build-posters.ps1') -ProjectFile $ProjectFile -OutputDir $OutputDir -Preset $Preset
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $scriptRoot 'qa-exports.ps1') -ProjectFile $ProjectFile -OutputDir $OutputDir -Preset $Preset
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
