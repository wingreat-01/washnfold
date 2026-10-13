import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_errors.dart';

/// One supported currency: how it is written and which cash values the
/// "amount tendered" quick buttons should offer.
class AppCurrency {
  final String code;
  final String name;
  final String symbol;

  /// 0 for currencies with no minor unit (yen, won...), otherwise 2.
  final int minorDigits;

  /// Common notes / coins used for the quick-cash chips.
  final List<double> bills;

  /// "Round up to a stack of ..." step, e.g. 100 for pesos.
  final double stackStep;

  /// Round-up steps offered once the total is above [largestBill].
  final List<double> roundUpSteps;
  final double largestBill;

  const AppCurrency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.bills,
    required this.stackStep,
    required this.roundUpSteps,
    required this.largestBill,
    this.minorDigits = 2,
  });

  static const php = AppCurrency(
    code: 'PHP',
    name: 'Philippine peso',
    symbol: '₱',
    // ₱200 is left out on purpose (BSP halted production in 2021).
    bills: [20, 50, 100, 500, 1000],
    stackStep: 100,
    roundUpSteps: [50, 100, 500],
    largestBill: 1000,
  );

  static const all = <AppCurrency>[
    php,
    AppCurrency(
      code: 'USD',
      name: 'US dollar',
      symbol: '\$',
      bills: [1, 5, 10, 20, 50, 100],
      stackStep: 10,
      roundUpSteps: [5, 10, 50],
      largestBill: 100,
    ),
    AppCurrency(
      code: 'EUR',
      name: 'Euro',
      symbol: '€',
      bills: [5, 10, 20, 50, 100, 200],
      stackStep: 10,
      roundUpSteps: [5, 10, 50],
      largestBill: 200,
    ),
    AppCurrency(
      code: 'GBP',
      name: 'British pound',
      symbol: '£',
      bills: [5, 10, 20, 50],
      stackStep: 10,
      roundUpSteps: [5, 10, 50],
      largestBill: 50,
    ),
    AppCurrency(
      code: 'JPY',
      name: 'Japanese yen',
      symbol: '¥',
      minorDigits: 0,
      bills: [1000, 5000, 10000],
      stackStep: 1000,
      roundUpSteps: [500, 1000, 5000],
      largestBill: 10000,
    ),
    AppCurrency(
      code: 'KRW',
      name: 'South Korean won',
      symbol: '₩',
      minorDigits: 0,
      bills: [1000, 5000, 10000, 50000],
      stackStep: 10000,
      roundUpSteps: [1000, 5000, 10000],
      largestBill: 50000,
    ),
    AppCurrency(
      code: 'SGD',
      name: 'Singapore dollar',
      symbol: 'S\$',
      bills: [2, 5, 10, 50, 100],
      stackStep: 10,
      roundUpSteps: [5, 10, 50],
      largestBill: 100,
    ),
    AppCurrency(
      code: 'AUD',
      name: 'Australian dollar',
      symbol: 'A\$',
      bills: [5, 10, 20, 50, 100],
      stackStep: 10,
      roundUpSteps: [5, 10, 50],
      largestBill: 100,
    ),
    AppCurrency(
      code: 'CAD',
      name: 'Canadian dollar',
      symbol: 'C\$',
      bills: [5, 10, 20, 50, 100],
      stackStep: 10,
      roundUpSteps: [5, 10, 50],
      largestBill: 100,
    ),
    AppCurrency(
      code: 'MYR',
      name: 'Malaysian ringgit',
      symbol: 'RM ',
      bills: [1, 5, 10, 50, 100],
      stackStep: 10,
      roundUpSteps: [5, 10, 50],
      largestBill: 100,
    ),
    AppCurrency(
      code: 'IDR',
      name: 'Indonesian rupiah',
      symbol: 'Rp ',
      minorDigits: 0,
      bills: [2000, 5000, 10000, 20000, 50000, 100000],
      stackStep: 10000,
      roundUpSteps: [5000, 10000, 50000],
      largestBill: 100000,
    ),
    AppCurrency(
      code: 'THB',
      name: 'Thai baht',
      symbol: '฿',
      bills: [20, 50, 100, 500, 1000],
      stackStep: 100,
      roundUpSteps: [50, 100, 500],
      largestBill: 1000,
    ),
    AppCurrency(
      code: 'VND',
      name: 'Vietnamese dong',
      symbol: '₫',
      minorDigits: 0,
      bills: [10000, 20000, 50000, 100000, 200000, 500000],
      stackStep: 100000,
      roundUpSteps: [10000, 50000, 100000],
      largestBill: 500000,
    ),
    AppCurrency(
      code: 'INR',
      name: 'Indian rupee',
      symbol: '₹',
      bills: [10, 20, 50, 100, 200, 500],
      stackStep: 100,
      roundUpSteps: [50, 100, 500],
      largestBill: 500,
    ),
    AppCurrency(
      code: 'AED',
      name: 'UAE dirham',
      symbol: 'AED ',
      bills: [5, 10, 20, 50, 100, 200, 500],
      stackStep: 100,
      roundUpSteps: [10, 50, 100],
      largestBill: 500,
    ),
  ];

  static AppCurrency byCode(String? code) =>
      all.firstWhere((c) => c.code == code, orElse: () => php);
}

/// Device-level preference: which currency prices and totals are shown in.
/// Remembered on this device, defaults to the Philippine peso. This only
/// changes how amounts are DISPLAYED: stored prices are not converted.
class CurrencySettings extends ChangeNotifier {
  static const _key = 'currency_code';

  AppCurrency _currency = AppCurrency.php;
  AppCurrency get currency => _currency;

  /// Symbol without padding, e.g. "₱", "RM". For input prefixes and labels.
  String get symbol => _currency.symbol.trim();

  /// A formatter for this currency. [decimals] is the number of decimals to
  /// show (0 or 2); currencies with no minor unit always show 0.
  NumberFormat format({int decimals = 2}) => NumberFormat.currency(
        symbol: _currency.symbol,
        decimalDigits: _currency.minorDigits == 0 ? 0 : decimals,
      );

  /// "₱70" for whole amounts, "₱70.50" otherwise.
  String money(double v) {
    final isWhole = (v - v.roundToDouble()).abs() < 0.005;
    return format(decimals: isWhole ? 0 : 2).format(v);
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = AppCurrency.byCode(prefs.getString(_key));
      if (loaded.code != _currency.code) {
        _currency = loaded;
        notifyListeners();
      }
    } catch (e) {
      logDebug('load currency failed: $e');
    }
  }

  Future<void> setCurrency(String code) async {
    final next = AppCurrency.byCode(code);
    if (next.code == _currency.code) return;
    _currency = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, next.code);
    } catch (e) {
      logDebug('save currency failed: $e');
    }
  }
}
