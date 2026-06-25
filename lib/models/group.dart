import 'package:flutter/material.dart';

class Group {
  final String id;
  String name;
  Color color;
  bool isVisible;
  String? parentGroupId;

  Group({
    required this.id,
    required this.name,
    required this.color,
    this.isVisible = true,
    this.parentGroupId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color.toARGB32(),
        'isVisible': isVisible,
        'parentGroupId': parentGroupId,
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        name: json['name'],
        color: Color(json['color']),
        isVisible: json['isVisible'] ?? true,
        parentGroupId: json['parentGroupId'],
      );

  Group copyWith(
      {String? name, Color? color, bool? isVisible, String? parentGroupId}) {
    return Group(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      isVisible: isVisible ?? this.isVisible,
      parentGroupId: parentGroupId ?? this.parentGroupId,
    );
  }
}
