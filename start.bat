@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo Starting Sondra Music Platform...
echo ====================================================

:: Force working directory to the folder containing this script, regardless of where it's launched
cd /d "%~dp0"
echo Working directory: %CD%

:: 1. Setup Python Virtual Environment (use system python only to create it)
if not exist "%~dp0backend\venv" (
    echo Creating virtual environment...
    python -m venv "%~dp0backend\venv"
    if errorlevel 1 (
        echo ERROR: Failed to create virtual environment. Is Python installed?
        pause
        exit /b 1
    )
)

:: Always use the venv python directly - do NOT rely on 'activate' since it doesn't work reliably in all launchers
set VENV_PYTHON=%~dp0backend\venv\Scripts\python.exe
set VENV_PIP=%~dp0backend\venv\Scripts\pip.exe

echo Installing python requirements...
"%VENV_PIP%" install -r "%~dp0backend\requirements.txt"

:: 2. Setup React Admin Frontend (only if static/index.html is missing)
if not exist "%~dp0backend\static\index.html" (
    echo Admin frontend static assets not found. Compiling admin panel...
    cd /d "%~dp0admin"
    
    if not exist "node_modules" (
        echo Installing node modules...
        call npm install
    )
    
    echo Building static assets...
    call npm run build
    
    echo Copying static files to backend/static...
    if not exist "%~dp0backend\static" mkdir "%~dp0backend\static"
    xcopy /y /e /q "dist\*" "%~dp0backend\static\"
    
    cd /d "%~dp0"
)

:: 3. Sync .env
echo Syncing root .env configuration to backend...
copy /y "%~dp0.env" "%~dp0backend\.env"

:: 4. Start FastAPI backend using venv python directly
echo Starting FastAPI backend...
echo ----------------------------------------------------
echo Open http://localhost:8000/admin in your browser
echo ----------------------------------------------------
cd /d "%~dp0backend"
"%VENV_PYTHON%" -m uvicorn main:app --host 0.0.0.0 --port 8000

pause
