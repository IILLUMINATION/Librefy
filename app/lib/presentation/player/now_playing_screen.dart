// Now Playing — full-screen player with artwork, transport, scrubber,
// queue access and license attribution.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_player_service.dart';
import '../../application/audio/audio_providers.dart';
import '../common/artwork.dart';
import '../common/track_actions.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(playbackSnapshotProvider);
    final svc = ref.watch(audioPlayerServiceProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Now playing'),
        actions: [
          if (snapAsync.valueOrNull?.current != null)
            DownloadIconButton(track: snapAsync.value!.current!),
          if (snapAsync.valueOrNull?.usingP2P == true) ...[
            _P2PChip(snap: snapAsync.value!),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: snapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (snap) {
          final t = snap.current;
          if (t == null) {
            return const Center(child: Text('Nothing is playing.'));
          }
          final progress = snap.duration.inMilliseconds == 0
              ? 0.0
              : snap.position.inMilliseconds / snap.duration.inMilliseconds;
          // LayoutBuilder lets the artwork shrink on short windows
          // (laptop debug, small phones, split-screen) so the column
          // never overflows. We cap the artwork at 320dp and at 40% of
          // the available height — whichever is smaller wins.
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final artSize = constraints.maxHeight * 0.4;
                final art = artSize.clamp(140.0, 320.0);
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    children: [
                      Artwork(url: t.artworkUrl, size: art, radius: 24),
                      const SizedBox(height: 20),
                      Text(
                        t.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.artist,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      if (snap.usingP2P) ...[
                        _P2PProgressBar(
                          progress: snap.p2pProgress,
                          peers: snap.p2pPeers,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: (v) {
                          final to = Duration(
                            milliseconds:
                                (snap.duration.inMilliseconds * v).round(),
                          );
                          svc.seek(to);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(snap.position)),
                            Text(_fmt(snap.duration)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            iconSize: 36,
                            onPressed: svc.previous,
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                          FilledButton(
                            onPressed: svc.togglePlay,
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(20),
                            ),
                            child: Icon(
                              snap.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 36,
                            ),
                          ),
                          IconButton(
                            iconSize: 36,
                            onPressed: svc.next,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      ),
                      if (t.attribution != null && t.attribution!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          t.attribution!,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final m = d.inMinutes.toString();
    return '$m:$s';
  }
}

class _P2PChip extends StatelessWidget {
  const _P2PChip({required this.snap});
  final PlaybackSnapshot snap;
  @override
  Widget build(BuildContext context) {
    final label = snap.p2pPeers > 0
        ? 'P2P · ${snap.p2pPeers}'
        : 'P2P';
    return Chip(
      avatar: const Icon(Icons.share_rounded, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _P2PProgressBar extends StatelessWidget {
  const _P2PProgressBar({required this.progress, required this.peers});
  final double progress;
  final int peers;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_download_outlined,
                size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Swarm cached ${(progress * 100).toStringAsFixed(0)}%'
              '${peers > 0 ? " · $peers peer${peers == 1 ? "" : "s"}" : ""}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(2)),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
