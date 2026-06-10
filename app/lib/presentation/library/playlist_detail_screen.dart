// Playlist detail: header with artwork + description, followed by the
// expanded list of tracks. Tapping a row plays the playlist from that
// point so the whole list becomes the active queue.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/state/providers.dart';
import '../../domain/entities/track.dart';
import '../common/artwork.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(playlistDetailProvider(id));

    return detail.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator.adaptive())),
      error: (e, _) => Scaffold(body: Center(child: Text(e.toString()))),
      data: (d) {
        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              pinned: true,
              expandedHeight: 280,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(d.playlist.title),
                background: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Artwork(url: d.playlist.artworkUrl, size: 180, radius: 16),
                  ),
                ),
              ),
            ),
            if (d.playlist.description != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(d.playlist.description!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: d.tracks.isEmpty
                          ? null
                          : () => ref
                              .read(audioPlayerServiceProvider)
                              .playQueue(d.tracks, startIndex: 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: d.tracks.length,
              itemBuilder: (_, i) => _Tile(
                track: d.tracks[i],
                queue: d.tracks,
                index: i,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      },
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.track, required this.queue, required this.index});
  final Track track;
  final List<Track> queue;
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Artwork(url: track.artworkUrl),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        ref.read(recentlyPlayedProvider.notifier).push(track);
        ref.read(audioPlayerServiceProvider).playQueue(queue, startIndex: index);
      },
    );
  }
}
