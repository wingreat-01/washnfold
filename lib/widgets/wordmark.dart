import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The Laundry Mate wordmark. On dark backgrounds it gets a soft light-blue
/// glow (a blurred, tinted copy of the image behind it) so the deep blue
/// letters stay readable; on light backgrounds it is drawn as-is.
class Wordmark extends StatelessWidget {
  final double height;
  const Wordmark({super.key, this.height = 46});

  static const _asset = 'assets/icon/wordmark.png';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final image = Image.asset(
      _asset,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'Laundry Mate',
      // Falls back to plain text if the image is missing.
      errorBuilder: (_, __, ___) => Text(
        'Laundry Mate',
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    if (!isDark) return image;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Glow: tinted silhouette of the wordmark, blurred.
        ExcludeSemantics(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
            child: ColorFiltered(
              colorFilter:
                  const ColorFilter.mode(Color(0x4078BEFF), BlendMode.srcIn),
              child: Image.asset(
                _asset,
                height: height,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        image,
      ],
    );
  }
}
