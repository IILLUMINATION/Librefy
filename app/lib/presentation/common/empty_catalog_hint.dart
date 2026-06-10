// Empty-catalog UI shown on Home when the backend returns no tracks.
//
// Two possible root causes the user might hit:
//   - The backend isn't running.
//   - The backend is running but the catalog is empty (e.g. stale DB
//     from before the embedded-seed change).
//
// We surface both, point at the configured base URL, and offer a quick
// jump into Settings so the user can verify it without diving into code.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/state/providers.dart';

class EmptyCatalogHint extends ConsumerWidget {
  const EmptyCatalogHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.library_music_outlined,
                    size: 28,
                    color: scheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Catalog is empty',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'No tracks were returned by the backend. Make sure '
                'librefyd is running and seeded.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Backend: $baseUrl',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => context.go('/settings'),
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Open settings'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      // Trigger a fresh fetch by invalidating the providers.
                      ref.invalidate(featuredPlaylistsProvider);
                      ref.invalidate(trendingTracksProvider);
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
