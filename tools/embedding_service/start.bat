@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title MindTrace Embedding Service

cd /d "%~dp0"

echo ========================================
echo   MindTrace Embedding Service
echo   BGE embeddings, OpenAI-compatible API
echo ========================================
echo.

echo [1/5] Checking Python...
rem The python.exe in WindowsApps is a Store redirector, not a real interpreter.
set "PY_EXE="
set "PY_LAUNCHER="
for /f "delims=" %%p in ('python -c "import sys;print(sys.executable)" 2^>nul') do set "PY_EXE=%%p"
if not defined PY_EXE goto :try_py_launcher
echo !PY_EXE! | findstr /I "WindowsApps" >nul
if errorlevel 1 set "PY_LAUNCHER=python"
if defined PY_LAUNCHER goto :python_ok

:try_py_launcher
py -3 -c "import sys" >nul 2>&1
if not errorlevel 1 set "PY_LAUNCHER=py -3"
if defined PY_LAUNCHER goto :python_ok

:no_python
echo [ERROR] Python 3.10+ was not found.
echo.
echo   Install it with one of these, then run this script again:
echo     winget install --id Python.Python.3.12 -e
echo     or download from https://www.python.org/downloads/
echo       and check "Add python.exe to PATH" during setup.
echo.
echo   If python.exe is shadowed by the Microsoft Store alias, turn the alias off:
echo     Settings - Apps - Advanced app settings - App execution aliases
pause
exit /b 1

:python_ok
for /f "tokens=*" %%v in ('%PY_LAUNCHER% --version 2^>^&1') do set PYTHON_VERSION=%%v
echo       !PYTHON_VERSION!  (launcher: !PY_LAUNCHER!)

echo.
echo [2/5] Checking port 8001...
set PORT_BUSY=
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /R /C:":8001 .*LISTENING"') do (
    set PORT_BUSY=%%p
)
if defined PORT_BUSY (
    echo [ERROR] Port 8001 is already used by process !PORT_BUSY!.
    echo Close the old embedding service, then run this script again.
    pause
    exit /b 1
)
echo       Port 8001 is available.

echo.
echo [3/5] Preparing virtual environment...
if not exist ".venv\Scripts\python.exe" (
    %PY_LAUNCHER% -m venv .venv
    if errorlevel 1 (
        echo [ERROR] Could not create the virtual environment.
        pause
        exit /b 1
    )
)
set PY=.venv\Scripts\python.exe
echo       !PY!

echo.
echo [4/5] Checking dependencies (first run installs, may take a few minutes)...
"%PY%" -c "import torch" >nul 2>&1
if errorlevel 1 (
    echo       Installing CPU build of torch...
    "%PY%" -m pip install --upgrade pip
    "%PY%" -m pip install torch --index-url https://download.pytorch.org/whl/cpu
    if errorlevel 1 (
        echo [ERROR] torch installation failed.
        pause
        exit /b 1
    )
)
"%PY%" -c "import fastapi, uvicorn, sentence_transformers" >nul 2>&1
if errorlevel 1 (
    echo       Installing service dependencies...
    "%PY%" -m pip install -r requirements.txt
    if errorlevel 1 (
        echo [ERROR] Dependency installation failed.
        pause
        exit /b 1
    )
)

echo.
echo [5/5] Starting service...
echo       First start downloads the model (about 1.3GB). Keep this window open.
echo.

rem Keep this line for a faster download in mainland China; delete it if not needed.
set HF_ENDPOINT=https://hf-mirror.com
rem Make Python print UTF-8 so the console does not show garbled Chinese.
set PYTHONIOENCODING=utf-8
rem Embedding model. bge-m3 is stronger than bge-large-zh-v1.5 on dense math corpora.
rem The app's embedding model field must match this value, otherwise vectors are tagged
rem with the old model and will not be rebuilt.
set MT_EMBED_MODEL=BAAI/bge-m3

"%PY%" server.py

pause
