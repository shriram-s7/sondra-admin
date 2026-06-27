#!/bin/bash
set -e

echo "===================================================="
echo "Starting Sondra Music Platform..."
echo "===================================================="

# Get the script folder path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# 1. Setup Python Virtual Environment
if [ ! -d "backend/venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv backend/venv
fi

echo "Activating virtual environment..."
source backend/venv/bin/activate

echo "Installing python requirements..."
pip install -r backend/requirements.txt

# 2. Setup React Admin Frontend
if [ ! -f "backend/static/index.html" ]; then
    echo "Admin frontend static assets not found. Compiling admin panel..."
    cd admin
    if [ ! -d "node_modules" ]; then
        echo "Installing node modules..."
        npm install
    fi
    echo "Building static assets..."
    npm run build
    
    echo "Copying static files to backend/static..."
    mkdir -p ../backend/static
    cp -r dist/* ../backend/static/
    cd ..
fi

# 3. Launch FastAPI Server
echo "Syncing root .env configuration to backend..."
cp -f "$DIR/.env" "$DIR/backend/.env"

echo "Starting FastAPI backend..."
echo "----------------------------------------------------"
echo "Open http://localhost:8000/admin in your browser"
echo "----------------------------------------------------"
cd backend
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
