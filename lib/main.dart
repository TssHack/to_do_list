import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:path_provider/path_provider.dart';

// Color适配器 - 修复序列化问题
class ColorAdapter extends TypeAdapter<Color> {
  @override
  final int typeId = 2;

  @override
  Color read(BinaryReader reader) {
    return Color(reader.readInt());
  }

  @override
  void write(BinaryWriter writer, Color obj) {
    writer.writeInt(obj.value);
  }
}

// 任务模型
@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  String title;
  @HiveField(1)
  bool isCompleted;
  @HiveField(2)
  DateTime? reminderTime;
  @HiveField(3)
  String? repeatType; // daily, weekly, none
  @HiveField(4)
  DateTime createdAt;
  @HiveField(5) // 新增字段：任务分类
  String? category;
  @HiveField(6) // 新增字段：优先级
  int priority; // 0: 低, 1: 中, 2: 高
  @HiveField(7) // 新增字段：通知音
  String? notificationSound;
  @HiveField(8) // 新增字段：启用 لرزش
  bool? enableVibration;

  Task({
    required this.title,
    this.isCompleted = false,
    this.reminderTime,
    this.repeatType = 'none',
    DateTime? createdAt,
    this.category,
    this.priority = 1,
    this.notificationSound,
    this.enableVibration = true,
  }) : createdAt = createdAt ?? DateTime.now();
}

// 笔记模型
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
  @HiveField(6) // 新增字段：最后修改时间
  DateTime? lastModified;

  Note({
    required this.title,
    required this.content,
    required this.category,
    this.isPinned = false,
    DateTime? createdAt,
    Color? color,
    DateTime? lastModified,
  }) : createdAt = createdAt ?? DateTime.now(),
       color = color ?? _getRandomColor(),
       lastModified = lastModified ?? DateTime.now();

  static Color _getRandomColor() {
    final colors = [
      const Color(0xFFFFE4E1), // Pink
      const Color(0xFFE1F5FE), // Light Blue
      const Color(0xFFE8F5E8), // Light Green
      const Color(0xFFFFF3E0), // Light Orange
      const Color(0xFFF3E5F5), // Light Purple
      const Color(0xFFE0F2F1), // Light Teal
    ];
    return colors[Random().nextInt(colors.length)];
  }
}

// 任务适配器
class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) {
    return Task(
      title: reader.read(),
      isCompleted: reader.read(),
      reminderTime: reader.read(),
      repeatType: reader.read(),
      createdAt: reader.read(),
      category: reader.read(),
      priority: reader.read(),
      notificationSound: reader.read(),
      enableVibration: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer.write(obj.title);
    writer.write(obj.isCompleted);
    writer.write(obj.reminderTime);
    writer.write(obj.repeatType);
    writer.write(obj.createdAt);
    writer.write(obj.category);
    writer.write(obj.priority);
    writer.write(obj.notificationSound);
    writer.write(obj.enableVibration);
  }
}

// 笔记适配器
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 1;

  @override
  Note read(BinaryReader reader) {
    return Note(
      title: reader.read(),
      content: reader.read(),
      category: reader.read(),
      isPinned: reader.read(),
      createdAt: reader.read(),
      color: reader.read(),
      lastModified: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) {
    writer.write(obj.title);
    writer.write(obj.content);
    writer.write(obj.category);
    writer.write(obj.isPinned);
    writer.write(obj.createdAt);
    writer.write(obj.color);
    writer.write(obj.lastModified);
  }
}

// 通知服务 - 增强版
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // 请求Android 13+权限
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    await androidImplementation?.requestNotificationsPermission();

    await _notificationsPlugin.initialize(settings);
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? repeatType,
    String? sound,
    bool? enableVibration,
  }) async {
    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'task_channel',
            'یادآوری کارها',
            channelDescription: 'نوتیفیکیشن برای یادآوری کارها',
            importance: Importance.high,
            priority: Priority.high,
            sound: sound != null && sound != 'silent'
                ? (sound == 'default'
                      ? null
                      : RawResourceAndroidNotificationSound(sound))
                : null,
            enableVibration: enableVibration ?? true,
            playSound: sound != 'silent',
          );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      );

      final tzDateTime = _convertToTZDateTime(scheduledTime);

      if (repeatType == 'daily') {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzDateTime,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          androidAllowWhileIdle: true,
        );
      } else if (repeatType == 'weekly') {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzDateTime,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          androidAllowWhileIdle: true,
        );
      } else {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzDateTime,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidAllowWhileIdle: true,
        );
      }
    } catch (e) {
      print('Error scheduling notification: $e');
    }
  }

  static tz.TZDateTime _convertToTZDateTime(DateTime dateTime) {
    final now = tz.TZDateTime.now(tz.local);
    final scheduled = tz.TZDateTime(
      tz.local,
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
      dateTime.minute,
    );

    // 如果时间在过去，移到明天
    if (scheduled.isBefore(now)) {
      return scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
    } catch (e) {
      print('Error canceling notification: $e');
    }
  }

  static Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      print('Error canceling all notifications: $e');
    }
  }

  static List<String> getFriendlyMessages() {
    return [
      'وقت انجام کارت رسیده! بزن بریم',
      'یه کار مهم منتظرته، حواست باشه',
      'کارت آماده‌ست! یلا به کارمون برسیم',
      'زنگ یادآوری! وقتشه کارتو انجام بدی',
      'کار مهمت یادت نره، بیا انجامش بدیم',
      'یادآوری دوستانه: کارت منتظرته',
      'وقت طلایی! بیا کارتو تمام کنیم',
    ];
  }
}

