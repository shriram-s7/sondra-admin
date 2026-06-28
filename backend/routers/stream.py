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
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Streams the song content from Google Drive acting as an authenticated proxy.
    Supports Range requests for seeking compatibility in browsers.
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
        access_token = gdrive.get_access_token()
        url = f"https://www.googleapis.com/drive/v3/files/{song.gdrive_file_id}?alt=media"

        # Pass through the Range header if requested by the browser
        headers = {"Authorization": f"Bearer {access_token}"}
        client_range = request.headers.get("range")
        if client_range:
            headers["Range"] = client_range

        # Fetch file info from GDrive to get the actual filename and mimeType
        gdrive_name = ""
        gdrive_mime = ""
        async with httpx.AsyncClient() as meta_client:
            meta_res = await meta_client.get(
                f"https://www.googleapis.com/drive/v3/files/{song.gdrive_file_id}?fields=name,mimeType",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            if meta_res.status_code == 200:
                gdrive_info = meta_res.json()
                gdrive_name = gdrive_info.get("name", "").lower()
                gdrive_mime = gdrive_info.get("mimeType", "")

        # Determine exact content type
        content_type = "audio/mpeg"
        if gdrive_mime and "audio" in gdrive_mime:
            content_type = gdrive_mime
        elif gdrive_name.endswith(".flac"):
            content_type = "audio/flac"
        elif gdrive_name.endswith(".m4a") or gdrive_name.endswith(".mp4"):
            content_type = "audio/mp4"
        elif gdrive_name.endswith(".wav"):
            content_type = "audio/wav"

        # Create an async client and stream the response
        client = httpx.AsyncClient()
        response = await client.send(
            client.build_request("GET", url, headers=headers),
            stream=True
        )

        if response.status_code not in [200, 206]:
            await response.aclose()
            await client.aclose()
            raise HTTPException(
                status_code=response.status_code, 
                detail=f"Google Drive API error: {response.status_code}"
            )

        # Set up response headers
        resp_headers = {
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
        }
        if "content-range" in response.headers:
            resp_headers["Content-Range"] = response.headers["content-range"]
        if "content-length" in response.headers:
            resp_headers["Content-Length"] = response.headers["content-length"]

        async def stream_generator():
            try:
                async for chunk in response.aiter_bytes(chunk_size=1024*128):
                    yield chunk
            finally:
                await response.aclose()
                await client.aclose()

        return StreamingResponse(
            stream_generator(),
            status_code=response.status_code,
            media_type=content_type,
            headers=resp_headers
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
