/// Whether a shop may still use the app: inside its 30-day free trial, or
/// inside a paid period. Dates come from the server, and "now" is the
/// SERVER's clock (plus the time elapsed since it was fetched), so changing
/// the phone's date can't extend a trial.
class ShopAccess {
  final DateTime trialEndsAt;
  final DateTime? subscriptionEndsAt;
  final bool isLifetime;
  final DateTime _serverNow;
  final Stopwatch _sinceFetch = Stopwatch()..start();

  ShopAccess({
    required this.trialEndsAt,
    required this.subscriptionEndsAt,
    this.isLifetime = false,
    required DateTime serverNow,
  }) : _serverNow = serverNow;

  factory ShopAccess.fromJson(Map<String, dynamic> json) {
    final sub = json['subscription_ends_at'] as String?;
    return ShopAccess(
      trialEndsAt: DateTime.parse(json['trial_ends_at'] as String),
      subscriptionEndsAt: sub == null ? null : DateTime.parse(sub),
      isLifetime: json['is_lifetime'] as bool? ?? false,
      serverNow: DateTime.parse(json['server_now'] as String),
    );
  }

  DateTime get now => _serverNow.add(_sinceFetch.elapsed);

  bool get hasSubscription =>
      subscriptionEndsAt != null && subscriptionEndsAt!.isAfter(now);

  bool get onTrial =>
      !isLifetime && !hasSubscription && trialEndsAt.isAfter(now);

  bool get hasAccess => isLifetime || hasSubscription || onTrial;

  /// Whole days left in the trial (a partial day counts as a day).
  int get trialDaysLeft {
    final left = trialEndsAt.difference(now);
    if (left.isNegative) return 0;
    return (left.inMinutes / (60 * 24)).ceil();
  }
}
