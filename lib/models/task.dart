import 'package:hive/hive.dart';

part 'task.g.dart';

@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  bool isCompleted;

  @HiveField(2)
  DateTime? reminderTime;

  @HiveField(3)
  String? repeatType;

  @HiveField(4)
  DateTime createdAt;

  Task({
    required this.title,
    this.isCompleted = false,
    this.reminderTime,
    this.repeatType = 'none',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
