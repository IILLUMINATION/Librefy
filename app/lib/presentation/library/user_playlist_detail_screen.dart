// Detail view for a user-created playlist (or the synthetic Liked).
//
// Reads tracks straight out of UserLibrary — they were snapshotted at
// add-time, so this view doesn't require the backend to be reachable.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/library/user_library.dart';
import '../../domain/entities/track.dart';
import '../common/artwork.dart';

class UserPlaylistDetailScreen extends ConsumerWidget {
  const UserPlaylistDetailScreen({required this.playlistId, super.key});
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(userLibraryProvider);
    final pl = lib.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => UserPlaylist(id: playlistId, name: 'Unknown', trackIds: []),
    );
    final tracks = pl.trackIds
        .map((id) => lib.trackFor(id))
        .whereType<Track>()
        .toList();
    final svc = ref.watch(audioPlayerServiceProvider);
    final isLiked = pl.id == kLikedPlaylistId;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            title: Text(pl.name),
            flexibleSpace: FlexibleSpaceBar(
              background: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: isLiked
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.queue_music_rounded,
                      size: 64,
                      color: isLiked
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => svc.playQueue(tracks, startIndex: 0),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () {
                            svc.toggleShuffle();
                            svc.playQueue(tracks, startIndex: 0);
                          },
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('This playlist is empty.',
                      textAlign: TextAlign.center),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) {
                final t = tracks[i];
                return Dismissible(
                  key: ValueKey('${pl.id}:${t.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: scheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: Icon(Icons.delete_outline_rounded,
                        color: scheme.onErrorContainer),
                  ),
                  onDismissed: (_) {
                    ref
                        .read(userLibraryProvider.notifier)
                        .removeTrackFromPlaylist(pl.id, t.id);
                  },
                  child: ListTile(
                    leading: Artwork(url: t.artworkUrl),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => svc.playQueue(tracks, startIndex: i),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