// 任务提供者 - 增强版
class TaskProvider extends ChangeNotifier {
  List<Task> _tasks = [];
  Box<Task>? _taskBox;
  String _searchQuery = '';
  String? _selectedCategory;
  String _sortCriteria = 'default'; // default, byDate, byPriority, byName

  List<Task> get tasks {
    List<Task> filteredTasks = List<Task>.from(_tasks);

    // 应用搜索过滤
    if (_searchQuery.isNotEmpty) {
      filteredTasks = filteredTasks
          .where(
            (task) =>
                task.title.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    // 应用分类过滤
    if (_selectedCategory != null) {
      filteredTasks = filteredTasks
          .where((task) => task.category == _selectedCategory)
          .toList();
    }

    return filteredTasks;
  }

  List<String> get categories {
    return _tasks.map((task) => task.category ?? 'بدون دسته').toSet().toList();
  }

  String? get selectedCategory => _selectedCategory;
  String get sortCriteria => _sortCriteria;

  Future<void> initializeHive() async {
    try {
      _taskBox = await Hive.openBox<Task>('tasks');
      _loadTasks();
    } catch (e) {
      print('Error initializing Hive for tasks: $e');
    }
  }

  void _loadTasks() {
    if (_taskBox != null) {
      _tasks = _taskBox!.values.toList();
      _sortTasks();
      notifyListeners();
    }
  }

  void _sortTasks() {
    switch (_sortCriteria) {
      case 'byDate':
        _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'byPriority':
        _tasks.sort((a, b) => b.priority.compareTo(a.priority));
        break;
      case 'byName':
        _tasks.sort((a, b) => a.title.compareTo(b.title));
        break;
      default:
        // Default sort: by completion, then priority, then creation date
        _tasks.sort((a, b) {
          if (a.isCompleted != b.isCompleted) {
            return a.isCompleted ? 1 : -1;
          }
          if (a.priority != b.priority) {
            return b.priority.compareTo(a.priority);
          }
          return b.createdAt.compareTo(a.createdAt);
        });
    }
  }

  void setSortCriteria(String criteria) {
    _sortCriteria = criteria;
    _sortTasks();
    notifyListeners();
  }

  Future<void> addTask(
    String title, {
    DateTime? reminderTime,
    String? repeatType,
    String? category,
    int priority = 1,
    String? notificationSound,
    bool? enableVibration,
  }) async {
    try {
      final task = Task(
        title: title,
        reminderTime: reminderTime,
        repeatType: repeatType ?? 'none',
        category: category,
        priority: priority,
        notificationSound: notificationSound,
        enableVibration: enableVibration,
      );

      await _taskBox?.add(task);
      _tasks.add(task);
      _sortTasks();

      // 设置通知
      if (reminderTime != null && reminderTime.isAfter(DateTime.now())) {
        final messages = NotificationService.getFriendlyMessages();
        final randomMessage = messages[Random().nextInt(messages.length)];

        await NotificationService.scheduleNotification(
          id: task.key ?? DateTime.now().millisecondsSinceEpoch,
          title: 'یادآوری کار',
          body: '$randomMessage\n📝 $title',
          scheduledTime: reminderTime,
          repeatType: repeatType,
          sound: notificationSound,
          enableVibration: enableVibration,
        );
      }

      notifyListeners();
    } catch (e) {
      print('Error adding task: $e');
    }
  }

  Future<void> toggleTask(int index) async {
    try {
      if (index < _tasks.length) {
        _tasks[index].isCompleted = !_tasks[index].isCompleted;
        await _tasks[index].save();
        _sortTasks();
        notifyListeners();
      }
    } catch (e) {
      print('Error toggling task: $e');
    }
  }

  Future<void> deleteTask(int index) async {
    try {
      if (index < _tasks.length) {
        // 取消相关通知
        if (_tasks[index].reminderTime != null) {
          await NotificationService.cancelNotification(
            _tasks[index].key ?? DateTime.now().millisecondsSinceEpoch,
          );
        }

        await _tasks[index].delete();
        _tasks.removeAt(index);
        notifyListeners();
      }
    } catch (e) {
      print('Error deleting task: $e');
    }
  }

  Future<void> updateTask(
    int index,
    String newTitle, {
    String? category,
    int? priority,
    DateTime? reminderTime,
    String? repeatType,
    String? notificationSound,
    bool? enableVibration,
  }) async {
    try {
      if (index < _tasks.length) {
        _tasks[index].title = newTitle;
        if (category != null) _tasks[index].category = category;
        if (priority != null) _tasks[index].priority = priority;
        if (reminderTime != null) _tasks[index].reminderTime = reminderTime;
        if (repeatType != null) _tasks[index].repeatType = repeatType;
        if (notificationSound != null)
          _tasks[index].notificationSound = notificationSound;
        if (enableVibration != null)
          _tasks[index].enableVibration = enableVibration;

        await _tasks[index].save();
        _sortTasks();
        notifyListeners();
      }
    } catch (e) {
      print('Error updating task: $e');
    }
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  Map<String, int> getTaskStats() {
    final total = _tasks.length;
    final completed = _tasks.where((t) => t.isCompleted).length;
    final pending = total - completed;
    final highPriority = _tasks.where((t) => t.priority == 2).length;

    return {
      'total': total,
      'completed': completed,
      'pending': pending,
      'highPriority': highPriority,
    };
  }
}

// 笔记提供者 - 增强版
class NoteProvider extends ChangeNotifier {
  List<Note> _notes = [];
  Box<Note>? _noteBox;
  String _searchQuery = '';
  String _sortCriteria = 'default'; // default, byDate, byName

  List<Note> get notes {
    if (_searchQuery.isEmpty) {
      return _sortedNotes;
    }

    return _sortedNotes
        .where(
          (note) =>
              note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              note.content.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              note.category.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  List<Note> get _sortedNotes {
    final sortedNotes = List<Note>.from(_notes);

    switch (_sortCriteria) {
      case 'byDate':
        sortedNotes.sort((a, b) => b.lastModified!.compareTo(a.lastModified!));
        break;
      case 'byName':
        sortedNotes.sort((a, b) => a.title.compareTo(b.title));
        break;
      default:
        // Default sort: pinned first, then by last modified
        sortedNotes.sort((a, b) {
          if (a.isPinned != b.isPinned) {
            return a.isPinned ? -1 : 1;
          }
          return b.lastModified!.compareTo(a.lastModified!);
        });
    }

    return sortedNotes;
  }

  String get sortCriteria => _sortCriteria;

  Future<void> initializeHive() async {
    try {
      _noteBox = await Hive.openBox<Note>('notes');
      _loadNotes();
    } catch (e) {
      print('Error initializing Hive for notes: $e');
    }
  }

  void _loadNotes() {
    if (_noteBox != null) {
      _notes = _noteBox!.values.toList();
      notifyListeners();
    }
  }

  void setSortCriteria(String criteria) {
    _sortCriteria = criteria;
    notifyListeners();
  }

  Future<void> addNote(String title, String content, String category) async {
    try {
      final note = Note(title: title, content: content, category: category);
      await _noteBox?.add(note);
      _notes.add(note);
      notifyListeners();
    } catch (e) {
      print('Error adding note: $e');
    }
  }

  Future<void> togglePin(int index) async {
    try {
      if (index < _notes.length) {
        _notes[index].isPinned = !_notes[index].isPinned;
        _notes[index].lastModified = DateTime.now();
        await _notes[index].save();
        notifyListeners();
      }
    } catch (e) {
      print('Error toggling pin: $e');
    }
  }

  Future<void> deleteNote(int index) async {
    try {
      if (index < _notes.length) {
        await _notes[index].delete();
        _notes.removeAt(index);
        notifyListeners();
      }
    } catch (e) {
      print('Error deleting note: $e');
    }
  }

  Future<void> updateNote(
    int index,
    String title,
    String content,
    String category,
  ) async {
    try {
      if (index < _notes.length) {
        _notes[index].title = title;
        _notes[index].content = content;
        _notes[index].category = category;
        _notes[index].lastModified = DateTime.now();
        await _notes[index].save();
        notifyListeners();
      }
    } catch (e) {
      print('Error updating note: $e');
    }
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  List<String> get categories {
    // Ensure unique categories
    return _notes.map((note) => note.category).toSet().toList();
  }

  Map<String, int> getNoteStats() {
    final total = _notes.length;
    final pinned = _notes.where((n) => n.isPinned).length;
    final uniqueCategories = categories.length;

    return {'total': total, 'pinned': pinned, 'categories': uniqueCategories};
  }
}

// 主题提供者 - فقط حالت روشن
class ThemeProvider extends ChangeNotifier {
  Color _primaryColor = const Color(0xFF6C63FF);
  int _themeIndex = 0;
  String _fontFamily = 'Vaziri';

  Color get primaryColor => _primaryColor;
  int get themeIndex => _themeIndex;
  String get fontFamily => _fontFamily;

  void setThemeColor(Color color, int index) {
    _primaryColor = color;
    _themeIndex = index;
    notifyListeners();
  }

  void setFontFamily(String fontFamily) {
    _fontFamily = fontFamily;
    notifyListeners();
  }

  // طراحی تم روشن با ظاهر مینیمال و فانتزی
  ThemeData get lightTheme => ThemeData(
    primarySwatch: Colors.blue,
    fontFamily: _fontFamily,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.black87,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        color: Colors.black87,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardColor: Colors.white,
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontFamily: _fontFamily, color: Colors.black87),
      bodyLarge: TextStyle(fontFamily: _fontFamily, color: Colors.black87),
      titleMedium: TextStyle(fontFamily: _fontFamily, color: Colors.black87),
      titleLarge: TextStyle(fontFamily: _fontFamily, color: Colors.black87),
    ),
    colorScheme: ColorScheme.fromSwatch().copyWith(
      primary: _primaryColor,
      secondary: _primaryColor,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 5,
        shadowColor: _primaryColor.withOpacity(0.3),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _primaryColor,
      foregroundColor: Colors.white,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.white.withOpacity(0.8),
      selectedItemColor: _primaryColor,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    iconTheme: IconThemeData(color: Colors.black87),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      textStyle: TextStyle(fontFamily: _fontFamily, color: Colors.black87),
    ),
  );
}

// ویجت منو همبرگری
class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu),
      onSelected: (value) {
        switch (value) {
          case 'about':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AboutPage()),
            );
            break;
          case 'settings':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
            break;
          case 'font':
            _showFontDialog(context);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'about',
          child: Row(
            children: [
              Icon(Icons.info, size: 20),
              SizedBox(width: 8),
              Text(
                'درباره توسعه‌دهنده',
                style: TextStyle(fontFamily: 'Vaziri'),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, size: 20),
              SizedBox(width: 8),
              Text('تنظیمات', style: TextStyle(fontFamily: 'Vaziri')),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'font',
          child: Row(
            children: [
              Icon(Icons.font_download, size: 20),
              SizedBox(width: 8),
              Text('تغییر فونت', style: TextStyle(fontFamily: 'Vaziri')),
            ],
          ),
        ),
      ],
    );
  }

