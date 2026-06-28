import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../services/offline_storage.dart';
import '../services/download_manager.dart';

class SongOptionsButton extends ConsumerWidget {
  final Map<String, dynamic> song;
  final bool inQueue;
  final int? queueIndex;
  final VoidCallback? onPlaylistChanged;
  final int? playlistId;
  final int? songEntryId;

  const SongOptionsButton({
    super.key,
    required this.song,
    this.inQueue = false,
    this.queueIndex,
    this.onPlaylistChanged,
    this.playlistId,
    this.songEntryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb ? false : Platform.isWindows) {
      return GestureDetector(
        onTapDown: (details) {
          _showWindowsDropdown(context, details.globalPosition, ref);
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
        ),
      );
    } else {
      return IconButton(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
        onPressed: () {
          _showAndroidBottomSheet(context, ref);
        },
      );
    }
  }

  void _showWindowsDropdown(BuildContext context, Offset globalPos, WidgetRef ref) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: const Color(0xFF111019),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: _buildMenuItems(context, ref, isWindows: true),
    );
  }

  // Right-click helper called by the enclosing song row Gesture Detector
  static void showRightClickMenu(
    BuildContext context,
    Offset globalPos,
    WidgetRef ref,
    Map<String, dynamic> song, {
    bool inQueue = false,
    int? queueIndex,
    VoidCallback? onPlaylistChanged,
    int? playlistId,
    int? songEntryId,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );

    final button = SongOptionsButton(
      song: song,
      inQueue: inQueue,
      queueIndex: queueIndex,
      onPlaylistChanged: onPlaylistChanged,
      playlistId: playlistId,
      songEntryId: songEntryId,
    );
    showMenu(
      context: context,
      position: position,
      color: const Color(0xFF111019),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: button._buildMenuItems(context, ref, isWindows: true),
    );
  }

  List<PopupMenuEntry<void>> _buildMenuItems(BuildContext context, WidgetRef ref, {required bool isWindows}) {
    return [
      _popupItem(
        icon: Icons.play_arrow_rounded,
        title: "Play Now",
        onTap: () {
          ref.read(playerProvider.notifier).playSong(song, [song]);
        },
      ),
      _popupItem(
        icon: Icons.playlist_play_rounded,
        title: "Play Next",
        onTap: () {
          ref.read(playerProvider.notifier).playNext(song);
        },
      ),
      _popupItem(
        icon: Icons.queue_music_rounded,
        title: "Add to Queue",
        onTap: () {
          ref.read(playerProvider.notifier).addToQueue(song);
        },
      ),
      _popupItem(
        icon: Icons.playlist_add_rounded,
        title: "Add to Personal Playlist",
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPlaylistSelectionDialog(context, type: 'personal');
          });
        },
      ),
      _popupItem(
        icon: Icons.download_for_offline_rounded,
        title: "Download for Offline",
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPlaylistSelectionDialog(context, type: 'offline');
          });
        },
      ),
      if (song['local_file_path'] != null && (song['local_file_path'] as String).isNotEmpty)
        _popupItem(
          icon: Icons.delete_outline_rounded,
          title: "Remove Local Download",
          color: Colors.redAccent,
          onTap: () async {
            final songId = song['id'] as int;
            await DownloadManager().deleteDownloadedFile(songId);
            await OfflineStorage().removeSongDownload(songId);
            if (onPlaylistChanged != null) {
              onPlaylistChanged!();
            }
          },
        ),
      if (inQueue && queueIndex != null)
        _popupItem(
          icon: Icons.remove_circle_outline_rounded,
          title: "Remove from Queue",
          color: Colors.redAccent,
          onTap: () {
            ref.read(playerProvider.notifier).removeFromQueue(queueIndex!);
          },
        ),
      if (playlistId != null && songEntryId != null)
        _popupItem(
          icon: Icons.playlist_remove_rounded,
          title: "Remove from Playlist",
          color: Colors.redAccent,
          onTap: () async {
            await OfflineStorage().deleteSong(playlistId!, songEntryId!);
            if (onPlaylistChanged != null) {
              onPlaylistChanged!();
            }
          },
        ),
    ];
  }

  PopupMenuItem<void> _popupItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return PopupMenuItem<void>(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? const Color(0xFF8B5CF6), size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showAndroidBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111019),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // Song Info Header
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white30),
                ),
                title: Text(
                  song['title'] ?? 'Unknown Title',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  song['artist'] ?? 'Unknown Artist',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(color: Colors.white10),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.play_arrow_rounded,
                title: "Play Now",
                onTap: () {
                  ref.read(playerProvider.notifier).playSong(song, [song]);
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.playlist_play_rounded,
                title: "Play Next",
                onTap: () {
                  ref.read(playerProvider.notifier).playNext(song);
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.queue_music_rounded,
                title: "Add to Queue",
                onTap: () {
                  ref.read(playerProvider.notifier).addToQueue(song);
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.playlist_add_rounded,
                title: "Add to Personal Playlist",
                onTap: () {
                  _showPlaylistSelectionDialog(context, type: 'personal');
                },
              ),
              _bottomSheetItem(
                context: ctx,
                icon: Icons.download_for_offline_rounded,
                title: "Download for Offline",
                onTap: () {
                  _showPlaylistSelectionDialog(context, type: 'offline');
                },
              ),
              if (song['local_file_path'] != null && (song['local_file_path'] as String).isNotEmpty)
                _bottomSheetItem(
                  context: ctx,
                  icon: Icons.delete_outline_rounded,
                  title: "Remove Local Download",
                  color: Colors.redAccent,
                  onTap: () async {
                    final songId = song['id'] as int;
                    await DownloadManager().deleteDownloadedFile(songId);
                    await OfflineStorage().removeSongDownload(songId);
                    if (onPlaylistChanged != null) {
                      onPlaylistChanged!();
                    }
                  },
                ),
              if (inQueue && queueIndex != null)
                _bottomSheetItem(
                  context: ctx,
                  icon: Icons.remove_circle_outline_rounded,
                  title: "Remove from Queue",
                  color: Colors.redAccent,
                  onTap: () {
                    ref.read(playerProvider.notifier).removeFromQueue(queueIndex!);
                  },
                ),
              if (playlistId != null && songEntryId != null)
                _bottomSheetItem(
                  context: ctx,
                  icon: Icons.playlist_remove_rounded,
                  title: "Remove from Playlist",
                  color: Colors.redAccent,
                  onTap: () async {
                    await OfflineStorage().deleteSong(playlistId!, songEntryId!);
                    if (onPlaylistChanged != null) {
                      onPlaylistChanged!();
                    }
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomSheetItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF8B5CF6)),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }

  void _showPlaylistSelectionDialog(BuildContext context, {required String type}) {
    final storage = OfflineStorage();
    final playlists = storage.getPlaylists().where((p) => p['type'] == type).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111019),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            type == 'personal' ? "Add to Personal Playlist" : "Download for Offline",
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                // Create New Option
                ListTile(
                  leading: const Icon(Icons.add_rounded, color: Color(0xFF8B5CF6)),
                  title: Text(
                    type == 'personal' ? "Create New Personal Playlist" : "Create New Offline Playlist",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _showCreatePlaylistPrompt(context, type: type);
                  },
                ),
                const Divider(color: Colors.white10),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        "No playlists of this type",
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                ...playlists.map((pl) {
                  return ListTile(
                    leading: Icon(
                      type == 'personal' ? Icons.playlist_play_rounded : Icons.offline_pin_rounded,
                      color: const Color(0xFF8B5CF6),
                    ),
                    title: Text(
                      pl['name'] ?? 'Unnamed',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _addSongToPlaylist(context, pl['id'] as int, type: type);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreatePlaylistPrompt(BuildContext context, {required String type}) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111019),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          type == 'personal' ? "New Personal Playlist" : "New Offline Playlist",
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Playlist Name",
            hintStyle: TextStyle(color: Colors.white30),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF8B5CF6)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text("Create", style: TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final pl = await OfflineStorage().createPlaylist(name, type: type);
      if (context.mounted) {
        await _addSongToPlaylist(context, pl['id'] as int, type: type);
      }
    }
  }

  Future<void> _addSongToPlaylist(BuildContext context, int playlistId, {required String type}) async {
    final storage = OfflineStorage();
    await storage.addSongsToPlaylist(playlistId, [song]);

    if (type == 'offline') {
      // Find the song entry inside the updated playlist to get the correct entry ID for DownloadManager
      final pl = storage.getPlaylist(playlistId);
      if (pl != null) {
        final songs = List<Map<String, dynamic>>.from(pl['songs'] ?? []);
        final entry = songs.firstWhere((s) => s['song_id'] == song['id']);
        // Trigger download
        DownloadManager().downloadSong(playlistId, entry);
      }
    }

    if (onPlaylistChanged != null) {
      onPlaylistChanged!();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == 'personal' 
                ? "Added to Personal Playlist"
                : "Added to Offline Playlist (Download started)",
          ),
          backgroundColor: const Color(0xFF8B5CF6),
        ),
      );
    }
  }
}
