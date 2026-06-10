// Home screen: featured playlists, trending tracks, recently played.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/state/providers.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../common/artwork.dart';
import '../common/empty_catalog_hint.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredPlaylistsProvider);
    final trending = ref.watch(trendingTracksProvider);
    final recent = ref.watch(recentlyPlayedProvider);

    // Show the big empty-catalog hint when BOTH featured and trending
    // came back empty. Single-section emptiness uses inline placeholders.
    final bothEmpty = featured.maybeWhen(
          data: (l) => l.isEmpty,
          orElse: () => false,
        ) &&
        trending.maybeWhen(
          data: (l) => l.isEmpty,
          orElse: () => false,
        );

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('Librefy'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => context.go('/search'),
            ),
          ],
        ),

        if (bothEmpty)
          const SliverToBoxAdapter(child: EmptyCatalogHint())
        else ...[
          const SliverToBoxAdapter(
            child: _SectionHeader(title: 'Featured'),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: featured.when(
                data: (pls) => _PlaylistRow(playlists: pls),
                error: (e, _) => _ErrorTile(message: e.toString()),
                loading: () => const _RowLoading(),
              ),
            ),
          ),
          if (recent.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: _SectionHeader(title: 'Recently played'),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: _RecentRow(tracks: recent),
              ),
            ),
          ],
          const SliverToBoxAdapter(
            child: _SectionHeader(title: 'Trending libre tracks'),
          ),
          trending.when(
            data: (tracks) {
              if (tracks.isEmpty) {
                return const SliverToBoxAdapter(
                  child: _EmptyTile(label: 'No trending tracks yet'),
                );
              }
              return SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) => _TrackTile(
                  track: tracks[i],
                  queue: tracks,
                  index: i,
                ),
              );
            },
            error: (e, _) => SliverToBoxAdapter(child: _ErrorTile(message: e.toString())),
            loading: () => const SliverToBoxAdapter(child: _RowLoading()),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlists});
  final List<Playlist> playlists;
  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) return const _EmptyTile(label: 'No playlists yet');
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: playlists.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final p = playlists[i];
        return SizedBox(
          width: 160,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            onTap: () => context.push('/playlist/${Uri.encodeComponent(p.id)}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Artwork(url: p.artworkUrl, size: 160, radius: 12),
                const SizedBox(height: 8),
                Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                if (p.description != null)
                  Text(p.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.tracks});
  final List<Track> tracks;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final t = tracks[i];
        return SizedBox(
          width: 140,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            onTap: () {
              ref.read(audioPlayerServiceProvider).playQueue(tracks, startIndex: i);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Artwork(url: t.artworkUrl, size: 140, radius: 12),
                const SizedBox(height: 8),
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile({required this.track, required this.queue, required this.index});
  final Track track;
  final List<Track> queue;
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Artwork(url: track.artworkUrl),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Chip(
        label: Text(track.license.code, style: Theme.of(context).textTheme.labelSmall),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
      onTap: () {
        ref.read(recentlyPlayedProvider.notifier).push(track);
        ref.read(audioPlayerServiceProvider).playQueue(queue, startIndex: index);
      },
    );
  }
}

class _RowLoading extends StatelessWidget {
  const _RowLoading();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator.adaptive(),
        ),
      );
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      );
}
