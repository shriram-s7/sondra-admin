import os
import base64
from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_
from typing import List, Optional
from database import get_db
from routers.auth import get_current_admin
import models
from pydantic import BaseModel, validator
from datetime import datetime

router = APIRouter(prefix="/songs", tags=["Songs"])

DEFAULT_COVER_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500" width="100%" height="100%">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1e3c72;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#2a5298;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="100%" height="100%" fill="url(#grad)" />
  <circle cx="250" cy="250" r="120" fill="none" stroke="#ffffff" stroke-width="4" opacity="0.1" />
  <circle cx="250" cy="250" r="80" fill="none" stroke="#ffffff" stroke-width="4" opacity="0.2" />
  <path d="M220 180v140l100-70-100-70z" fill="#ffffff" opacity="0.8" />
  <text x="250" y="380" font-family="'Outfit', sans-serif" font-size="28" fill="#ffffff" text-anchor="middle" font-weight="bold" opacity="0.7">Sondra Music</text>
</svg>"""

# Nested playlist model
class PlaylistBriefResponse(BaseModel):
    id: int
    gdrive_folder_id: str
    name: str

    class Config:
        orm_mode = True

# Main song response model
class SongResponse(BaseModel):
    id: int
    gdrive_file_id: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    genre: Optional[str] = None
    duration_seconds: int = 0
    cover_url: Optional[str] = None
    playlist_id: Optional[int] = None
    created_at: datetime
    playlist: Optional[PlaylistBriefResponse] = None

    @validator("cover_url", pre=True, always=True)
    def resolve_cover_url(cls, v, values):
        song_id = values.get("id")
        if v and song_id:
            return f"/api/songs/{song_id}/cover"
        return None

    class Config:
        orm_mode = True

# Song metadata PATCH schema
class SongUpdate(BaseModel):
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    genre: Optional[str] = None

@router.get("", response_model=List[SongResponse])
def get_songs(
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves all songs, including joined playlist details."""
    return db.query(models.Song).options(joinedload(models.Song.playlist)).all()

@router.get("/search", response_model=List[SongResponse])
def search_songs(
    q: str,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Performs case-insensitive searches in titles, artists, and albums."""
    search_filter = f"%{q}%"
    return db.query(models.Song)\
        .options(joinedload(models.Song.playlist))\
        .filter(
            or_(
                models.Song.title.ilike(search_filter),
                models.Song.artist.ilike(search_filter),
                models.Song.album.ilike(search_filter)
            )
        )\
        .all()

@router.get("/{song_id}", response_model=SongResponse)
def get_song(
    song_id: int,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves a single song metadata by ID."""
    song = db.query(models.Song).options(joinedload(models.Song.playlist)).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    return song

@router.patch("/{song_id}", response_model=SongResponse)
def update_song_metadata(
    song_id: int,
    payload: SongUpdate,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Updates metadata (title, artist, album, genre) locally in the SQLite DB."""
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    if payload.title is not None:
        song.title = payload.title
    if payload.artist is not None:
        song.artist = payload.artist
    if payload.album is not None:
        song.album = payload.album
    if payload.genre is not None:
        song.genre = payload.genre

    db.commit()
    db.refresh(song)
    
    # Reload with joined playlist info
    return db.query(models.Song).options(joinedload(models.Song.playlist)).filter(models.Song.id == song_id).first()

@router.get("/{song_id}/cover")
def get_song_cover(
    song_id: int,
    db: Session = Depends(get_db)
):
    """
    Serves the cover image of the song by decoding the base64 data stored in the DB.
    Does not require authentication to let the audio player fetch images easily in img elements.
    """
    song = db.query(models.Song).filter(models.Song.id == song_id).first()
    if song and song.cover_url and song.cover_url.startswith("data:"):
        try:
            # Format: "data:image/png;base64,iVBORw0KG..."
            header, base64_data = song.cover_url.split(",", 1)
            mime_type = header.split(";")[0].split(":")[1]
            image_bytes = base64.b64decode(base64_data)
            return Response(content=image_bytes, media_type=mime_type)
        except Exception as e:
            print(f"Error decoding cover art base64: {e}")
            
    # Return beautiful SVG fallback if no cover art is cached
    return Response(content=DEFAULT_COVER_SVG, media_type="image/svg+xml")
