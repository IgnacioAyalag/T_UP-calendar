import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import '../models/task.dart';
import '../models/group.dart';

class StorageHelper {
  static const String _eventsKey = 'saved_calendar_events';
  static const String _tasksKey = 'saved_calendar_tasks';
  static const String _groupsKey = 'saved_calendar_groups';
  static const String _taskViewsKey = 'saved_calendar_task_views';
  static const String _homeCardOrderKey = 'saved_home_card_order';

  // Save/Load the order of cards on the home screen (a simple list of ids).
  static Future<void> saveHomeCardOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setStringList(_homeCardOrderKey, order);
    debugPrint('[StorageHelper] saveHomeCardOrder($order) -> $ok');
  }

  static Future<List<String>?> loadHomeCardOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_homeCardOrderKey);
  }

  // Save/Load the home screen's custom task-card views (raw JSON maps,
  // since the view model lives in home_page.dart, not models/).
  static Future<void> saveTaskViews(List<Map<String, dynamic>> views) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(_taskViewsKey, jsonEncode(views));
    debugPrint('[StorageHelper] saveTaskViews(${views.length}) -> $ok');
  }

  static Future<List<Map<String, dynamic>>> loadTaskViews() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_taskViewsKey);
    if (encoded == null) return [];
    final List decoded = jsonDecode(encoded);
    return decoded.cast<Map<String, dynamic>>();
  }

  // Save/Load Events
  static Future<void> saveEvents(List<Event> events) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(events.map((e) => e.toJson()).toList());
    final ok = await prefs.setString(_eventsKey, encoded);
    debugPrint(
        '[StorageHelper] saveEvents(${events.length}) -> $ok, ${encoded.length} bytes');
  }

  static Future<List<Event>> loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_eventsKey);
    if (encoded == null) return [];
    final List decoded = jsonDecode(encoded);
    return decoded.map((item) => Event.fromJson(item)).toList();
  }

  // Save/Load Tasks
  static Future<void> saveTasks(List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(tasks.map((t) => t.toJson()).toList());
    final ok = await prefs.setString(_tasksKey, encoded);
    debugPrint(
        '[StorageHelper] saveTasks(${tasks.length}) -> $ok, ${encoded.length} bytes');
  }

  static Future<List<Task>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_tasksKey);
    if (encoded == null) return [];
    final List decoded = jsonDecode(encoded);
    return decoded.map((item) => Task.fromJson(item)).toList();
  }

  // Save/Load Groups
  static Future<void> saveGroups(List<Group> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(groups.map((g) => g.toJson()).toList());
    final ok = await prefs.setString(_groupsKey, encoded);
    debugPrint(
        '[StorageHelper] saveGroups(${groups.length}) -> $ok, ${encoded.length} bytes');
  }

  static Future<List<Group>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_groupsKey);
    if (encoded == null) return [];
    final List decoded = jsonDecode(encoded);
    return decoded.map((item) => Group.fromJson(item)).toList();
  }
}
