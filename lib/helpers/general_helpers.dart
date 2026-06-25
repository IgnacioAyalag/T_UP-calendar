import 'package:flutter/material.dart';
import '../models/group.dart';
import '../models/task.dart';

Color textOnColor(Color color) =>
    color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

Color borderOnColor(Color color) =>
    color.computeLuminance() > 0.72 ? Colors.black54 : Colors.white70;

String hexKey(Color color) =>
    '#${color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}';

bool isItemVisible(List<String> itemGroupIds, List<Group> globalGroups) =>
    itemGroupIds.isEmpty ||
    itemGroupIds.any((id) => globalGroups
        .firstWhere((g) => g.id == id,
            orElse: () => Group(id: '', name: '', color: Colors.transparent))
        .isVisible);

List<Task> getSortedTasks(List<Task> tasks) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  return [
    ...tasks.where((t) =>
        !t.isCompleted && t.endDate != null && t.endDate!.isBefore(todayStart)),
    ...tasks.where((t) =>
        !t.isCompleted &&
        (t.endDate == null || !t.endDate!.isBefore(todayStart)) &&
        (t.startDate == null || !t.startDate!.isAfter(now))),
    ...tasks.where((t) =>
        !t.isCompleted && t.startDate != null && t.startDate!.isAfter(now)),
    ...tasks.where((t) => t.isCompleted),
  ];
}
