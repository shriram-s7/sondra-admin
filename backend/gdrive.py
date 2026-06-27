import os
import io
import base64
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from dotenv import load_dotenv

# Mutagen parsing
from mutagen import File as MutagenFile
from mutagen.easyid3 import EasyID3
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4
from mutagen.flac import FLAC

load_dotenv()

SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))

def get_drive_service():
    """
    Returns an authenticated Google Drive API service client.
    Uses token.json if it exists and is valid, otherwise performs OAuth2 local server flow.
    """
    creds = None
    token_path = os.path.join(BACKEND_DIR, "token.json")
    
    # Load credentials.json path from env or use default
    creds_env = os.getenv("GDRIVE_OAUTH_CREDS", "credentials.json")
    if os.path.isabs(creds_env):
        creds_path = creds_env
    else:
        creds_path = os.path.join(BACKEND_DIR, creds_env)
        # Handle file name mismatch fallback automatically
        if not os.path.exists(creds_path):
            for name in ["credentials.json", "creds.json"]:
                p = os.path.join(BACKEND_DIR, name)
                if os.path.exists(p):
                    creds_path = p
                    break

    # 1. Try loading from GDRIVE_TOKEN_JSON environment variable first (for cloud services like Render)
    token_env = os.getenv("GDRIVE_TOKEN_JSON")
    if token_env:
        try:
            import json
            creds_info = json.loads(token_env)
            
            # Inject client_id and client_secret if missing, to allow token refresh on headless servers
            if "client_id" not in creds_info or "client_secret" not in creds_info:
                client_config = None
                creds_env_str = os.getenv("GDRIVE_CREDS_JSON")
                if creds_env_str:
                    try:
                        client_config = json.loads(creds_env_str)
                    except Exception:
                        pass
                if not client_config and os.path.exists(creds_path):
                    try:
                        with open(creds_path, "r") as f:
                            client_config = json.load(f)
                    except Exception:
                        pass
                
                if client_config:
                    key = "installed" if "installed" in client_config else "web"
                    if key in client_config:
                        creds_info["client_id"] = client_config[key]["client_id"]
                        creds_info["client_secret"] = client_config[key]["client_secret"]
            
            creds = Credentials.from_authorized_user_info(creds_info, SCOPES)
            print("Loaded Google OAuth credentials from GDRIVE_TOKEN_JSON environment variable.")
        except Exception as e:
            print(f"Error parsing GDRIVE_TOKEN_JSON from env: {e}")

    # 2. Fallback to loading token.json file
    if not creds and os.path.exists(token_path):
        try:
            # We also inject client_id and client_secret to local token.json if loaded to ensure refresh works locally
            with open(token_path, "r") as f:
                import json
                creds_info = json.load(f)
            
            if "client_id" not in creds_info or "client_secret" not in creds_info:
                client_config = None
                if os.path.exists(creds_path):
                    try:
                        with open(creds_path, "r") as f2:
                            client_config = json.load(f2)
                    except Exception:
                        pass
                if client_config:
                    key = "installed" if "installed" in client_config else "web"
                    if key in client_config:
                        creds_info["client_id"] = client_config[key]["client_id"]
                        creds_info["client_secret"] = client_config[key]["client_secret"]
            
            creds = Credentials.from_authorized_user_info(creds_info, SCOPES)
        except Exception as e:
            print(f"Error loading token.json: {e}")

    # 3. If no valid credentials, run Desktop flow or load client configs from env
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception as e:
                print(f"Error refreshing credentials: {e}")
                creds = None
                
        if not creds:
            # Check if we can load credentials configuration from environment variable
            creds_env_str = os.getenv("GDRIVE_CREDS_JSON")
            if creds_env_str:
                raise RuntimeError(
                    "Google Drive OAuth token has expired or is invalid, and could not be refreshed. "
                    "Please regenerate a fresh token.json locally (run start.bat) and update GDRIVE_TOKEN_JSON on Render."
                )
            else:
                if not os.path.exists(creds_path):
                    # Try fallback names if 'credentials.json' is configured but might be 'creds.json'
                    alternate_path = os.path.join(BACKEND_DIR, "creds.json")
                    if os.path.exists(alternate_path):
                        creds_path = alternate_path
                    else:
                        raise FileNotFoundError(
                            f"Google Drive credentials file not found at '{creds_path}'. "
                            "Please download Desktop client credentials JSON from Google Cloud Console, "
                            "save it in the backend folder, and configure GDRIVE_OAUTH_CREDS in your .env."
                        )
                
                flow = InstalledAppFlow.from_client_secrets_file(creds_path, SCOPES)
                # Starts local server and opens browser for desktop client authentication
                creds = flow.run_local_server(port=0)
            
            # Save token
            try:
                with open(token_path, "w") as token_file:
                    token_file.write(creds.to_json())
            except Exception as e:
                print(f"Could not save token.json file (read-only environment like Render): {e}")

    return build("drive", "v3", credentials=creds)


