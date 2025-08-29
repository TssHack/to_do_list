import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:math';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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

  Task({
    required this.title,
    this.isCompleted = false,
    this.reminderTime,
    this.repeatType = 'none',
    DateTime? createdAt,
    this.category,
    this.priority = 1,
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
    DateTime? lastModified, // 修复：移除this.，避免重复初始化
  }) : createdAt = createdAt ?? DateTime.now(),
       color = color ?? _getRandomColor(),
       lastModified = lastModified ?? DateTime.now(); // 修复：只在初始化列表中设置一次

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
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'task_channel',
          'یادآوری کارها',
          channelDescription: 'نوتیفیکیشن برای یادآوری کارها',
          importance: Importance.high,
          priority: Priority.high,
          sound: sound != null
              ? RawResourceAndroidNotificationSound(sound)
              : null,
          enableVibration: enableVibration ?? true,
          playSound: sound != null,
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
    await _notificationsPlugin.cancel(id);
  }

  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
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

  List<Task> get tasks {
    List<Task> filteredTasks = List<Task>.from(_tasks);

    // 应用搜索过滤
    if (_searchQuery.isNotEmpty) {
      filteredTasks = filteredTasks
          .where((task) => task.title.contains(_searchQuery))
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
    _tasks.sort((a, b) {
      // 首先按完成状态排序
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      // 然后按优先级排序
      if (a.priority != b.priority) {
        return b.priority.compareTo(a.priority);
      }
      // 最后按创建时间排序
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> addTask(
    String title, {
    DateTime? reminderTime,
    String? repeatType,
    String? category,
    int priority = 1,
  }) async {
    final task = Task(
      title: title,
      reminderTime: reminderTime,
      repeatType: repeatType ?? 'none',
      category: category,
      priority: priority,
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
        sound: 'notification_sound',
        enableVibration: true,
      );
    }

    notifyListeners();
  }

  Future<void> toggleTask(int index) async {
    if (index < _tasks.length) {
      _tasks[index].isCompleted = !_tasks[index].isCompleted;
      await _tasks[index].save();
      _sortTasks();
      notifyListeners();
    }
  }

  Future<void> deleteTask(int index) async {
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
  }

  Future<void> updateTask(
    int index,
    String newTitle, {
    String? category,
    int? priority,
    DateTime? reminderTime,
    String? repeatType,
  }) async {
    if (index < _tasks.length) {
      _tasks[index].title = newTitle;
      if (category != null) _tasks[index].category = category;
      if (priority != null) _tasks[index].priority = priority;
      if (reminderTime != null) _tasks[index].reminderTime = reminderTime;
      if (repeatType != null) _tasks[index].repeatType = repeatType;

      await _tasks[index].save();
      _sortTasks();
      notifyListeners();
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

  List<Note> get notes {
    if (_searchQuery.isEmpty) {
      return _sortedNotes;
    }
    return _sortedNotes
        .where(
          (note) =>
              note.title.contains(_searchQuery) ||
              note.content.contains(_searchQuery) ||
              note.category.contains(_searchQuery),
        )
        .toList();
  }

  List<Note> get _sortedNotes {
    final sortedNotes = List<Note>.from(_notes);
    sortedNotes.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.lastModified!.compareTo(a.lastModified!);
    });
    return sortedNotes;
  }

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

  Future<void> addNote(String title, String content, String category) async {
    final note = Note(title: title, content: content, category: category);

    await _noteBox?.add(note);
    _notes.add(note);
    notifyListeners();
  }

  Future<void> togglePin(int index) async {
    if (index < _notes.length) {
      _notes[index].isPinned = !_notes[index].isPinned;
      _notes[index].lastModified = DateTime.now();
      await _notes[index].save();
      notifyListeners();
    }
  }

  Future<void> deleteNote(int index) async {
    final actualIndex = _getActualIndex(index);
    if (actualIndex != -1) {
      try {
        await _notes[actualIndex].delete();
        _notes.removeAt(actualIndex);
        notifyListeners();
      } catch (e) {
        print('Error deleting note: $e');
      }
    }
  }

  Future<void> updateNote(
    int index,
    String title,
    String content,
    String category,
  ) async {
    final actualIndex = _getActualIndex(index);
    if (actualIndex != -1) {
      _notes[actualIndex].title = title;
      _notes[actualIndex].content = content;
      _notes[actualIndex].category = category;
      _notes[actualIndex].lastModified = DateTime.now();
      await _notes[actualIndex].save();
      notifyListeners();
    }
  }

  int _getActualIndex(int displayIndex) {
    try {
      final displayedNotes = notes;
      if (displayIndex < displayedNotes.length) {
        final targetNote = displayedNotes[displayIndex];
        return _notes.indexOf(targetNote);
      }
    } catch (e) {
      print('Error getting actual index: $e');
    }
    return -1;
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  List<String> get categories {
    return _notes.map((note) => note.category).toSet().toList();
  }

  Map<String, int> getNoteStats() {
    final total = _notes.length;
    final pinned = _notes.where((n) => n.isPinned).length;
    final uniqueCategories = categories.length;

    return {'total': total, 'pinned': pinned, 'categories': uniqueCategories};
  }
}

// 主题提供者
class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  ThemeData get lightTheme => ThemeData(
    primarySwatch: Colors.blue,
    fontFamily: 'Vaziri',
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Vaziri',
        color: Colors.black87,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardColor: Colors.white,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontFamily: 'Vaziri'),
      bodyLarge: TextStyle(fontFamily: 'Vaziri'),
      titleMedium: TextStyle(fontFamily: 'Vaziri'),
      titleLarge: TextStyle(fontFamily: 'Vaziri'),
    ),
  );

  ThemeData get darkTheme => ThemeData(
    primarySwatch: Colors.blue,
    fontFamily: 'Vaziri',
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Vaziri',
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardColor: const Color(0xFF1E1E1E),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontFamily: 'Vaziri'),
      bodyLarge: TextStyle(fontFamily: 'Vaziri'),
      titleMedium: TextStyle(fontFamily: 'Vaziri'),
      titleLarge: TextStyle(fontFamily: 'Vaziri'),
    ),
  );
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
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.isDarkMode
                ? ThemeMode.dark
                : ThemeMode.light,
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

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const TasksPage(),
    const NotesPage(),
    const StatsPage(), // 新增统计页面
    const SettingsPage(), // 新增设置页面
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF6C63FF),
          unselectedItemColor: Colors.grey,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.check_circle_outline),
              activeIcon: Icon(Icons.check_circle),
              label: 'کارها',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.note_outlined),
              activeIcon: Icon(Icons.note),
              label: 'یادداشت‌ها',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: 'آمار',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'تنظیمات',
            ),
          ],
        ),
      ),
    );
  }
}

