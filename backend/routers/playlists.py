from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from database import get_db
from routers.auth import get_current_admin
import models
from pydantic import BaseModel
from datetime import datetime

router = APIRouter(prefix="/playlists", tags=["Playlists"])

# Song representation inside playlists list/detail
class PlaylistSongResponse(BaseModel):
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

    class Config:
        orm_mode = True

# Main playlist list structure
class PlaylistListResponse(BaseModel):
    id: int
    gdrive_folder_id: str
    name: str
    created_at: datetime
    songs: List[PlaylistSongResponse]
    song_count: int

    class Config:
        orm_mode = True

@router.get("", response_model=List[PlaylistListResponse])
def get_playlists(
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves all synced playlists with song lists and count metrics."""
    playlists = db.query(models.Playlist).options(joinedload(models.Playlist.songs)).all()
    for p in playlists:
        p.song_count = len(p.songs)
    return playlists


@router.get("/{playlist_id}", response_model=PlaylistListResponse)
def get_playlist(
    playlist_id: int,
    db: Session = Depends(get_db),
    admin: str = Depends(get_current_admin)
):
    """Retrieves a single playlist, sorting the songs array by created_at."""
    playlist = db.query(models.Playlist).filter(models.Playlist.id == playlist_id).first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")

    # Query songs explicitly sorted by created_at
    sorted_songs = db.query(models.Song)\
        .filter(models.Song.playlist_id == playlist_id)\
        .order_by(models.Song.created_at.asc())\
        .all()

    playlist.songs = sorted_songs
    playlist.song_count = len(sorted_songs)
    return playlist
