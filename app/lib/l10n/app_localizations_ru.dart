// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Librefy';

  @override
  String get navHome => 'Главная';

  @override
  String get navSearch => 'Поиск';

  @override
  String get navLibrary => 'Библиотека';

  @override
  String get navSettings => 'Настройки';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsP2P => 'Пиринговая доставка (P2P)';

  @override
  String get settingsP2PSubtitle =>
      'Некоторые треки приходят от пиров, а не с сервера';

  @override
  String get settingsBackendUrl => 'Адрес backend';

  @override
  String get settingsAbout => 'О Librefy';

  @override
  String get settingsVersion => 'Версия';

  @override
  String get settingsPrivacy => 'Политика конфиденциальности';

  @override
  String get p2pIntroTitle => 'Пиринговая доставка';

  @override
  String get p2pIntroBody =>
      'Librefy умеет проигрывать треки, отдаваемые другими пирами, вместо того чтобы тянуть каждый байт с сервера. Это быстрее в загруженных сетях и бережнее к ресурсам бэкенда.';

  @override
  String get p2pIntroMeans => 'Что это значит на практике:';

  @override
  String get p2pIntroBullet1 =>
      'Некоторые треки открываются из swarm через libtorrent.';

  @override
  String get p2pIntroBullet2 =>
      'Ваше устройство временно раздаёт эти куски обратно.';

  @override
  String get p2pIntroBullet3 =>
      'Раздаются только треки, помеченные как libre/CC.';

  @override
  String get p2pIntroBullet4 =>
      'Использование диска и трафика ограничено — см. Настройки.';

  @override
  String get p2pIntroEnable => 'Включить пиринговую доставку';

  @override
  String get p2pIntroContinue => 'Продолжить';

  @override
  String get privacyTitle => 'Политика конфиденциальности';

  @override
  String get privacyIntro =>
      'Перед тем как продолжить, ознакомьтесь с тем, что происходит с вашими данными:';

  @override
  String get privacyDontCollectTitle => 'Что мы НЕ собираем';

  @override
  String get privacyDontCollect1 => 'Аккаунтов нет — регистрация не требуется.';

  @override
  String get privacyDontCollect2 =>
      'Нет рекламных идентификаторов и сторонних SDK-аналитик.';

  @override
  String get privacyDontCollect3 =>
      'Не отправляем e-mail, номер телефона или контакты.';

  @override
  String get privacyServerTitle => 'Что уходит на сервер';

  @override
  String get privacyServer1 =>
      'Запросы каталога к выбранному backend (по умолчанию — официальный сервер Librefy).';

  @override
  String get privacyServer2 =>
      'Анонимный счётчик прослушиваний трека (без user-id).';

  @override
  String get privacyServer3 =>
      'Адрес backend можно сменить в Настройках или поднять свой librefyd — тогда данные останутся у вас.';

  @override
  String get privacyP2PTitle => 'P2P (по желанию)';

  @override
  String get privacyP2P1 =>
      'Если включить пиринговую доставку, ваш IP временно виден другим участникам раздачи.';

  @override
  String get privacyP2P2 =>
      'Доступны только треки с лицензиями CC / public domain.';

  @override
  String get privacyP2P3 => 'P2P можно отключить в Настройках в любой момент.';

  @override
  String get privacyLocalTitle => 'Локально на устройстве';

  @override
  String get privacyLocal =>
      'Кэш обложек и торрент-кэш хранятся только на вашем устройстве и удаляются при удалении приложения.';

  @override
  String get privacyAcceptHint =>
      'Нажимая «Принять и продолжить», вы соглашаетесь с описанной выше обработкой данных.';

  @override
  String get privacyExit => 'Выйти';

  @override
  String get privacyAccept => 'Принять и продолжить';

  @override
  String get playerNowPlaying => 'Сейчас играет';

  @override
  String get playerQueue => 'Очередь';

  @override
  String get playerShuffle => 'Перемешать';

  @override
  String get playerRepeat => 'Повтор';

  @override
  String get trackLikeAdd => 'В избранное';

  @override
  String get trackLikeRemove => 'Убрать из избранного';

  @override
  String get trackDownload => 'Скачать';

  @override
  String get trackAddToPlaylist => 'Добавить в плейлист';

  @override
  String downloadSaved(String path) {
    return 'Сохранено в $path';
  }

  @override
  String downloadFailed(String error) {
    return 'Не удалось скачать: $error';
  }

  @override
  String get errorP2POnlyEngineMissing =>
      'Этот трек доступен только через P2P (magnet), но движок торрентов недоступен на этом устройстве, а HTTP-источника у трека нет. Попросите оператора добавить streamUrl в админ-панели.';

  @override
  String get errorP2POnlyOpenFailed =>
      'Этот трек доступен только через P2P (magnet), но движок не смог открыть magnet (нет метаданных, пиров или ссылка некорректна), а HTTP-источника у трека нет.';

  @override
  String get errorNoSource =>
      'У трека нет ни streamUrl, ни magnet — нечего воспроизводить.';
}
