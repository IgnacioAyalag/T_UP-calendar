import 'package:flutter/material.dart';
import 'repeat_config.dart';

class SubTask {
  String name;
  bool isCompleted;

  SubTask({required this.name, this.isCompleted = false});

  Map<String, dynamic> toJson() => {
        'name': name,
        'isCompleted': isCompleted,
      };

  factory SubTask.fromJson(Map<String, dynamic> json) => SubTask(
        name: json['name'],
        isCompleted: json['isCompleted'] ?? false,
      );
}

class Task {
  String id;
  String name;
  String description;
  bool isCompleted;
  Color color;
  List<SubTask> subtasks;
  DateTime? startDate;
  DateTime? endDate;
  DateTime? completedDate;
  List<String> groupIds;
  RepeatConfig repeatConfig;
  // Internal bookkeeping so the "expiring soon" notification only fires once
  // per task instead of every time the task list is checked.
  bool expiringSoonNotified;

  Task({
    String? id,
    required this.name,
    required this.description,
    this.isCompleted = false,
    this.color = Colors.blue,
    List<SubTask>? subtasks,
    this.startDate,
    this.endDate,
    this.completedDate,
    List<String>? groupIds,
    RepeatConfig? repeatConfig,
    this.expiringSoonNotified = false,
  })  : this.id = id ??
            '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(name)}',
        this.subtasks = subtasks ?? [],
        this.groupIds = groupIds ?? [],
        this.repeatConfig = repeatConfig ?? RepeatConfig();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'isCompleted': isCompleted,
        'color': color.toARGB32(),
        'subtasks': subtasks.map((e) => e.toJson()).toList(),
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'completedDate': completedDate?.toIso8601String(),
        'groupIds': groupIds,
        'repeatConfig': repeatConfig.toJson(),
        'expiringSoonNotified': expiringSoonNotified,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        // Older saved tasks won't have an id — generate one on load so they
        // get a stable identity going forward.
        id: json['id'] ??
            '${DateTime.now().microsecondsSinceEpoch}_${json.hashCode}',
        name: json['name'],
        description: json['description'] ?? '',
        isCompleted: json['isCompleted'] ?? false,
        color: Color(json['color']),
        subtasks: (json['subtasks'] as List?)
                ?.map((e) => SubTask.fromJson(e))
                .toList() ??
            [],
        startDate: json['startDate'] != null
            ? DateTime.parse(json['startDate'])
            : null,
        endDate:
            json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
        completedDate: json['completedDate'] != null
            ? DateTime.parse(json['completedDate'])
            : null,
        groupIds: List<String>.from(json['groupIds'] ?? []),
        repeatConfig: json['repeatConfig'] != null
            ? RepeatConfig.fromJson(json['repeatConfig'])
            : RepeatConfig(),
        expiringSoonNotified: json['expiringSoonNotified'] ?? false,
      );
}
