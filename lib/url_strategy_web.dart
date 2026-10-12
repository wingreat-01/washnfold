import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web only: use clean URLs (no '#') so links like /track/:orderId work.
void configureUrlStrategy() {
  usePathUrlStrategy();
}
