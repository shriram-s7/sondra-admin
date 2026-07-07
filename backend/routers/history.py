from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, joinedload
from datetime import datetime, time
from database import get_db
from routers.auth import get_current_admin
import models
from pydantic import BaseModel, validator
from typing import List, Optional

router = APIRouter(prefix="/history", tags=["Listen History"])

# Request Pydantic Schema
class HistoryLogRequest(BaseModel):
    song_id: int
    position_seconds: int

# Song response schema inside history
class SongBriefResponse(BaseModel):
    id: int
    gdrive_file_id: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    genre: Optional[str] = None
    duration_seconds: int = 0
    cover_url: Optional[str] = None
    playlist_id: Optional[int] = None

    @validator("cover_url", pre=True, always=True)
    def resolve_cover_url(cls, v, values):
        song_id = values.get("id")
        if v and song_id:
            return f"/api/songs/{song_id}/cover"
        return None

    class Config:
        orm_mode = True

# Response Pydantic Schema
class HistoryResponse(BaseModel):
    id: int
    song_id: int
    listened_at: datetime
    position_seconds: int
    song: SongBriefResponse

    class Config:
        orm_mode = True

@router.post("", response_model=HistoryResponse)
def log_listen_history(
    payload: HistoryLogRequest,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """
    Logs or updates listening history for a song.
    Upserts by matching the song_id and the current date (same day, UTC).
    """
    # Verify song exists
    song = db.query(models.Song).filter(models.Song.id == payload.song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    # Define the UTC boundary for today
    now = datetime.utcnow()
    start_of_day = datetime.combine(now.date(), time.min)
    end_of_day = datetime.combine(now.date(), time.max)

    # Search for an entry on the same date for this song
    history_entry = db.query(models.ListenHistory).filter(
        models.ListenHistory.song_id == payload.song_id,
        models.ListenHistory.listened_at >= start_of_day,
        models.ListenHistory.listened_at <= end_of_day
    ).first()

    if history_entry:
        # Update details
        history_entry.position_seconds = payload.position_seconds
        history_entry.listened_at = now
    else:
        # Create new entry
        history_entry = models.ListenHistory(
            song_id=payload.song_id,
            position_seconds=payload.position_seconds,
            listened_at=now
        )
        db.add(history_entry)

    db.commit()
    db.refresh(history_entry)
    return history_entry


@router.get("/recent", response_model=List[HistoryResponse])
def get_recent_history(
    limit: int = 20,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves recently played songs, limited to 20 by default."""
    return db.query(models.ListenHistory)\
        .options(joinedload(models.ListenHistory.song))\
        .order_by(models.ListenHistory.listened_at.desc())\
        .limit(limit)\
        .all()


@router.get("/continue", response_model=List[HistoryResponse])
def get_continue_history(
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """
    Retrieves songs played but not finished.
    Filters songs where position > 30s and position < (duration - 30s).
    """
    return db.query(models.ListenHistory)\
        .join(models.Song)\
        .options(joinedload(models.ListenHistory.song))\
        .filter(
            models.ListenHistory.position_seconds > 30,
            models.ListenHistory.position_seconds < (models.Song.duration_seconds - 30)
        )\
        .order_by(models.ListenHistory.listened_at.desc())\
        .limit(10)\
        .all()
