import 'package:flutter/material.dart';
import 'repeat_config.dart';

class SubEvent {
  String title;
  String description;
  DateTime startTime;
  DateTime endTime;

  SubEvent({
    required this.title,
    this.description = '',
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
      };

  factory SubEvent.fromJson(Map<String, dynamic> json) => SubEvent(
        title: json['title'],
        description: json['description'] ?? '',
        startTime: DateTime.parse(json['startTime']),
        endTime: DateTime.parse(json['endTime']),
      );
}

class Event {
  String title;
  String description;
  DateTime startTime;
  DateTime endTime;
  Color color;
  int columnBias;
  List<SubEvent> subEvents;
  List<String> groupIds;
  RepeatConfig repeatConfig;

  Event({
    required this.title,
    this.description = '',
    required this.startTime,
    required this.endTime,
    this.color = Colors.blue,
    this.columnBias = 0,
    List<SubEvent>? subEvents,
    List<String>? groupIds,
    RepeatConfig? repeatConfig,
  })  : this.subEvents = subEvents ?? [],
        this.groupIds = groupIds ?? [],
        this.repeatConfig = repeatConfig ?? RepeatConfig();

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'color': color.toARGB32(), // Save color as an integer key
        'columnBias': columnBias,
        'subEvents': subEvents.map((e) => e.toJson()).toList(),
        'groupIds': groupIds,
        'repeatConfig': repeatConfig.toJson(),
      };

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        title: json['title'],
        description: json['description'] ?? '',
        startTime: DateTime.parse(json['startTime']),
        endTime: DateTime.parse(json['endTime']),
        color: Color(json['color']), // Reconstruct Color from integer key
        columnBias: json['columnBias'] ?? 0,
        subEvents: (json['subEvents'] as List?)
                ?.map((e) => SubEvent.fromJson(e))
                .toList() ??
            [],
        groupIds: List<String>.from(json['groupIds'] ?? []),
        repeatConfig: json['repeatConfig'] != null
            ? RepeatConfig.fromJson(json['repeatConfig'])
            : RepeatConfig(),
      );
}
