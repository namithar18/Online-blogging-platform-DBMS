# Helpers for the API and constraint tests. Dot-sourced by run-all.ps1.
$script:Base = "http://localhost:3000"
$script:Container = "blogdb_nextjs"
$script:Db = "blog"
$script:Sessions = @{}
$script:Results = New-Object System.Collections.ArrayList
$script:Last = $null
$script:Counter = 0
$script:Section = ""

function Section($name) {
  $script:Section = $name
  ""
  "=== $name"
}

# Log in as NAME@example.com and keep the session cookie for later requests.
function Login($name) {
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $body = @{ email = "$name@example.com"; password = "Passw0rd!" } | ConvertTo-Json
  try {
    Invoke-WebRequest -Uri "$script:Base/api/auth/login" -Method POST -Body $body -ContentType "application/json" -WebSession $s -UseBasicParsing | Out-Null
    $script:Sessions[$name] = $s
  } catch {
    throw "Login failed for $name : $($_.Exception.Message) - check the dev server terminal"
  }
}

# Send one request. Returns the status code; the parsed JSON body is in $script:Last.
function Send($who, $method, $path, $json) {
  $p = @{ Uri = "$script:Base$path"; Method = $method; UseBasicParsing = $true; MaximumRedirection = 0 }
  if ($who -ne "none") { $p.WebSession = $script:Sessions[$who] }
  if ($json) { $p.Body = $json; $p.ContentType = "application/json" }
  $code = 0
  $text = ""
  try {
    $r = Invoke-WebRequest @p
    $code = [int]$r.StatusCode
    $text = [string]$r.Content
  } catch {
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $text = [string]$_.ErrorDetails.Message
  }
  $script:Last = $null
  if ($text) { try { $script:Last = $text | ConvertFrom-Json } catch {} }
  return $code
}

function Record($desc, $call, $expected, $actual, $ok) {
  $script:Counter++
  $id = "TC{0:D2}" -f $script:Counter
  $status = "FAIL"
  if ($ok) { $status = "PASS" }
  $row = [pscustomobject]@{
    Id          = $id
    Section     = $script:Section
    Description = ([string]$desc).Replace("|", "/")
    Call        = ([string]$call).Replace("|", "/")
    Expected    = ([string]$expected).Replace("|", "/")
    Actual      = ([string]$actual).Replace("|", "/")
    Status      = $status
  }
  [void]$script:Results.Add($row)
  "{0} {1,-4} {2} (expected {3}, got {4})" -f $id, $status, $desc, $expected, $actual
}

# A request whose status code must equal $expect.
function Check($desc, $who, $method, $path, $json, $expect) {
  $code = Send $who $method $path $json
  Record $desc "$who $method $path" $expect $code ($code -eq $expect)
}

# A condition on the last response (or anything else) that must be true.
function CheckTrue($desc, $cond) {
  Record $desc "check" "True" ([string][bool]$cond) ([bool]$cond)
}

# Run a statement in Postgres and return its trimmed output.
function Sql($query) {
  return (docker exec $script:Container psql -U postgres -d $script:Db -t -A -c $query 2>&1 | Out-String).Trim()
}

# An invalid statement sent straight to the database: its error must contain $fragment.
# Use single quotes only inside $sql (PowerShell 5.1 mangles double quotes in native arguments).
function CheckSql($desc, $sql, $fragment) {
  $out = (docker exec $script:Container psql -U postgres -d $script:Db -c $sql 2>&1 | Out-String)
  $line = $out -split "`n" | Where-Object { $_ -match "ERROR" } | Select-Object -First 1
  $actual = "no error"
  if ($line) { $actual = $line.Trim() }
  Record $desc "SQL" "error containing: $fragment" $actual ($out -like "*$fragment*")
}