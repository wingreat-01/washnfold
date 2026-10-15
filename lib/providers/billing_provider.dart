import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/supabase_service.dart';
import '../utils/app_errors.dart';

/// Product ID of the one-time "Lifetime Plan" in Play Console
/// (Monetize -> Products -> In-app products). Must match exactly.
const kLifetimeProductId = 'lifetime_plan';

/// Google Play Billing for the Lifetime Plan (Android only; there is no Play
/// Billing on the web, where the app falls back to the email flow).
///
/// Flow: buy -> Play's purchase sheet -> the purchase token is sent to the
/// `verify-lifetime-purchase` Edge Function, which checks it with Google,
/// unlocks the shop and acknowledges the purchase.
class BillingProvider extends ChangeNotifier {
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Play's product (localized price), once loaded.
  ProductDetails? product;
  bool available = false;
  bool purchasing = false;
  String? error;

  /// Goes up each time a purchase has been verified and the shop unlocked.
  int activations = 0;

  /// Called after a verified purchase so the app can reload the shop's plan.
  Future<void> Function()? onLifetimeActivated;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // Looked up lazily: on the web there is no billing plugin to talk to.
  InAppPurchase get _iap => InAppPurchase.instance;

  Future<void> init() async {
    if (!supported || _sub != null) return;
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        logDebug('purchase stream error: $e');
        purchasing = false;
        notifyListeners();
      },
    );
    try {
      available = await _iap.isAvailable();
      if (available) {
        final res = await _iap.queryProductDetails({kLifetimeProductId});
        product = res.productDetails.isEmpty ? null : res.productDetails.first;
      }
    } catch (e) {
      logDebug('billing init failed: $e');
    }
    notifyListeners();
  }

  Future<void> buyLifetime() async {
    if (!supported || purchasing) return;
    error = null;
    await init();
    if (!available || product == null) {
      error = "Google Play isn't available right now. Please try again "
          'in a moment.';
      notifyListeners();
      return;
    }
    purchasing = true;
    notifyListeners();
    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product!),
      );
      if (!started) {
        purchasing = false;
        notifyListeners();
      }
    } catch (e) {
      logDebug('buyLifetime failed: $e');
      purchasing = false;
      error = 'Could not start the purchase. Please try again.';
      notifyListeners();
    }
  }

  /// For a purchase that was paid but not yet applied (e.g. after a
  /// reinstall or a dropped connection).
  Future<void> restore() async {
    if (!supported) return;
    error = null;
    await init();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      logDebug('restore failed: $e');
      error = 'Could not check your purchases. Please try again.';
      notifyListeners();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != kLifetimeProductId) continue;
      switch (p.status) {
        case PurchaseStatus.pending:
          purchasing = true;
          notifyListeners();
          break;
        case PurchaseStatus.error:
          purchasing = false;
          error = p.error?.message ?? 'The purchase did not go through.';
          if (p.pendingCompletePurchase) await _complete(p);
          notifyListeners();
          break;
        case PurchaseStatus.canceled:
          purchasing = false;
          if (p.pendingCompletePurchase) await _complete(p);
          notifyListeners();
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p);
          break;
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    purchasing = true;
    error = null;
    notifyListeners();
    try {
      await SupabaseService.instance.client.functions.invoke(
        'verify-lifetime-purchase',
        body: {
          'productId': p.productID,
          'purchaseToken': p.verificationData.serverVerificationData,
        },
      );
      if (p.pendingCompletePurchase) await _complete(p);
      activations++;
      await onLifetimeActivated?.call();
    } catch (e) {
      // Not completed on purpose: Google keeps the purchase and hands it to
      // the app again next time, so a failed check can be retried.
      logDebug('verify lifetime purchase failed: $e');
      error = "We couldn't confirm your purchase yet. You have not been "
          'charged twice. Tap "Restore purchase" in Settings to try again.';
    } finally {
      purchasing = false;
      notifyListeners();
    }
  }

  Future<void> _complete(PurchaseDetails p) async {
    try {
      await _iap.completePurchase(p);
    } catch (e) {
      // The server may already have acknowledged it; that is fine.
      logDebug('completePurchase: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
