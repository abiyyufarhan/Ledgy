# Checks Git upload candidates without printing secret values.
# This is an additional check, not a guarantee against every secret format.
$ErrorActionPreference = 'Stop'
$auditRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $auditRoot
try {
    & git rev-parse --show-toplevel 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Jalankan git init -b main terlebih dahulu.' }
    $auditFiles = @(& git -c core.quotepath=false ls-files --cached --others --exclude-standard | Sort-Object -Unique)
    $auditProblems = [Collections.Generic.List[string]]::new()
    $auditPatterns = @{
        'Private key' = '-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----'
        'Supabase secret key' = 'sb_secret_[A-Za-z0-9_-]{15,}'
        'Supabase CLI token' = 'sbp_[a-fA-F0-9]{30,}'
        'GitHub token' = '(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,})'
        'AWS access key' = '(?:AKIA|ASIA)[A-Z0-9]{16}'
        'Database connection with password' = '(?i)(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?):\/\/[^\s/:]+:[^\s@]+@'
        'Assigned credential' = '(?i)["'']?(?:service_role_key|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_ACCESS_TOKEN|DB_PASSWORD|DATABASE_PASSWORD|AWS_SECRET_ACCESS_KEY|storePassword|keyPassword)["'']?\s*[:=]\s*["''][^"'']{8,}["'']'
    }
    foreach ($auditFile in $auditFiles) {
        if ($auditFile -match '(?i)(^|/)(release-private|\.temp|\.branches|\.aws|backups|private)/|(^|/)(key\.properties|client-config\.local\.json|\.env(?:\..+)?)$|\.(?:jks|keystore|pem|pfx|p12|db|sqlite|sqlite3)(?:-wal|-shm)?$') {
            if ($auditFile -notmatch '\.env\.(example|sample)$') { $auditProblems.Add("Excluded file tracked: $auditFile") }
        }
        if ($auditFile -notmatch '(?i)\.(dart|json|yaml|yml|toml|md|txt|ps1|sh|properties|kts|gradle|xml|sql|csv|conf|ini)$') { continue }
        $auditFullPath = Join-Path $auditRoot $auditFile
        if (!(Test-Path -LiteralPath $auditFullPath -PathType Leaf)) { continue }
        $auditContent = [IO.File]::ReadAllText($auditFullPath)
        foreach ($auditRule in $auditPatterns.GetEnumerator()) {
            if ([regex]::IsMatch($auditContent, $auditRule.Value)) { $auditProblems.Add("$($auditRule.Key): $auditFile") }
        }
        # JWT keys are flagged even when they might be public anon keys: review before sharing.
        if ([regex]::IsMatch($auditContent, 'eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}')) {
            $auditProblems.Add("JWT credential requires review: $auditFile")
        }
    }
    Write-Host "Checked $($auditFiles.Count) Git upload candidates. Secret values are never displayed."
    if ($auditProblems.Count -gt 0) {
        $auditProblems | ForEach-Object { Write-Host "REVIEW: $_" }
        throw 'Pemeriksaan menemukan kandidat sensitif. Perbaiki sebelum commit/push.'
    }
    Write-Host 'PASS: no blocked files or supported secret patterns found.'
} finally { Pop-Location }