  void _showFontDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) => AlertDialog(
          title: const Text(
            'تغییر فونت',
            style: TextStyle(fontFamily: 'Vaziri'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  'Vaziri',
                  style: TextStyle(fontFamily: 'Vaziri'),
                ),
                onTap: () {
                  themeProvider.setFontFamily('Vaziri');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text(
                  'Samim',
                  style: TextStyle(fontFamily: 'Samim'),
                ),
                onTap: () {
                  themeProvider.setFontFamily('Samim');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text(
                  'Shabnam',
                  style: TextStyle(fontFamily: 'Shabnam'),
                ),
                onTap: () {
                  themeProvider.setFontFamily('Shabnam');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// صفحه درباره توسعه‌دهنده
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('درباره توسعه‌دهنده'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).primaryColor.withOpacity(0.2),
              ),
              child: Icon(
                Icons.person,
                size: 60,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'توسعه‌دهنده برنامه',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Vaziri',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'نام توسعه‌دهنده: احسان فضلی',
              style: TextStyle(fontSize: 16, fontFamily: 'Vaziri'),
            ),
            const SizedBox(height: 8),
            const Text(
              'ایمیل: ehsanfazlinejad@example.com',
              style: TextStyle(fontSize: 16, fontFamily: 'Vaziri'),
            ),
            const SizedBox(height: 24),
            const Text(
              'درباره برنامه',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Vaziri',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'این برنامه برای مدیریت کارها و یادداشت‌ها طراحی شده است. '
              'با رابط کاربری مدرن و امکانات پیشرفته، به شما کمک می‌کند '
              'تا کارهای روزمره خود را به بهترین شکل ممکن مدیریت کنید.',
              style: TextStyle(fontSize: 14, fontFamily: 'Vaziri'),
              textAlign: TextAlign.justify,
            ),
            const SizedBox(height: 24),
            const Text(
              'ویژگی‌های برنامه',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Vaziri',
              ),
            ),
            const SizedBox(height: 8),
            const FeatureItem(icon: Icons.check_circle, title: 'مدیریت کارها'),
            const FeatureItem(icon: Icons.note, title: 'مدیریت یادداشت‌ها'),
            const FeatureItem(icon: Icons.notifications, title: 'یادآوری‌ها'),
            const FeatureItem(icon: Icons.category, title: 'دسته‌بندی‌ها'),
            const FeatureItem(icon: Icons.bar_chart, title: 'آمار و گزارشات'),
            const SizedBox(height: 24),
            const Text(
              'نسخه برنامه',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Vaziri',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'نسخه: 1.0.0',
              style: TextStyle(fontSize: 16, fontFamily: 'Vaziri'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ویجت آیتم ویژگی
class FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;

  const FeatureItem({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontFamily: 'Vaziri'),
          ),
        ],
      ),
    );
  }
}