// 任务页面 - 增强版
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
      duration: const Duration(milliseconds: 300),
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
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return IconButton(
                icon: Icon(
                  themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                ),
                onPressed: themeProvider.toggleTheme,
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
                      TextField(
                        controller: _searchController,
                        onChanged: taskProvider.updateSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'جستجو در کارها...',
                          hintStyle: const TextStyle(fontFamily: 'Vaziri'),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        style: const TextStyle(fontFamily: 'Vaziri'),
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
                              child: FilterChip(
                                label: Text(category),
                                selected: isSelected,
                                onSelected: (selected) {
                                  taskProvider.setSelectedCategory(
                                    selected
                                        ? (index == 0 ? null : category)
                                        : null,
                                  );
                                },
                                backgroundColor: Colors.grey[200],
                                selectedColor: Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.2),
                                checkmarkColor: Theme.of(context).primaryColor,
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
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF4CAF50)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                        'کل کارها',
                        '${taskProvider.getTaskStats()['total']}',
                        Icons.list_alt,
                      ),
                      _buildStatCard(
                        'انجام شده',
                        '${taskProvider.getTaskStats()['completed']}',
                        Icons.check_circle,
                      ),
                      _buildStatCard(
                        'اولویت بالا',
                        '${taskProvider.getTaskStats()['highPriority']}',
                        Icons.priority_high,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTaskDialog(context),
        backgroundColor: const Color(0xFF6C63FF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'کار جدید',
          style: TextStyle(color: Colors.white, fontFamily: 'Vaziri'),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Vaziri',
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'Vaziri',
            ),
          ),
        ],
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: GestureDetector(
          onTap: () => taskProvider.toggleTask(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: task.isCompleted
                  ? const Color(0xFF4CAF50)
                  : Colors.transparent,
              border: Border.all(
                color: task.isCompleted ? const Color(0xFF4CAF50) : Colors.grey,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: task.isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
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
                  color: task.isCompleted ? Colors.grey : null,
                  fontFamily: 'Vaziri',
                  fontSize: 16,
                ),
              ),
            ),
            Container(
              width: 8,
              height: 8,
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontFamily: 'Vaziri',
                  ),
                ),
              ),
            if (task.reminderTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'یادآوری: ${DateFormat('yyyy/MM/dd - HH:mm', 'fa').format(task.reminderTime!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontFamily: 'Vaziri',
                  ),
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: const Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('ویرایش', style: TextStyle(fontFamily: 'Vaziri')),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: const Row(
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
          Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'هنوز کاری نداری!',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[600],
              fontFamily: 'Vaziri',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'با کلیک روی دکمه پایین، اولین کارتو اضافه کن',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('کار جدید', style: TextStyle(fontFamily: 'Vaziri')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
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
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          selectedDateTime == null
                              ? 'تنظیم یادآوری'
                              : DateFormat(
                                  'MM/dd - HH:mm',
                                ).format(selectedDateTime!),
                          style: const TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ),
                    ),
                  ],
                ),
                if (selectedDateTime != null) ...[
                  const SizedBox(height: 8),
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
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لغو', style: TextStyle(fontFamily: 'Vaziri')),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  context.read<TaskProvider>().addTask(
                    titleController.text,
                    reminderTime: selectedDateTime,
                    repeatType: repeatType,
                    category: selectedCategory,
                    priority: priority,
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'ویرایش کار',
            style: TextStyle(fontFamily: 'Vaziri'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لغو', style: TextStyle(fontFamily: 'Vaziri')),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  taskProvider.updateTask(
                    index,
                    titleController.text,
                    category: selectedCategory,
                    priority: priority,
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
      ),
    );
  }
}

