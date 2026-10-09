import 'package:flutter/material.dart';

import '../providers/tile_layout_settings.dart';

/// Screens narrower than this (phones) let staff pick 2, 3 or 4 tiles per
/// row; wider screens keep the automatic layout.
const double kTilePickerMaxWidth = 600;

bool isPhoneWidth(BuildContext context) =>
    MediaQuery.of(context).size.width < kTilePickerMaxWidth;

/// Small "grid + number" button that opens a menu to choose how many
/// machine tiles to show per row.
class TileColumnsMenu extends StatelessWidget {
  final int columns;
  final ValueChanged<int> onChanged;

  const TileColumnsMenu({
    super.key,
    required this.columns,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<int>(
      tooltip: 'Tiles per row',
      initialValue: columns,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final c in TileLayoutSettings.options)
          CheckedPopupMenuItem<int>(
            value: c,
            checked: c == columns,
            child: Text('$c per row'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_rounded, size: 20, color: color),
            const SizedBox(width: 4),
            Text(
              '$columns',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
