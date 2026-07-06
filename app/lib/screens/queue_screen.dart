import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../widgets/song_cover.dart';
import 'dart:io' show Platform;
import '../widgets/song_options_menu.dart';
import '../widgets/song_download_indicator.dart';
import '../widgets/mini_player.dart';
import 'now_playing_screen.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    final currentSong = playerState.currentSong;
    final manualQueue = playerState.queue;
    final showNowPlaying = ref.watch(showNowPlayingProvider);

    final remainingPlaylistSongs = <Map<String, dynamic>>[];
    if (currentSong != null && playerState.activePlaylist.isNotEmpty) {
      final currentIdx = playerState.activePlaylist.indexWhere((s) => s["id"] == currentSong["id"]);
      if (currentIdx != -1) {
        for (int i = currentIdx + 1; i < playerState.activePlaylist.length; i++) {
          remainingPlaylistSongs.add(playerState.activePlaylist[i]);
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF08070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111019),
        foregroundColor: Colors.white,
        title: const Text("Play Queue", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (manualQueue.isNotEmpty)
            TextButton(
              onPressed: () => notifier.clearQueue(),
              child: const Text("Clear Queue", style: TextStyle(color: Color(0xFF8B5CF6))),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (currentSong != null) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                        child: Text("Now playing", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: GestureDetector(
                        onSecondaryTapDown: (details) {
                          if (Platform.isWindows) {
                            SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, currentSong);
                          }
                        },
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          leading: SongCoverWidget(
                            song: currentSong,
                            width: 48,
                            height: 48,
                            borderRadius: 6.0,
                          ),
                          title: Text(
                            currentSong["title"] ?? "Unknown Track",
                            style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            currentSong["artist"] ?? "Unknown Artist",
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SongDownloadIndicator(songId: currentSong["id"]),
                              const SizedBox(width: 6),
                              SongOptionsButton(song: currentSong),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (manualQueue.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                        child: Text("Next in Queue", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SliverReorderableList(
                      itemCount: manualQueue.length,
                      onReorder: (oldIndex, newIndex) {
                        notifier.reorderQueue(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final s = manualQueue[index];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey("queue_${s['id']}_$index"),
                          index: index,
                          child: Dismissible(
                            key: ValueKey("dismiss_${s['id']}_$index"),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              notifier.removeFromQueue(index);
                            },
                            background: Container(
                              color: Colors.redAccent.withOpacity(0.2),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                            ),
                            child: GestureDetector(
                              onSecondaryTapDown: (details) {
                                if (Platform.isWindows) {
                                  SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s, inQueue: true, queueIndex: index);
                                }
                              },
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                leading: SongCoverWidget(
                                  song: s,
                                  width: 44,
                                  height: 44,
                                  borderRadius: 6.0,
                                ),
                                title: Text(
                                  s["title"] ?? "Unknown Track",
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  s["artist"] ?? "Unknown Artist",
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SongDownloadIndicator(songId: s["id"]),
                                    const SizedBox(width: 6),
                                    SongOptionsButton(song: s, inQueue: true, queueIndex: index),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.drag_handle_rounded, color: Colors.white24),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  if (remainingPlaylistSongs.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                        child: Text("Next up from active list", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final s = remainingPlaylistSongs[index];
                          return GestureDetector(
                            onSecondaryTapDown: (details) {
                              if (Platform.isWindows) {
                                SongOptionsButton.showRightClickMenu(context, details.globalPosition, ref, s);
                              }
                            },
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              leading: SongCoverWidget(
                                song: s,
                                width: 44,
                                height: 44,
                                borderRadius: 6.0,
                              ),
                              title: Text(
                                s["title"] ?? "Unknown Track",
                                style: const TextStyle(color: Colors.white60, fontSize: 14),
                              ),
                              subtitle: Text(
                                s["artist"] ?? "Unknown Artist",
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SongDownloadIndicator(songId: s["id"]),
                                  const SizedBox(width: 6),
                                  SongOptionsButton(song: s),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: remainingPlaylistSongs.length,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!kIsWeb && Platform.isAndroid && currentSong != null && !showNowPlaying)
              MiniPlayer(
                onTap: () {
                  ref.read(showNowPlayingProvider.notifier).state = true;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NowPlayingScreen(),
                    ),
                  ).then((_) {
                    ref.read(showNowPlayingProvider.notifier).state = false;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}
