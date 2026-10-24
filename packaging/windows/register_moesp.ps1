# SPDX-License-Identifier: GPL-3.0-only
# Development-only per-user association (no administrator rights).
# For release installs use the Inno Setup script instead.
param(
    [string]$ExePath = (Join-Path $PSScriptRoot "..\..\build\windows\x64\runner\Release\moesketchpad.exe"),
    [string]$IconPath = (Join-Path $PSScriptRoot "..\..\assets\if.ico")
)
$ErrorActionPreference = "Stop"
$exe = (Resolve-Path $ExePath).Path
$icon = (Resolve-Path $IconPath).Path
$classes = "HKCU:\Software\Classes"
New-Item -Path "$classes\.moesp" -Force | Out-Null
Set-ItemProperty -Path "$classes\.moesp" -Name "(default)" -Value "MoeSketchpad.Document"
Set-ItemProperty -Path "$classes\.moesp" -Name "Content Type" -Value "application/x-moesketchpad"
New-Item -Path "$classes\MoeSketchpad.Document\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$classes\MoeSketchpad.Document\DefaultIcon" -Name "(default)" -Value "$icon,0"
New-Item -Path "$classes\MoeSketchpad.Document\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$classes\MoeSketchpad.Document\shell\open\command" -Name "(default)" -Value "`"$exe`" `"%1`""
Write-Host "Registered .moesp for the current user. Use Windows Settings > Default apps to confirm."
