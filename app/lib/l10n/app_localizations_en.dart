// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Librefy';

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsP2P => 'Peer-assisted delivery (P2P)';

  @override
  String get settingsP2PSubtitle =>
      'Some tracks are streamed from peers instead of a server';

  @override
  String get settingsBackendUrl => 'Backend URL';

  @override
  String get settingsAbout => 'About Librefy';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsPrivacy => 'Privacy policy';

  @override
  String get p2pIntroTitle => 'Peer-assisted streaming';

  @override
  String get p2pIntroBody =>
      'Librefy can play tracks delivered through peers instead of downloading every byte from a server. It\'s faster on busy networks and respects the project\'s lightweight backend ethic.';

  @override
  String get p2pIntroMeans => 'What this means in practice:';

  @override
  String get p2pIntroBullet1 => 'Some tracks open from a swarm via libtorrent.';

  @override
  String get p2pIntroBullet2 =>
      'Your device temporarily shares those pieces back.';

  @override
  String get p2pIntroBullet3 =>
      'Only tracks the operator marked as libre/CC are eligible.';

  @override
  String get p2pIntroBullet4 =>
      'Disk + bandwidth usage is bounded; see Settings.';

  @override
  String get p2pIntroEnable => 'Enable peer delivery';

  @override
  String get p2pIntroContinue => 'Continue';

  @override
  String get privacyTitle => 'Privacy policy';

  @override
  String get privacyIntro =>
      'Before you continue, take a look at what happens with your data:';

  @override
  String get privacyDontCollectTitle => 'What we DON\'T collect';

  @override
  String get privacyDontCollect1 =>
      'No accounts — registration is not required.';

  @override
  String get privacyDontCollect2 =>
      'No advertising IDs or third-party analytics SDKs.';

  @override
  String get privacyDontCollect3 =>
      'We don\'t send your email, phone number, or contacts.';

  @override
  String get privacyServerTitle => 'What goes to the server';

  @override
  String get privacyServer1 =>
      'Catalog requests to the selected backend (default is the official Librefy server).';

  @override
  String get privacyServer2 => 'Anonymous per-track play counter (no user-id).';

  @override
  String get privacyServer3 =>
      'You can change the backend in Settings or run your own librefyd — then everything stays with you.';

  @override
  String get privacyP2PTitle => 'P2P (optional)';

  @override
  String get privacyP2P1 =>
      'If you enable peer delivery, your IP is briefly visible to other swarm participants.';

  @override
  String get privacyP2P2 => 'Only CC / public-domain tracks are eligible.';

  @override
  String get privacyP2P3 => 'P2P can be turned off in Settings at any time.';

  @override
  String get privacyLocalTitle => 'Locally on the device';

  @override
  String get privacyLocal =>
      'Cover-art and torrent caches stay only on your device and are removed when the app is uninstalled.';

  @override
  String get privacyAcceptHint =>
      'By tapping \"Accept and continue\" you agree to the data handling described above.';

  @override
  String get privacyExit => 'Quit';

  @override
  String get privacyAccept => 'Accept and continue';

  @override
  String get playerNowPlaying => 'Now playing';

  @override
  String get playerQueue => 'Queue';

  @override
  String get playerShuffle => 'Shuffle';

  @override
  String get playerRepeat => 'Repeat';

  @override
  String get trackLikeAdd => 'Add to Liked';

  @override
  String get trackLikeRemove => 'Remove from Liked';

  @override
  String get trackDownload => 'Download';

  @override
  String get trackAddToPlaylist => 'Add to playlist';

  @override
  String downloadSaved(String path) {
    return 'Saved to $path';
  }

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get errorP2POnlyEngineMissing =>
      'This track is only available over P2P (magnet), but the torrent engine is not available on this device, and there is no HTTP source. Ask the operator to add a streamUrl in the admin panel.';

  @override
  String get errorP2POnlyOpenFailed =>
      'This track is only available over P2P (magnet), but the torrent engine couldn\'t open this magnet (no metadata, no peers, or invalid magnet), and there is no HTTP source.';

  @override
  String get errorNoSource =>
      'This track has no playable source (no streamUrl, no magnet).';
}
