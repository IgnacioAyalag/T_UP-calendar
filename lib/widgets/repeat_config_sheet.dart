import 'package:flutter/material.dart';
import '../models/repeat_config.dart';

Future<RepeatConfig?> showRepeatConfigSheet(
  BuildContext context,
  RepeatConfig initial,
) async {
  RepeatConfig config = initial.clone();

  return showModalBottomSheet<RepeatConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        const weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        const weekdayValues = [1, 2, 3, 4, 5, 6, 7];

        Widget _freqTile(String label, RepeatFrequency freq, IconData icon) {
          final selected = config.frequency == freq;
          return GestureDetector(
            onTap: () => setState(() => config.frequency = freq),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? Colors.blue.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? Colors.blue : Colors.grey.shade200,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: selected ? Colors.blue : Colors.grey.shade500),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.blue.shade800 : Colors.black87,
                    fontSize: 14,
                  )),
                  const Spacer(),
                  if (selected)
                    const Icon(Icons.check_circle, color: Colors.blue, size: 18),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(99)),
                )),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.repeat, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    const Text('Repeat', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (config.isActive)
                      TextButton(
                        onPressed: () => setState(() => config = RepeatConfig()),
                        child: const Text('Clear', style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _freqTile('No repeat',    RepeatFrequency.none,    Icons.block),
                _freqTile('Daily',        RepeatFrequency.daily,   Icons.wb_sunny_outlined),
                _freqTile('Weekly',       RepeatFrequency.weekly,  Icons.view_week_outlined),
                _freqTile('Monthly',      RepeatFrequency.monthly, Icons.calendar_month_outlined),
                _freqTile('Yearly',       RepeatFrequency.yearly,  Icons.event_repeat_outlined),
                _freqTile('Custom interval', RepeatFrequency.custom, Icons.tune),

                // ── Weekday picker (weekly only) ──────────────────────────
                if (config.frequency == RepeatFrequency.weekly) ...[
                  const SizedBox(height: 16),
                  const Text('Repeat on these days', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(7, (i) {
                      final val = weekdayValues[i];
                      final selected = config.weekdays.contains(val);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (selected) config.weekdays.remove(val);
                          else config.weekdays.add(val);
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? Colors.blue : Colors.grey.shade100,
                            border: Border.all(
                              color: selected ? Colors.blue.shade700 : Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              weekdayLabels[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: selected ? Colors.white : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],

                // ── Interval stepper (all active frequencies) ────────────
                if (config.frequency != RepeatFrequency.none) ...[
                  const SizedBox(height: 16),
                  Text(
                    config.frequency == RepeatFrequency.weekly  ? 'Every N weeks'  :
                    config.frequency == RepeatFrequency.monthly ? 'Every N months' :
                    config.frequency == RepeatFrequency.yearly  ? 'Every N years'  : 'Every N days',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StepperButton(
                        icon: Icons.remove,
                        onTap: () => setState(() { if (config.interval > 1) config.interval--; }),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 52, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Center(
                          child: Text('${config.interval}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      StepperButton(
                        icon: Icons.add,
                        onTap: () => setState(() { config.interval++; }),
                      ),
                    ],
                  ),
                ],

                // ── Repeat count ──────────────────────────────────────────
                if (config.isActive) ...[
                  const SizedBox(height: 16),
                  const Text('How many times', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                  const SizedBox(height: 4),
                  const Text('Set to 0 for unlimited repeats', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StepperButton(
                        icon: Icons.remove,
                        onTap: () => setState(() { if (config.customCount > 0) config.customCount--; }),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 68, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Center(
                          child: Text(
                            config.customCount == 0 ? '∞' : '${config.customCount}×',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      StepperButton(
                        icon: Icons.add,
                        onTap: () => setState(() { config.customCount++; }),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, config),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const StepperButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, size: 18, color: Colors.blue),
      ),
    );
  }
}
