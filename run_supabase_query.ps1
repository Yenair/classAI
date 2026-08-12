# Read-only Supabase Management API query runner.
# Reads the Supabase CLI access token from Windows Credential Manager and
# POSTs the SQL query in $env:SUPABASE_SQL to the Management API query endpoint.
# This only executes whatever SQL is provided; caller must pass SELECT-only queries.
param(
  [string]$Sql = ""
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class CredUtilQ {
    [StructLayout(LayoutKind.Sequential)]
    public struct CREDENTIAL {
        public uint Flags;
        public int Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern void CredFree(IntPtr cred);

    public static string Read(string target) {
        IntPtr ptr;
        if (!CredRead(target, 1, 0, out ptr)) {
            int err = Marshal.GetLastWin32Error();
            return "ERROR_" + err;
        }
        try {
            CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
            if (cred.CredentialBlobSize > 0) {
                byte[] blob = new byte[cred.CredentialBlobSize];
                Marshal.Copy(cred.CredentialBlob, blob, 0, (int)cred.CredentialBlobSize);
                return Encoding.UTF8.GetString(blob);
            }
            return "";
        } finally {
            CredFree(ptr);
        }
    }
}
"@

$targets = @("Supabase CLI:supabase", "supabase", "supabase-cli")
$token = ""
foreach ($t in $targets) {
    $r = [CredUtilQ]::Read($t)
    if (-not $r.StartsWith("ERROR_")) {
        $trimmed = $r.Trim()
        if ($trimmed.Length -gt 20) {
            $token = $trimmed
            break
        }
    }
}
if ($token -eq "") {
    Write-Output "NO_TOKEN_FOUND"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Sql)) {
    $Sql = $env:SUPABASE_SQL
}
if ([string]::IsNullOrWhiteSpace($Sql)) {
    Write-Output "NO_SQL_PROVIDED"
    exit 2
}

$projRef = "zbqhxqnkoggckxoyoqox"
$uri = "https://api.supabase.com/v1/projects/$projRef/database/query"
$headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }
$body = @{ query = $Sql } | ConvertTo-Json

try {
    $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body -TimeoutSec 120
    $resp | ConvertTo-Json -Depth 10
} catch {
    Write-Output "API_ERROR: $($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output "BODY: $($_.ErrorDetails.Message)" }
    exit 3
}
