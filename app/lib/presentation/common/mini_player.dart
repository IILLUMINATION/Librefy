// MiniPlayer — the always-on playback control strip pinned above the
// navigation bar. Tapping it expands to the full Now Playing screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/audio/audio_providers.dart';
import 'artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(playbackSnapshotProvider);
    final snap = snapAsync.valueOrNull;
    final track = snap?.current;
    if (track == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final progress = (snap!.duration.inMilliseconds == 0)
        ? 0.0
        : (snap.position.inMilliseconds / snap.duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => context.push('/now-playing'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Artwork(url: track.artworkUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: ref.read(audioPlayerServiceProvider).togglePlay,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: ref.read(audioPlayerServiceProvider).next,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(2)),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
