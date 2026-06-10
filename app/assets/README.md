# Librefy app assets

This file exists so the `assets/` directory always contains at least
one bundled file. Flutter's tool only generates `AssetManifest.bin`
when there is at least one declared asset; an empty manifest crashes
`google_fonts` at runtime (it tries to look up cached font binaries
through the asset bundle before falling back to network fetch).

Drop additional assets here and list them in `pubspec.yaml`.
