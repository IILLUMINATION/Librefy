// Search screen with debounced input.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/state/providers.dart';
import '../../domain/entities/track.dart';
import '../common/artwork.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SearchBar(
            controller: _ctrl,
            onChanged: _onChanged,
            hintText: 'Search libre music',
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (_ctrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _ctrl.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: results.when(
            data: (res) {
              final tracks = res.tracks;
              if (tracks.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _ctrl.text.isEmpty
                          ? 'Try searching for an artist, mood or genre.'
                          : 'No matches.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) => _SearchTrackTile(
                  track: tracks[i],
                  queue: tracks,
                  index: i,
                ),
              );
            },
            error: (e, _) => Center(child: Text(e.toString())),
            loading: () => const Center(child: CircularProgressIndicator.adaptive()),
          ),
        ),
      ],
    );
  }
}

class _SearchTrackTile extends ConsumerWidget {
  const _SearchTrackTile({required this.track, required this.queue, required this.index});
  final Track track;
  final List<Track> queue;
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Artwork(url: track.artworkUrl),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${track.artist} • ${track.provider}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Chip(
        label: Text(track.license.code, style: Theme.of(context).textTheme.labelSmall),
        visualDensity: VisualDensity.compact,
      ),
      onTap: () {
        ref.read(recentlyPlayedProvider.notifier).push(track);
        ref.read(audioPlayerServiceProvider).playQueue(queue, startIndex: index);
      },
    );
  }
}
