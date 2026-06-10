// Reusable artwork tile with a graceful fallback when the URL is missing
// or fails to load.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    required this.url,
    this.size = 56,
    this.radius = 8,
    super.key,
  });

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded, color: scheme.onSurfaceVariant),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}
