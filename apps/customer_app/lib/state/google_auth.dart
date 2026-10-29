import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

String? _nonEmpty(String value) => value.isEmpty ? null : value;

/// Web uses the Web client ID directly; Android / iOS ask Google for an ID token
/// whose audience is the Web client ID (serverClientId), which the API verifies.
final GoogleSignIn _google = GoogleSignIn(
  scopes: const ['email', 'profile'],
  clientId: kIsWeb
      ? _nonEmpty(BmConfig.googleWebClientId)
      : (defaultTargetPlatform == TargetPlatform.iOS ? _nonEmpty(BmConfig.googleIosClientId) : null),
  serverClientId: kIsWeb ? null : _nonEmpty(BmConfig.googleWebClientId),
);

/// Returns false when the user closed the Google window.
Future<bool> signInWithGoogle(Session session, String locale) async {
  final account = await _google.signIn();
  if (account == null) return false;
  final auth = await account.authentication;
  await session.loginWithGoogle(idToken: auth.idToken, accessToken: auth.accessToken, locale: locale);
  return true;
}

Future<void> signOutGoogle() async {
  try {
    await _google.signOut();
  } catch (_) {
    // Not signed in with Google.
  }
}
