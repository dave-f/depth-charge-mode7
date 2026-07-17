# Build depthcharge.ssd; pass -run to boot it in b2 afterwards.
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force build | Out-Null
    & tools\beebasm\beebasm.exe -i src\main.asm -do build\depthcharge.ssd -opt 3 -title "DEPTHCHARGE" -v
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "Built build\depthcharge.ssd"
    if ($args -contains '-run') {
        Start-Process (Resolve-Path tools\b2\b2.exe) -ArgumentList '-0', (Resolve-Path build\depthcharge.ssd), '-b'
    }
}
finally {
    Pop-Location
}
