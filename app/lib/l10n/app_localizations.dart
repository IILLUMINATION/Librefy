import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Librefy'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get settingsLanguageRussian;

  /// No description provided for @settingsP2P.
  ///
  /// In en, this message translates to:
  /// **'Peer-assisted delivery (P2P)'**
  String get settingsP2P;

  /// No description provided for @settingsP2PSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Some tracks are streamed from peers instead of a server'**
  String get settingsP2PSubtitle;

  /// No description provided for @settingsBackendUrl.
  ///
  /// In en, this message translates to:
  /// **'Backend URL'**
  String get settingsBackendUrl;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About Librefy'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacy;

  /// No description provided for @p2pIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Peer-assisted streaming'**
  String get p2pIntroTitle;

  /// No description provided for @p2pIntroBody.
  ///
  /// In en, this message translates to:
  /// **'Librefy can play tracks delivered through peers instead of downloading every byte from a server. It\'s faster on busy networks and respects the project\'s lightweight backend ethic.'**
  String get p2pIntroBody;

  /// No description provided for @p2pIntroMeans.
  ///
  /// In en, this message translates to:
  /// **'What this means in practice:'**
  String get p2pIntroMeans;

  /// No description provided for @p2pIntroBullet1.
  ///
  /// In en, this message translates to:
  /// **'Some tracks open from a swarm via libtorrent.'**
  String get p2pIntroBullet1;

  /// No description provided for @p2pIntroBullet2.
  ///
  /// In en, this message translates to:
  /// **'Your device temporarily shares those pieces back.'**
  String get p2pIntroBullet2;

  /// No description provided for @p2pIntroBullet3.
  ///
  /// In en, this message translates to:
  /// **'Only tracks the operator marked as libre/CC are eligible.'**
  String get p2pIntroBullet3;

  /// No description provided for @p2pIntroBullet4.
  ///
  /// In en, this message translates to:
  /// **'Disk + bandwidth usage is bounded; see Settings.'**
  String get p2pIntroBullet4;

  /// No description provided for @p2pIntroEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable peer delivery'**
  String get p2pIntroEnable;

  /// No description provided for @p2pIntroContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get p2pIntroContinue;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyTitle;

  /// No description provided for @privacyIntro.
  ///
  /// In en, this message translates to:
  /// **'Before you continue, take a look at what happens with your data:'**
  String get privacyIntro;

  /// No description provided for @privacyDontCollectTitle.
  ///
  /// In en, this message translates to:
  /// **'What we DON\'T collect'**
  String get privacyDontCollectTitle;

  /// No description provided for @privacyDontCollect1.
  ///
  /// In en, this message translates to:
  /// **'No accounts — registration is not required.'**
  String get privacyDontCollect1;

  /// No description provided for @privacyDontCollect2.
  ///
  /// In en, this message translates to:
  /// **'No advertising IDs or third-party analytics SDKs.'**
  String get privacyDontCollect2;

  /// No description provided for @privacyDontCollect3.
  ///
  /// In en, this message translates to:
  /// **'We don\'t send your email, phone number, or contacts.'**
  String get privacyDontCollect3;

  /// No description provided for @privacyServerTitle.
  ///
  /// In en, this message translates to:
  /// **'What goes to the server'**
  String get privacyServerTitle;

  /// No description provided for @privacyServer1.
  ///
  /// In en, this message translates to:
  /// **'Catalog requests to the selected backend (default is the official Librefy server).'**
  String get privacyServer1;

  /// No description provided for @privacyServer2.
  ///
  /// In en, this message translates to:
  /// **'Anonymous per-track play counter (no user-id).'**
  String get privacyServer2;

  /// No description provided for @privacyServer3.
  ///
  /// In en, this message translates to:
  /// **'You can change the backend in Settings or run your own librefyd — then everything stays with you.'**
  String get privacyServer3;

  /// No description provided for @privacyP2PTitle.
  ///
  /// In en, this message translates to:
  /// **'P2P (optional)'**
  String get privacyP2PTitle;

  /// No description provided for @privacyP2P1.
  ///
  /// In en, this message translates to:
  /// **'If you enable peer delivery, your IP is briefly visible to other swarm participants.'**
  String get privacyP2P1;

  /// No description provided for @privacyP2P2.
  ///
  /// In en, this message translates to:
  /// **'Only CC / public-domain tracks are eligible.'**
  String get privacyP2P2;

  /// No description provided for @privacyP2P3.
  ///
  /// In en, this message translates to:
  /// **'P2P can be turned off in Settings at any time.'**
  String get privacyP2P3;

  /// No description provided for @privacyLocalTitle.
  ///
  /// In en, this message translates to:
  /// **'Locally on the device'**
  String get privacyLocalTitle;

  /// No description provided for @privacyLocal.
  ///
  /// In en, this message translates to:
  /// **'Cover-art and torrent caches stay only on your device and are removed when the app is uninstalled.'**
  String get privacyLocal;

  /// No description provided for @privacyAcceptHint.
  ///
  /// In en, this message translates to:
  /// **'By tapping \"Accept and continue\" you agree to the data handling described above.'**
  String get privacyAcceptHint;

  /// No description provided for @privacyExit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get privacyExit;

  /// No description provided for @privacyAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept and continue'**
  String get privacyAccept;

  /// No description provided for @playerNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get playerNowPlaying;

  /// No description provided for @playerQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get playerQueue;

  /// No description provided for @playerShuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get playerShuffle;

  /// No description provided for @playerRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get playerRepeat;

  /// No description provided for @trackLikeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to Liked'**
  String get trackLikeAdd;

  /// No description provided for @trackLikeRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from Liked'**
  String get trackLikeRemove;

  /// No description provided for @trackDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get trackDownload;

  /// No description provided for @trackAddToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get trackAddToPlaylist;

  /// No description provided for @downloadSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String downloadSaved(String path);

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(String error);

  /// No description provided for @errorP2POnlyEngineMissing.
  ///
  /// In en, this message translates to:
  /// **'This track is only available over P2P (magnet), but the torrent engine is not available on this device, and there is no HTTP source. Ask the operator to add a streamUrl in the admin panel.'**
  String get errorP2POnlyEngineMissing;

  /// No description provided for @errorP2POnlyOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'This track is only available over P2P (magnet), but the torrent engine couldn\'t open this magnet (no metadata, no peers, or invalid magnet), and there is no HTTP source.'**
  String get errorP2POnlyOpenFailed;

  /// No description provided for @errorNoSource.
  ///
  /// In en, this message translates to:
  /// **'This track has no playable source (no streamUrl, no magnet).'**
  String get errorNoSource;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
