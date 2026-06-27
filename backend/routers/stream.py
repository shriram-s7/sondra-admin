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
    db: Session = Depends(get_db),
    admin: str = Depends(verify_token)
):
    """
    Generates and returns a direct Google Drive download URL.
    Updates permissions on Google Drive so the file is readable by 'anyone'.
    """
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    try:
        direct_url = gdrive.get_direct_stream_url(song.gdrive_file_id)
        return {"stream_url": direct_url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate stream link: {str(e)}")

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
