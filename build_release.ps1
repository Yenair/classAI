# Reminder before building the release APK
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  TODO: UPDATE LIVE PAYSTACK KEY IN SUPABASE" -ForegroundColor Yellow
Write-Host "  supabase secrets set PAYSTACK_SECRET_KEY=sk_live_..." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to continue the build..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Build device-specific release APKs (one per CPU ABI) instead of a universal APK.
# This avoids shipping all three architectures in a single 460 MiB artifact.
# Distribute app-arm64-v8a-release.apk for modern Android phones.
Write-Host "Building per-ABI release APKs..." -ForegroundColor Cyan
flutter build apk --release --split-per-abi

# Also produce an Android App Bundle for Play Store distribution.
# Play will generate and serve the optimal ABI/device-specific APKs from this.
Write-Host "Building Android App Bundle..." -ForegroundColor Cyan
flutter build appbundle --release