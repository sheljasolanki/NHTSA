# Runs every SQL script in this folder in order and saves each output to Results/sql_output/.
# Usage (from any folder):  powershell -ExecutionPolicy Bypass -File sql\run_all.ps1
# Stops at the first script that fails.
param(
    [string]$Server = "localhost",
    [string]$Database = "NHTSA_v2"
)

$sqlDir = $PSScriptRoot
$outDir = Join-Path (Split-Path $sqlDir -Parent) "Results\sql_output"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Get-ChildItem -Path $sqlDir -Filter "*.sql" | Sort-Object Name | ForEach-Object {
    $outFile = Join-Path $outDir ($_.BaseName + ".txt")
    Write-Host "Running $($_.Name) ..."
    $start = Get-Date
    & sqlcmd -S $Server -d $Database -E -b -I -W -s "|" -i $_.FullName -o $outFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $($_.Name). See $outFile" -ForegroundColor Red
        exit 1
    }
    Write-Host ("  done in {0:N0}s -> {1}" -f ((Get-Date) - $start).TotalSeconds, $outFile)
}
Write-Host "All scripts finished."
