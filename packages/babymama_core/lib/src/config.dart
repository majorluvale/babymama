/// Build-time configuration, passed with --dart-define. Example:
///   flutter run --dart-define=API_URL=http://10.0.2.2:4000
class BmConfig {
  /// Base URL of the Babymama API (without /api).
  /// Android emulator: http://10.0.2.2:4000 - real device: your computer's LAN IP.
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:4000');

  /// Google OAuth "Web application" client ID (used on web, and as server client ID on mobile).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google OAuth iOS client ID.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static const supportPhone = String.fromEnvironment('SUPPORT_PHONE', defaultValue: '+254700000000');
  static const supportWhatsapp = String.fromEnvironment('SUPPORT_WHATSAPP', defaultValue: '254700000000');
}
