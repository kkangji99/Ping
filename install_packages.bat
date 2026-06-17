@echo off
cd /d "C:\Users\ineast\Claude\Projects\Ping"

echo Installing supabase_flutter...
flutter pub add supabase_flutter

echo Installing table_calendar...
flutter pub add table_calendar

echo Installing provider...
flutter pub add provider

echo Installing intl...
flutter pub add intl

echo All packages installed!
flutter pub get
pause