// 笔记页面 - 增强版
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
      duration: const Duration(milliseconds: 300),
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
      appBar: AppBar(title: const Text('یادداشت‌های من')),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Consumer<NoteProvider>(
          builder: (context, noteProvider, child) {
            return Column(
              children: [
                // 搜索栏
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
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

                // 笔记统计卡片
                if (noteProvider.notes.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2196F3), Color(0xFF21CBF3)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2196F3).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNoteStatCard(
                          'کل یادداشت‌ها',
                          '${noteProvider.getNoteStats()['total']}',
                          Icons.note,
                        ),
                        _buildNoteStatCard(
                          'سنجاق شده',
                          '${noteProvider.getNoteStats()['pinned']}',
                          Icons.push_pin,
                        ),
                        _buildNoteStatCard(
                          'دسته‌ها',
                          '${noteProvider.getNoteStats()['categories']}',
                          Icons.category,
                        ),
                      ],
                    ),
                  ),

                // 笔记网格
                Expanded(
                  child: noteProvider.notes.isEmpty
                      ? _buildEmptyNotesState()
                      : _buildNotesGrid(noteProvider),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddNoteDialog(context),
        backgroundColor: const Color(0xFF2196F3),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'یادداشت جدید',
          style: TextStyle(color: Colors.white, fontFamily: 'Vaziri'),
        ),
      ),
    );
  }

  Widget _buildNoteStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Vaziri',
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'Vaziri',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesGrid(NoteProvider noteProvider) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: noteProvider.notes.length,
      itemBuilder: (context, index) {
        final note = noteProvider.notes[index];
        return _buildNoteCard(context, note, index, noteProvider);
      },
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
      child: Container(
        decoration: BoxDecoration(
          color: note.color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (note.isPinned)
                    const Icon(Icons.push_pin, size: 16, color: Colors.red),
                  Text(
                    note.title,
                    style: const TextStyle(
                      fontFamily: 'Vaziri',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      note.content,
                      style: const TextStyle(
                        fontFamily: 'Vaziri',
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      note.category,
                      style: const TextStyle(
                        fontFamily: 'Vaziri',
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'آخرین ویرایش: ${DateFormat('yyyy/MM/dd', 'fa').format(note.lastModified!)}',
                    style: const TextStyle(
                      fontFamily: 'Vaziri',
                      fontSize: 8,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: PopupMenuButton(
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(
                          note.isPinned
                              ? Icons.push_pin_outlined
                              : Icons.push_pin,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          note.isPinned ? 'برداشتن سنجاق' : 'سنجاق کردن',
                          style: const TextStyle(fontFamily: 'Vaziri'),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: const Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
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
                onSelected: (value) {
                  if (value == 'pin') {
                    noteProvider.togglePin(index);
                  } else if (value == 'delete') {
                    noteProvider.deleteNote(index);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyNotesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note_add_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'هنوز یادداشتی نداری!',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[600],
              fontFamily: 'Vaziri',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ایده‌ها و خاطراتتو اینجا یادداشت کن',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              fontFamily: 'Vaziri',
            ),
          ),
        ],
      ),
    );
  }

  void _showAddNoteDialog(BuildContext context) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final categoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'یادداشت جدید',
          style: TextStyle(fontFamily: 'Vaziri'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'متن یادداشت',
                  labelStyle: TextStyle(fontFamily: 'Vaziri'),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Vaziri'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  labelText: 'دسته‌بندی',
                  labelStyle: TextStyle(fontFamily: 'Vaziri'),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Vaziri'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو', style: TextStyle(fontFamily: 'Vaziri')),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  contentController.text.isNotEmpty) {
                context.read<NoteProvider>().addNote(
                  titleController.text,
                  contentController.text,
                  categoryController.text.isEmpty
                      ? 'عمومی'
                      : categoryController.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('ذخیره', style: TextStyle(fontFamily: 'Vaziri')),
          ),
        ],
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
    final categoryController = TextEditingController(text: note.category);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'جزئیات یادداشت',
            style: TextStyle(fontFamily: 'Vaziri'),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان',
                    labelStyle: TextStyle(fontFamily: 'Vaziri'),
                  ),
                  style: const TextStyle(fontFamily: 'Vaziri'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'متن یادداشت',
                    labelStyle: TextStyle(fontFamily: 'Vaziri'),
                  ),
                  style: const TextStyle(fontFamily: 'Vaziri'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: 'دسته‌بندی',
                    labelStyle: TextStyle(fontFamily: 'Vaziri'),
                  ),
                  style: const TextStyle(fontFamily: 'Vaziri'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لغو', style: TextStyle(fontFamily: 'Vaziri')),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty &&
                    contentController.text.isNotEmpty) {
                  noteProvider.updateNote(
                    index,
                    titleController.text,
                    contentController.text,
                    categoryController.text,
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
      ),
    );
  }
}

// 统计页面 - 新增
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
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
      appBar: AppBar(title: const Text('آمار و گزارش')),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Consumer2<TaskProvider, NoteProvider>(
          builder: (context, taskProvider, noteProvider, child) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 任务统计
                  _buildSectionTitle('آمار کارها'),
                  const SizedBox(height: 16),
                  _buildTaskStats(taskProvider),
                  const SizedBox(height: 24),

                  // 笔记统计
                  _buildSectionTitle('آمار یادداشت‌ها'),
                  const SizedBox(height: 16),
                  _buildNoteStats(noteProvider),
                  const SizedBox(height: 24),

                  // 优先级分布
                  _buildSectionTitle('توزیع اولویت‌ها'),
                  const SizedBox(height: 16),
                  _buildPriorityChart(taskProvider),
                  const SizedBox(height: 24),

                  // 分类分布
                  _buildSectionTitle('توزیع دسته‌بندی‌ها'),
                  const SizedBox(height: 16),
                  _buildCategoryChart(taskProvider, noteProvider),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        fontFamily: 'Vaziri',
      ),
    );
  }

  Widget _buildTaskStats(TaskProvider taskProvider) {
    final stats = taskProvider.getTaskStats();
    final completionRate = stats['total']! > 0
        ? (stats['completed']! / stats['total']! * 100).toStringAsFixed(1)
        : '0';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('کل کارها', '${stats['total']}', Icons.list_alt),
                _buildStatItem(
                  'انجام شده',
                  '${stats['completed']}',
                  Icons.check_circle,
                ),
                _buildStatItem(
                  'در انتظار',
                  '${stats['pending']}',
                  Icons.schedule,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: stats['total']! > 0
                  ? stats['completed']! / stats['total']!
                  : 0,
              backgroundColor: Colors.grey[200],
              color: Colors.green,
              minHeight: 10,
            ),
            const SizedBox(height: 8),
            Text(
              'نرخ تکمیل: $completionRate%',
              style: const TextStyle(fontFamily: 'Vaziri'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteStats(NoteProvider noteProvider) {
    final stats = noteProvider.getNoteStats();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('کل یادداشت‌ها', '${stats['total']}', Icons.note),
            _buildStatItem('سنجاق شده', '${stats['pinned']}', Icons.push_pin),
            _buildStatItem('دسته‌ها', '${stats['categories']}', Icons.category),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).primaryColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'Vaziri',
          ),
        ),
        Text(title, style: const TextStyle(fontSize: 12, fontFamily: 'Vaziri')),
      ],
    );
  }

  Widget _buildPriorityChart(TaskProvider taskProvider) {
    final tasks = taskProvider.tasks;
    final low = tasks.where((t) => t.priority == 0).length;
    final medium = tasks.where((t) => t.priority == 1).length;
    final high = tasks.where((t) => t.priority == 2).length;
    final total = tasks.length;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPriorityItem('پایین', low, Colors.green),
                _buildPriorityItem('متوسط', medium, Colors.orange),
                _buildPriorityItem('بالا', high, Colors.red),
              ],
            ),
            const SizedBox(height: 16),
            if (total > 0)
              Row(
                children: [
                  Expanded(
                    flex: low,
                    child: Container(height: 20, color: Colors.green),
                  ),
                  Expanded(
                    flex: medium,
                    child: Container(height: 20, color: Colors.orange),
                  ),
                  Expanded(
                    flex: high,
                    child: Container(height: 20, color: Colors.red),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityItem(String title, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 8),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Vaziri',
          ),
        ),
        Text(title, style: const TextStyle(fontSize: 12, fontFamily: 'Vaziri')),
      ],
    );
  }

  Widget _buildCategoryChart(
    TaskProvider taskProvider,
    NoteProvider noteProvider,
  ) {
    final taskCategories = taskProvider.categories;
    final noteCategories = noteProvider.categories;
    final allCategories = {...taskCategories, ...noteCategories}.toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final category in allCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        style: const TextStyle(fontFamily: 'Vaziri'),
                      ),
                    ),
                    Container(
                      width: 100,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.7, // 示例值，实际应根据比例计算
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${taskCategories.contains(category) ? 'T' : ''}${noteCategories.contains(category) ? 'N' : ''}',
                      style: const TextStyle(fontFamily: 'Vaziri'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 设置页面 - 新增
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
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
      appBar: AppBar(title: const Text('تنظیمات')),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 主题设置
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return ListTile(
                    title: const Text(
                      'حالت نمایش',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                    trailing: Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (value) {
                        themeProvider.toggleTheme();
                      },
                    ),
                    subtitle: Text(
                      themeProvider.isDarkMode ? 'تاریک' : 'روشن',
                      style: const TextStyle(fontFamily: 'Vaziri'),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // 通知设置
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                title: const Text(
                  'تنظیمات نوتیفیکیشن',
                  style: TextStyle(fontFamily: 'Vaziri'),
                ),
                trailing: const Icon(Icons.notifications),
                onTap: () {
                  // 导航到通知设置页面
                },
              ),
            ),

            const SizedBox(height: 16),

            // 数据管理
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text(
                      'پشتیبان‌گیری',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                    trailing: const Icon(Icons.backup),
                    onTap: () {
                      // 实现备份功能
                    },
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text(
                      'بازیابی داده‌ها',
                      style: TextStyle(fontFamily: 'Vaziri'),
                    ),
                    trailing: const Icon(Icons.restore),
                    onTap: () {
                      // 实现恢复功能
                    },
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text(
                      'پاک‌سازی داده‌ها',
                      style: TextStyle(fontFamily: 'Vaziri', color: Colors.red),
                    ),
                    trailing: const Icon(Icons.delete, color: Colors.red),
                    onTap: () {
                      _showClearDataDialog(context);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 关于
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                title: const Text(
                  'درباره برنامه',
                  style: TextStyle(fontFamily: 'Vaziri'),
                ),
                trailing: const Icon(Icons.info),
                onTap: () {
                  _showAboutDialog(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'پاک‌سازی داده‌ها',
          style: TextStyle(fontFamily: 'Vaziri'),
        ),
        content: const Text(
          'آیا از پاک‌سازی تمام داده‌ها اطمینان دارید؟ این عمل غیرقابل بازگشت است.',
          style: TextStyle(fontFamily: 'Vaziri'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو', style: TextStyle(fontFamily: 'Vaziri')),
          ),
          ElevatedButton(
            onPressed: () async {
              // 清除所有数据
              await Hive.box<Task>('tasks').clear();
              await Hive.box<Note>('notes').clear();

              // 刷新提供者
              context.read<TaskProvider>()._loadTasks();
              context.read<NoteProvider>()._loadNotes();

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'تمام داده‌ها با موفقیت پاک شدند',
                    style: TextStyle(fontFamily: 'Vaziri'),
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'پاک‌سازی',
              style: TextStyle(color: Colors.white, fontFamily: 'Vaziri'),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'درباره برنامه',
          style: TextStyle(fontFamily: 'Vaziri'),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مدیریت کارها و یادداشت‌ها',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Vaziri',
              ),
            ),
            SizedBox(height: 16),
            Text('نسخه: 1.0.0', style: TextStyle(fontFamily: 'Vaziri')),
            SizedBox(height: 8),
            Text('توسعه‌دهنده: تیم ما', style: TextStyle(fontFamily: 'Vaziri')),
            SizedBox(height: 16),
            Text(
              'این برنامه برای مدیریت کارها و یادداشت‌های روزانه طراحی شده است.',
              style: TextStyle(fontFamily: 'Vaziri'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن', style: TextStyle(fontFamily: 'Vaziri')),
          ),
        ],
      ),
    );
  }
}
