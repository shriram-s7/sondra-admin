import os
import asyncio
import json
from datetime import datetime
from typing import List, Optional, Set
from fastapi import APIRouter, Depends, BackgroundTasks, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from database import get_db, SessionLocal
from routers.auth import get_current_admin
import gdrive
import models
from googleapiclient.errors import HttpError

router = APIRouter(prefix="/sync", tags=["Sync"])

# Set of active SSE connection queues
sse_listeners: Set[asyncio.Queue] = set()

# In-memory sync status tracking
class SyncStateManager:
    def __init__(self):
        self.last_sync: Optional[datetime] = None
        self.is_syncing: bool = False
        
    def set_syncing(self, status: bool):
        self.is_syncing = status
        
    def mark_completed(self):
        self.last_sync = datetime.utcnow()
        self.is_syncing = False

sync_manager = SyncStateManager()

# In-memory sync log array tracking last 10 synchronization cycles
sync_logs = []

async def broadcast_sse_event(event_type: str, data: dict = None):
    """Broadcasts an SSE event to all connected listeners."""
    event = {"type": event_type}
    if data:
        event.update(data)
    
    # Send event to all client queues
    for queue in list(sse_listeners):
        try:
            await queue.put(event)
        except Exception:
            pass

def sync_library_logic():
    """
    Synchronous Google Drive library synchronization.
    Runs in a background thread to prevent event loop blockage.
    """
    db = SessionLocal()
    sync_manager.set_syncing(True)
    songs_added = 0
    songs_removed = 0
    try:
        root_id = os.getenv("GDRIVE_ROOT_FOLDER_ID")
        if not root_id:
            print("Sync Error: GDRIVE_ROOT_FOLDER_ID environment variable is missing.")
            return

        # 1. Fetch playlist folders inside Root Folder from Drive
        drive_folders = gdrive.list_playlist_folders(root_id)
        
        all_seen_folder_ids = set()
        all_seen_song_ids = set()

        # 2. For each folder: Upsert Playlist row
        for folder in drive_folders:
            folder_id = folder["id"]
            all_seen_folder_ids.add(folder_id)
            
            db_playlist = db.query(models.Playlist).filter(models.Playlist.gdrive_folder_id == folder_id).first()
            if not db_playlist:
                db_playlist = models.Playlist(
                    gdrive_folder_id=folder_id,
                    name=folder["name"]
                )
                db.add(db_playlist)
                db.commit()
                db.refresh(db_playlist)
            else:
                if db_playlist.name != folder["name"]:
                    db_playlist.name = folder["name"]
                    db.commit()

            # 3. For each playlist folder: Fetch songs
            songs = gdrive.list_songs_in_folder(folder_id)
            
            for song in songs:
                song_id = song["id"]
                all_seen_song_ids.add(song_id)
                
                # Check if song exists in DB
                db_song = db.query(models.Song).filter(models.Song.gdrive_file_id == song_id).first()
                if not db_song:
                    # 4. If song not in DB: Fetch metadata and insert
                    print(f"Sync: Downloading and extracting metadata for: {song['name']}")
                    meta = gdrive.get_file_metadata(song_id)
                    
                    new_song = models.Song(
                        gdrive_file_id=song_id,
                        title=meta["title"],
                        artist=meta["artist"],
                        album=meta["album"],
                        genre=meta["genre"],
                        duration_seconds=meta["duration_seconds"],
                        cover_url=meta["cover_url"], # base64 data URI
                        playlist_id=db_playlist.id
                    )
                    db.add(new_song)
                    db.commit()
                    songs_added += 1
                else:
                    # Make sure it's linked to the correct playlist (if moved)
                    if db_song.playlist_id != db_playlist.id:
                        db_song.playlist_id = db_playlist.id
                        db.commit()

        # 5. Delete Song rows whose gdrive_file_id no longer exists in Drive
        songs_removed = db.query(models.Song).filter(~models.Song.gdrive_file_id.in_(all_seen_song_ids)).delete(synchronize_session=False)
        
        # 6. Delete Playlist rows whose gdrive_folder_id no longer exists in Drive
        db.query(models.Playlist).filter(~models.Playlist.gdrive_folder_id.in_(all_seen_folder_ids)).delete(synchronize_session=False)
        
        db.commit()
        sync_manager.mark_completed()
        
        # Write successful run log
        sync_logs.append({
            "timestamp": datetime.utcnow().isoformat(),
            "songs_added": songs_added,
            "songs_removed": songs_removed,
            "errors": "None"
        })
        if len(sync_logs) > 10:
            sync_logs.pop(0)
            
        print("Sync completed successfully.")

    except HttpError as e:
        sync_manager.set_syncing(False)
        err_msg = "Google Drive API quota exceeded. Skipping sync." if (e.resp.status in [403, 429] and any(kw in str(e).lower() for kw in ["quota", "rate", "limit", "exhausted", "exceeded"])) else f"Sync failed with Google HTTP error: {e}"
        print(f"WARNING: {err_msg}" if "quota" in err_msg.lower() else err_msg)
        
        sync_logs.append({
            "timestamp": datetime.utcnow().isoformat(),
            "songs_added": songs_added,
            "songs_removed": 0,
            "errors": err_msg
        })
        if len(sync_logs) > 10:
            sync_logs.pop(0)
            
    except Exception as e:
        sync_manager.set_syncing(False)
        err_msg = f"Sync failed with error: {e}"
        print(err_msg)
        
        sync_logs.append({
            "timestamp": datetime.utcnow().isoformat(),
            "songs_added": songs_added,
            "songs_removed": 0,
            "errors": err_msg
        })
        if len(sync_logs) > 10:
            sync_logs.pop(0)
            
    finally:
        db.close()


