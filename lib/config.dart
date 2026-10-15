/// Fill these in from your Supabase project settings (Project Settings → API).
/// For real deployments, prefer passing these via --dart-define instead of
/// hardcoding them here:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dietefbjoywhmebwzhww.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRpZXRlZmJqb3l3aG1lYnd6aHd3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyNzE3NjAsImV4cCI6MjEwNjg0Nzc2MH0.HgVdhqoifW0nJs9jdLkspT4gfggrkmCzJazy71LSouY',
  );

  /// Where people write to subscribe after the free trial. Change this to
  /// your real support address.
  static const supportEmail = 'laundrymate@prohubapps.com';

  /// Lifetime Plan: one-time price in pesos (early launch promo).
  static const lifetimePricePhp = 790;

  /// The public URL this web app is deployed at, used to build the
  /// customer-facing tracking links encoded in each order's QR code.
  /// Pass your real domain once deployed:
  ///   --dart-define=WEB_BASE_URL=https://laundrymate.prohubapps.com
  static const webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://laundrymate.prohubapps.com',
  );

  /// Web OAuth client ID from Google Cloud (the same one set in Supabase →
  /// Authentication → Providers → Google). The native Android sign-in uses it
  /// as serverClientId so the ID token is accepted by Supabase.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '588477716677-ivogpk6e7rrgcle9rrq6qt2iv9rlnbqt.apps.googleusercontent.com',
  );

  /// No longer used by Google sign-in (Android now signs in natively). Kept
  /// only so the AndroidManifest.xml deep link still matches; safe to delete
  /// together with that intent-filter.
  static const mobileAuthRedirect = 'io.supabase.washnfold://login-callback';

  /// Public privacy policy page (served from web/privacy/index.html).
  static String get privacyPolicyUrl => '$webBaseUrl/privacy';

  static String trackingUrl(String orderId) => '$webBaseUrl/track/$orderId';

  /// Permanent QR URL for one shop. The shop UUID is an identifier, not a
  /// secret; the database RPC still scopes every lookup to this shop.
  static String shopTrackingUrl(String shopId) =>
      '$webBaseUrl/track?shop=$shopId';

  /// Typical length of one wash cycle, in minutes. Used only to ESTIMATE how
  /// long a waiting order must wait for a washer to free up (washer start
  /// time + this). Change it to match your machines.
  static const washerCycleMinutes = 45;

  /// Same idea for dryers. Each machine can override both from its
  /// Configure form; these are only the defaults for new machines.
  static const dryerCycleMinutes = 60;
}
