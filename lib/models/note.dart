import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'note.g.dart';

@HiveType(typeId: 1)
class Note extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  String content;

  @HiveField(2)
  String category;

  @HiveField(3)
  bool isPinned;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  Color color;

  Note({
    required this.title,
    required this.content,
    required this.category,
    this.isPinned = false,
    DateTime? createdAt,
    Color? color,
  })  : createdAt = createdAt ?? DateTime.now(),
        color = color ?? _getRandomColor();

  static Color _getRandomColor() {
    final colors = [
      const Color(0xFFFFE4E1),
      const Color(0xFFE1F5FE),
      const Color(0xFFE8F5E8),
      const Color(0xFFFFF3E0),
      const Color(0xFFF3E5F5),
      const Color(0xFFE0F2F1),
    ];
    return colors[Random().nextInt(colors.length)];
  }
}
