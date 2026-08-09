# Reads the Supabase CLI access token from Windows Credential Manager and
# queries the Management API for the real deployed verify_jwt per function.

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class CredUtil {
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

# Try several candidate target names used by the Supabase CLI
$targets = @(
    "Supabase CLI:supabase",
    "supabase",
    "supabase-cli"
)

$token = ""
foreach ($t in $targets) {
    $r = [CredUtil]::Read($t)
    if (-not $r.StartsWith("ERROR_")) {
        $trimmed = $r.Trim()
        if ($trimmed.Length -gt 20) {
            Write-Output "FOUND_TARGET=$t"
            $token = $trimmed
            break
        }
    }
}

if ($token -eq "") {
    Write-Output "NO_TOKEN_FOUND"
    exit 1
}

Write-Output "TOKEN_LEN=$($token.Length)"
Write-Output "TOKEN_PREFIX=$($token.Substring(0, [Math]::Min(10, $token.Length)))"

$headers = @{
    "Authorization" = "Bearer $token"
}

$projRef = "zbqhxqnkoggckxoyoqox"
$uri = "https://api.supabase.com/v1/projects/$projRef/functions"

try {
    $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 60
    Write-Output "=== FUNCTIONS (real deployed verify_jwt) ==="
    foreach ($f in $resp) {
        $name = $f.slug
        $vjwt = $f.verify_jwt
        $ver = $f.version
        Write-Output ("{0,-30} verify_jwt={1,-6} version={2}" -f $name, $vjwt, $ver)
    }
} catch {
    Write-Output "API_ERROR: $($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output "BODY: $($_.ErrorDetails.Message)" }
    exit 2
}
