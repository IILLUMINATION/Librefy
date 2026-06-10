// Library tab.
//
// Sections (top → bottom):
//   1. Liked (synthetic) — always present.
//   2. User playlists — created in-app, persisted on-device.
//   3. Recently played — ephemeral, in-memory only.
//
// Tapping the "+" FAB creates a new empty playlist.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/library/user_library.dart';
import '../../application/state/providers.dart';
import '../common/artwork.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(userLibraryProvider);
    final recent = ref.watch(recentlyPlayedProvider);
    final svc = ref.watch(audioPlayerServiceProvider);
    final liked = lib.liked!;
    final pls = lib.userPlaylists;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await _promptName(context);
          if (name == null || name.isEmpty) return;
          await ref.read(userLibraryProvider.notifier).createPlaylist(name);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New playlist'),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(title: Text('Library')),

          // Liked tile
          SliverToBoxAdapter(
            child: ListTile(
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: const Text('Liked',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${liked.trackIds.length} track${liked.trackIds.length == 1 ? "" : "s"}'),
              onTap: () => context.push('/library/playlist/${liked.id}'),
            ),
          ),

          // User playlists
          if (pls.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Your playlists',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            SliverList.builder(
              itemCount: pls.length,
              itemBuilder: (_, i) {
                final p = pls[i];
                return ListTile(
                  leading: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.queue_music_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                      '${p.trackIds.length} track${p.trackIds.length == 1 ? "" : "s"}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _showPlaylistMenu(context, ref, p.id, p.name),
                  ),
                  onTap: () => context.push('/library/playlist/${p.id}'),
                );
              },
            ),
          ],

          // Recently played
          if (recent.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 4),
                child: Text('Recently played',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            SliverList.builder(
              itemCount: recent.length,
              itemBuilder: (_, i) {
                final t = recent[i];
                return ListTile(
                  leading: Artwork(url: t.artworkUrl),
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(t.artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => svc.playQueue(recent, startIndex: i),
                );
              },
            ),
          ],

          if (pls.isEmpty && recent.isEmpty && liked.trackIds.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Tracks you like or play will show up here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  void _showPlaylistMenu(
      BuildContext context, WidgetRef ref, String id, String currentName) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final name =
                    await _promptName(context, initial: currentName);
                if (name == null || name.isEmpty) return;
                await ref
                    .read(userLibraryProvider.notifier)
                    .renamePlaylist(id, name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await ref.read(userLibraryProvider.notifier).deletePlaylist(id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(initial.isEmpty ? 'New playlist' : 'Rename playlist'),
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
          child: Text(initial.isEmpty ? 'Create' : 'Save'),
        ),
      ],
    ),
  );
}
