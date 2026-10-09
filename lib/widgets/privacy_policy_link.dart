import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// Opens the public privacy policy page in the browser.
Future<void> openPrivacyPolicy(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await launchUrl(
    Uri.parse(AppConfig.privacyPolicyUrl),
    mode: LaunchMode.externalApplication,
  );
  if (!ok) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open ${AppConfig.privacyPolicyUrl}')),
    );
  }
}

/// Small "By creating an account you agree to our Privacy Policy" line
/// (or just a "Privacy Policy" link when [agreeText] is false), shown on the
/// login / sign-up screen. Google Play requires a privacy policy link inside
/// the app.
class PrivacyPolicyNotice extends StatefulWidget {
  final bool agreeText;
  const PrivacyPolicyNotice({super.key, this.agreeText = false});

  @override
  State<PrivacyPolicyNotice> createState() => _PrivacyPolicyNoticeState();
}

class _PrivacyPolicyNoticeState extends State<PrivacyPolicyNotice> {
  late final TapGestureRecognizer _tap;

  @override
  void initState() {
    super.initState();
    _tap = TapGestureRecognizer()..onTap = () => openPrivacyPolicy(context);
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall;
    final link = base?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          if (widget.agreeText)
            const TextSpan(
                text: 'By creating an account you agree to our '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _tap),
          if (widget.agreeText) const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