// صفحه تنظیمات
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // فقط سوییچ‌هایی که کار عملی دارند باقی می‌مونن
          SwitchListTile(
            title: const Text(
              'فعال‌سازی نوتیفیکیشن',
              style: TextStyle(fontFamily: 'Vaziri'),
            ),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() {
                _notificationsEnabled = value;
              });
            },
          ),
          SwitchListTile(
            title: const Text(
              'صدای نوتیفیکیشن',
              style: TextStyle(fontFamily: 'Vaziri'),
            ),
            value: _soundEnabled,
            onChanged: (value) {
              setState(() {
                _soundEnabled = value;
              });
            },
          ),
          SwitchListTile(
            title: const Text('لرزش', style: TextStyle(fontFamily: 'Vaziri')),
            value: _vibrationEnabled,
            onChanged: (value) {
              setState(() {
                _vibrationEnabled = value;
              });
            },
          ),
          const SizedBox(height: 24),

          // فقط نسخه برنامه باقی می‌مونه
          ListTile(
            title: const Text(
              'نسخه برنامه',
              style: TextStyle(fontFamily: 'Vaziri'),
            ),
            trailing: const Text(
              '1.0.0',
              style: TextStyle(fontFamily: 'Vaziri'),
            ),
          ),
        ],
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化Hive
  await Hive.initFlutter();
  Hive.registerAdapter(TaskAdapter());
  Hive.registerAdapter(NoteAdapter());
  Hive.registerAdapter(ColorAdapter()); // 注册Color适配器

  // 初始化时区
  tz.initializeTimeZones();

  // 设置本地时区
  try {
    final String timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
  } catch (e) {
    print('Could not get the local timezone: $e');
    tz.setLocalLocation(tz.UTC);
  }

  // 初始化通知
  await NotificationService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TaskProvider()..initializeHive()),
        ChangeNotifierProvider(create: (_) => NoteProvider()..initializeHive()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'کارهای من',
            theme: themeProvider.lightTheme,
            home: const MainScreen(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('fa', 'IR'),
            supportedLocales: const [Locale('fa', 'IR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final List<Widget> _pages = [
    const TasksPage(),
    const NotesPage(),
    const StatsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: IndexedStack(index: _currentIndex, children: _pages),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Theme.of(context).primaryColor,
            unselectedItemColor: Colors.grey,
            backgroundColor: Colors.transparent,
            elevation: 0,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.check_circle_outline),
                activeIcon: const Icon(Icons.check_circle),
                label: 'کارها',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.note_outlined),
                activeIcon: const Icon(Icons.note),
                label: 'یادداشت‌ها',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.bar_chart_outlined),
                activeIcon: const Icon(Icons.bar_chart),
                label: 'آمار',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ویجت کارت شیشه‌ای
class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? color;
  final double? blur;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.color,
    this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin ?? const EdgeInsets.all(8),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withOpacity(0.7),
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ویجت دکمه نئومورفیک
class NeumorphicButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? color;

  const NeumorphicButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.borderRadius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? Theme.of(context).primaryColor;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: width,
        height: height,
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: borderRadius ?? BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.8),
              blurRadius: 15,
              offset: const Offset(-5, -5),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(5, 5),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ویجت کارت آماری
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? Theme.of(context).primaryColor;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: cardColor, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              fontFamily: 'Vaziri',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black54,
              fontFamily: 'Vaziri',
            ),
          ),
        ],
      ),
    );
  }
}

