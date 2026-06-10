# Legal & Licensing Policy

Librefy ships **only** content that is legally redistributable.
This document is the policy the project commits to.

## In-scope content

The official catalog and the default-built app may surface tracks under:

- Public domain (PD, `CC0`)
- Creative Commons attribution variants (`CC-BY`, `CC-BY-SA`, `CC-BY-ND`, `CC-BY-NC` *with operator opt-in*)
- Royalty-free / redistribute-allowed licences explicitly granted by the rights holder
- Music released by artists under terms that permit streaming, caching and redistribution

Every track stored in the database carries a `license` block:

```json
{
  "code": "CC-BY-4.0",
  "name": "Creative Commons Attribution 4.0",
  "url": "https://creativecommons.org/licenses/by/4.0/"
}
```

Tracks without verified licence metadata are **not** displayed by the
official app and **not** indexed by the official providers.

## Out-of-scope content

The official build never:

- Indexes commercial copyrighted catalogues (Spotify / YouTube Music / etc.).
- Bundles scrapers, DRM-circumvention helpers, or pirate-stream providers.
- Promotes, mirrors or links to such providers.

## Torrent / P2P

`libtorrent` and similar engines are **delivery technologies**. Librefy
uses them strictly to reduce the load on the original libre content
hosts. The torrent layer in the official build:

- Is opt-in (default build ships `HttpOnlyTorrentService`).
- Only opens swarms whose magnet URIs come from the libre catalog.
- Does not expose a "general-purpose" torrent client UI.

## Third-party / community providers

The provider architecture lets users plug in additional sources. Such
plugins are not part of the official project. Users who install them
take full responsibility for the legality of the content surfaced.

## Attribution

The Now Playing screen displays the `attribution` string whenever a
track is played for the first time in a session, so CC-BY-style
requirements are met without user effort.

## Removal requests

If you are the rights holder of content surfaced by an official
provider and you want it removed, open an issue with proof of
ownership. Removal is automatic for content that turns out to lack a
verifiable libre licence.
