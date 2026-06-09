# build_foss_release.ps1
# This script builds the FOSS version of the APK locally.
# It applies the same changes that F-Droid does during the build, compiles the APK, and then reverts the changes.

Write-Host "Preparing FOSS build environment..." -ForegroundColor Green

# 1. Back up files that will be modified
Copy-Item pubspec.yaml pubspec.yaml.bak
Copy-Item lib/Services/google_drive_sync_service.dart lib/Services/google_drive_sync_service.dart.bak
Copy-Item android/app/build.gradle.kts android/app/build.gradle.kts.bak
Copy-Item android/settings.gradle.kts android/settings.gradle.kts.bak

# 2. Remove jniLibs if present
if (Test-Path android/app/src/main/jniLibs) {
    Remove-Item -Recurse -Force android/app/src/main/jniLibs
}

# 3. Modify pubspec.yaml (remove google_sign_in and extension_google_sign_in_as_googleapis_auth)
(Get-Content pubspec.yaml) | Where-Object { 
    $_ -notmatch 'google_sign_in' -and $_ -notmatch 'extension_google_sign_in_as_googleapis_auth' 
} | Set-Content pubspec.yaml

# 4. Copy FOSS sync service stub
Copy-Item lib/Services/google_drive_sync_service_foss.dart lib/Services/google_drive_sync_service.dart -Force

# 5. Modify android/app/build.gradle.kts and android/settings.gradle.kts (remove google-services plugin)
(Get-Content android/app/build.gradle.kts) | Where-Object { 
    $_ -notmatch 'com.google.gms.google-services' 
} | Set-Content android/app/build.gradle.kts

(Get-Content android/settings.gradle.kts) | Where-Object { 
    $_ -notmatch 'com.google.gms.google-services' 
} | Set-Content android/settings.gradle.kts

# 6. Build the APK
Write-Host "Running Flutter build..." -ForegroundColor Green
flutter clean
flutter pub get
flutter build apk --release

# 7. Copy output to a separate directory
$version = (Select-String -Path pubspec.yaml.bak -Pattern '^version:').Line.Split(' ')[1].Split('+')[0]
$outputDir = "build/foss-release"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}
Copy-Item build/app/outputs/flutter-apk/app-release.apk "$outputDir/Bifrost-foss-v$version.apk" -Force

Write-Host "FOSS APK build complete: $outputDir/Bifrost-foss-v$version.apk" -ForegroundColor Green

# 8. Restore backed up files
Write-Host "Restoring files..." -ForegroundColor Green
Move-Item pubspec.yaml.bak pubspec.yaml -Force
Move-Item lib/Services/google_drive_sync_service.dart.bak lib/Services/google_drive_sync_service.dart -Force
Move-Item android/app/build.gradle.kts.bak android/app/build.gradle.kts -Force
Move-Item android/settings.gradle.kts.bak android/settings.gradle.kts -Force

Write-Host "FOSS Build Script Finished." -ForegroundColor Green
