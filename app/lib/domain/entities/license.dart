// Licence metadata.
//
// We display the [code] in compact UI (e.g. chips) and use [name] + [url]
// in the "About this track" sheet. [attribution] holds the credit string
// required by some CC licences and should be shown whenever the track
// plays for the first time in a session.
import 'package:flutter/foundation.dart';

@immutable
class License {
  const License({
    required this.code,
    required this.name,
    this.url,
  });

  final String code;
  final String name;
  final String? url;

  /// A safe placeholder for missing or unrecognised licences. The UI MUST
  /// surface this clearly so unverified material is never auto-played
  /// in the official catalog.
  static const License unknown = License(code: 'UNKNOWN', name: 'Unknown');

  bool get isLibre {
    final c = code.toUpperCase();
    return c.startsWith('CC') || c == 'PD' || c == 'PUBLIC-DOMAIN';
  }
}
