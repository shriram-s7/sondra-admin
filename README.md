# Sondra: Personal Music Streaming Platform

Sondra is a private, lightweight, and high-fidelity music streaming system. It streams your personal audio catalog stored in Google Drive directly to client devices through a secure FastAPI proxy backend and an elegant React-based admin dashboard.

---

## Architecture Overview
- **Backend:** Python FastAPI + SQLAlchemy (SQLite database).
- **File Storage:** Google Drive (Read-only proxy streaming).
- **Admin Dashboard:** React + Vite (Served statically by FastAPI at `/admin`).
- **Clients:** Desktop browser admin panel and mobile/desktop apps.

---

## Setup Guide (One Time)

Follow these steps to authorize Google Drive access and boot the application:

### 1. Configure Google Cloud Console Credentials
1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a **New Project**.
3. Search for and enable the **Google Drive API** in your project.
4. Navigate to the **Credentials** screen:
   - Click **Create Credentials** → select **OAuth client ID**.
   - If prompted, configure the OAuth Consent Screen (select **External**, configure your user details, and add the `.../auth/drive.readonly` scopes).
   - Set the Application Type to **Desktop app**.
   - Download the generated JSON credentials file and rename it to `credentials.json`.
5. Put `credentials.json` into the `sondra/backend/` directory.

### 2. Configure Environment Variables
1. Duplicate the `.env.example` file in the project folder and name it `.env`.
2. Open `.env` and configure:
   - `ADMIN_USERNAME`: Admin login username.
   - `ADMIN_PASSWORD`: Admin login password (customizable from Settings).
   - `JWT_SECRET`: A secure random secret key.
   - `GDRIVE_ROOT_FOLDER_ID`: The long ID from your "MUSIC ALL" Google Drive folder URL (e.g. `drive.google.com/drive/u/0/folders/GDRIVE_ROOT_FOLDER_ID`).
   - `SYNC_INTERVAL_SECONDS`: Background directory synchronization check frequency (defaults to `30` seconds).

### 3. Launch the Server & Authorize
1. Double-click `start.bat` (on Windows) or run `./start.sh` (on Linux/macOS) in your terminal.
2. During the first startup, a browser window will automatically open asking you to sign in with your Google Account to authorize Google Drive read access.
3. Grant authorization. A `token.json` file will be created inside the `sondra/backend/` directory to cache your credentials securely.
4. Open **[http://localhost:8000/admin/](http://localhost:8000/admin/)** in your web browser.
5. Log in with your configured admin credentials.

---

## Daily Use
- **Manage Playlists & Songs:**
  - Manually upload song files (`.mp3`, `.flac`, `.m4a`, `.wav`) to subfolders inside the `MUSIC ALL` Google Drive folder.
  - Each subfolder acts as a **Playlist** inside Sondra.
  - The backend sync service scans your folders periodically (every 30s) and downloads/extracts track tags and base64 cover art.
  - Any connected apps or browser tabs receive Server-Sent Events (SSE) updates and refresh their UI dynamically on completed syncs.

---

## Deploy to Render (Backend API)

You can deploy the backend to Render's free tier. Since SQLite files reset on redeploys, Sondra automatically runs a full library synchronization on startup so the database is rebuilt from your Google Drive (which remains the single source of truth).

### 1. Retrieve JSON String Configurations
To deploy file-less, you need to copy the JSON strings of your Google credentials into Render environment variables:
1. Open `sondra/backend/credentials.json` (or `creds.json`) and copy its **entire text content** (the raw client secrets JSON string).
2. Open `sondra/backend/token.json` and copy its **entire text content** (the OAuth access token JSON string generated after your local login).

### 2. Configure Render Web Service
1. Create a new Web Service on Render, connect your Git repository, and select **Python** as the environment.
2. Render will automatically parse `render.yaml` if you choose "Blueprint" deployment, or you can create it manually using these details:
   - **Build Command:** `pip install -r backend/requirements.txt`
   - **Start Command:** `cd backend && uvicorn main:app --host 0.0.0.0 --port $PORT`
3. Add the following Environment Variables in the Render settings page:
   - `ADMIN_USERNAME`: Your custom login username (e.g. `shriram`).
   - `ADMIN_PASSWORD`: Your custom login password.
   - `JWT_SECRET`: Your custom encryption key.
   - `GDRIVE_ROOT_FOLDER_ID`: Your Google Drive folder URL or ID.
   - `GDRIVE_CREDS_JSON`: (Paste the entire content of `credentials.json` copied in Step 1).
   - `GDRIVE_TOKEN_JSON`: (Paste the entire content of `token.json` copied in Step 1).
   - `CORS_ORIGINS`: Your Vercel admin site URL (e.g., `https://sondra-admin.vercel.app`).
   - `SYNC_INTERVAL_SECONDS`: `60`

---

## Deploy to Vercel (Admin Frontend)

You can deploy the React admin dashboard to Vercel separately for fast static loading.

1. Connect your repository to Vercel.
2. Configure project settings:
   - **Root Directory:** `admin`
   - **Build Command:** `npm run build`
   - **Output Directory:** `dist`
3. Set the following environment variable:
   - `VITE_API_URL`: The URL of your Render backend API (e.g., `https://sondra-backend-cxkc.onrender.com`).
4. Vercel will build and serve your app. Vercel routes are pre-configured to fallback to SPA indexing using the [vercel.json](file:///e:/PROJECT%20SONDRA/sondra/admin/vercel.json) settings.

---

## Keep Backend Awake (Free)

To prevent your Render free tier instance from spinning down and sleeping:
1. Go to [UptimeRobot](https://uptimerobot.com/) and create a free account.
2. Click **Add New Monitor**.
3. Select **Monitor Type:** `HTTP(s)`
4. Set **Friendly Name:** `Sondra Backend`
5. Set **URL (or IP):** `https://your-render-url.onrender.com/health` (replace with your actual Render backend URL).
6. Set **Monitoring Interval:** Every `14 minutes`.
7. Save. This will ping your API periodically, keeping the container active.

---

## Build Client Applications

First, ensure you have navigated to the app directory:
```bash
cd sondra/app
```

### 1. Build Android APK
1. Run the compilation command:
   ```bash
   flutter build apk --release
   ```
2. The compiled APK is saved at:
   `app/build/app/outputs/flutter-apk/app-release.apk`
3. Transfer `app-release.apk` to your phone and install it.
4. Open the app, type in your server URL (e.g., `https://sondra-backend-cxkc.onrender.com`), log in with your admin credentials, and listen to music!

### 2. Build Windows Executable & Installer
1. Run the Windows release compile command:
   ```bash
   flutter build windows --release
   ```
2. The standalone output directory is created at:
   `app/build/windows/x64/runner/Release/`
3. To package this bundle into a single self-contained `.exe` setup installer:
   - Open **Inno Setup** compiler on Windows.
   - Open the compiler script at: [inno_setup.iss](file:///e:/PROJECT%20SONDRA/sondra/app/windows/inno_setup.iss).
   - Click **Compile** (or press `Ctrl+F9`).
   - The standalone installer `SondraSetup.exe` will be built inside:
     `app/build/windows/installer/SondraSetup.exe`