async def execute_sync_and_broadcast():
    """Runs the sync in a thread pool and broadcasts SSE notification on completion."""
    await asyncio.to_thread(sync_library_logic)
    await broadcast_sse_event("library_updated")


@router.post("", status_code=202)
def trigger_sync(
    background_tasks: BackgroundTasks,
    admin: str = Depends(get_current_admin)
):
    """Manually triggers library synchronization in the background."""
    if sync_manager.is_syncing:
        raise HTTPException(status_code=409, detail="A synchronization is already running.")
        
    background_tasks.add_task(execute_sync_and_broadcast)
    return {"message": "Sync triggered successfully."}


@router.get("/status")
def get_sync_status(
    admin: str = Depends(get_current_admin)
):
    """Retrieves sync status and totals from the database."""
    db = SessionLocal()
    try:
        total_songs = db.query(models.Song).count()
        total_playlists = db.query(models.Playlist).count()
        
        try:
            interval = int(os.getenv("SYNC_INTERVAL_SECONDS", "900"))
        except Exception:
            interval = 900
            
        return {
            "last_sync": sync_manager.last_sync.isoformat() if sync_manager.last_sync else None,
            "total_songs": total_songs,
            "total_playlists": total_playlists,
            "is_syncing": sync_manager.is_syncing,
            "sync_interval_seconds": interval,
            "gdrive_root_folder_id": os.getenv("GDRIVE_ROOT_FOLDER_ID", "Not Configured")
        }
    finally:
        db.close()

@router.get("/logs")
def get_sync_logs(
    admin: str = Depends(get_current_admin)
):
    """Retrieves the last 10 sync log details."""
    return sync_logs


@router.get("/events")
async def sse_events_endpoint(request: Request):
    """
    SSE stream endpoint. Clients connect here to receive
    real-time event broadcasts such as library updates.
    """
    queue = asyncio.Queue()
    sse_listeners.add(queue)
    
    async def sse_generator():
        try:
            while True:
                if await request.is_disconnected():
                    break
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=20.0)
                    yield f"data: {json.dumps(event)}\n\n"
                except asyncio.TimeoutError:
                    # Keep-alive ping
                    yield ": ping\n\n"
        finally:
            sse_listeners.remove(queue)
            
    return StreamingResponse(sse_generator(), media_type="text/event-stream")
