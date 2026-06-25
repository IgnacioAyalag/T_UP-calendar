import '../models/repeat_config.dart';
import '../models/task.dart';
import '../models/event.dart';

List<DateTime> buildRepeatDates(DateTime base, RepeatConfig cfg) {
  if (!cfg.isActive) return [base];

  if (cfg.frequency == RepeatFrequency.weekly && cfg.weekdays.isNotEmpty) {
    final List<DateTime> dates = [];
    int added = 0;
    final int cap = cfg.customCount == 0 ? 52 : cfg.customCount;
    DateTime weekStart = base;

    for (int w = 0;
        added < cap &&
            w <
                (cfg.customCount == 0
                    ? 52
                    : (cfg.customCount / cfg.weekdays.length).ceil());
        w++) {
      for (final wd in (cfg.weekdays.toList()..sort())) {
        int delta = wd - weekStart.weekday;
        if (delta < 0) delta += 7;
        final candidate = DateTime(weekStart.year, weekStart.month,
            weekStart.day + delta, base.hour, base.minute);
        if (!candidate.isBefore(base)) {
          dates.add(candidate);
          if (++added >= cap) break;
        }
      }
      if (added >= cap) break;
      weekStart = weekStart.add(Duration(days: 7 * cfg.interval));
    }
    return dates.isEmpty ? [base] : dates;
  }

  final List<DateTime> dates = [base];
  final int limit = cfg.customCount == 0 ? 365 : cfg.customCount;
  DateTime cursor = base;

  while (dates.length < limit) {
    DateTime? next = switch (cfg.frequency) {
      RepeatFrequency.daily ||
      RepeatFrequency.custom =>
        cursor.add(Duration(days: cfg.interval)),
      RepeatFrequency.weekly => cursor.add(Duration(days: 7 * cfg.interval)),
      RepeatFrequency.monthly => DateTime(cursor.year,
          cursor.month + cfg.interval, cursor.day, cursor.hour, cursor.minute),
      RepeatFrequency.yearly => DateTime(cursor.year + cfg.interval,
          cursor.month, cursor.day, cursor.hour, cursor.minute),
      _ => null,
    };
    if (next == null) break;
    dates.add(next);
    cursor = next;
  }
  return dates;
}

List<Event> expandEventWithRepeat(Event source) {
  if (!source.repeatConfig.isActive) return [source];
  final duration = source.endTime.difference(source.startTime);
  return buildRepeatDates(source.startTime, source.repeatConfig)
      .map((d) => Event(
            title: source.title,
            description: source.description,
            startTime: d,
            endTime: d.add(duration),
            color: source.color,
            columnBias: source.columnBias,
            subEvents: source.subEvents,
            groupIds: List.from(source.groupIds),
            repeatConfig: RepeatConfig(),
          ))
      .toList();
}

List<Task> expandTaskWithRepeat(Task source) {
  if (!source.repeatConfig.isActive) return [source];
  return buildRepeatDates(
          source.startDate ?? DateTime.now(), source.repeatConfig)
      .map((d) {
    final dur = (source.startDate != null && source.endDate != null)
        ? source.endDate!.difference(source.startDate!)
        : Duration.zero;
    return Task(
      name: source.name,
      description: source.description,
      isCompleted: source.isCompleted,
      color: source.color,
      subtasks: source.subtasks
          .map((s) => SubTask(name: s.name, isCompleted: s.isCompleted))
          .toList(),
      startDate: d,
      endDate: dur.inDays > 0 ? d.add(dur) : d,
      groupIds: List.from(source.groupIds),
      repeatConfig: RepeatConfig(),
    );
  }).toList();
}
