@echo off
setlocal EnableExtensions

cd /d "%~dp0"

if not exist "tools\ocr_service\start.bat" (
    echo [ERROR] Missing tools\ocr_service\start.bat
    echo Please make sure the OCR service files are included in this project.
    pause
    exit /b 1
)

call "tools\ocr_service\start.bat"
