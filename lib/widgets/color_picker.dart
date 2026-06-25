import 'package:flutter/material.dart';
import '../helpers/general_helpers.dart';

// Shared row of tappable color swatches, used by event/task color pickers.
// `showCheckOnSelected` draws a checkmark inside the selected swatch instead
// of just a border ring, matching whichever style the caller previously used.
Widget buildColorSwatchRow({
  required List<Color> colors,
  required Color selectedColor,
  required ValueChanged<Color> onSelected,
  double size = 28,
  bool showCheckOnSelected = false,
  double spacing = 8,
}) {
  return Wrap(
    spacing: spacing,
    runSpacing: spacing,
    children: colors.map((color) {
      final isSelected = selectedColor.toARGB32() == color.toARGB32();
      return GestureDetector(
        onTap: () => onSelected(color),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.black87 : Colors.transparent,
              width: 2,
            ),
          ),
          child: (isSelected && showCheckOnSelected)
              ? Icon(Icons.check, size: size * 0.5, color: Colors.white)
              : null,
        ),
      );
    }).toList(),
  );
}

Widget buildColorSlider({
  required String label,
  required double value,
  required double min,
  required double max,
  required Color activeColor,
  required String valueLabel,
  required ValueChanged<double> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              valueLabel,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: activeColor,
            inactiveTrackColor: activeColor.withAlpha((0.18 * 255).round()),
            thumbColor: activeColor,
            overlayColor: activeColor.withAlpha((0.12 * 255).round()),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );
}

Future<Color?> showRainbowColorPicker(
  BuildContext context,
  Color initialColor,
) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      double hue = HSVColor.fromColor(initialColor).hue;
      double saturation = HSVColor.fromColor(initialColor).saturation;
      double value = HSVColor.fromColor(initialColor).value;

      Color buildColor() =>
          HSVColor.fromAHSV(1, hue, saturation, value).toColor();

      return StatefulBuilder(
        builder: (context, setSheetState) {
          final selected = buildColor();
          final previewBorder = borderOnColor(selected);

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: selected,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: previewBorder,
                            width: 1.2,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Pick a Color',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: const [
                          Colors.red,
                          Colors.orange,
                          Colors.yellow,
                          Colors.green,
                          Colors.cyan,
                          Colors.blue,
                          Colors.purple,
                          Colors.pink,
                          Colors.red,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected,
                          border: Border.all(color: previewBorder, width: 2),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  buildColorSlider(
                    label: 'Hue',
                    value: hue,
                    min: 0,
                    max: 360,
                    activeColor: selected,
                    valueLabel: '${hue.round()}°',
                    onChanged: (val) => setSheetState(() => hue = val),
                  ),
                  buildColorSlider(
                    label: 'Saturation',
                    value: saturation,
                    min: 0,
                    max: 1,
                    activeColor: selected,
                    valueLabel: saturation.toStringAsFixed(2),
                    onChanged: (val) => setSheetState(() => saturation = val),
                  ),
                  buildColorSlider(
                    label: 'Brightness',
                    value: value,
                    min: 0.1,
                    max: 1,
                    activeColor: selected,
                    valueLabel: value.toStringAsFixed(2),
                    onChanged: (val) => setSheetState(() => value = val),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          child: Text('Cancel'),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetCtx, selected),
                          child: Text('Use This Color'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
