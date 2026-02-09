# PowerShell script to check for plugin updates and 16KB alignment support
# This script helps identify which plugins may need updates

Write-Host "Checking Flutter plugin versions and 16KB alignment status..." -ForegroundColor Cyan
Write-Host ""

$pluginsToCheck = @(
    @{Name="flutter_image_compress"; CurrentVersion="^2.3.0"; HasNative=true; Priority="High"},
    @{Name="flutter_sound"; CurrentVersion="^9.28.0"; HasNative=true; Priority="High"},
    @{Name="audioplayers"; CurrentVersion="^6.5.1"; HasNative=true; Priority="High"},
    @{Name="video_player"; CurrentVersion="^2.10.0"; HasNative=true; Priority="High"},
    @{Name="moor_flutter"; CurrentVersion=""; HasNative=true; Priority="Medium"},
    @{Name="google_maps_flutter"; CurrentVersion="^2.5.0"; HasNative=true; Priority="Medium"},
    @{Name="flutter_facebook_auth"; CurrentVersion="^7.0.1"; HasNative=true; Priority="Low"},
    @{Name="google_sign_in"; CurrentVersion="^6.2.1"; HasNative=true; Priority="Low"}
)

Write-Host "Plugins with Native Code (may have 16KB alignment issues):" -ForegroundColor Yellow
Write-Host "=" * 80

foreach ($plugin in $pluginsToCheck) {
    $priorityColor = switch ($plugin.Priority) {
        "High" { "Red" }
        "Medium" { "Yellow" }
        "Low" { "Green" }
        default { "White" }
    }
    
    Write-Host "`nPlugin: $($plugin.Name)" -ForegroundColor White
    Write-Host "  Current Version: $($plugin.CurrentVersion)" -ForegroundColor Gray
    Write-Host "  Priority: $($plugin.Priority)" -ForegroundColor $priorityColor
    Write-Host "  Has Native Code: $($plugin.HasNative)" -ForegroundColor Gray
    Write-Host "  Action Required:" -ForegroundColor Cyan
    Write-Host "    1. Visit: https://pub.dev/packages/$($plugin.Name)" -ForegroundColor Yellow
    Write-Host "    2. Check latest version and changelog" -ForegroundColor Yellow
    Write-Host "    3. Search GitHub issues for '16KB' or 'page size'" -ForegroundColor Yellow
    Write-Host "    4. Update if newer version supports 16KB alignment" -ForegroundColor Yellow
}

Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "Recommended Actions:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. HIGH PRIORITY - Check these first:" -ForegroundColor Red
Write-Host "   - flutter_image_compress" -ForegroundColor White
Write-Host "   - flutter_sound" -ForegroundColor White
Write-Host "   - audioplayers" -ForegroundColor White
Write-Host "   - video_player" -ForegroundColor White
Write-Host ""
Write-Host "2. After building AAB, use Android Studio APK Analyzer to identify" -ForegroundColor Yellow
Write-Host "   which specific .so files have 4KB alignment" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. For each problematic plugin:" -ForegroundColor Yellow
Write-Host "   a. Check pub.dev for latest version" -ForegroundColor White
Write-Host "   b. Review GitHub issues/PRs for 16KB support" -ForegroundColor White
Write-Host "   c. Update or replace as needed" -ForegroundColor White
Write-Host ""
Write-Host "4. Alternative solutions:" -ForegroundColor Yellow
Write-Host "   - Replace with pure Dart/Java/Kotlin alternatives" -ForegroundColor White
Write-Host "   - Use platform channels with native Android APIs" -ForegroundColor White
Write-Host "   - Remove if functionality is not essential" -ForegroundColor White
Write-Host ""
Write-Host "Check complete! Review the guide in 16KB_ALIGNMENT_FIX_GUIDE.md" -ForegroundColor Green

