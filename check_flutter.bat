@echo off
echo Flutter 설치 확인 중...
echo. > "%~dp0check_result.txt"
echo [PATH에서 flutter 검색] >> "%~dp0check_result.txt"
where flutter >> "%~dp0check_result.txt" 2>&1
echo. >> "%~dp0check_result.txt"
echo [C:\tools\flutter 폴더 확인] >> "%~dp0check_result.txt"
if exist "C:\tools\flutter\bin\flutter.bat" (
    echo 발견: C:\tools\flutter\bin\flutter.bat >> "%~dp0check_result.txt"
) else (
    echo 없음: C:\tools\flutter >> "%~dp0check_result.txt"
)
echo. >> "%~dp0check_result.txt"
echo [flutter 버전] >> "%~dp0check_result.txt"
flutter --version >> "%~dp0check_result.txt" 2>&1
echo. >> "%~dp0check_result.txt"
echo 완료. check_result.txt 를 확인하세요.
type "%~dp0check_result.txt"
pause
