@echo off
echo =============================================
echo  개발 도구 설치 스크립트 (Windows)
echo =============================================
echo.

echo [1/3] Node.js & npm 버전 확인...
node --version
npm --version
echo.

echo [2/3] Bun 설치 중...
npm install -g bun
bun --version
echo.

echo [3/3] Supabase CLI 설치 중...
npm install -g supabase
supabase --version
echo.

echo =============================================
echo  설치 완료! 각 버전이 출력되었으면 성공입니다.
echo =============================================
pause
