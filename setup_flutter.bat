@echo off
cd /d "C:\Users\ineast\Claude\Projects\Ping"

echo Step 1: flutter create
flutter create . --org com.ping --project-name ping
if %ERRORLEVEL% neq 0 (
    echo ERROR: flutter create failed
    pause
    exit /b 1
)

echo Step 2: supabase_flutter
flutter pub add supabase_flutter

echo Step 3: table_calendar
flutter pub add table_calendar

echo Step 4: provider
flutter pub add provider

echo Step 5: intl
flutter pub add intl

echo Done!
if exist "lib\main.dart" (
    echo lib\main.dart OK
) else (
    echo lib\main.dart NOT FOUND
)
pause