def get_access_token():
    """Retrieves current valid access token for proxy request usage."""
    # We call get_drive_service which refreshes the token.json if needed
    service = get_drive_service()
    return service._http.credentials.token


def list_playlist_folders(root_folder_id: str):
    """
    Returns a list of dictionaries containing folder information:
    [{"id": folder_gdrive_id, "name": folder_name}]
    Lists all folders directly inside the given root folder ID.
    """
    if not root_folder_id:
        return []
        
    # Programmatically extract the clean folder ID if a full URL was provided
    root_folder_id = root_folder_id.strip()
    if "drive.google.com" in root_folder_id:
        if "/folders/" in root_folder_id:
            root_folder_id = root_folder_id.split("/folders/")[-1]
        elif "/file/d/" in root_folder_id:
            root_folder_id = root_folder_id.split("/file/d/")[-1]
        root_folder_id = root_folder_id.split("?")[0].split("/")[0]
        
    service = get_drive_service()
    query = f"'{root_folder_id}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    
    folders = []
    page_token = None
    while True:
        response = service.files().list(
            q=query,
            spaces="drive",
            fields="nextPageToken, files(id, name)",
            pageToken=page_token
        ).execute()
        
        folders.extend(response.get("files", []))
        page_token = response.get("nextPageToken", None)
        if not page_token:
            break
            
    return [{"id": f["id"], "name": f["name"]} for f in folders]


def list_songs_in_folder(folder_id: str):
    """
    Returns a list of songs directly inside the folder:
    [{"id": file_gdrive_id, "name": filename, "mimeType": ..., "size": ...}]
    Filters for mp3, flac, and m4a files.
    """
    service = get_drive_service()
    query = f"'{folder_id}' in parents and trashed = false"
    
    files = []
    page_token = None
    while True:
        response = service.files().list(
            q=query,
            spaces="drive",
            fields="nextPageToken, files(id, name, mimeType, size)",
            pageToken=page_token
        ).execute()
        
        files.extend(response.get("files", []))
        page_token = response.get("nextPageToken", None)
        if not page_token:
            break
            
    audio_extensions = (".mp3", ".flac", ".m4a")
    songs = []
    for f in files:
        name = f.get("name", "")
        name_lower = name.lower()
        mime = f.get("mimeType", "")
        
        is_audio = (
            name_lower.endswith(audio_extensions) or
            mime.startswith("audio/") or
            (mime == "application/octet-stream" and name_lower.endswith(audio_extensions))
        )
        if is_audio:
            songs.append({
                "id": f["id"],
                "name": name,
                "mimeType": mime,
                "size": int(f.get("size", 0))
            })
            
    return songs


def get_stream_url(gdrive_file_id: str):
    """
    Returns a direct streamable URL for Google Drive media.
    Our proxy stream endpoint forwards requests to this API endpoint.
    """
    return f"https://www.googleapis.com/drive/v3/files/{gdrive_file_id}?alt=media"


