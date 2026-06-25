enum RepeatFrequency { none, daily, weekly, monthly, yearly, custom }

class RepeatConfig {
  RepeatFrequency frequency;
  int interval;
  int customCount;
  List<int> weekdays;

  RepeatConfig({
    this.frequency = RepeatFrequency.none,
    this.interval = 1,
    this.customCount = 0,
    List<int>? weekdays,
  }) : weekdays = weekdays ?? [];

  // Convert to JSON Map
  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        'interval': interval,
        'customCount': customCount,
        'weekdays': weekdays,
      };

  // Build from JSON Map
  factory RepeatConfig.fromJson(Map<String, dynamic> json) => RepeatConfig(
        frequency: RepeatFrequency.values.firstWhere(
          (e) => e.name == json['frequency'],
          orElse: () => RepeatFrequency.none,
        ),
        interval: json['interval'] ?? 1,
        customCount: json['customCount'] ?? 0,
        weekdays: List<int>.from(json['weekdays'] ?? []),
      );

  RepeatConfig clone() => RepeatConfig(
        frequency: frequency,
        interval: interval,
        customCount: customCount,
        weekdays: List.from(weekdays),
      );
  bool get isActive => frequency != RepeatFrequency.none;

  String get label {
    switch (frequency) {
      case RepeatFrequency.none:
        return 'No repeat';
      case RepeatFrequency.daily:
        return interval == 1 ? 'Every day' : 'Every $interval days';
      case RepeatFrequency.weekly:
        if (weekdays.isEmpty)
          return interval == 1 ? 'Every week' : 'Every $interval weeks';
        const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final days =
            (weekdays.toList()..sort()).map((d) => names[d]).join(', ');
        return 'Weekly on $days';
      case RepeatFrequency.monthly:
        return interval == 1 ? 'Every month' : 'Every $interval months';
      case RepeatFrequency.yearly:
        return interval == 1 ? 'Every year' : 'Every $interval years';
      case RepeatFrequency.custom:
        return 'Every $interval days';
    }
  }
}
