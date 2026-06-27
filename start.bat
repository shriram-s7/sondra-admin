@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo Starting Sondra Music Platform...
echo ====================================================

cd %~dp0

:: 1. Setup Python Virtual Environment
if not exist backend\venv (
    echo Creating virtual environment...
    python -m venv backend\venv
)

echo Activating virtual environment...
call backend\venv\Scripts\activate

echo Installing python requirements...
pip install -r backend\requirements.txt

:: 2. Setup React Admin Frontend
if not exist backend\static\index.html (
    echo Admin frontend static assets not found. Compiling admin panel...
    cd admin
    if not exist node_modules (
        echo Installing node modules...
        call npm install
    )
    echo Building static assets...
    call npm run build
    
    echo Copying static files to backend/static...
    if not exist ..\backend\static mkdir ..\backend\static
    xcopy /y /e dist\* ..\backend\static\
    cd ..
)

echo Syncing root .env configuration to backend...
copy /y "%~dp0.env" "%~dp0backend\.env"

echo Starting FastAPI backend...
echo ----------------------------------------------------
echo Open http://localhost:8000/admin in your browser
echo ----------------------------------------------------
cd backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000

pause
