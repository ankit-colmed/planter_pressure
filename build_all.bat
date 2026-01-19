@echo off
REM ==============================================================================
REM Planter Pressure OPTIMIZED - Build Script
REM ==============================================================================

setlocal EnableDelayedExpansion

echo.
echo ============================================================
echo Planter Pressure OPTIMIZED - Build
echo ============================================================
echo.

set PROJECT_ROOT=%~dp0
cd /d "%PROJECT_ROOT%"

set PYTHON_HOME=C:\Users\adit\AppData\Local\Programs\Python\Python312

REM Check Python
if not exist "%PYTHON_HOME%\python.exe" (
    echo ERROR: Python not found at %PYTHON_HOME%
    exit /b 1
)
echo Python: %PYTHON_HOME%

REM Build native engine
echo.
echo [1/4] Building native engine...
cd native_engine\windows
if not exist build mkdir build
cd build

cmake -G "Visual Studio 17 2022" -A x64 -DPython3_ROOT_DIR="%PYTHON_HOME%" ..
if %ERRORLEVEL% neq 0 exit /b 1

cmake --build . --config Release
if %ERRORLEVEL% neq 0 exit /b 1

cd /d "%PROJECT_ROOT%"

REM Build Flutter
echo.
echo [2/4] Building Flutter app...
call flutter pub get
call flutter build windows --release
if %ERRORLEVEL% neq 0 exit /b 1

REM Copy DLLs
echo.
echo [3/4] Copying DLLs...
set OUT=build\windows\x64\runner\Release

copy /Y "native_engine\windows\build\bin\Release\image_processor_engine.dll" "%OUT%\"
copy /Y "native_engine\windows\build\bin\Release\app_modules.zip" "%OUT%\"
copy /Y "%PYTHON_HOME%\python312.dll" "%OUT%\"
copy /Y "%PYTHON_HOME%\python3.dll" "%OUT%\"

REM Copy Python script (REMOVED - Embedded in app_modules.zip)
echo.
echo [4/4] Copying Python script... SKIPPED (Embedded)
REM if not exist "%OUT%\data\flutter_assets\assets\python" mkdir "%OUT%\data\flutter_assets\assets\python"
REM copy /Y "assets\python\process.py" "%OUT%\data\flutter_assets\assets\python\"

echo.
echo ============================================================
echo BUILD COMPLETE!
echo ============================================================
echo.
echo Output: %PROJECT_ROOT%%OUT%
echo.
echo Run: flutter run -d windows
echo.

pause
