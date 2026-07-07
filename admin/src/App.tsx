import { useState, useEffect, useRef } from "react";
import { 
  Play, 
  Pause, 
  SkipForward, 
  SkipBack, 
  Volume2, 
  VolumeX, 
  Search, 
  Music, 
  LayoutDashboard, 
  LogOut, 
  ListMusic,
  Settings as SettingsIcon,
  Edit2,
  X,
  Clock
} from "lucide-react";
import api from "./api";
import "./App.css";

// Interfaces
interface Playlist {
  id: number;
  gdrive_folder_id: string;
  name: string;
  created_at: string;
  song_count: number;
  songs: Song[];
}

interface Song {
  id: number;
  gdrive_file_id: string;
  title: string | null;
  artist: string | null;
  album: string | null;
  genre: string | null;
  duration_seconds: number;
  cover_url: string | null;
  playlist_id: number | null;
  created_at: string;
  playlist?: {
    id: number;
    gdrive_folder_id: string;
    name: string;
  } | null;
}

const getSeededColors = (title: string) => {
  const songTitle = title || "";
  let hash = 0;
  for (let i = 0; i < songTitle.length; i++) {
    hash = songTitle.charCodeAt(i) + ((hash << 5) - hash);
  }
  
  const palettes = [
    ["#F43F5E", "#FB7185"], // Rose
    ["#EC4899", "#F472B6"], // Pink
    ["#D946EF", "#E879F9"], // Fuchsia
    ["#A855F7", "#C084FC"], // Purple
    ["#8B5CF6", "#A78BFA"], // Violet
    ["#6366F1", "#818CF8"], // Indigo
    ["#3B82F6", "#60A5FA"], // Blue
    ["#0EA5E9", "#38BDF8"], // Light Blue
    ["#06B6D4", "#22D3EE"], // Cyan
    ["#14B8A6", "#2DD4BF"], // Teal
    ["#10B981", "#34D399"], // Emerald
    ["#22C55E", "#4ADE80"], // Green
    ["#EAB308", "#FACC15"], // Yellow
    ["#F97316", "#FB923C"], // Orange
    ["#EF4444", "#F87171"], // Red
  ];
  
  const index = Math.abs(hash) % palettes.length;
  return palettes[index];
};

const SongCover = ({ song, size = "40px", fontSize = "14px" }: { song: Song; size?: string; fontSize?: string }) => {
  const [hasError, setHasError] = useState(false);
  const title = song.title || "Unknown";
  const initial = title.charAt(0).toUpperCase() || "♫";

  const apiBase = import.meta.env.VITE_API_URL || "";
  const cleanApiBase = apiBase.endsWith("/") ? apiBase.slice(0, -1) : apiBase;
  const coverUrl = (song.cover_url && (song.cover_url.startsWith('data:') || song.cover_url.startsWith('http')))
    ? song.cover_url
    : (song.cover_url ? `${cleanApiBase}/api/songs/${song.id}/cover` : undefined);

  if (hasError || !song.cover_url) {
    const colors = getSeededColors(title);
    return (
      <div 
        style={{
          width: size,
          height: size,
          borderRadius: "6px",
          background: `linear-gradient(135deg, ${colors[0]}, ${colors[1]})`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "#ffffff",
          fontWeight: "bold",
          fontSize: fontSize,
          textShadow: "1px 2px 4px rgba(0,0,0,0.35)",
          flexShrink: 0,
        }}
      >
        {initial}
      </div>
    );
  }

  return (
    <img
      src={coverUrl}
      onError={() => setHasError(true)}
      style={{
        width: size,
        height: size,
        borderRadius: "6px",
        objectFit: "cover",
        flexShrink: 0,
      }}
      alt=""
    />
  );
};

