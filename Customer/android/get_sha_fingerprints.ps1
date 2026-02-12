# PowerShell script to extract SHA-1 and SHA-256 from release keystore
# Run this from android/app directory

$keystorePath = "app\my-release-key.jks"
$alias = "my-key-alias"
$storepass = "071417"
$keypass = "071417"

Write-Host "Extracting SHA fingerprints from release keystore..." -ForegroundColor Cyan
Write-Host ""

# Get SHA-1
$sha1Output = & keytool -list -v -keystore $keystorePath -alias $alias -storepass $storepass -keypass $keypass 2>&1 | Select-String -Pattern "SHA1:" -Context 0,1

# Get SHA-256  
$sha256Output = & keytool -list -v -keystore $keystorePath -alias $alias -storepass $storepass -keypass $keypass 2>&1 | Select-String -Pattern "SHA256:" -Context 0,1

if ($sha1Output) {
    Write-Host "SHA-1 Fingerprint:" -ForegroundColor Green
    Write-Host $sha1Output -ForegroundColor White
    Write-Host ""
}

if ($sha256Output) {
    Write-Host "SHA-256 Fingerprint:" -ForegroundColor Green
    Write-Host $sha256Output -ForegroundColor White
    Write-Host ""
}

# Extract just the hash values (removing colons)
$sha1Hash = ($sha1Output -split "SHA1:")[1].Trim() -replace ":", "" -replace "`r`n", ""
$sha256Hash = ($sha256Output -split "SHA256:")[1].Trim() -replace ":", "" -replace "`r`n", ""

Write-Host "SHA-1 (no colons): $sha1Hash" -ForegroundColor Yellow
Write-Host "SHA-256 (no colons): $sha256Hash" -ForegroundColor Yellow
Write-Host ""
Write-Host "Add these to Firebase Console > Project Settings > Your App > SHA certificate fingerprints" -ForegroundColor Cyan
