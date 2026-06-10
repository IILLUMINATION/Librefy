// Library screen — for now a "Recently played" list. Will host
// user-curated playlists in v0.2 (still device-local, privacy-first).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/state/providers.dart';
import '../common/artwork.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(recentlyPlayedProvider);
    final svc = ref.watch(audioPlayerServiceProvider);

    return CustomScrollView(
      slivers: [
        const SliverAppBar.medium(title: Text('Library')),
        if (tracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Tracks you play will show up here.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              return ListTile(
                leading: Artwork(url: t.artworkUrl),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => svc.playQueue(tracks, startIndex: i),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}