function App() {
  const [token, setToken] = useState<string | null>(localStorage.getItem("sondra_token"));
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  // Navigation state
  const [activeTab, setActiveTab] = useState<"dashboard" | "library" | "playlists" | "settings">("dashboard");
  
  // Data lists
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [songs, setSongs] = useState<Song[]>([]);
  const [filteredSongs, setFilteredSongs] = useState<Song[]>([]);

  // Search & Modals
  const [searchQuery, setSearchQuery] = useState("");
  const [editingSong, setEditingSong] = useState<Song | null>(null);
  const [editTitle, setEditTitle] = useState("");
  const [editArtist, setEditArtist] = useState("");
  const [editAlbum, setEditAlbum] = useState("");
  const [editGenre, setEditGenre] = useState("");
  const [expandedPlaylist, setExpandedPlaylist] = useState<Playlist | null>(null);

  // Settings states
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [passwordError, setPasswordError] = useState("");
  const [passwordSuccess, setPasswordSuccess] = useState("");

  // Persistent Player states
  const [currentSong, setCurrentSong] = useState<Song | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);
  const [isMuted, setIsMuted] = useState(false);
  const [shuffle] = useState(false);
  const [repeat] = useState<"none" | "one" | "all">("none");
  const [activePlaylistSongs, setActivePlaylistSongs] = useState<Song[]>([]);
  const [songQueue, setSongQueue] = useState<Song[]>([]);
  const [showQueue, setShowQueue] = useState(false);

  const audioRef = useRef<HTMLAudioElement | null>(null);

  const addToQueue = (song: Song) => {
    setSongQueue((prev) => [...prev, song]);
  };

  const removeFromQueue = (index: number) => {
    setSongQueue((prev) => prev.filter((_, i) => i !== index));
  };

  const clearQueue = () => {
    setSongQueue([]);
  };

  // Auth Handling
  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoginError("");
    setIsLoading(true);
    try {
      const response = await api.post("/auth/login", { username, password });
      const { access_token } = response.data;
      localStorage.setItem("sondra_token", access_token);
      setToken(access_token);
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || "Invalid credentials.";
      setLoginError(errorMsg);
    } finally {
      setIsLoading(false);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem("sondra_token");
    setToken(null);
    setCurrentSong(null);
    setIsPlaying(false);
    if (audioRef.current) {
      audioRef.current.pause();
    }
  };

  // Load Library Data
  const loadLibraryData = async () => {
    try {
      const [playlistsRes, songsRes] = await Promise.all([
        api.get("/api/playlists"),
        api.get("/api/songs"),
      ]);

      setPlaylists(playlistsRes.data);
      setSongs(songsRes.data);
      setFilteredSongs(songsRes.data);
    } catch (err: any) {
      console.error("Error loading library data:", err);
    }
  };

  useEffect(() => {
    if (token) {
      loadLibraryData();
    }
  }, [token]);

  // SSE Broadcast alerts — silently reloads library data on backend updates
  useEffect(() => {
    if (!token) return;

    const apiBase = import.meta.env.VITE_API_URL || "";
    const cleanApiBase = apiBase.endsWith("/") ? apiBase.slice(0, -1) : apiBase;
    const eventSource = new EventSource(`${cleanApiBase}/api/events?token=${token}`);

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "library_updated") {
          loadLibraryData();
        }
      } catch (err) {
        console.error("SSE parse error:", err);
      }
    };

    eventSource.onerror = () => {
      console.warn("SSE disconnected. Reconnecting automatically...");
    };

    return () => {
      eventSource.close();
    };
  }, [token]);

  // Handle Search Filtering
  useEffect(() => {
    if (!token) return;

    const performSearch = async () => {
      if (!searchQuery) {
        setFilteredSongs(songs);
        return;
      }
      try {
        const res = await api.get(`/api/songs/search?q=${encodeURIComponent(searchQuery)}`);
        setFilteredSongs(res.data);
      } catch (err) {
        console.error("Search failed:", err);
      }
    };

    const timeout = setTimeout(performSearch, 300);
    return () => clearTimeout(timeout);
  }, [searchQuery, songs, token]);

  // PATCH Password
  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError("");
    setPasswordSuccess("");
    try {
      await api.patch("/auth/password", {
        current_password: currentPassword,
        new_password: newPassword,
      });
      setPasswordSuccess("Password changed successfully!");
      setCurrentPassword("");
      setNewPassword("");
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || "Failed to change password.";
      setPasswordError(errorMsg);
    }
  };

  // Metadata editor modal trigger
  const handleOpenEditModal = (song: Song) => {
    setEditingSong(song);
    setEditTitle(song.title || "");
    setEditArtist(song.artist || "");
    setEditAlbum(song.album || "");
    setEditGenre(song.genre || "");
  };

  const handleSaveMetadata = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingSong) return;
    try {
      const res = await api.patch(`/api/songs/${editingSong.id}`, {
        title: editTitle,
        artist: editArtist,
        album: editAlbum,
        genre: editGenre,
      });
      
      // Update local states
      setSongs((prev) => prev.map((s) => (s.id === editingSong.id ? res.data : s)));
      setFilteredSongs((prev) => prev.map((s) => (s.id === editingSong.id ? res.data : s)));
      
      // Update current song if it's the one being modified
      if (currentSong?.id === editingSong.id) {
        setCurrentSong(res.data);
      }

      setEditingSong(null);
    } catch (err: any) {
      const errorMsg = err.response?.data?.error || "Failed to update metadata.";
      console.error(errorMsg);
    }
  };

  const handlePlaySong = (song: Song, playlistSongsList: Song[] = []) => {
    setCurrentSong(song);
    setIsPlaying(true);
    setActivePlaylistSongs(playlistSongsList.length > 0 ? playlistSongsList : songs);
    
    const apiBase = import.meta.env.VITE_API_URL || "";
    const cleanApiBase = apiBase.endsWith("/") ? apiBase.slice(0, -1) : apiBase;
    const streamUrl = `${cleanApiBase}/api/stream/${song.id}/proxy?token=${token}`;
    
    if (audioRef.current) {
      audioRef.current.src = streamUrl;
      audioRef.current.load();
      audioRef.current.play().catch((err) => console.error("Playback error:", err));
    }
  };

  const togglePlay = () => {
    if (!currentSong) {
      if (filteredSongs.length > 0) {
        handlePlaySong(filteredSongs[0]);
      }
      return;
    }
    
    if (isPlaying) {
      audioRef.current?.pause();
      setIsPlaying(false);
    } else {
      audioRef.current?.play().catch((err) => console.error("Playback resume error:", err));
      setIsPlaying(true);
    }
  };

  const handleAudioEnded = () => {
    handleNextSong();
  };

  const handleNextSong = () => {
    if (songQueue.length > 0) {
      const next = songQueue[0];
      setSongQueue((prev) => prev.slice(1));
      handlePlaySong(next, activePlaylistSongs);
      return;
    }

    if (activePlaylistSongs.length === 0) return;
    const currentIndex = activePlaylistSongs.findIndex((s) => s.id === currentSong?.id);
    let nextIndex = 0;

    if (shuffle) {
      nextIndex = Math.floor(Math.random() * activePlaylistSongs.length);
    } else if (currentIndex !== -1) {
      nextIndex = currentIndex + 1;
      if (nextIndex >= activePlaylistSongs.length) {
        if (repeat === "all") {
          nextIndex = 0;
        } else {
          setIsPlaying(false);
          return;
        }
      }
    }
    handlePlaySong(activePlaylistSongs[nextIndex], activePlaylistSongs);
  };

  const handlePrevSong = () => {
    if (activePlaylistSongs.length === 0 || !currentSong) return;

    if (currentTime > 3) {
      if (audioRef.current) audioRef.current.currentTime = 0;
      return;
    }

    const currentIndex = activePlaylistSongs.findIndex((s) => s.id === currentSong.id);
    let prevIndex = 0;

    if (shuffle) {
      prevIndex = Math.floor(Math.random() * activePlaylistSongs.length);
    } else if (currentIndex !== -1) {
      prevIndex = currentIndex - 1;
      if (prevIndex < 0) {
        if (repeat === "all") {
          prevIndex = activePlaylistSongs.length - 1;
        } else {
          prevIndex = 0;
        }
      }
    }
    handlePlaySong(activePlaylistSongs[prevIndex], activePlaylistSongs);
  };

  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = isMuted ? 0 : volume;
    }
  }, [volume, isMuted]);

  const onTimeUpdate = () => {
    if (audioRef.current) {
      setCurrentTime(audioRef.current.currentTime);
    }
  };

  const onLoadedMetadata = () => {
    if (audioRef.current) {
      setDuration(audioRef.current.duration);
    }
  };

  const formatTime = (seconds: number) => {
    if (isNaN(seconds)) return "00:00";
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  };

  if (!token) {
    return (
      <div className="login-container">
        <div className="glass-card login-card">
          <div className="login-logo flex-center">
            <Music color="#ffffff" size={28} />
          </div>
          <h1 className="login-title">Sondra</h1>
          <p className="login-subtitle">Personal Admin Music Streaming</p>
          
          <form className="login-form" onSubmit={handleLogin}>
            {loginError && <div className="login-error">{loginError}</div>}
            
            <div className="form-group">
              <label className="form-label">Admin Username</label>
              <input
                type="text"
                placeholder="Enter username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                required
              />
            </div>
            
            <div className="form-group">
              <label className="form-label">Password</label>
              <input
                type="password"
                placeholder="Enter password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            
            <button type="submit" className="btn-primary" style={{ marginTop: "12px" }} disabled={isLoading}>
              {isLoading ? "Authenticating..." : "Log In"}
            </button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="app-container">
      <audio
        ref={audioRef}
        onTimeUpdate={onTimeUpdate}
        onLoadedMetadata={onLoadedMetadata}
        onEnded={handleAudioEnded}
      />

      {/* Sidebar Layout */}
      <aside className="sidebar glass" style={{ width: "220px" }}>
        <div className="logo-container">
          <div className="logo-icon flex-center">
            <Music color="#ffffff" size={20} />
          </div>
          <span className="logo-text">Sondra</span>
        </div>

        <nav className="nav-menu">
          <button
            className={`nav-item ${activeTab === "dashboard" ? "active" : ""}`}
            onClick={() => setActiveTab("dashboard")}
          >
            <LayoutDashboard size={18} />
            Dashboard
          </button>
          <button
            className={`nav-item ${activeTab === "library" ? "active" : ""}`}
            onClick={() => setActiveTab("library")}
          >
            <Music size={18} />
            Library
          </button>
          <button
            className={`nav-item ${activeTab === "playlists" ? "active" : ""}`}
            onClick={() => {
              setActiveTab("playlists");
              setExpandedPlaylist(null);
            }}
          >
            <ListMusic size={18} />
            Playlists
          </button>
          <button
            className={`nav-item ${activeTab === "settings" ? "active" : ""}`}
            onClick={() => setActiveTab("settings")}
          >
            <SettingsIcon size={18} />
            Settings
          </button>
        </nav>

        <button className="nav-item" onClick={handleLogout} style={{ marginTop: "auto", color: "var(--color-danger)" }}>
          <LogOut size={18} />
          Logout
        </button>
      </aside>

      {/* Main Panel Area */}
      <main className="main-content">
        <div className="top-bar">
          <h2 style={{ fontSize: "22px" }}>
            {activeTab === "dashboard" && "Dashboard"}
            {activeTab === "library" && "Music Library"}
            {activeTab === "playlists" && "Playlists"}
            {activeTab === "settings" && "Platform Settings"}
          </h2>
          <div className="user-profile">
            <span style={{ fontSize: "14px", fontWeight: 500 }}>Admin Portal</span>
            <div className="avatar flex-center">A</div>
          </div>
        </div>

        <div className="content-pane">
          {/* Dashboard Tab */}
          {activeTab === "dashboard" && (
            <div>
              <div className="stats-grid">
                <div className="glass-card stat-card">
                  <div className="stat-icon flex-center">
                    <Music size={24} />
                  </div>
                  <div>
                    <div className="stat-value">{songs.length}</div>
                    <div className="stat-label">Total Songs</div>
                  </div>
                </div>

                <div className="glass-card stat-card">
                  <div className="stat-icon flex-center">
                    <ListMusic size={24} />
                  </div>
                  <div>
                    <div className="stat-value">{playlists.length}</div>
                    <div className="stat-label">Total Playlists</div>
                  </div>
                </div>

              </div>
            </div>
          )}

          {/* Library Tab */}
          {activeTab === "library" && (
            <div>
              <div className="search-container">
                <div className="search-input-wrapper">
                  <Search size={18} className="search-icon" />
                  <input
                    type="text"
                    placeholder="Search by title, artist, album..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                </div>
              </div>

              <div className="glass-card" style={{ overflow: "hidden" }}>
                <table className="song-table">
                  <thead>
                    <tr>
                      <th>Title</th>
                      <th>Artist</th>
                      <th>Album</th>
                      <th>Folder Playlist (Read Only)</th>
                      <th><Clock size={14} /></th>
                      <th>Edit</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredSongs.map((song) => (
                      <tr key={song.id} className="song-row">
                        <td onClick={() => handlePlaySong(song, filteredSongs)}>
                          <div className="song-info-cell">
                            <SongCover song={song} size="40px" fontSize="14px" />
                            <span className="song-title">{song.title}</span>
                          </div>
                        </td>
                        <td onClick={() => handlePlaySong(song, filteredSongs)}>
                          <span className="song-artist">{song.artist}</span>
                        </td>
                        <td onClick={() => handlePlaySong(song, filteredSongs)}>
                          <span className="song-album-cell">{song.album}</span>
                        </td>
                        <td>
                          <span style={{ color: "var(--color-primary)", fontWeight: 500 }}>
                            {song.playlist?.name || "Root Folder"}
                          </span>
                        </td>
                        <td>
                          <span className="song-duration">{formatTime(song.duration_seconds)}</span>
                        </td>
                        <td>
                          <div className="flex-center" style={{ gap: "8px" }}>
                            <button
                              onClick={() => addToQueue(song)}
                              className="edit-metadata-btn flex-center"
                              style={{ color: "var(--color-primary)", padding: "6px" }}
                              title="Add to Queue"
                            >
                              <ListMusic size={14} />
                            </button>
                            <button
                              onClick={() => handleOpenEditModal(song)}
                              className="edit-metadata-btn flex-center"
                              style={{ color: "var(--text-muted)", padding: "6px" }}
                            >
                              <Edit2 size={14} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                    {filteredSongs.length === 0 && (
                      <tr>
                        <td colSpan={6} style={{ textAlign: "center", padding: "40px", color: "var(--text-muted)" }}>
                          No songs found. Add music folders in Google Drive to populate the library.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Playlists Tab */}
          {activeTab === "playlists" && (
            <div>
              {!expandedPlaylist ? (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: "24px" }}>
                  {playlists.map((playlist) => (
                    <div
                      key={playlist.id}
                      className="glass-card playlist-grid-card"
                      onClick={() => setExpandedPlaylist(playlist)}
                      style={{ cursor: "pointer", padding: "24px", minHeight: "200px", display: "flex", flexDirection: "column" }}
                    >
                      <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "12px" }}>
                        <h4 style={{ fontSize: "18px" }}>{playlist.name}</h4>
                        <span style={{ fontSize: "12px", background: "rgba(124, 58, 237, 0.15)", color: "var(--color-primary)", padding: "4px 8px", borderRadius: "12px", fontWeight: 600 }}>
                          {playlist.song_count} songs
                        </span>
                      </div>
                      
                      {/* Short list of titles preview */}
                      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "4px", color: "var(--text-secondary)", fontSize: "13px", marginTop: "8px", overflow: "hidden" }}>
                        {playlist.songs.slice(0, 3).map((song) => (
                          <div key={song.id} style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                            • {song.title}
                          </div>
                        ))}
                        {playlist.songs.length > 3 && (
                          <div style={{ color: "var(--text-muted)", fontSize: "11px", marginTop: "4px" }}>
                            + {playlist.songs.length - 3} more tracks...
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                  {playlists.length === 0 && (
                    <div style={{ color: "var(--text-muted)" }}>No playlists found. Add folders in Google Drive to get started.</div>
                  )}
                </div>
              ) : (
                <div>
                  <button className="btn-secondary" onClick={() => setExpandedPlaylist(null)} style={{ marginBottom: "20px" }}>
                    ← Back to Playlists
                  </button>
                  <div className="glass-card" style={{ padding: "28px" }}>
                    <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "20px" }}>
                      <h3 style={{ fontSize: "22px" }}>{expandedPlaylist.name} Details</h3>
                      <span style={{ fontSize: "14px", color: "var(--text-muted)" }}>
                        {expandedPlaylist.song_count} total songs
                      </span>
                    </div>

                    <table className="song-table">
                      <thead>
                        <tr>
                          <th>Title</th>
                          <th>Artist</th>
                          <th>Album</th>
                          <th>Duration</th>
                        </tr>
                      </thead>
                      <tbody>
                        {expandedPlaylist.songs.map((song) => (
                          <tr key={song.id} className="song-row" onClick={() => handlePlaySong(song, expandedPlaylist.songs)}>
                            <td>{song.title}</td>
                            <td>{song.artist}</td>
                            <td>{song.album}</td>
                            <td>{formatTime(song.duration_seconds)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Settings Tab */}
          {activeTab === "settings" && (
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "32px" }}>
              {/* Password Editor Form */}
              <div className="glass-card" style={{ padding: "28px" }}>
                <h3 style={{ fontSize: "18px", marginBottom: "20px" }}>Change Admin Password</h3>
                <form onSubmit={handlePasswordChange} className="login-form">
                  {passwordError && <div className="login-error">{passwordError}</div>}
                  {passwordSuccess && <div style={{ color: "var(--color-success)", padding: "10px", borderRadius: "6px", background: "rgba(16,185,129,0.1)", textAlign: "center", fontSize: "14px" }}>{passwordSuccess}</div>}
                  
                  <div className="form-group">
                    <label className="form-label">Current Password</label>
                    <input
                      type="password"
                      placeholder="Enter current password"
                      value={currentPassword}
                      onChange={(e) => setCurrentPassword(e.target.value)}
                      required
                    />
                  </div>

                  <div className="form-group">
                    <label className="form-label">New Password</label>
                    <input
                      type="password"
                      placeholder="Enter new password"
                      value={newPassword}
                      onChange={(e) => setNewPassword(e.target.value)}
                      required
                    />
                  </div>

                  <button type="submit" className="btn-primary" style={{ marginTop: "12px" }}>
                    Update Password
                  </button>
                </form>
              </div>

              {/* Drive Integration Parameters */}
              <div className="glass-card" style={{ padding: "28px" }}>
                <h3 style={{ fontSize: "18px", marginBottom: "20px" }}>Drive Integration Parameters</h3>
                <p style={{ color: "var(--text-muted)", fontSize: "14px" }}>
                  Configure your GDRIVE_ROOT_FOLDER_ID and OAuth in the backend environment variables.
                </p>
              </div>
            </div>
          )}
        </div>
      </main>

      {/* Persistent mini-player bar at the bottom */}
      {currentSong && (
        <div className="player-bar glass" style={{ height: "80px", gridTemplateColumns: "1fr 2fr 1fr", position: "fixed", bottom: 0, left: 0, width: "100%", borderTop: "1px solid var(--border-glass)" }}>
          <div className="player-song-details">
            <SongCover song={currentSong} size="48px" fontSize="16px" />
            <div className="player-song-meta">
              <span className="player-title">{currentSong.title}</span>
              <span className="player-artist">{currentSong.artist}</span>
            </div>
          </div>

          <div className="player-center">
            <div className="player-controls" style={{ gap: "16px" }}>
              <button className="control-btn" onClick={handlePrevSong}>
                <SkipBack size={18} fill="currentColor" />
              </button>
              <button className="play-pause-btn flex-center" onClick={togglePlay} style={{ width: "36px", height: "36px" }}>
                {isPlaying ? <Pause size={16} fill="currentColor" /> : <Play size={16} fill="currentColor" style={{ marginLeft: "2px" }} />}
              </button>
              <button className="control-btn" onClick={handleNextSong}>
                <SkipForward size={18} fill="currentColor" />
              </button>
            </div>
            <div className="player-timeline" style={{ width: "100%", maxWidth: "420px" }}>
              <span>{formatTime(currentTime)}</span>
              <div className="timeline-slider-container">
                <input
                  type="range"
                  min="0"
                  max={duration || 0}
                  value={currentTime}
                  onChange={(e) => {
                    const targetVal = Number(e.target.value);
                    if (audioRef.current) {
                      audioRef.current.currentTime = targetVal;
                      setCurrentTime(targetVal);
                    }
                  }}
                />
              </div>
              <span>{formatTime(duration)}</span>
            </div>
          </div>

          <div className="player-right">
            <button 
              onClick={() => setShowQueue(!showQueue)} 
              className="control-btn" 
              style={{ color: showQueue ? "var(--color-primary)" : "inherit", marginRight: "8px" }}
              title="Play Queue"
            >
              <ListMusic size={16} />
            </button>
            <button onClick={() => setIsMuted(!isMuted)} className="control-btn">
              {isMuted || volume === 0 ? <VolumeX size={16} /> : <Volume2 size={16} />}
            </button>
            <div className="volume-container">
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                value={isMuted ? 0 : volume}
                onChange={(e) => {
                  const targetVol = Number(e.target.value);
                  setVolume(targetVol);
                  setIsMuted(false);
                }}
              />
            </div>
          </div>
        </div>
      )}

      {/* Queue Drawer Panel */}
      {showQueue && (
        <aside className="sidebar glass" style={{ width: "300px", position: "fixed", right: 0, top: 0, height: "calc(100% - 80px)", zIndex: 10, padding: "20px", display: "flex", flexDirection: "column", borderLeft: "1px solid var(--border-glass)" }}>
          <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "16px" }}>
            <h3 style={{ fontSize: "16px", fontWeight: "bold", display: "flex", alignItems: "center", gap: "8px", margin: 0 }}><ListMusic size={18} /> Play Queue</h3>
            <button onClick={() => setShowQueue(false)} className="control-btn" style={{ padding: "4px" }}><X size={18} /></button>
          </div>

          <div style={{ flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: "16px" }}>
            {/* Now Playing */}
            {currentSong && (
              <div>
                <span style={{ fontSize: "11px", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: 600 }}>Now Playing</span>
                <div style={{ display: "flex", alignItems: "center", gap: "10px", marginTop: "8px" }}>
                  <SongCover song={currentSong} size="36px" fontSize="12px" />
                  <div style={{ overflow: "hidden" }}>
                    <div style={{ fontWeight: 600, fontSize: "13px", color: "var(--color-primary)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{currentSong.title}</div>
                    <div style={{ fontSize: "11px", color: "var(--text-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{currentSong.artist}</div>
                  </div>
                </div>
              </div>
            )}

            {/* Next In Queue (Manual) */}
            <div>
              <div className="flex-center" style={{ justifyContent: "space-between", marginBottom: "8px" }}>
                <span style={{ fontSize: "11px", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: 600 }}>Next in Queue</span>
                {songQueue.length > 0 && <button onClick={clearQueue} style={{ fontSize: "11px", background: "none", border: "none", color: "var(--color-danger)", cursor: "pointer", padding: 0 }}>Clear</button>}
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                {songQueue.map((s, idx) => (
                  <div key={idx} style={{ display: "flex", alignItems: "center", gap: "10px", padding: "6px", background: "rgba(255,255,255,0.02)", borderRadius: "6px" }}>
                    <SongCover song={s} size="32px" fontSize="11px" />
                    <div style={{ flex: 1, overflow: "hidden" }}>
                      <div style={{ fontWeight: 500, fontSize: "12px", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.title}</div>
                      <div style={{ fontSize: "10px", color: "var(--text-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.artist}</div>
                    </div>
                    <button onClick={() => removeFromQueue(idx)} style={{ background: "none", border: "none", color: "rgba(255,255,255,0.3)", cursor: "pointer", fontSize: "16px", padding: "0 4px" }}>&times;</button>
                  </div>
                ))}
                {songQueue.length === 0 && <div style={{ fontSize: "12px", color: "var(--text-muted)", fontStyle: "italic" }}>Queue is empty</div>}
              </div>
            </div>

            {/* Next Up (Remaining Playlist) */}
            {activePlaylistSongs.length > 0 && currentSong && (
              <div>
                <span style={{ fontSize: "11px", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: 600 }}>Next Up from List</span>
                <div style={{ display: "flex", flexDirection: "column", gap: "8px", marginTop: "8px" }}>
                  {(() => {
                    const idx = activePlaylistSongs.findIndex(s => s.id === currentSong.id);
                    if (idx === -1) return null;
                    const upcoming = activePlaylistSongs.slice(idx + 1, idx + 6); // next 5 songs
                    if (upcoming.length === 0) return <div style={{ fontSize: "12px", color: "var(--text-muted)", fontStyle: "italic" }}>No more songs in list</div>;
                    return upcoming.map((s, uIdx) => (
                      <div key={uIdx} style={{ display: "flex", alignItems: "center", gap: "10px", padding: "4px" }}>
                        <SongCover song={s} size="32px" fontSize="11px" />
                        <div style={{ overflow: "hidden" }}>
                          <div style={{ fontWeight: 500, fontSize: "12px", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.title}</div>
                          <div style={{ fontSize: "10px", color: "var(--text-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.artist}</div>
                        </div>
                      </div>
                    ));
                  })()}
                </div>
              </div>
            )}
          </div>
        </aside>
      )}

      {/* Metadata Editor Inline Modal Overlay */}
      {editingSong && (
        <div className="modal-overlay flex-center" style={{ position: "fixed", top: 0, left: 0, width: "100vw", height: "100vh", background: "rgba(0,0,0,0.6)", zIndex: 1000 }}>
          <div className="glass-card" style={{ width: "480px", padding: "32px", borderRadius: "16px", position: "relative" }}>
            <button
              onClick={() => setEditingSong(null)}
              style={{ position: "absolute", top: "20px", right: "20px", color: "var(--text-muted)" }}
            >
              <X size={20} />
            </button>
            <h3 style={{ fontSize: "20px", marginBottom: "24px" }} className="flex-center">
              Edit Track Metadata
            </h3>
            
            <form onSubmit={handleSaveMetadata} className="login-form">
              <div className="form-group">
                <label className="form-label">Track Title</label>
                <input
                  type="text"
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  required
                />
              </div>

              <div className="form-group">
                <label className="form-label">Artist</label>
                <input
                  type="text"
                  value={editArtist}
                  onChange={(e) => setEditArtist(e.target.value)}
                  required
                />
              </div>

              <div className="form-group">
                <label className="form-label">Album Name</label>
                <input
                  type="text"
                  value={editAlbum}
                  onChange={(e) => setEditAlbum(e.target.value)}
                />
              </div>

              <div className="form-group">
                <label className="form-label">Genre</label>
                <input
                  type="text"
                  value={editGenre}
                  onChange={(e) => setEditGenre(e.target.value)}
                />
              </div>

              <div className="flex-center" style={{ gap: "16px", marginTop: "24px" }}>
                <button type="button" className="btn-secondary" style={{ flex: 1 }} onClick={() => setEditingSong(null)}>
                  Cancel
                </button>
                <button type="submit" className="btn-primary" style={{ flex: 1 }}>
                  Save Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
