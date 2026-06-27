import io
import googleapiclient.http
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
import httpx
from database import get_db
import gdrive
import models
from jose import jwt
from routers.auth import JWT_SECRET, ALGORITHM, ADMIN_USERNAME
from pydantic import BaseModel
from datetime import datetime
from typing import Optional

router = APIRouter(prefix="/stream", tags=["Streaming"])

class ListenLogRequest(BaseModel):
    position_seconds: int

def verify_token(request: Request):
    """Verifies token from either Authorization header or 'token' query parameter."""
    token = None
    auth_header = request.headers.get("authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ")[1]
    else:
        token = request.query_params.get("token")

    if not token:
        raise HTTPException(status_code=401, detail="Authentication token required")

    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None or username != ADMIN_USERNAME:
            raise HTTPException(status_code=401, detail="Invalid token username")
        return username
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

@router.get("/{song_id}")
def stream_song(
    song_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: str = Depends(verify_token)
):
    """
    Returns the backend proxy stream URL for a given song ID in a JSON payload.
    """
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    # Get the JWT token from headers or query params
    token = None
    auth_header = request.headers.get("authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ")[1]
    else:
        token = request.query_params.get("token")

    # Construct the proxy URL using Render host domain if available
    host = request.headers.get("host", "localhost:8000")
    scheme = "https" if "render.com" in host or request.headers.get("x-forwarded-proto") == "https" else "http"
    proxy_url = f"{scheme}://{host}/api/stream/{song.id}/proxy?token={token}"

    return {"stream_url": proxy_url}

@router.get("/{song_id}/proxy")
async def stream_song_proxy(
    song_id: int,
    token: str,
    db: Session = Depends(get_db)
):
    """
    Streams the song content from Google Drive acting as an authenticated proxy.
    Validates token from the query parameters.
    """
    try:
        # Validate JWT token
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None or username != ADMIN_USERNAME:
            raise HTTPException(status_code=401, detail="Invalid token")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    try:
        drive_service = gdrive.get_drive_service()
        request = drive_service.files().get_media(fileId=song.gdrive_file_id)

        # Determine content type based on file extension
        content_type = "audio/mpeg"
        if song.filename and song.filename.lower().endswith(".flac"):
            content_type = "audio/flac"
        elif song.filename and (song.filename.lower().endswith(".m4a") or song.filename.lower().endswith(".mp4")):
            content_type = "audio/mp4"
        elif song.filename and song.filename.lower().endswith(".wav"):
            content_type = "audio/wav"

        def iterfile():
            fh = io.BytesIO()
            downloader = googleapiclient.http.MediaIoBaseDownload(fh, request, chunksize=1024*256)
            done = False
            last_position = 0
            while not done:
                _, done = downloader.next_chunk()
                fh.seek(last_position)
                chunk = fh.read()
                last_position = fh.tell()
                yield chunk

        return StreamingResponse(
            iterfile(),
            media_type=content_type,
            headers={"Accept-Ranges": "bytes", "Cache-Control": "no-cache"}
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Proxy streaming failed: {str(e)}")

@router.post("/{song_id}/listen")
def record_listen(
    song_id: int,
    log_data: ListenLogRequest,
    db: Session = Depends(get_db),
    admin: str = Depends(verify_token)
):
    """Records a listening session/position milestone in history."""
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    history_entry = models.ListenHistory(
        song_id=song.id,
        position_seconds=log_data.position_seconds,
        listened_at=datetime.utcnow()
    )
    db.add(history_entry)
    db.commit()
    db.refresh(history_entry)

    return {"message": "Listen event logged.", "id": history_entry.id}
