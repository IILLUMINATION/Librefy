// Track-level action widgets, currently just the "download to device"
// icon button. Lives in presentation/common so any list/tile/now-playing
// view can drop one in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/download/download_service.dart';
import '../../domain/entities/track.dart';

class DownloadIconButton extends ConsumerWidget {
  const DownloadIconButton({required this.track, super.key});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(downloadProgressProvider(track.id)).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    if (progress != null && progress.done && progress.error == null) {
      return IconButton(
        tooltip: 'Saved to ${progress.path}',
        icon: Icon(Icons.download_done_rounded, color: scheme.primary),
        onPressed: () => _showSavedSnackBar(context, progress.path!),
      );
    }
    if (progress != null && !progress.done) {
      return Tooltip(
        message:
            'Downloading… ${(progress.fraction * 100).toStringAsFixed(0)}%',
        child: SizedBox.square(
          dimension: 40,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: CircularProgressIndicator(
              value: progress.total > 0 ? progress.fraction : null,
              strokeWidth: 2.5,
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Download',
      icon: const Icon(Icons.download_outlined),
      onPressed: () => _start(context, ref),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(downloadServiceProvider);
    final player = ref.read(audioPlayerServiceProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final src = await player.resolveForDownload(track.id);
      final path = await svc.download(track, src.uri);
      if (context.mounted) _showSavedSnackBar(context, path);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  void _showSavedSnackBar(BuildContext context, String path) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Saved to $path',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
