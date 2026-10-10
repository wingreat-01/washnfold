import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Logs only in debug builds. In release builds nothing is written to the
/// device log (Android logcat / browser console).
void logDebug(String message) {
  if (kDebugMode) debugPrint(message);
}

void logStack(StackTrace stackTrace) {
  if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
}

/// Turns any exception into a short message that is safe to show to a user.
///
/// Raw exception text can contain table names, constraint names, SQL hints
/// and server details, so it is never shown. Messages written by this app
/// itself ([StaffActionException], [AccountDeletionException], [StateError])
/// are already readable and are passed through.
///
/// Always call [logDebug] with the real error before showing this.
String friendlyError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is StaffActionException) return error.message;
  if (error is AccountDeletionException) return error.message;
  if (error is StateError) return error.message;

  if (error is TimeoutException) {
    return 'The server took too long to answer. Please try again.';
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501': // insufficient_privilege / RLS
        return "You don't have permission to do that.";
      case '23505': // unique_violation
        return 'That already exists.';
      case '23503': // foreign_key_violation
        return "That can't be changed because it is still in use.";
      case '23514': // check_violation
      case '22001': // string too long
        return 'Some of the details are not valid. Please check and try again.';
    }
    return fallback;
  }
  if (error is AuthException) {
    return 'Your session has expired or the sign-in failed. Please sign in again.';
  }

  // Network failures (SocketException, ClientException, ...). Matched by
  // name so this file also compiles for web, where dart:io is unavailable.
  final type = error.runtimeType.toString();
  if (type.contains('SocketException') ||
      type.contains('ClientException') ||
      type.contains('HandshakeException')) {
    return 'No connection. Check your internet and try again.';
  }
  return fallback;
}
