import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import '../models/task.dart';
import '../models/group.dart';

class StorageHelper {
  static const _eventsKey = 'saved_calendar_events';
  static const _tasksKey = 'saved_calendar_tasks';
  static const _groupsKey = 'saved_calendar_groups';
  static const _taskViewsKey = 'saved_calendar_task_views';
  static const _cardOrderKey = 'saved_home_card_order';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> saveHomeCardOrder(List<String> order) async =>
      (await _prefs).setStringList(_cardOrderKey, order);

  static Future<List<String>?> loadHomeCardOrder() async =>
      (await _prefs).getStringList(_cardOrderKey);

  static Future<void> saveTaskViews(List<Map<String, dynamic>> views) async =>
      (await _prefs).setString(_taskViewsKey, jsonEncode(views));

  static Future<List<Map<String, dynamic>>> loadTaskViews() async {
    final raw = (await _prefs).getString(_taskViewsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> saveEvents(List<Event> events) async =>
      (await _prefs).setString(
          _eventsKey, jsonEncode(events.map((e) => e.toJson()).toList()));

  static Future<List<Event>> loadEvents() async {
    final raw = (await _prefs).getString(_eventsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Event.fromJson(e)).toList();
  }

  static Future<void> saveTasks(List<Task> tasks) async => (await _prefs)
      .setString(_tasksKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));

  static Future<List<Task>> loadTasks() async {
    final raw = (await _prefs).getString(_tasksKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Task.fromJson(e)).toList();
  }

  static Future<void> saveGroups(List<Group> groups) async =>
      (await _prefs).setString(
          _groupsKey, jsonEncode(groups.map((g) => g.toJson()).toList()));

  static Future<List<Group>> loadGroups() async {
    final raw = (await _prefs).getString(_groupsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Group.fromJson(e)).toList();
  }
}