// Task page - طراحی مینیمال و فانتزی
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('کارهای من'),
        actions: [
          const HamburgerMenu(),
          Consumer<TaskProvider>(
            builder: (context, taskProvider, child) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                onSelected: (value) {
                  taskProvider.setSortCriteria(value);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'default',
                    child: Text(
                      'پیش‌فرض',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'byDate',
                    child: Text(
                      'تاریخ',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'byPriority',
                    child: Text(
                      'اولویت',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'byName',
                    child: Text('نام', style: TextStyle(fontFamily: 'Vaziri')),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Consumer<TaskProvider>(
          builder: (context, taskProvider, child) {
            return Column(
              children: [
                // 搜索和过滤栏
                Container(
                  margin: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 搜索框
                      GlassCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: taskProvider.updateSearchQuery,
                          decoration: InputDecoration(
                            hintText: 'جستجو در کارها...',
                            hintStyle: const TextStyle(fontFamily: 'Vaziri'),
                            prefixIcon: const Icon(Icons.search),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          style: const TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 分类过滤器
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: taskProvider.categories.length + 1,
                          itemBuilder: (context, index) {
                            final category = index == 0
                                ? 'همه'
                                : taskProvider.categories[index - 1];
                            final isSelected =
                                taskProvider.selectedCategory ==
                                (index == 0 ? null : category);

                            return Container(
                              margin: const EdgeInsets.only(left: 8),
                              child: NeumorphicButton(
                                onPressed: () {
                                  taskProvider.setSelectedCategory(
                                    isSelected
                                        ? (index == 0 ? null : category)
                                        : null,
                                  );
                                },
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.black54,
                                    fontFamily: 'Vaziri',
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // 任务统计卡片
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          title: 'کل کارها',
                          value: '${taskProvider.getTaskStats()['total']}',
                          icon: Icons.list_alt,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          title: 'انجام شده',
                          value: '${taskProvider.getTaskStats()['completed']}',
                          icon: Icons.check_circle,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                // 任务列表
                Expanded(
                  child: taskProvider.tasks.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: taskProvider.tasks.length,
                          itemBuilder: (context, index) {
                            final task = taskProvider.tasks[index];
                            return _buildTaskCard(
                              context,
                              task,
                              index,
                              taskProvider,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'tasks_fab', // منحصر به فرد کردن تگ Hero
        onPressed: () => _showAddTaskDialog(context),
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    Task task,
    int index,
    TaskProvider taskProvider,
  ) {
    final priorityColors = [
      Colors.green, // 低优先级
      Colors.orange, // 中优先级
      Colors.red, // 高优先级
    ];

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: GestureDetector(
          onTap: () => taskProvider.toggleTask(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: task.isCompleted
                  ? const Color(0xFF4CAF50)
                  : Colors.transparent,
              border: Border.all(
                color: task.isCompleted ? const Color(0xFF4CAF50) : Colors.grey,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: task.isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  decoration: task.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: task.isCompleted ? Colors.grey : Colors.black87,
                  fontFamily: 'Vaziri',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: priorityColors[task.priority],
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.category != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'دسته: ${task.category}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontFamily: 'Vaziri',
                  ),
                ),
              ),
            if (task.reminderTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'یادآوری: ${DateFormat('yyyy/MM/dd - HH:mm', 'fa').format(task.reminderTime!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontFamily: 'Vaziri',
                  ),
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('ویرایش', style: TextStyle(fontFamily: 'Vaziri')),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'حذف',
                    style: TextStyle(fontFamily: 'Vaziri', color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'edit') {
              _showEditTaskDialog(context, task, index, taskProvider);
            } else if (value == 'delete') {
              taskProvider.deleteTask(index);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 100,
            color: Colors.grey.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'هنوز کاری نداری!',
            style: TextStyle(
              fontSize: 24,
              color: Colors.grey.withOpacity(0.7),
              fontFamily: 'Vaziri',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'با کلیک روی دکمه پایین، اولین کارتو اضافه کن',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.withOpacity(0.5),
              fontFamily: 'Vaziri',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    final titleController = TextEditingController();
    DateTime? selectedDateTime;
    String repeatType = 'none';
    String? selectedCategory;
    int priority = 1;
    String? selectedSound = 'default';
    bool? enableVibration = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: GlassCard(
            margin: EdgeInsets.zero,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'کار جدید',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Vaziri',
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'عنوان کار',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Vaziri'),
                  ),
                  const SizedBox(height: 16),
                  // 分类选择
                  Consumer<TaskProvider>(
                    builder: (context, taskProvider, child) {
                      return DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'دسته‌بندی',
                          labelStyle: TextStyle(fontFamily: 'Vaziri'),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('بدون دسته'),
                          ),
                          ...taskProvider.categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedCategory = value;
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // 优先级选择
                  Row(
                    children: [
                      const Text(
                        'اولویت: ',
                        style: TextStyle(fontFamily: 'Vaziri'),
                      ),
                      const SizedBox(width: 8),
                      for (int i = 0; i < 3; i++)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              priority = i;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: priority == i
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              i == 0
                                  ? 'پایین'
                                  : i == 1
                                  ? 'متوسط'
                                  : 'بالا',
                              style: TextStyle(
                                color: priority == i
                                    ? Colors.white
                                    : Colors.black,
                                fontFamily: 'Vaziri',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  NeumorphicButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) {
                          setState(() {
                            selectedDateTime = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        } else {
                          setState(() {
                            selectedDateTime = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              9, // 默认上午9点
                              0,
                            );
                          });
                        }
                      }
                    },
                    child: Text(
                      selectedDateTime == null
                          ? 'تنظیم یادآوری'
                          : DateFormat(
                              'MM/dd - HH:mm',
                            ).format(selectedDateTime!),
                      style: const TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ),
                  if (selectedDateTime != null) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: repeatType,
                      decoration: const InputDecoration(
                        labelText: 'نوع تکرار',
                        labelStyle: TextStyle(fontFamily: 'Vaziri'),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('بدون تکرار'),
                        ),
                        DropdownMenuItem(value: 'daily', child: Text('روزانه')),
                        DropdownMenuItem(value: 'weekly', child: Text('هفتگی')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          repeatType = value ?? 'none';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'تنظیمات نوتیفیکیشن',
                      style: TextStyle(
                        fontFamily: 'Vaziri',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedSound,
                      decoration: const InputDecoration(
                        labelText: 'صدای نوتیفیکیشن',
                        labelStyle: TextStyle(fontFamily: 'Vaziri'),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'default',
                          child: Text('پیش‌فرض'),
                        ),
                        DropdownMenuItem(
                          value: 'notification_sound',
                          child: Text('صدای سفارشی'),
                        ),
                        DropdownMenuItem(
                          value: 'silent',
                          child: Text('بدون صدا'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedSound = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<bool>(
                      value: enableVibration,
                      decoration: const InputDecoration(
                        labelText: 'لرزش',
                        labelStyle: TextStyle(fontFamily: 'Vaziri'),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: true, child: Text('فعال')),
                        DropdownMenuItem(value: false, child: Text('غیرفعال')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          enableVibration = value;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      NeumorphicButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'لغو',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                      NeumorphicButton(
                        onPressed: () {
                          if (titleController.text.isNotEmpty) {
                            context.read<TaskProvider>().addTask(
                              titleController.text,
                              reminderTime: selectedDateTime,
                              repeatType: repeatType,
                              category: selectedCategory,
                              priority: priority,
                              notificationSound: selectedSound,
                              enableVibration: enableVibration,
                            );
                            Navigator.pop(context);
                          }
                        },
                        child: const Text(
                          'اضافه کردن',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditTaskDialog(
    BuildContext context,
    Task task,
    int index,
    TaskProvider taskProvider,
  ) {
    final titleController = TextEditingController(text: task.title);
    String? selectedCategory = task.category;
    int priority = task.priority;
    String? selectedSound = task.notificationSound ?? 'default';
    bool? enableVibration = task.enableVibration ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: GlassCard(
            margin: EdgeInsets.zero,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ویرایش کار',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Vaziri',
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'عنوان کار',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Vaziri'),
                  ),
                  const SizedBox(height: 16),
                  Consumer<TaskProvider>(
                    builder: (context, taskProvider, child) {
                      return DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'دسته‌بندی',
                          labelStyle: TextStyle(fontFamily: 'Vaziri'),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('بدون دسته'),
                          ),
                          ...taskProvider.categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedCategory = value;
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'اولویت: ',
                        style: TextStyle(fontFamily: 'Vaziri'),
                      ),
                      const SizedBox(width: 8),
                      for (int i = 0; i < 3; i++)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              priority = i;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: priority == i
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              i == 0
                                  ? 'پایین'
                                  : i == 1
                                  ? 'متوسط'
                                  : 'بالا',
                              style: TextStyle(
                                color: priority == i
                                    ? Colors.white
                                    : Colors.black,
                                fontFamily: 'Vaziri',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'تنظیمات نوتیفیکیشن',
                    style: TextStyle(
                      fontFamily: 'Vaziri',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedSound,
                    decoration: const InputDecoration(
                      labelText: 'صدای نوتیفیکیشن',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'default',
                        child: Text('پیش‌فرض'),
                      ),
                      DropdownMenuItem(
                        value: 'notification_sound',
                        child: Text('صدای سفارشی'),
                      ),
                      DropdownMenuItem(
                        value: 'silent',
                        child: Text('بدون صدا'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedSound = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<bool>(
                    value: enableVibration,
                    decoration: const InputDecoration(
                      labelText: 'لرزش',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('فعال')),
                      DropdownMenuItem(value: false, child: Text('غیرفعال')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        enableVibration = value;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      NeumorphicButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'لغو',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                      NeumorphicButton(
                        onPressed: () {
                          if (titleController.text.isNotEmpty) {
                            taskProvider.updateTask(
                              index,
                              titleController.text,
                              category: selectedCategory,
                              priority: priority,
                              notificationSound: selectedSound,
                              enableVibration: enableVibration,
                            );
                            Navigator.pop(context);
                          }
                        },
                        child: const Text(
                          'ذخیره',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 笔记页面 - طراحی مینیمال و فانتزی
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('یادداشت‌ها'),
        actions: [
          const HamburgerMenu(),
          Consumer<NoteProvider>(
            builder: (context, noteProvider, child) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                onSelected: (value) {
                  noteProvider.setSortCriteria(value);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'default',
                    child: Text(
                      'پیش‌فرض',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'byDate',
                    child: Text(
                      'تاریخ',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'byName',
                    child: Text('نام', style: TextStyle(fontFamily: 'Vaziri')),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Consumer<NoteProvider>(
          builder: (context, noteProvider, child) {
            return Column(
              children: [
                // 搜索框
                Container(
                  margin: const EdgeInsets.all(16),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: noteProvider.updateSearchQuery,
                      decoration: InputDecoration(
                        hintText: 'جستجو در یادداشت‌ها...',
                        hintStyle: const TextStyle(fontFamily: 'Vaziri'),
                        prefixIcon: const Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: const TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ),
                ),
                // 笔记统计卡片
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          title: 'کل یادداشت‌ها',
                          value: '${noteProvider.getNoteStats()['total']}',
                          icon: Icons.note,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          title: 'پین شده',
                          value: '${noteProvider.getNoteStats()['pinned']}',
                          icon: Icons.push_pin,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
                // 笔记列表
                Expanded(
                  child: noteProvider.notes.isEmpty
                      ? _buildEmptyState()
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 1.0,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: noteProvider.notes.length,
                          itemBuilder: (context, index) {
                            final note = noteProvider.notes[index];
                            return _buildNoteCard(
                              context,
                              note,
                              index,
                              noteProvider,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'notes_fab', // منحصر به فرد کردن تگ Hero
        onPressed: () => _showAddNoteDialog(context),
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildNoteCard(
    BuildContext context,
    Note note,
    int index,
    NoteProvider noteProvider,
  ) {
    return GestureDetector(
      onTap: () => _showNoteDetailDialog(context, note, index, noteProvider),
      child: GlassCard(
        color: note.color.withOpacity(0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Vaziri',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (note.isPinned)
                  const Icon(Icons.push_pin, size: 16, color: Colors.red),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                note.content,
                style: const TextStyle(fontSize: 14, fontFamily: 'Vaziri'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              note.category,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontFamily: 'Vaziri',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.note_outlined,
            size: 100,
            color: Colors.grey.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'هنوز یادداشتی نداری!',
            style: TextStyle(
              fontSize: 24,
              color: Colors.grey.withOpacity(0.7),
              fontFamily: 'Vaziri',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'با کلیک روی دکمه پایین، اولین یادداشتتو اضافه کن',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.withOpacity(0.5),
              fontFamily: 'Vaziri',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAddNoteDialog(BuildContext context) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final newCategoryController = TextEditingController();

    String? selectedCategory;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: GlassCard(
            margin: EdgeInsets.zero,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'یادداشت جدید',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Vaziri',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // عنوان
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'عنوان',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Vaziri'),
                  ),
                  const SizedBox(height: 16),

                  // محتوا
                  TextField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      labelText: 'محتوا',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    style: const TextStyle(fontFamily: 'Vaziri'),
                  ),
                  const SizedBox(height: 16),

                  // دسته‌بندی
                  Consumer<NoteProvider>(
                    builder: (context, noteProvider, child) {
                      return DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'دسته‌بندی',
                          labelStyle: TextStyle(fontFamily: 'Vaziri'),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          ...noteProvider.categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }),
                          const DropdownMenuItem(
                            value: 'new',
                            child: Text('➕ دسته جدید'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedCategory = value;
                          });
                        },
                      );
                    },
                  ),

                  // فقط اگر دسته جدید انتخاب شد
                  if (selectedCategory == 'new') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: newCategoryController,
                      decoration: const InputDecoration(
                        labelText: 'نام دسته جدید',
                        labelStyle: TextStyle(fontFamily: 'Vaziri'),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // دکمه‌ها
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      NeumorphicButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'لغو',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                      NeumorphicButton(
                        onPressed: () {
                          final category = selectedCategory == 'new'
                              ? newCategoryController.text
                              : selectedCategory;

                          if (titleController.text.isNotEmpty &&
                              contentController.text.isNotEmpty &&
                              category != null &&
                              category.isNotEmpty) {
                            context.read<NoteProvider>().addNote(
                              titleController.text,
                              contentController.text,
                              category,
                            );
                            Navigator.pop(context);
                          }
                        },
                        child: const Text(
                          'اضافه کردن',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showNoteDetailDialog(
    BuildContext context,
    Note note,
    int index,
    NoteProvider noteProvider,
  ) {
    final titleController = TextEditingController(text: note.title);
    final contentController = TextEditingController(text: note.content);
    String? selectedCategory = note.category;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: GlassCard(
            margin: EdgeInsets.zero,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'یادداشت',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Vaziri',
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'عنوان',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Vaziri'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      labelText: 'محتوا',
                      labelStyle: TextStyle(fontFamily: 'Vaziri'),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    style: const TextStyle(fontFamily: 'Vaziri'),
                  ),
                  const SizedBox(height: 16),
                  Consumer<NoteProvider>(
                    builder: (context, noteProvider, child) {
                      return DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'دسته‌بندی',
                          labelStyle: TextStyle(fontFamily: 'Vaziri'),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          ...noteProvider.categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }),
                          const DropdownMenuItem(
                            value: null,
                            child: Text('دسته جدید'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedCategory = value;
                          });
                        },
                      );
                    },
                  ),
                  if (selectedCategory == null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          selectedCategory = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'نام دسته جدید',
                        labelStyle: TextStyle(fontFamily: 'Vaziri'),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      NeumorphicButton(
                        onPressed: () {
                          noteProvider.togglePin(index);
                          Navigator.pop(context);
                        },
                        child: Row(
                          children: [
                            Icon(
                              note.isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              color: note.isPinned ? Colors.red : null,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              note.isPinned ? 'برداشتن پین' : 'پین کردن',
                              style: const TextStyle(fontFamily: 'Vaziri'),
                            ),
                          ],
                        ),
                      ),
                      NeumorphicButton(
                        onPressed: () {
                          noteProvider.deleteNote(index);
                          Navigator.pop(context);
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'حذف',
                              style: TextStyle(
                                fontFamily: 'Vaziri',
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      NeumorphicButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'لغو',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                      NeumorphicButton(
                        onPressed: () {
                          if (titleController.text.isNotEmpty &&
                              contentController.text.isNotEmpty &&
                              selectedCategory != null &&
                              selectedCategory!.isNotEmpty) {
                            noteProvider.updateNote(
                              index,
                              titleController.text,
                              contentController.text,
                              selectedCategory!,
                            );
                            Navigator.pop(context);
                          }
                        },
                        child: const Text(
                          'ذخیره',
                          style: TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 统计页面 - طراحی مینیمال و فانتزی
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('آمار و گزارشات'),
        actions: [
          const HamburgerMenu(),
          PopupMenuButton<int>(
            icon: const Icon(Icons.color_lens),
            onSelected: (index) {
              final colors = [
                const Color(0xFF6C63FF),
                Colors.green,
                Colors.red,
                Colors.teal,
                Colors.purple,
              ];
              context.read<ThemeProvider>().setThemeColor(colors[index], index);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFF6C63FF)),
                    SizedBox(width: 8),
                    Text('بنفش'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('سبز'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Colors.red),
                    SizedBox(width: 8),
                    Text('قرمز'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 3,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('فیروزه‌ای'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 4,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('ارغوانی'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer2<TaskProvider, NoteProvider>(
        builder: (context, taskProvider, noteProvider, child) {
          final taskStats = taskProvider.getTaskStats();
          final noteStats = noteProvider.getNoteStats();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 总览卡片
                GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text(
                        'نمای کلی',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Vaziri',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          StatCard(
                            title: 'کل کارها',
                            value: '${taskStats['total']}',
                            icon: Icons.list_alt,
                          ),
                          StatCard(
                            title: 'کل یادداشت‌ها',
                            value: '${noteStats['total']}',
                            icon: Icons.note,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 任务统计
                const Text(
                  'آمار کارها',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Vaziri',
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatsCard(
                  context,
                  'کارهای انجام شده',
                  '${taskStats['completed']}',
                  Icons.check_circle,
                  Colors.green,
                  taskStats['total']! > 0
                      ? (taskStats['completed']! / taskStats['total']!)
                      : 0.0,
                ),
                const SizedBox(height: 12),
                _buildStatsCard(
                  context,
                  'کارهای در انتظار',
                  '${taskStats['pending']}',
                  Icons.hourglass_empty,
                  Colors.orange,
                  taskStats['total']! > 0
                      ? (taskStats['pending']! / taskStats['total']!)
                      : 0.0,
                ),
                const SizedBox(height: 12),
                _buildStatsCard(
                  context,
                  'کارهای با اولویت بالا',
                  '${taskStats['highPriority']}',
                  Icons.priority_high,
                  Colors.red,
                  taskStats['total']! > 0
                      ? (taskStats['highPriority']! / taskStats['total']!)
                      : 0.0,
                ),
                const SizedBox(height: 24),
                // 笔记统计
                const Text(
                  'آمار یادداشت‌ها',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Vaziri',
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatsCard(
                  context,
                  'یادداشت‌های پین شده',
                  '${noteStats['pinned']}',
                  Icons.push_pin,
                  Colors.amber,
                  noteStats['total']! > 0
                      ? (noteStats['pinned']! / noteStats['total']!)
                      : 0.0,
                ),
                const SizedBox(height: 12),
                _buildStatsCard(
                  context,
                  'تعداد دسته‌بندی‌ها',
                  '${noteStats['categories']}',
                  Icons.category,
                  Colors.teal,
                  1.0,
                ),
                const SizedBox(height: 24),
                // 分类分布
                const Text(
                  'توزیع دسته‌بندی کارها',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Vaziri',
                  ),
                ),
                const SizedBox(height: 16),
                _buildCategoryDistribution(taskProvider, context),
                const SizedBox(height: 24),
                // 笔记分类
                const Text(
                  'دسته‌بندی یادداشت‌ها',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Vaziri',
                  ),
                ),
                const SizedBox(height: 16),
                _buildNoteCategories(noteProvider, context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    double progress,
  ) {
    return GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontFamily: 'Vaziri',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        fontFamily: 'Vaziri',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryDistribution(
    TaskProvider taskProvider,
    BuildContext context,
  ) {
    final categories = taskProvider.categories;

    if (categories.isEmpty) {
      return const GlassCard(
        child: Center(
          child: Text(
            'هیچ دسته‌بندی برای کارها وجود ندارد',
            style: TextStyle(fontFamily: 'Vaziri'),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((category) {
        final count = taskProvider.tasks
            .where((task) => task.category == category)
            .length;

        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '$category: $count',
            style: const TextStyle(fontFamily: 'Vaziri'),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNoteCategories(NoteProvider noteProvider, BuildContext context) {
    final categories = noteProvider.categories;

    if (categories.isEmpty) {
      return const GlassCard(
        child: Center(
          child: Text(
            'هیچ دسته‌بندی برای یادداشت‌ها وجود ندارد',
            style: TextStyle(fontFamily: 'Vaziri'),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((category) {
        final count = noteProvider.notes
            .where((note) => note.category == category)
            .length;

        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '$category: $count',
            style: const TextStyle(fontFamily: 'Vaziri'),
          ),
        );
      }).toList(),
    );
  }
}

// Extensions for JSON serialization
extension TaskExtension on Task {
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'isCompleted': isCompleted,
      'reminderTime': reminderTime?.toIso8601String(),
      'repeatType': repeatType,
      'createdAt': createdAt.toIso8601String(),
      'category': category,
      'priority': priority,
      'notificationSound': notificationSound,
      'enableVibration': enableVibration,
    };
  }
}

extension NoteExtension on Note {
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'category': category,
      'isPinned': isPinned,
      'createdAt': createdAt.toIso8601String(),
      'color': color.value,
      'lastModified': lastModified?.toIso8601String(),
    };
  }
}

