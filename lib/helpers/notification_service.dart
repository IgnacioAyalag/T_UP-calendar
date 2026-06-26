import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/event.dart';
import '../models/task.dart';

/// Wraps flutter_local_notifications for the three notification types this
/// app needs:
///  1. Per-event reminders ("notify me N minutes before this event").
///  2. A persistent (ongoing) notification listing today's tasks.
///  3. One-shot pop-ups for tasks due within the next 24 hours.
///
/// All flutter_local_notifications calls here use fully named parameters,
/// matching the installed v21.0.0 API (every public method on
/// FlutterLocalNotificationsPlugin takes zero positional arguments).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _eventChannelId = 'event_reminders';
  static const String _eventChannelName = 'Event reminders';
  static const String _dailyChannelId = 'daily_tasks_persistent';
  static const String _dailyChannelName = 'Today\'s tasks';
  static const String _expiringChannelId = 'tasks_expiring_soon';
  static const String _expiringChannelName = 'Tasks due soon';

  // Fixed id for the single persistent "today's tasks" notification — using
  // a constant id means re-showing it always updates the same notification
  // instead of stacking new ones.
  static const int _persistentDailyTasksId = 999999;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      // Fall back to whatever default the timezone package picked (UTC) —
      // notifications will still fire, just without DST-aware precision.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: InitializationSettings(android: androidInit, iOS: darwinInit),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  // A stable 31-bit int id derived from a String id, since the plugin
  // requires int notification ids but our models use String ids.
  int _intIdFor(String stringId) => stringId.hashCode & 0x7FFFFFFF;

  // --- Event reminders ---------------------------------------------------

  Future<void> scheduleEventReminder(Event event) async {
    final id = _intIdFor(event.id);
    await _plugin.cancel(id: id);

    final minutesBefore = event.notifyMinutesBefore;
    if (minutesBefore == null) return;

    final fireTime = event.startTime.subtract(Duration(minutes: minutesBefore));
    if (fireTime.isBefore(DateTime.now())) return; // don't schedule the past

    await _plugin.zonedSchedule(
      id: id,
      title: event.title.isEmpty ? 'Event reminder' : event.title,
      body: _reminderBody(event, minutesBefore),
      scheduledDate: tz.TZDateTime.from(fireTime, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _eventChannelId,
          _eventChannelName,
          channelDescription: 'Reminders for upcoming calendar events',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelEventReminder(String eventId) async {
    await _plugin.cancel(id: _intIdFor(eventId));
  }

  String _reminderBody(Event event, int minutesBefore) {
    if (minutesBefore < 60) return 'Starts in $minutesBefore minutes';
    if (minutesBefore % 1440 == 0) {
      final days = minutesBefore ~/ 1440;
      return days == 1 ? 'Starts tomorrow' : 'Starts in $days days';
    }
    if (minutesBefore % 60 == 0) {
      final hours = minutesBefore ~/ 60;
      return hours == 1 ? 'Starts in 1 hour' : 'Starts in $hours hours';
    }
    return 'Starts in $minutesBefore minutes';
  }

  // --- Persistent "today's tasks" notification ---------------------------

  /// Shows/updates a single ongoing notification listing the names of all
  /// incomplete tasks due today. Hides it entirely if there are none.
  Future<void> refreshPersistentDailyTasksNotification(
      List<Task> allTasks) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final todaysTasks = allTasks.where((t) {
      if (t.isCompleted) return false;
      final due = t.endDate ?? t.startDate;
      if (due == null) return false;
      return !due.isBefore(todayStart) && due.isBefore(todayEnd);
    }).toList();

    if (todaysTasks.isEmpty) {
      await _plugin.cancel(id: _persistentDailyTasksId);
      return;
    }

    final names = todaysTasks.map((t) => t.name).toList();
    final body = names.join(', ');
    final title = todaysTasks.length == 1
        ? '1 task due today'
        : '${todaysTasks.length} tasks due today';

    await _plugin.show(
      id: _persistentDailyTasksId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannelId,
          _dailyChannelName,
          channelDescription: 'An ongoing reminder of what\'s due today',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          styleInformation: InboxStyleInformation(
            names,
            contentTitle: title,
            summaryText: 'Today\'s tasks',
          ),
        ),
        iOS: const DarwinNotificationDetails(presentSound: false),
      ),
    );
  }

  // --- "Expiring soon" one-shot task alerts -------------------------------

  /// Checks every incomplete task and fires a one-time pop-up for any task
  /// due within the next 24 hours that hasn't already been alerted about.
  /// Returns the ids of tasks that were just notified, so the caller can
  /// mark them (task.expiringSoonNotified = true) and persist that change.
  Future<List<String>> checkExpiringSoonTasks(List<Task> allTasks) async {
    final now = DateTime.now();
    final notifiedIds = <String>[];

    for (final task in allTasks) {
      if (task.isCompleted || task.expiringSoonNotified) continue;
      final due = task.endDate ?? task.startDate;
      if (due == null) continue;

      final hoursUntilDue = due.difference(now).inMinutes / 60.0;
      final isExpiringSoon = hoursUntilDue <= 24 && hoursUntilDue >= 0;
      if (!isExpiringSoon) continue;

      await _plugin.show(
        id: _intIdFor('expiring_${task.id}'),
        title: '${task.name} is due soon',
        body: _expiringBody(due),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _expiringChannelId,
            _expiringChannelName,
            channelDescription: 'Alerts for tasks due within 24 hours',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      notifiedIds.add(task.id);
    }
    return notifiedIds;
  }

  String _expiringBody(DateTime due) {
    final hours = due.difference(DateTime.now()).inHours;
    if (hours <= 1) return 'Due within the hour';
    return 'Due in about $hours hours';
  }
}
