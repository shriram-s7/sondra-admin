from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from database import Base

class Playlist(Base):
    __tablename__ = "playlists"

    id = Column(Integer, primary_key=True, index=True)
    gdrive_folder_id = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    songs = relationship("Song", back_populates="playlist", cascade="all, delete-orphan")


class Song(Base):
    __tablename__ = "songs"

    id = Column(Integer, primary_key=True, index=True)
    gdrive_file_id = Column(String, unique=True, index=True, nullable=False)
    title = Column(String, nullable=True)
    artist = Column(String, nullable=True)
    album = Column(String, nullable=True)
    genre = Column(String, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    cover_url = Column(String, nullable=True)
    playlist_id = Column(Integer, ForeignKey("playlists.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    playlist = relationship("Playlist", back_populates="songs")
    history_entries = relationship("ListenHistory", back_populates="song", cascade="all, delete-orphan")


class ListenHistory(Base):
    __tablename__ = "listen_history"

    id = Column(Integer, primary_key=True, index=True)
    song_id = Column(Integer, ForeignKey("songs.id", ondelete="CASCADE"), nullable=False)
    listened_at = Column(DateTime, default=datetime.utcnow)
    position_seconds = Column(Integer, nullable=False, default=0)

    # Relationships
    song = relationship("Song", back_populates="history_entries")
