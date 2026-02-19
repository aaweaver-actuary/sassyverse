$ErrorActionPreference = 'Stop'
$root = Get-Location
$target = Join-Path $root 'src/pipr/predicates.sas'
$content = Get-Content $target
$macros = @()
foreach ($line in $content) {
  if ($line -match '^\s*%macro\s+([A-Za-z_][A-Za-z0-9_]*)') {
    $macros += $Matches[1].ToLower()
  }
}
$macros = $macros | Sort-Object -Unique
$sasFiles = Get-ChildItem -Recurse -File -Filter *.sas | Where-Object { $_.FullName -ne $target }
$rows = @()
foreach ($m in $macros) {
  $pattern = [regex]::Escape('%' + $m) + '\b'
  $extMatches = @()
  foreach ($f in $sasFiles) {
    $ms = Select-String -Path $f.FullName -Pattern $pattern -AllMatches
    if ($ms) {
      foreach ($hit in $ms) {
        $extMatches += [pscustomobject]@{
          file = $hit.Path.Replace($root.Path + '\', '')
          line = $hit.LineNumber
          text = $hit.Line.Trim()
        }
      }
    }
  }

  $defAndCalls = Select-String -Path $target -Pattern $pattern -AllMatches
  $selfTotal = ($defAndCalls | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
  if (-not $selfTotal) { $selfTotal = 0 }

  $rows += [pscustomobject]@{
    macro = $m
    external_ref_count = $extMatches.Count
    external_refs = ($extMatches | Select-Object -First 8 | ForEach-Object { "$($_.file):$($_.line)" }) -join '; '
    self_ref_count = $selfTotal
  }
}

$out = Join-Path $root 'reports/predicates_macro_usage.csv'
$rows |
  Sort-Object @(
    @{ Expression = 'external_ref_count'; Descending = $true },
    @{ Expression = 'macro'; Descending = $false }
  ) |
  Export-Csv -NoTypeInformation -Path $out
Write-Output "Wrote $out"
