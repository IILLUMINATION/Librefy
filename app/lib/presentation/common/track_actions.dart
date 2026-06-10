// Track-level action widgets:
//   - DownloadIconButton — save current track to disk with progress.
//   - LikeIconButton     — toggle the synthetic "Liked" playlist.
//   - AddToPlaylistButton — menu to add the track to any user playlist
//                            (with "Create new…" inline).
// All three live in presentation/common so list rows, Now Playing, and
// any future tile can drop them in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/download/download_service.dart';
import '../../application/library/user_library.dart';
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

class LikeIconButton extends ConsumerWidget {
  const LikeIconButton({required this.track, super.key});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(userLibraryProvider).isLiked(track.id);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: liked ? 'Remove from Liked' : 'Add to Liked',
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ? scheme.primary : null,
      ),
      onPressed: () async {
        await ref.read(userLibraryProvider.notifier).toggleLike(track);
      },
    );
  }
}

class AddToPlaylistButton extends ConsumerWidget {
  const AddToPlaylistButton({required this.track, super.key});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Add to playlist',
      icon: const Icon(Icons.playlist_add_rounded),
      onPressed: () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _AddToPlaylistSheet(track: track),
    );
  }
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(userLibraryProvider);
    final playlists = lib.userPlaylists;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Add to playlist',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('Create new playlist'),
            onTap: () async {
              Navigator.of(context).pop();
              final name = await _promptForName(context);
              if (name == null || name.isEmpty) return;
              final pl =
                  await ref.read(userLibraryProvider.notifier).createPlaylist(name);
              await ref
                  .read(userLibraryProvider.notifier)
                  .addTrackToPlaylist(pl.id, track);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added to "${pl.name}"')),
                );
              }
            },
          ),
          const Divider(),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Text(
                'You have no playlists yet. Tap "Create new playlist" above.',
              ),
            ),
          for (final p in playlists)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(p.name),
              subtitle: Text(
                  '${p.trackIds.length} track${p.trackIds.length == 1 ? "" : "s"}'),
              trailing: p.trackIds.contains(track.id)
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () async {
                await ref
                    .read(userLibraryProvider.notifier)
                    .addTrackToPlaylist(p.id, track);
                if (context.mounted) Navigator.of(context).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added to "${p.name}"')),
                  );
                }
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

Future<String?> _promptForName(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
