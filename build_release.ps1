# Reminder before building the release APK
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  TODO: UPDATE LIVE PAYSTACK KEY IN SUPABASE" -ForegroundColor Yellow
Write-Host "  supabase secrets set PAYSTACK_SECRET_KEY=sk_live_..." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to continue the build..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# (Your actual build command will go below this line)
flutter build apk --release
# or whatever your full build command is