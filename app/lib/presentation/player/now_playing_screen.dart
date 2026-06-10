// Now Playing — full-screen player with artwork, transport, scrubber,
// queue access and license attribution.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_providers.dart';
import '../common/artwork.dart';

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
          if (snapAsync.valueOrNull?.usingP2P == true)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.share_rounded, size: 16),
                label: const Text('P2P'),
                visualDensity: VisualDensity.compact,
              ),
            ),
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
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(),
                  Artwork(url: t.artworkUrl, size: 320, radius: 24),
                  const SizedBox(height: 24),
                  Text(t.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(t.artist,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 24),
                  Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (v) {
                      final to = Duration(
                        milliseconds: (snap.duration.inMilliseconds * v).round(),
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
                          snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
                  const SizedBox(height: 24),
                  if (t.attribution != null && t.attribution!.isNotEmpty)
                    Text(
                      t.attribution!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  const Spacer(),
                ],
              ),
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
