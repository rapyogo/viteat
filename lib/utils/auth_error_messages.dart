import 'package:firebase_auth/firebase_auth.dart';

/// Messages d'erreur d'authentification lisibles (cles traduites via `.tr`
/// par ShowToastDialog.showToast). Avant, la plupart des codes Firebase ne
/// produisaient aucun message (ex. `invalid-credential`) ou affichaient le
/// texte anglais brut de Firebase.
class AuthErrorMessages {
  AuthErrorMessages._();

  static String fromException(Object error) {
    if (error is FirebaseAuthException) return fromCode(error.code);
    return "Something went wrong. Check your internet connection and try again.";
  }

  static String fromCode(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'INVALID_LOGIN_CREDENTIALS':
        return "Incorrect email or password.";
      case 'invalid-email':
        return "Invalid Email.";
      case 'user-disabled':
        return "This account has been disabled. Please contact support.";
      case 'too-many-requests':
        return "Too many attempts. Please wait a few minutes and try again.";
      case 'network-request-failed':
        return "No internet connection. Check your network and try again.";
      case 'invalid-phone-number':
        return "The phone number you entered looks invalid. Please check and try again.";
      case 'quota-exceeded':
        return "Too many SMS requests. Please try again later.";
      case 'captcha-check-failed':
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return "Security check failed. Please try again.";
      case 'invalid-verification-code':
        return "Invalid Code";
      case 'session-expired':
        return "The code has expired. Please request a new one.";
      default:
        return "Something went wrong. Please try again.";
    }
  }
}