def get_file_metadata(gdrive_file_id: str):
    """
    Downloads the file temporarily, reads tags with Mutagen:
    (title, artist, album, genre, duration_seconds, embedded cover art as base64 data URI),
    deletes the temp file, and returns the dict.
    Falls back to the filename as title if tag metadata is missing.
    """
    service = get_drive_service()
    
    # 1. Fetch file name first
    file_info = service.files().get(fileId=gdrive_file_id, fields="name").execute()
    filename = file_info.get("name", "Unknown Track")
    
    # Setup temp path
    temp_dir = os.path.join(BACKEND_DIR, "cache", "temp")
    os.makedirs(temp_dir, exist_ok=True)
    temp_path = os.path.join(temp_dir, f"metadata_{gdrive_file_id}.tmp")
    
    metadata = {
        "title": None,
        "artist": "Unknown Artist",
        "album": "Unknown Album",
        "genre": "Unknown",
        "duration_seconds": 0,
        "cover_url": None  # stores base64 image data URI
    }
    
    # 2. Download file
    try:
        request = service.files().get_media(fileId=gdrive_file_id)
        with io.FileIO(temp_path, "wb") as fh:
            downloader = MediaIoBaseDownload(fh, request)
            done = False
            while not done:
                _, done = downloader.next_chunk()
                
        # 3. Read tags with mutagen
        audio = MutagenFile(temp_path)
        if audio is not None:
            if audio.info:
                metadata["duration_seconds"] = int(audio.info.length)
                
            if hasattr(audio, "tags") and audio.tags:
                if isinstance(audio, MP3):
                    try:
                        easy_audio = EasyID3(temp_path)
                        metadata["title"] = easy_audio.get("title", [None])[0]
                        metadata["artist"] = easy_audio.get("artist", [None])[0]
                        metadata["album"] = easy_audio.get("album", [None])[0]
                        metadata["genre"] = easy_audio.get("genre", [None])[0]
                    except Exception:
                        pass
                    
                    # APIC cover frame extraction
                    for tag_name in audio.tags.keys():
                        if tag_name.startswith("APIC"):
                            apic = audio.tags[tag_name]
                            if apic.data:
                                b64 = base64.b64encode(apic.data).decode("utf-8")
                                metadata["cover_url"] = f"data:{apic.mime};base64,{b64}"
                            break
                            
                elif isinstance(audio, MP4):
                    tags = audio.tags
                    metadata["title"] = tags.get("\xa9nam", [None])[0]
                    metadata["artist"] = tags.get("\xa9ART", [None])[0]
                    metadata["album"] = tags.get("\xa9alb", [None])[0]
                    metadata["genre"] = tags.get("\xa9gen", [None])[0]
                    
                    if "covr" in tags:
                        covr = tags["covr"]
                        if isinstance(covr, list) and len(covr) > 0:
                            b64 = base64.b64encode(bytes(covr[0])).decode("utf-8")
                            # MP4 covers can be jpg/png. Default to jpeg if unknown.
                            metadata["cover_url"] = f"data:image/jpeg;base64,{b64}"
                            
                elif isinstance(audio, FLAC):
                    tags = audio.tags
                    metadata["title"] = tags.get("title", [None])[0]
                    metadata["artist"] = tags.get("artist", [None])[0]
                    metadata["album"] = tags.get("album", [None])[0]
                    metadata["genre"] = tags.get("genre", [None])[0]
                    
                    if audio.pictures:
                        pic = audio.pictures[0]
                        if pic.data:
                            b64 = base64.b64encode(pic.data).decode("utf-8")
                            metadata["cover_url"] = f"data:{pic.mime};base64,{b64}"
                            
                else:
                    tags = audio.tags
                    if hasattr(tags, "get"):
                        metadata["title"] = tags.get("title", [None])[0]
                        metadata["artist"] = tags.get("artist", [None])[0]
                        metadata["album"] = tags.get("album", [None])[0]
                        metadata["genre"] = tags.get("genre", [None])[0]

    except Exception as e:
        print(f"Error reading tags from GDrive file {gdrive_file_id}: {e}")
    finally:
        # Clean up temp file
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass

    # Clean text values
    for fld in ["title", "artist", "album", "genre"]:
        val = metadata[fld]
        if isinstance(val, list):
            metadata[fld] = str(val[0]) if val else None
        elif val is not None:
            metadata[fld] = str(val).strip()

    # Title fallback to filename without extension
    if not metadata["title"]:
        name_without_ext, _ = os.path.splitext(filename)
        if " - " in name_without_ext:
            parts = name_without_ext.split(" - ", 1)
            metadata["artist"] = parts[0].strip()
            metadata["title"] = parts[1].strip()
        else:
            metadata["title"] = name_without_ext.strip()
            
    # Ensure default values exist
    if not metadata["artist"]:
        metadata["artist"] = "Unknown Artist"
    if not metadata["album"]:
        metadata["album"] = "Unknown Album"
    if not metadata["genre"]:
        metadata["genre"] = "Unknown"

    return metadata


def get_direct_stream_url(gdrive_file_id: str) -> str:
    """
    Ensures the Google Drive file is temporarily accessible by anyone with the link
    and returns a direct streamable download link.
    """
    service = get_drive_service()
    try:
        # Check or create reader permission for "anyone"
        permission = {
            'type': 'anyone',
            'role': 'reader'
        }
        service.permissions().create(fileId=gdrive_file_id, body=permission).execute()
    except Exception as e:
        print(f"Error creating file sharing permission for {gdrive_file_id}: {e}")
    
    # Return the direct usercontent download URL format to bypass cross-origin redirect headers
    return f"https://drive.usercontent.google.com/download?id={gdrive_file_id}&export=download"
