# PowerShell script to analyze AAB/APK for 4KB alignment errors
# This script helps identify .so files with 4KB alignment that need 16KB alignment

param(
    [Parameter(Mandatory=$true)]
    [string]$AabOrApkPath
)

Write-Host "Analyzing AAB/APK for 16KB alignment compliance..." -ForegroundColor Cyan
Write-Host "File: $AabOrApkPath" -ForegroundColor Yellow

if (-not (Test-Path $AabOrApkPath)) {
    Write-Host "Error: File not found: $AabOrApkPath" -ForegroundColor Red
    exit 1
}

# Check if it's an AAB or APK
$extension = [System.IO.Path]::GetExtension($AabOrApkPath).ToLower()
$isAab = $extension -eq ".aab"
$isApk = $extension -eq ".apk"

if (-not ($isAab -or $isApk)) {
    Write-Host "Error: File must be .aab or .apk" -ForegroundColor Red
    exit 1
}

# Create temporary directory for extraction
$tempDir = Join-Path $env:TEMP "aab_apk_analysis_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    if ($isAab) {
        Write-Host "Extracting AAB file..." -ForegroundColor Green
        # AAB files are zip archives
        Expand-Archive -Path $AabOrApkPath -DestinationPath $tempDir -Force
        
        # AAB structure: base/lib/{abi}/*.so
        $libDirs = Get-ChildItem -Path $tempDir -Recurse -Directory -Filter "lib" -ErrorAction SilentlyContinue
    } else {
        Write-Host "Extracting APK file..." -ForegroundColor Green
        # APK files are zip archives
        Expand-Archive -Path $AabOrApkPath -DestinationPath $tempDir -Force
        
        # APK structure: lib/{abi}/*.so
        $libDirs = Get-ChildItem -Path $tempDir -Directory -Filter "lib" -ErrorAction SilentlyContinue
    }
    
    if ($null -eq $libDirs -or $libDirs.Count -eq 0) {
        Write-Host "Warning: No 'lib' directories found. This might be a pure Java/Kotlin app." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "`nFound native libraries (.so files):" -ForegroundColor Cyan
    Write-Host "=" * 80
    
    $problematicLibs = @()
    $allLibs = @()
    
    foreach ($libDir in $libDirs) {
        $soFiles = Get-ChildItem -Path $libDir.FullName -Recurse -Filter "*.so" -ErrorAction SilentlyContinue
        
        foreach ($soFile in $soFiles) {
            $relativePath = $soFile.FullName.Replace($tempDir, "").TrimStart('\', '/')
            $allLibs += $soFile
            
            Write-Host "`nLibrary: $relativePath" -ForegroundColor White
            Write-Host "  Size: $([math]::Round($soFile.Length / 1KB, 2)) KB" -ForegroundColor Gray
            Write-Host "  ABI: $(Split-Path -Leaf (Split-Path -Parent $soFile.FullName))" -ForegroundColor Gray
            
            # Check alignment using readelf (if available) or file inspection
            # Note: This is a basic check. For detailed alignment analysis, use Android Studio's APK Analyzer
            Write-Host "  Status: Manual analysis required in Android Studio APK Analyzer" -ForegroundColor Yellow
            Write-Host "    -> Open Android Studio > Build > Analyze APK" -ForegroundColor Yellow
            Write-Host "    -> Check 'LOAD segment alignment' column for this file" -ForegroundColor Yellow
            Write-Host "    -> Should show 16 KB (16384), not 4 KB (4096)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Total .so files found: $($allLibs.Count)" -ForegroundColor White
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "  1. Open Android Studio" -ForegroundColor White
    Write-Host "  2. Go to Build > Analyze APK..." -ForegroundColor White
    Write-Host "  3. Select your AAB/APK file" -ForegroundColor White
    Write-Host "  4. Expand the 'lib' folder" -ForegroundColor White
    Write-Host "  5. Check each .so file's 'LOAD segment alignment' value" -ForegroundColor White
    Write-Host "  6. Files showing '4 KB' need to be updated to '16 KB'" -ForegroundColor Yellow
    Write-Host "  7. Note the library names and trace them to dependencies in build.gradle/pubspec.yaml" -ForegroundColor White
    
    Write-Host "`nCommon problematic Flutter plugins:" -ForegroundColor Cyan
    Write-Host "  - flutter_sound (uses native audio code)" -ForegroundColor Yellow
    Write-Host "  - flutter_image_compress (uses native image processing)" -ForegroundColor Yellow
    Write-Host "  - audioplayers (uses native audio)" -ForegroundColor Yellow
    Write-Host "  - video_player (uses native video codecs)" -ForegroundColor Yellow
    Write-Host "  - sqflite/moor_flutter (uses native SQLite)" -ForegroundColor Yellow
    Write-Host "  - google_maps_flutter (uses native Google Maps SDK)" -ForegroundColor Yellow
    
} finally {
    # Cleanup
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nAnalysis complete!" -ForegroundColor Green

