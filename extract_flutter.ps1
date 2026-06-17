$zip = "C:\Users\ineast\AppData\Local\Temp\chocolatey\flutter\3.41.9\flutter_windows_3.41.9-stable.zip"
$dest = "C:\tools"

if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest | Out-Null
}

Write-Host "Flutter 압축 해제 중... (1~2분 소요)" -ForegroundColor Cyan
Expand-Archive -Path $zip -DestinationPath $dest -Force
Write-Host "완료!" -ForegroundColor Green

# PATH에 추가 (현재 사용자)
$flutterBin = "C:\tools\flutter\bin"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$flutterBin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$flutterBin", "User")
    Write-Host "PATH에 Flutter 추가 완료" -ForegroundColor Green
} else {
    Write-Host "이미 PATH에 있음" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Flutter 버전 확인:" -ForegroundColor Cyan
& "C:\tools\flutter\bin\flutter.bat" --version

Write-Host ""
Write-Host "새 CMD 창을 열고 setup_flutter.bat을 실행하세요!" -ForegroundColor Yellow
pause
