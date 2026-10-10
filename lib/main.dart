import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mobile_reminder_service.dart';

// --- Note & Connection Models ---

enum ViewMode { canvas, list, dashboard }

class Board {
  final String id;
  String name;
  int colorValue;

  Board({
    required this.id,
    required this.name,
    required this.colorValue,
  });
}

class BoardDraft {
  final String name;
  final int colorValue;

  const BoardDraft({required this.name, required this.colorValue});
}

class Note {
  final String id;
  String boardId;
  String title;
  String content;
  String documentBody;
  late final ValueNotifier<Offset> positionNotifier;
  int colorValue;
  bool isLocked;

  Note({
    required this.id,
    this.boardId = 'default',
    required this.title,
    required this.content,
    this.documentBody = '',
    required Offset position,
    this.colorValue = 0xFF1E1E22,
    this.isLocked = false,
  }) {
    positionNotifier = ValueNotifier<Offset>(position);
  }

  Offset get position => positionNotifier.value;
  set position(Offset val) => positionNotifier.value = val;

  void dispose() {
    positionNotifier.dispose();
  }
}

class Connection {
  final String fromId;
  final String toId;

  Connection(this.fromId, this.toId);
}

final List<Color> darkNoteColors = [
  const Color(0xFF1E1E22),
  const Color(0xFF1E293B),
  const Color(0xFF0F291E),
  const Color(0xFF311B29),
  const Color(0xFF3B1D11),
  const Color(0xFF1F1D36),
];

final List<Color> lightNoteColors = [
  const Color(0xFFF1F5F9),
  const Color(0xFFE0F2FE),
  const Color(0xFFDCFCE7),
  const Color(0xFFFCE7F3),
  const Color(0xFFFEF3C7),
  const Color(0xFFEDE9FE),
];

const List<Color> _boardPalette = [
  Color(0xFF22D3EE),
  Color(0xFFA78BFA),
  Color(0xFFFB7185),
  Color(0xFF34D399),
  Color(0xFFFBBF24),
  Color(0xFF60A5FA),
];

// --- Database Helper ---

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'obsidian_notes.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE boards (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            colorValue INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE note_activity (
            activityDate TEXT PRIMARY KEY
          )
        ''');
        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            boardId TEXT NOT NULL DEFAULT 'default',
            title TEXT,
            content TEXT,
            documentBody TEXT,
            dx REAL,
            dy REAL,
            colorValue INTEGER,
            isLocked INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db
            .execute('CREATE INDEX notes_board_id_index ON notes (boardId)');
        await db.insert(
          'boards',
          {
            'id': 'default',
            'name': 'My first board',
            'colorValue': 0xFF22D3EE,
          },
        );
        await db.execute('''
          CREATE TABLE connections (
            fromId TEXT,
            toId TEXT,
            PRIMARY KEY (fromId, toId)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE notes ADD COLUMN documentBody TEXT DEFAULT ""');
        }
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE notes ADD COLUMN isLocked INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE boards (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              colorValue INTEGER NOT NULL
            )
          ''');
          await db.insert(
            'boards',
            {
              'id': 'default',
              'name': 'My first board',
              'colorValue': 0xFF22D3EE,
            },
          );
          await db.execute(
              "ALTER TABLE notes ADD COLUMN boardId TEXT NOT NULL DEFAULT 'default'");
          await db
              .execute('CREATE INDEX notes_board_id_index ON notes (boardId)');
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE note_activity (
              activityDate TEXT PRIMARY KEY
            )
          ''');
        }
      },
    );
  }

  static Future<List<Board>> fetchBoards() async {
    final db = await database;
    final rows = await db.query('boards', orderBy: 'rowid ASC');
    return rows
        .map(
          (row) => Board(
            id: row['id'] as String,
            name: row['name'] as String,
            colorValue: row['colorValue'] as int,
          ),
        )
        .toList();
  }

  static Future<void> insertBoard(Board board) async {
    final db = await database;
    await db.insert('boards', {
      'id': board.id,
      'name': board.name,
      'colorValue': board.colorValue,
    });
  }

  static Future<void> updateBoard(Board board) async {
    final db = await database;
    await db.update(
      'boards',
      {'name': board.name, 'colorValue': board.colorValue},
      where: 'id = ?',
      whereArgs: [board.id],
    );
  }

  static Future<List<Note>> fetchNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes');
    return maps.map((map) {
      final rawContent = map['content'] as String;
      final cleanContent =
          rawContent == 'Click to add content...' ? '' : rawContent;
      return Note(
        id: map['id'] as String,
        boardId: (map['boardId'] as String?) ?? 'default',
        title: map['title'] as String,
        content: cleanContent,
        documentBody: (map['documentBody'] as String?) ?? '',
        position: ui.Offset(
          (map['dx'] as num).toDouble(),
          (map['dy'] as num).toDouble(),
        ),
        colorValue: (map['colorValue'] as int?) ?? 0xFF1E1E22,
        isLocked: (map['isLocked'] as int? ?? 0) != 0,
      );
    }).toList();
  }

  static Future<void> insertNote(Note note) async {
    final db = await database;
    await db.insert(
      'notes',
      {
        'id': note.id,
        'boardId': note.boardId,
        'title': note.title,
        'content': note.content,
        'documentBody': note.documentBody,
        'dx': note.position.dx,
        'dy': note.position.dy,
        'colorValue': note.colorValue,
        'isLocked': note.isLocked ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> createNote(Note note, DateTime createdAt) async {
    final db = await database;
    final dateKey = activityDateKey(createdAt);
    await db.transaction((transaction) async {
      await transaction.insert('notes', {
        'id': note.id,
        'boardId': note.boardId,
        'title': note.title,
        'content': note.content,
        'documentBody': note.documentBody,
        'dx': note.position.dx,
        'dy': note.position.dy,
        'colorValue': note.colorValue,
        'isLocked': note.isLocked ? 1 : 0,
      });
      await transaction.insert(
        'note_activity',
        {'activityDate': dateKey},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  static Future<Set<String>> fetchNoteActivityDates() async {
    final db = await database;
    final rows = await db.query('note_activity', columns: ['activityDate']);
    return rows.map((row) => row['activityDate'] as String).toSet();
  }

  static Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update(
      'notes',
      {
        'boardId': note.boardId,
        'title': note.title,
        'content': note.content,
        'documentBody': note.documentBody,
        'dx': note.position.dx,
        'dy': note.position.dy,
        'colorValue': note.colorValue,
        'isLocked': note.isLocked ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  static Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    await db.delete('connections',
        where: 'fromId = ? OR toId = ?', whereArgs: [id, id]);
  }

  static Future<List<Connection>> fetchConnections() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('connections');
    return maps
        .map(
            (map) => Connection(map['fromId'] as String, map['toId'] as String))
        .toList();
  }

  static Future<void> insertConnection(Connection conn) async {
    final db = await database;
    await db.insert(
      'connections',
      {'fromId': conn.fromId, 'toId': conn.toId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> deleteConnection(Connection conn) async {
    final db = await database;
    await db.delete(
      'connections',
      where: '(fromId = ? AND toId = ?) OR (fromId = ? AND toId = ?)',
      whereArgs: [conn.fromId, conn.toId, conn.toId, conn.fromId],
    );
  }

  static String activityDateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

int calculateNoteStreak(Set<String> activityDates, DateTime today) {
  String dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  final localToday = DateTime(today.year, today.month, today.day);
  if (!activityDates.contains(dateKey(localToday)) &&
      !activityDates.contains(
        dateKey(localToday.subtract(const Duration(days: 1))),
      )) {
    return 0;
  }

  var streak = 0;
  var currentDay = activityDates.contains(dateKey(localToday))
      ? localToday
      : localToday.subtract(const Duration(days: 1));
  while (activityDates.contains(dateKey(currentDay))) {
    streak++;
    currentDay = currentDay.subtract(const Duration(days: 1));
  }
  return streak;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const ObsidianAppRoot());
}

class ObsidianAppRoot extends StatefulWidget {
  const ObsidianAppRoot({super.key});

  @override
  State<ObsidianAppRoot> createState() => _ObsidianAppRootState();
}

class _ObsidianAppRootState extends State<ObsidianAppRoot> {
  bool isDarkMode = true;

  void toggleTheme() {
    setState(() {
      isDarkMode = !isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF168F7D),
        brightness: Brightness.light,
        surface: const Color(0xFFF7F8F6),
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F8F6),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF168F7D),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF82E0C5),
        brightness: Brightness.dark,
        surface: const Color(0xFF171A19),
      ),
      scaffoldBackgroundColor: const Color(0xFF101211),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF82E0C5),
          foregroundColor: const Color(0xFF10211D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: lightTheme,
      darkTheme: darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US')],
      home: ObsidianNoteApp(
        isDarkMode: isDarkMode,
        onToggleTheme: toggleTheme,
      ),
    );
  }
}

class ObsidianNoteApp extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const ObsidianNoteApp({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<ObsidianNoteApp> createState() => _ObsidianNoteAppState();
}

class _ObsidianNoteAppState extends State<ObsidianNoteApp>
    with WidgetsBindingObserver {
  ViewMode activeMode = ViewMode.canvas;

  List<Board> boards = [];
  String activeBoardId = 'default';
  List<Note> allNotes = [];
  List<Connection> connections = [];

  List<Note> get notes =>
      allNotes.where((note) => note.boardId == activeBoardId).toList();

  List<Connection> get visibleConnections {
    final visibleNoteIds = notes.map((note) => note.id).toSet();
    return connections
        .where((connection) =>
            visibleNoteIds.contains(connection.fromId) &&
            visibleNoteIds.contains(connection.toId))
        .toList();
  }

  int cachedTotalWords = 0;
  Set<String> cachedConnectedNoteIds = {};
  Set<String> activityDates = {};

  String? connectingFromId;
  bool dailyReminderEnabled = false;
  bool _mobileFeaturesReady = false;
  TimeOfDay dailyReminderTime = const TimeOfDay(hour: 20, minute: 0);
  late Future<SharedPreferences> _preferences;

  final ChangeNotifier canvasRepaintNotifier = ChangeNotifier();

  Color get _accentColor =>
      widget.isDarkMode ? const Color(0xFF82E0C5) : const Color(0xFF168F7D);

  Color get _surfaceColor =>
      widget.isDarkMode ? const Color(0xFF171A19) : Colors.white;

  Color get _hairlineColor => widget.isDarkMode
      ? Colors.white.withValues(alpha: 0.075)
      : const Color(0xFF17231F).withValues(alpha: 0.09);

  bool get isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  int get currentNoteStreak =>
      calculateNoteStreak(activityDates, DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preferences = SharedPreferences.getInstance();
    _loadFromDatabase();
    _initializeMobileFeatures();
  }

  Future<void> _initializeMobileFeatures() async {
    try {
      final preferences = await _preferences;
      final savedBoardId = preferences.getString('active_board_id');
      final enabled = isMobilePlatform &&
          (preferences.getBool('daily_note_reminder_enabled') ?? false);
      final hour = preferences.getInt('daily_note_reminder_hour') ?? 20;
      final minute = preferences.getInt('daily_note_reminder_minute') ?? 0;
      if (isMobilePlatform && enabled) {
        await MobileReminderService.initialize();
        await MobileReminderService.scheduleDaily(hour: hour, minute: minute);
      }
      if (!mounted) return;
      setState(() {
        if (savedBoardId != null &&
            boards.any((board) => board.id == savedBoardId)) {
          activeBoardId = savedBoardId;
          _recalculateMetrics();
        }
        dailyReminderEnabled = enabled;
        dailyReminderTime = TimeOfDay(hour: hour, minute: minute);
        _mobileFeaturesReady = isMobilePlatform;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _mobileFeaturesReady = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not set up mobile reminders: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setDailyReminder(bool enabled) async {
    if (!isMobilePlatform || !_mobileFeaturesReady) return;
    try {
      if (!enabled) {
        await MobileReminderService.cancel();
        final preferences = await _preferences;
        await preferences.setBool('daily_note_reminder_enabled', false);
        if (mounted) setState(() => dailyReminderEnabled = false);
        return;
      }

      final selectedTime = await showTimePicker(
        context: context,
        initialTime: dailyReminderTime,
        helpText: 'Choose your daily note reminder time',
      );
      if (selectedTime == null || !mounted) return;

      await MobileReminderService.initialize();
      final permissionGranted = await MobileReminderService.requestPermission();
      if (!permissionGranted) {
        throw StateError('Notification permission was not granted.');
      }
      await MobileReminderService.scheduleDaily(
        hour: selectedTime.hour,
        minute: selectedTime.minute,
      );
      final preferences = await _preferences;
      await preferences.setBool('daily_note_reminder_enabled', true);
      await preferences.setInt('daily_note_reminder_hour', selectedTime.hour);
      await preferences.setInt(
        'daily_note_reminder_minute',
        selectedTime.minute,
      );
      if (!mounted) return;
      setState(() {
        dailyReminderEnabled = true;
        dailyReminderTime = selectedTime;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update daily reminder: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final note in allNotes) {
      note.dispose();
    }
    canvasRepaintNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistAllNotes();
    }
  }

  Future<void> _persistAllNotes() async {
    await Future.wait(allNotes.map(DBHelper.updateNote));
  }

  void _recalculateMetrics() {
    cachedConnectedNoteIds =
        visibleConnections.expand((c) => [c.fromId, c.toId]).toSet();
    cachedTotalWords = notes.fold<int>(0, (sum, note) {
      final docText = note.content;
      return sum +
          note.title.split(' ').where((w) => w.isNotEmpty).length +
          docText.split(' ').where((w) => w.isNotEmpty).length;
    });
  }

  Future<void> _loadFromDatabase() async {
    var loadedBoards = await DBHelper.fetchBoards();
    final loadedNotes = await DBHelper.fetchNotes();
    final loadedConnections = await DBHelper.fetchConnections();
    final loadedActivityDates = await DBHelper.fetchNoteActivityDates();
    if (!mounted) {
      for (final note in loadedNotes) {
        note.dispose();
      }
      return;
    }
    final preferences = await _preferences;
    if (!mounted) {
      for (final note in loadedNotes) {
        note.dispose();
      }
      return;
    }

    if (loadedBoards.isEmpty) {
      final defaultBoard = Board(
        id: 'default',
        name: 'My first board',
        colorValue: 0xFF22D3EE,
      );
      await DBHelper.insertBoard(defaultBoard);
      if (!mounted) {
        for (final note in loadedNotes) {
          note.dispose();
        }
        return;
      }
      loadedBoards = [defaultBoard];
    }
    boards = loadedBoards;
    final savedBoardId = preferences.getString('active_board_id');
    activeBoardId = boards.any((board) => board.id == savedBoardId)
        ? savedBoardId!
        : boards.first.id;
    activityDates = loadedActivityDates;

    if (loadedNotes.isEmpty) {
      final n1 = Note(
        id: '1',
        boardId: activeBoardId,
        title: 'Main Architecture',
        content: 'Core project structure and specs.',
        documentBody: '',
        position: const ui.Offset(300, 300),
        colorValue: 0xFF1E293B,
      );
      final n2 = Note(
        id: '2',
        boardId: activeBoardId,
        title: 'Database Schema',
        content: 'Local SQLite tables.',
        documentBody: '',
        position: const ui.Offset(640, 200),
        colorValue: 0xFF0F291E,
      );
      final c1 = Connection('1', '2');

      await DBHelper.insertNote(n1);
      await DBHelper.insertNote(n2);
      await DBHelper.insertConnection(c1);
      if (!mounted) {
        n1.dispose();
        n2.dispose();
        return;
      }

      allNotes = [n1, n2];
      connections = [c1];
    } else {
      allNotes = loadedNotes;
      connections = loadedConnections;
    }

    _attachListeners();
    _recalculateMetrics();
    setState(() {});
  }

  void _attachListeners() {
    for (var note in allNotes) {
      note.positionNotifier.addListener(_onNoteMoved);
    }
  }

  void _onNoteMoved() {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    canvasRepaintNotifier.notifyListeners();
  }

  Color _getNoteColor(int storedColorValue) {
    if (widget.isDarkMode) {
      return Color(storedColorValue);
    }
    final index =
        darkNoteColors.indexWhere((c) => c.toARGB32() == storedColorValue);
    if (index != -1 && index < lightNoteColors.length) {
      return lightNoteColors[index];
    }
    return const Color(0xFFF1F5F9);
  }

  void _changeNoteColor(Note note, Color color) async {
    final darkValue = widget.isDarkMode
        ? color.toARGB32()
        : darkNoteColors[lightNoteColors.indexOf(color)].toARGB32();

    setState(() {
      note.colorValue = darkValue;
    });
    await DBHelper.updateNote(note);
  }

  Future<void> _toggleNoteLock(Note note) async {
    final previousLockState = note.isLocked;
    setState(() => note.isLocked = !previousLockState);

    try {
      await DBHelper.updateNote(note);
    } catch (error) {
      if (!mounted) return;
      setState(() => note.isLocked = previousLockState);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update note lock: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _switchBoard(String boardId) async {
    if (boardId == activeBoardId) return;
    setState(() {
      activeBoardId = boardId;
      connectingFromId = null;
      _recalculateMetrics();
    });
    await _rememberActiveBoard(boardId);
  }

  Future<void> _rememberActiveBoard(String boardId) async {
    try {
      final preferences = await _preferences;
      await preferences.setString('active_board_id', boardId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remember active board: $error')),
      );
    }
  }

  Future<void> _createBoard() async {
    final draft = await _showBoardEditor(
      title: 'Create a board',
      initialName: '',
      initialColorValue:
          _boardPalette[boards.length % _boardPalette.length].toARGB32(),
      actionLabel: 'Create board',
    );
    if (draft == null || !mounted) return;

    if (boards
        .any((board) => board.name.toLowerCase() == draft.name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A board with that name already exists')),
      );
      return;
    }

    final board = Board(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: draft.name,
      colorValue: draft.colorValue,
    );
    try {
      await DBHelper.insertBoard(board);
      if (!mounted) return;
      setState(() {
        boards = [...boards, board];
        activeBoardId = board.id;
        activeMode = ViewMode.canvas;
        _recalculateMetrics();
      });
      await _rememberActiveBoard(board.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create board: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<BoardDraft?> _showBoardEditor({
    required String title,
    required String initialName,
    required int initialColorValue,
    required String actionLabel,
  }) {
    return showDialog<BoardDraft>(
      context: context,
      builder: (context) => BoardEditorDialog(
        title: title,
        initialName: initialName,
        initialColorValue: initialColorValue,
        actionLabel: actionLabel,
      ),
    );
  }

  Future<void> _renameBoard(Board board) async {
    final draft = await _showBoardEditor(
      title: 'Customize board',
      initialName: board.name,
      initialColorValue: board.colorValue,
      actionLabel: 'Save changes',
    );
    if (draft == null || !mounted) return;

    if (boards.any((item) =>
        item.id != board.id &&
        item.name.toLowerCase() == draft.name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A board with that name already exists')),
      );
      return;
    }
    if (draft.name == board.name && draft.colorValue == board.colorValue) {
      return;
    }

    final previousName = board.name;
    final previousColor = board.colorValue;
    setState(() {
      board
        ..name = draft.name
        ..colorValue = draft.colorValue;
    });
    try {
      await DBHelper.updateBoard(board);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        board
          ..name = previousName
          ..colorValue = previousColor;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update board: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _moveNoteToBoard(Note note, String boardId) async {
    if (note.boardId == boardId) return;
    final previousBoardId = note.boardId;
    setState(() {
      note.boardId = boardId;
      connectingFromId = null;
      _recalculateMetrics();
    });

    try {
      await DBHelper.updateNote(note);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        note.boardId = previousBoardId;
        _recalculateMetrics();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not move note: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    final destinationName = boards.firstWhere((b) => b.id == boardId).name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved to $destinationName'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Open board',
          onPressed: () => _switchBoard(boardId),
        ),
      ),
    );
  }

  Future<void> _addNote() async {
    final createdAt = DateTime.now();
    final newNote = Note(
      id: createdAt.microsecondsSinceEpoch.toString(),
      boardId: activeBoardId,
      title: 'Untitled Note',
      content: '',
      documentBody: '',
      position: const ui.Offset(400, 400),
      colorValue: darkNoteColors[0].toARGB32(),
    );

    newNote.positionNotifier.addListener(_onNoteMoved);

    setState(() {
      allNotes.add(newNote);
    });

    _recalculateMetrics();
    try {
      await DBHelper.createNote(newNote, createdAt);
      if (!mounted) return;
      setState(() {
        activityDates.add(DBHelper.activityDateKey(createdAt));
        _recalculateMetrics();
      });
    } catch (error) {
      newNote.positionNotifier.removeListener(_onNoteMoved);
      if (mounted) {
        setState(() {
          allNotes.remove(newNote);
          _recalculateMetrics();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save new note: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      newNote.dispose();
    }
  }

  void _deleteNote(int index) async {
    final note = notes[index];
    note.positionNotifier.removeListener(_onNoteMoved);

    setState(() {
      allNotes.remove(note);
      connections.removeWhere((c) => c.fromId == note.id || c.toId == note.id);
    });

    _recalculateMetrics();
    note.dispose();
    await DBHelper.deleteNote(note.id);
  }

  void _deleteConnection(Connection conn) async {
    setState(() {
      connections.removeWhere((c) =>
          (c.fromId == conn.fromId && c.toId == conn.toId) ||
          (c.fromId == conn.toId && c.toId == conn.fromId));
    });
    _recalculateMetrics();
    await DBHelper.deleteConnection(conn);
  }

  void _handleRightClickConnect(String noteId) async {
    if (connectingFromId == null) {
      setState(() => connectingFromId = noteId);
    } else if (connectingFromId == noteId) {
      setState(() => connectingFromId = null);
    } else {
      final fromId = connectingFromId!;
      final toId = noteId;

      final exists = connections.any((c) =>
          (c.fromId == fromId && c.toId == toId) ||
          (c.fromId == toId && c.toId == fromId));

      if (!exists) {
        final newConnection = Connection(fromId, toId);
        setState(() {
          connections.add(newConnection);
          connectingFromId = null;
        });

        _recalculateMetrics();
        await DBHelper.insertConnection(newConnection);
      } else {
        setState(() => connectingFromId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor:
          widget.isDarkMode ? const Color(0xFF101211) : const Color(0xFFF7F8F6),
      body: Stack(
        children: [
          Positioned.fill(
            child: ScreenSwitcher(
              screenKey: (activeMode, activeBoardId),
              child: _buildBodyView(),
            ),
          ),
          _buildBoardSwitcher(isCompact: isCompact),
          if (isCompact)
            _buildMobileNavigation()
          else
            _buildFloatingControlBar(),
        ],
      ),
    );
  }

  Widget _buildBodyView() {
    switch (activeMode) {
      case ViewMode.canvas:
        return _buildCanvasView();
      case ViewMode.list:
        return SafeArea(child: _buildListView());
      case ViewMode.dashboard:
        return SafeArea(child: _buildDashboardView());
    }
  }

  Widget _buildFloatingControlBar() {
    final barBg = _surfaceColor.withValues(alpha: 0.96);
    final borderColor = _hairlineColor;
    final inactiveIconColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.48)
        : const Color(0xFF17231F).withValues(alpha: 0.48);

    return Positioned(
      left: 20,
      top: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: barBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: widget.isDarkMode ? 0.2 : 0.055),
              blurRadius: 20,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              style: _navigationButtonStyle(activeMode == ViewMode.canvas),
              icon: Icon(
                Icons.bubble_chart_outlined,
                color: activeMode == ViewMode.canvas
                    ? _accentColor
                    : inactiveIconColor,
                size: 19,
              ),
              onPressed: () => setState(() => activeMode = ViewMode.canvas),
              tooltip: 'Canvas View',
            ),
            const SizedBox(height: 4),
            IconButton(
              style: _navigationButtonStyle(activeMode == ViewMode.list),
              icon: Icon(
                Icons.view_list_outlined,
                color: activeMode == ViewMode.list
                    ? _accentColor
                    : inactiveIconColor,
                size: 19,
              ),
              onPressed: () => setState(() => activeMode = ViewMode.list),
              tooltip: 'List View',
            ),
            const SizedBox(height: 4),
            IconButton(
              style: _navigationButtonStyle(activeMode == ViewMode.dashboard),
              icon: Icon(
                Icons.insights_outlined,
                color: activeMode == ViewMode.dashboard
                    ? _accentColor
                    : inactiveIconColor,
                size: 19,
              ),
              onPressed: () => setState(() => activeMode = ViewMode.dashboard),
              tooltip: 'Dashboard View',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(width: 24, height: 1, color: borderColor),
            ),
            IconButton(
              icon: Icon(
                widget.isDarkMode
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: widget.isDarkMode
                    ? const Color(0xFFE8C989)
                    : const Color(0xFF576C68),
                size: 19,
              ),
              onPressed: widget.onToggleTheme,
              tooltip: widget.isDarkMode ? 'Light Mode' : 'Dark Mode',
            ),
            const SizedBox(height: 4),
            IconButton(
              icon: Icon(
                Icons.add_rounded,
                color: _accentColor,
                size: 21,
              ),
              onPressed: _addNote,
              tooltip: 'New Note',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardSwitcher({required bool isCompact}) {
    if (boards.isEmpty) return const SizedBox.shrink();
    final currentBoard =
        boards.firstWhere((board) => board.id == activeBoardId);
    final boardNoteCounts = <String, int>{};
    for (final note in allNotes) {
      boardNoteCounts.update(
        note.boardId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final barColor = _surfaceColor.withValues(alpha: 0.96);
    final borderColor = _hairlineColor;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + (isCompact ? 6 : 16),
      left: isCompact ? 12 : 78,
      right: isCompact ? 12 : 16,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            height: 54,
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: widget.isDarkMode ? 0.25 : 0.07,
                  ),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Icon(
                    Icons.layers_outlined,
                    size: 17,
                    color: Color(currentBoard.colorValue),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: boards.map((board) {
                        final isActive = board.id == activeBoardId;
                        final boardNoteCount = boardNoteCounts[board.id] ?? 0;
                        final boardColor = Color(board.colorValue);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? boardColor.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActive
                                    ? boardColor.withValues(alpha: 0.45)
                                    : Colors.transparent,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _switchBoard(board.id),
                              onLongPress: () => _renameBoard(board),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 7,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      width: isActive ? 8 : 6,
                                      height: isActive ? 8 : 6,
                                      decoration: BoxDecoration(
                                        color: boardColor.withValues(
                                          alpha: isActive ? 1 : 0.55,
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: isActive
                                            ? [
                                                BoxShadow(
                                                  color: boardColor.withValues(
                                                      alpha: 0.5),
                                                  blurRadius: 8,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 150),
                                      child: Text(
                                        board.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isActive
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: widget.isDarkMode
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? boardColor.withValues(alpha: 0.2)
                                            : borderColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '$boardNoteCount',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: isActive
                                              ? boardColor
                                              : (widget.isDarkMode
                                                  ? Colors.white54
                                                  : Colors.black54),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  tooltip: 'Board options',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                    size: 20,
                  ),
                  onSelected: (action) {
                    if (action == 'rename') _renameBoard(currentBoard);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 18),
                          const SizedBox(width: 10),
                          Text('Customize ${currentBoard.name}'),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Create a new board',
                  onPressed: _createBoard,
                  style: IconButton.styleFrom(
                    backgroundColor:
                        Color(currentBoard.colorValue).withValues(alpha: 0.16),
                    foregroundColor: Color(currentBoard.colorValue),
                    fixedSize: const Size(38, 38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileNavigation() {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final background = _surfaceColor.withValues(alpha: 0.97);
    const destinations = [
      (ViewMode.canvas, Icons.bubble_chart_outlined, 'Canvas'),
      (ViewMode.list, Icons.notes_outlined, 'Notes'),
      (ViewMode.dashboard, Icons.insights_outlined, 'Insights'),
    ];

    return Positioned(
      left: 16,
      right: 16,
      bottom: safeBottom + 10,
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _hairlineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: widget.isDarkMode ? 0.2 : 0.07,
              ),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final (mode, icon, label) in destinations)
              Expanded(
                child: _buildMobileNavigationItem(
                  mode: mode,
                  icon: icon,
                  label: label,
                ),
              ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'New note',
              child: Material(
                color: _accentColor,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _addNote,
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.add_rounded,
                      size: 23,
                      color: Color(0xFF10211D),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileNavigationItem({
    required ViewMode mode,
    required IconData icon,
    required String label,
  }) {
    final isSelected = activeMode == mode;
    final foreground = isSelected
        ? _accentColor
        : (widget.isDarkMode
            ? Colors.white.withValues(alpha: 0.56)
            : const Color(0xFF17231F).withValues(alpha: 0.56));
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => setState(() => activeMode = mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isSelected
                  ? _accentColor.withValues(alpha: 0.11)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 19),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _navigationButtonStyle(bool selected) {
    return IconButton.styleFrom(
      backgroundColor:
          selected ? _accentColor.withValues(alpha: 0.11) : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      fixedSize: const Size(42, 42),
    );
  }

  Widget _buildCanvasView() {
    final canvasBg =
        widget.isDarkMode ? const Color(0xFF101211) : const Color(0xFFF1F4F1);
    final accentColor = _accentColor;
    final notesById = {for (final note in notes) note.id: note};

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(500),
      minScale: 0.2,
      maxScale: 2.5,
      child: Container(
        width: 2500,
        height: 2500,
        decoration: BoxDecoration(
          color: canvasBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _accentColor.withValues(alpha: 0.18),
            width: 1.0,
          ),
        ),
        child: Stack(
          children: [
            CustomPaint(
              painter: DotGridPainter(
                color: widget.isDarkMode
                    ? Colors.white.withValues(alpha: 0.035)
                    : const Color(0xFF64766E).withValues(alpha: 0.12),
              ),
              child: Stack(
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: const Size(2500, 2500),
                      painter: ConnectionPainter(
                        notes: notes,
                        connections: visibleConnections,
                        fallbackLineColor: accentColor,
                        isDarkMode: widget.isDarkMode,
                        repaint: canvasRepaintNotifier,
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: canvasRepaintNotifier,
                    builder: (context, _) {
                      return Stack(
                        children: visibleConnections.map((conn) {
                          final fromNote = notesById[conn.fromId];
                          final toNote = notesById[conn.toId];
                          if (fromNote == null || toNote == null) {
                            return const SizedBox.shrink();
                          }

                          final start =
                              fromNote.position + const ui.Offset(140, 50);
                          final end =
                              toNote.position + const ui.Offset(140, 50);
                          final mid = ui.Offset(
                            (start.dx + end.dx) / 2,
                            (start.dy + end.dy) / 2,
                          );

                          return Positioned(
                            left: mid.dx - 14,
                            top: mid.dy - 14,
                            child: HoverConnectionButton(
                              onDelete: () => _deleteConnection(conn),
                              isDarkMode: widget.isDarkMode,
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  ...notes.asMap().entries.map((entry) {
                    final index = entry.key;
                    final note = entry.value;

                    return ValueListenableBuilder<Offset>(
                      valueListenable: note.positionNotifier,
                      builder: (context, pos, child) {
                        return Positioned(
                          left: pos.dx,
                          top: pos.dy,
                          child: child!,
                        );
                      },
                      child: RepaintBoundary(
                        child: CanvasNoteCard(
                          key: ValueKey(note.id),
                          note: note,
                          index: index,
                          isDarkMode: widget.isDarkMode,
                          isConnectingSource: connectingFromId == note.id,
                          cardColor: _getNoteColor(note.colorValue),
                          boards: boards,
                          onMoveToBoard: (boardId) =>
                              _moveNoteToBoard(note, boardId),
                          onToggleLock: () => _toggleNoteLock(note),
                          onChangeColor: (c) => _changeNoteColor(note, c),
                          onDeleteNote: () => _deleteNote(index),
                          onConnect: _handleRightClickConnect,
                          onSaved: () {
                            _recalculateMetrics();
                            setState(() {});
                          },
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    if (notes.isEmpty) {
      final boardName =
          boards.firstWhere((board) => board.id == activeBoardId).name;
      return Center(
        child: Padding(
          padding: EdgeInsets.only(
            left: isCompact ? 20 : 78,
            right: 20,
            bottom: isCompact ? 88 : 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 38,
                color: _accentColor.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 12),
              Text(
                '$boardName is ready for ideas',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create a note here, or switch to another board above.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _addNote,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a note'),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        left: isCompact ? 12 : 90,
        right: isCompact ? 12 : 32,
        top: 88,
        bottom: isCompact ? 100 : 24,
      ),
      child: ListView.builder(
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return ListNoteCard(
            key: ValueKey(note.id),
            note: note,
            isDarkMode: widget.isDarkMode,
            cardColor: _getNoteColor(note.colorValue),
            onDelete: () => _deleteNote(index),
            onToggleLock: () => _toggleNoteLock(note),
            boards: boards,
            onMoveToBoard: (boardId) => _moveNoteToBoard(note, boardId),
            onPersist: DBHelper.updateNote,
            onSaved: () {
              _recalculateMetrics();
              setState(() {});
            },
          );
        },
      ),
    );
  }

  Widget _buildDashboardView() {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final textColor =
        widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final cardBg = _surfaceColor;
    final border = Border.all(color: _hairlineColor);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalInset = constraints.maxWidth < 600 ? 32.0 : 122.0;
        final contentWidth = (constraints.maxWidth - horizontalInset)
            .clamp(1.0, double.infinity);
        final columns = contentWidth >= 1160
            ? 5
            : contentWidth >= 940
                ? 4
                : contentWidth >= 560
                    ? 2
                    : 1;
        final statCardWidth = (contentWidth - (16 * (columns - 1))) / columns;
        final showSideBySide = contentWidth >= 820;

        final recentNotes = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: border,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent canvas notes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 14),
              if (notes.isEmpty)
                Text(
                  'Your canvas is ready for its first idea.',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6)),
                )
              else
                ...notes.take(5).map((note) {
                  final displayContent = note.content.trim();
                  final hasContent = displayContent.isNotEmpty &&
                      displayContent != 'Click to add content...';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: _getNoteColor(note.colorValue),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                hasContent
                                    ? displayContent
                                    : 'No text body yet',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor.withValues(
                                      alpha: hasContent ? 0.62 : 0.38),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Open canvas',
                          icon: Icon(
                            Icons.arrow_outward_rounded,
                            size: 18,
                            color: _accentColor,
                          ),
                          onPressed: () =>
                              setState(() => activeMode = ViewMode.canvas),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );

        final quickActions = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: border,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick actions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: () {
                    _addNote();
                    setState(() => activeMode = ViewMode.canvas);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create a note'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: textColor.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => setState(() => activeMode = ViewMode.canvas),
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('Explore canvas'),
                ),
              ),
            ],
          ),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: isCompact ? 16 : 90,
            right: isCompact ? 16 : 32,
            top: 94,
            bottom: isCompact ? 112 : 40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR WORKSPACE',
                style: TextStyle(
                  color: _accentColor.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Workspace overview',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A clear view of the ideas taking shape on your canvas.',
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.62), fontSize: 14),
              ),
              const SizedBox(height: 24),
              _buildDailyHabitCard(
                cardBg: cardBg,
                border: border,
                textColor: textColor,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: statCardWidth,
                    child: _buildStatCard(
                      'Total notes',
                      notes.length.toString(),
                      Icons.sticky_note_2_outlined,
                      cardBg,
                      border,
                      textColor,
                      const Color(0xFF49B9A4),
                    ),
                  ),
                  SizedBox(
                    width: statCardWidth,
                    child: _buildStatCard(
                      'Connected notes',
                      cachedConnectedNoteIds.length.toString(),
                      Icons.hub_outlined,
                      cardBg,
                      border,
                      textColor,
                      const Color(0xFF8D83E8),
                    ),
                  ),
                  SizedBox(
                    width: statCardWidth,
                    child: _buildStatCard(
                      'Connections',
                      visibleConnections.length.toString(),
                      Icons.timeline_rounded,
                      cardBg,
                      border,
                      textColor,
                      const Color(0xFFE18B73),
                    ),
                  ),
                  SizedBox(
                    width: statCardWidth,
                    child: _buildStatCard(
                      'Words',
                      cachedTotalWords.toString(),
                      Icons.short_text_rounded,
                      cardBg,
                      border,
                      textColor,
                      const Color(0xFFD5A94F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (showSideBySide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: recentNotes),
                    const SizedBox(width: 18),
                    Expanded(flex: 2, child: quickActions),
                  ],
                )
              else ...[
                recentNotes,
                const SizedBox(height: 16),
                quickActions,
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color bg,
      BoxBorder border, Color textColor, Color accentColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: widget.isDarkMode ? 0.09 : 0.075),
            bg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.18),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, color: textColor.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyHabitCard({
    required Color cardBg,
    required BoxBorder border,
    required Color textColor,
  }) {
    final streak = currentNoteStreak;
    final accentColor = boards.isEmpty
        ? _accentColor
        : Color(
            boards.firstWhere((board) => board.id == activeBoardId).colorValue,
          );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cardBg,
            accentColor.withValues(alpha: widget.isDarkMode ? 0.14 : 0.1),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: border,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F43).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFFF9F43),
                  size: 25,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      streak == 1 ? '1 day in a row' : '$streak days in a row',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      streak > 0
                          ? 'Your daily note streak is alive. Keep the spark going.'
                          : 'Create a note today to start a streak.',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (streak > 0)
                Text(
                  '$streak',
                  style: const TextStyle(
                    color: Color(0xFFFF9F43),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          if (isMobilePlatform) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1,
                color: textColor.withValues(alpha: 0.1),
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: textColor.withValues(alpha: 0.72),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily nudge',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        dailyReminderEnabled
                            ? 'Every day at ${MaterialLocalizations.of(context).formatTimeOfDay(dailyReminderTime)}'
                            : 'A gentle reminder to add to your streak',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.58),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (dailyReminderEnabled)
                  TextButton(
                    onPressed: _mobileFeaturesReady
                        ? () => _setDailyReminder(true)
                        : null,
                    child: const Text('Time'),
                  ),
                Switch.adaptive(
                  value: dailyReminderEnabled,
                  onChanged: _mobileFeaturesReady ? _setDailyReminder : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ScreenSwitcher extends StatelessWidget {
  final Object screenKey;
  final Widget child;

  const ScreenSwitcher({
    super.key,
    required this.screenKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(animation);
        final scale = Tween<double>(begin: 0.985, end: 1).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(screenKey),
        child: child,
      ),
    );
  }
}

class BoardEditorDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final int initialColorValue;
  final String actionLabel;

  const BoardEditorDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.initialColorValue,
    required this.actionLabel,
  });

  @override
  State<BoardEditorDialog> createState() => _BoardEditorDialogState();
}

class _BoardEditorDialogState extends State<BoardEditorDialog> {
  late final TextEditingController _nameController;
  late int _selectedColorValue;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _selectedColorValue = widget.initialColorValue;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      BoardDraft(name: name, colorValue: _selectedColorValue),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Board name',
                hintText: 'e.g. Studio projects',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Text(
              'BOARD COLOR',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _boardPalette.map((color) {
                final colorValue = color.toARGB32();
                final selected = _selectedColorValue == colorValue;
                return Tooltip(
                  message: _boardColorName(color),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () =>
                        setState(() => _selectedColorValue = colorValue),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Color(0xFF101318),
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

String _boardColorName(Color color) {
  if (color == _boardPalette[0]) return 'Cyan';
  if (color == _boardPalette[1]) return 'Violet';
  if (color == _boardPalette[2]) return 'Rose';
  if (color == _boardPalette[3]) return 'Mint';
  if (color == _boardPalette[4]) return 'Amber';
  return 'Blue';
}

class ListNoteCard extends StatefulWidget {
  final Note note;
  final bool isDarkMode;
  final Color cardColor;
  final List<Board> boards;
  final VoidCallback onDelete;
  final Future<void> Function() onToggleLock;
  final ValueChanged<String> onMoveToBoard;
  final Future<void> Function(Note) onPersist;
  final VoidCallback onSaved;

  const ListNoteCard({
    super.key,
    required this.note,
    required this.isDarkMode,
    required this.cardColor,
    required this.boards,
    required this.onDelete,
    required this.onToggleLock,
    required this.onMoveToBoard,
    required this.onPersist,
    required this.onSaved,
  });

  @override
  State<ListNoteCard> createState() => _ListNoteCardState();
}

class BoardMoveButton extends StatelessWidget {
  final List<Board> boards;
  final String currentBoardId;
  final bool isLocked;
  final ValueChanged<String> onMove;
  final Color foregroundColor;

  const BoardMoveButton({
    super.key,
    required this.boards,
    required this.currentBoardId,
    required this.isLocked,
    required this.onMove,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final otherBoards =
        boards.where((board) => board.id != currentBoardId).toList();
    return PopupMenuButton<String>(
      enabled: otherBoards.isNotEmpty && !isLocked,
      tooltip: isLocked
          ? 'Unlock note to move it to another board'
          : 'Move note to another board',
      icon: Icon(
        Icons.drive_file_move_outline,
        color: otherBoards.isEmpty || isLocked
            ? foregroundColor.withValues(alpha: 0.25)
            : foregroundColor,
        size: 20,
      ),
      onSelected: onMove,
      itemBuilder: (context) => otherBoards
          .map(
            (board) => PopupMenuItem<String>(
              value: board.id,
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: Color(board.colorValue),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(board.name)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ListNoteCardState extends State<ListNoteCard> {
  late final TextEditingController _titleController;
  late final QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  bool _isExpanded = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _quillController = _createQuillController();
  }

  QuillController _createQuillController() {
    if (widget.note.documentBody.isNotEmpty) {
      try {
        final documentJson = jsonDecode(widget.note.documentBody);
        return QuillController(
          document: Document.fromJson(documentJson),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } on FormatException {
        // Fall back to the plain-text preview if the stored JSON is malformed.
      }
    }

    final text = widget.note.content.trim();
    final content =
        text.isEmpty || text == 'Click to add content...' ? '\n' : '$text\n';
    return QuillController(
      document: Document.fromJson([
        {'insert': content}
      ]),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    setState(() => _isSaving = true);
    final plainText = _quillController.document.toPlainText().trim();
    widget.note
      ..title = _titleController.text.trim().isEmpty
          ? 'Untitled Note'
          : _titleController.text.trim()
      ..content = plainText == 'Click to add content...' ? '' : plainText
      ..documentBody =
          plainText.isEmpty || plainText == 'Click to add content...'
              ? ''
              : jsonEncode(_quillController.document.toDelta().toJson());

    try {
      await widget.onPersist(widget.note);
      if (!mounted) return false;
      setState(() {
        _isSaving = false;
        _isExpanded = false;
      });
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note saved'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save note: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  Future<void> _toggleLock() async {
    if (_isExpanded && !await _save()) return;
    await widget.onToggleLock();
    if (mounted) {
      setState(() {
        if (widget.note.isLocked) _isExpanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final preview = widget.note.content.trim();
    final hasContent =
        preview.isNotEmpty && preview != 'Click to add content...';

    return Card(
      color: widget.cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey(widget.note.isLocked),
        enabled: !widget.note.isLocked,
        initiallyExpanded: false,
        onExpansionChanged: (expanded) =>
            setState(() => _isExpanded = expanded),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          widget.note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            hasContent ? preview : 'Click to add content...',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor.withValues(alpha: hasContent ? 0.6 : 0.4),
              fontStyle: hasContent ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BoardMoveButton(
              boards: widget.boards,
              currentBoardId: widget.note.boardId,
              isLocked: widget.note.isLocked,
              onMove: widget.onMoveToBoard,
              foregroundColor: textColor.withValues(alpha: 0.6),
            ),
            IconButton(
              tooltip: widget.note.isLocked ? 'Unlock note' : 'Lock note',
              icon: Icon(
                widget.note.isLocked
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                color: widget.note.isLocked
                    ? Colors.amberAccent
                    : textColor.withValues(alpha: 0.42),
              ),
              onPressed: _toggleLock,
            ),
            IconButton(
              tooltip: 'Delete note',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: textColor.withValues(alpha: 0.42),
              ),
              onPressed: widget.onDelete,
            ),
            AnimatedRotation(
              turns: _isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.keyboard_arrow_down_rounded, color: textColor),
            ),
          ],
        ),
        children: [
          Divider(color: textColor.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            enabled: !_isSaving,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: QuillSimpleToolbar(
              controller: _quillController,
              config: const QuillSimpleToolbarConfig(
                showFontFamily: false,
                showFontSize: false,
                showBoldButton: true,
                showItalicButton: true,
                showUnderLineButton: true,
                showStrikeThrough: false,
                showInlineCode: false,
                showColorButton: false,
                showBackgroundColorButton: false,
                showClearFormat: false,
                showAlignmentButtons: false,
                showHeaderStyle: false,
                showListNumbers: false,
                showListBullets: true,
                showListCheck: false,
                showCodeBlock: false,
                showQuote: false,
                showIndent: false,
                showLink: false,
                showUndo: true,
                showRedo: true,
                showDirection: false,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 180,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? Colors.black.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: textColor.withValues(alpha: 0.1)),
            ),
            child: QuillEditor(
              focusNode: _editorFocusNode,
              scrollController: _editorScrollController,
              controller: _quillController,
              config: const QuillEditorConfig(
                placeholder: 'Write something...',
                padding: EdgeInsets.all(4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isSaving
                  ? null
                  : () async {
                      await _save();
                    },
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Canvas Note Card Widget ---

class CanvasNoteCard extends StatefulWidget {
  final Note note;
  final int index;
  final bool isDarkMode;
  final bool isConnectingSource;
  final Color cardColor;
  final List<Board> boards;
  final ValueChanged<String> onMoveToBoard;
  final VoidCallback onToggleLock;
  final Function(Color) onChangeColor;
  final VoidCallback onDeleteNote;
  final Function(String) onConnect;
  final VoidCallback onSaved;

  const CanvasNoteCard({
    super.key,
    required this.note,
    required this.index,
    required this.isDarkMode,
    required this.isConnectingSource,
    required this.cardColor,
    required this.boards,
    required this.onMoveToBoard,
    required this.onToggleLock,
    required this.onChangeColor,
    required this.onDeleteNote,
    required this.onConnect,
    required this.onSaved,
  });

  @override
  State<CanvasNoteCard> createState() => _CanvasNoteCardState();
}

class _CanvasNoteCardState extends State<CanvasNoteCard> {
  bool isEditing = false;
  bool isHovered = false;
  bool isSaving = false;
  late TextEditingController _titleController;
  late QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _initQuillController();
  }

  void _initQuillController() {
    final rawContent = widget.note.content.trim();
    if (rawContent == 'Click to add content...') {
      widget.note.content = '';
    }

    if (widget.note.documentBody.isNotEmpty) {
      try {
        final docJson = jsonDecode(widget.note.documentBody);
        _quillController = QuillController(
          document: Document.fromJson(docJson),
          selection: const TextSelection.collapsed(offset: 0),
        );
        return;
      } catch (_) {}
    }
    _quillController = _fallbackQuillController();
  }

  QuillController _fallbackQuillController() {
    final text = widget.note.content.trim();
    final isEmpty = text.isEmpty || text == 'Click to add content...';

    final docDelta = isEmpty
        ? [
            {'insert': '\n'}
          ]
        : [
            {'insert': '$text\n'}
          ];

    return QuillController(
      document: Document.fromJson(docDelta),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (isSaving) return;
    final previousTitle = widget.note.title;
    final previousContent = widget.note.content;
    final previousDocumentBody = widget.note.documentBody;
    final textTitle = _titleController.text.trim();
    final plainText = _quillController.document.toPlainText().trim();
    widget.note
      ..title = textTitle.isEmpty ? 'Untitled Note' : textTitle
      ..content = plainText.isEmpty || plainText == 'Click to add content...'
          ? ''
          : plainText
      ..documentBody =
          plainText.isEmpty || plainText == 'Click to add content...'
              ? ''
              : jsonEncode(_quillController.document.toDelta().toJson());
    setState(() => isSaving = true);
    try {
      await DBHelper.updateNote(widget.note);
      if (!mounted) return;
      setState(() {
        isSaving = false;
        isEditing = false;
      });
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      widget.note
        ..title = previousTitle
        ..content = previousContent
        ..documentBody = previousDocumentBody;
      _titleController.text = previousTitle;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save note: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor =
        widget.isDarkMode ? const Color(0xFF82E0C5) : const Color(0xFF168F7D);
    final textColor =
        widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = widget.isDarkMode
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF475569);

    final cardBorderColor = widget.isConnectingSource
        ? Colors.amberAccent
        : (widget.isDarkMode
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.12));
    final palette = widget.isDarkMode ? darkNoteColors : lightNoteColors;

    final displayContent = widget.note.content.trim();
    final hasContent = displayContent.isNotEmpty &&
        displayContent != 'Click to add content...';

    return MouseRegion(
      cursor: widget.note.isLocked
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: AnimatedScale(
        scale: isHovered ? 1.025 : 1,
        alignment: Alignment.topLeft,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.94, end: 1),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: child,
            );
          },
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onSecondaryTap: () => widget.onConnect(widget.note.id),
              onLongPress: () => widget.onConnect(widget.note.id),
              onPanUpdate: widget.note.isLocked
                  ? null
                  : (details) {
                      widget.note.position += details.delta;
                    },
              onPanEnd: widget.note.isLocked
                  ? null
                  : (_) {
                      const double gridSize = 20.0;

                      final snappedX =
                          (widget.note.position.dx / gridSize).round() *
                              gridSize;
                      final snappedY =
                          (widget.note.position.dy / gridSize).round() *
                              gridSize;

                      widget.note.position = ui.Offset(snappedX, snappedY);
                      DBHelper.updateNote(widget.note);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 280,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cardBorderColor,
                    width: widget.isConnectingSource ? 2.0 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: widget.isDarkMode
                            ? (isHovered ? 0.48 : 0.34)
                            : 0.08,
                      ),
                      blurRadius: isHovered ? 22 : 14,
                      offset: Offset(0, isHovered ? 8 : 4),
                    )
                  ],
                ),
                child: isEditing
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _titleController,
                            enabled: !isSaving,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                fontSize: 15),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Untitled Note',
                              hintStyle: TextStyle(
                                  color: textColor.withValues(alpha: 0.3)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: QuillSimpleToolbar(
                              controller: _quillController,
                              config: const QuillSimpleToolbarConfig(
                                showFontFamily: false,
                                showFontSize: false,
                                showBoldButton: true,
                                showItalicButton: true,
                                showUnderLineButton: true,
                                showStrikeThrough: false,
                                showInlineCode: false,
                                showColorButton: false,
                                showBackgroundColorButton: false,
                                showClearFormat: false,
                                showAlignmentButtons: false,
                                showHeaderStyle: false,
                                showListNumbers: false,
                                showListBullets: true,
                                showListCheck: false,
                                showCodeBlock: false,
                                showQuote: false,
                                showIndent: false,
                                showLink: false,
                                showUndo: false,
                                showRedo: false,
                                showDirection: false,
                                showSearchButton: false,
                                showSubscript: false,
                                showSuperscript: false,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 120,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: widget.isDarkMode
                                  ? Colors.black12
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: QuillEditor(
                              focusNode: _editorFocusNode,
                              scrollController: _editorScrollController,
                              controller: _quillController,
                              config: const QuillEditorConfig(
                                placeholder: 'Click to add content...',
                                padding: EdgeInsets.all(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: palette.map((color) {
                              final isSelected = widget.isDarkMode
                                  ? widget.note.colorValue == color.toARGB32()
                                  : darkNoteColors[palette.indexOf(color)]
                                          .toARGB32() ==
                                      widget.note.colorValue;

                              return GestureDetector(
                                onTap: () => widget.onChangeColor(color),
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? accentColor
                                          : Colors.black12,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      await _save();
                                    },
                              child: Text(
                                isSaving ? 'Saving...' : 'Save',
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : InkWell(
                        onTap: widget.note.isLocked
                            ? null
                            : () => setState(() => isEditing = true),
                        borderRadius: BorderRadius.circular(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      if (widget.note.isLocked) ...[
                                        const Icon(
                                          Icons.lock_rounded,
                                          size: 14,
                                          color: Colors.amberAccent,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Expanded(
                                        child: Text(
                                          widget.note.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                            fontSize: 14,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                BoardMoveButton(
                                  boards: widget.boards,
                                  currentBoardId: widget.note.boardId,
                                  isLocked: widget.note.isLocked,
                                  onMove: widget.onMoveToBoard,
                                  foregroundColor:
                                      textColor.withValues(alpha: 0.45),
                                ),
                                IconButton(
                                  tooltip: widget.note.isLocked
                                      ? 'Unlock note'
                                      : 'Lock note',
                                  icon: Icon(
                                    widget.note.isLocked
                                        ? Icons.lock_rounded
                                        : Icons.lock_open_rounded,
                                    color: widget.note.isLocked
                                        ? Colors.amberAccent
                                        : textColor.withValues(alpha: 0.45),
                                    size: 18,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: widget.onToggleLock,
                                ),
                                IconButton(
                                  tooltip: 'Delete note',
                                  onPressed: widget.onDeleteNote,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: textColor.withValues(alpha: 0.3),
                                    size: 16,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hasContent
                                  ? displayContent
                                  : 'Click to add content...',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: hasContent
                                    ? subTextColor
                                    : subTextColor.withValues(alpha: 0.4),
                                fontSize: 13,
                                height: 1.4,
                                fontStyle: hasContent
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Connection Delete Button Widget ---

class HoverConnectionButton extends StatefulWidget {
  final VoidCallback onDelete;
  final bool isDarkMode;

  const HoverConnectionButton({
    super.key,
    required this.onDelete,
    required this.isDarkMode,
  });

  @override
  State<HoverConnectionButton> createState() => _HoverConnectionButtonState();
}

class _HoverConnectionButtonState extends State<HoverConnectionButton> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: widget.onDelete,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isHovered
                ? Colors.redAccent
                : (widget.isDarkMode ? const Color(0xFF18181B) : Colors.white),
            shape: BoxShape.circle,
            border: Border.all(
              color: isHovered
                  ? Colors.red
                  : (widget.isDarkMode ? Colors.white24 : Colors.black26),
              width: 1.5,
            ),
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: isHovered ? 16 : 12,
              color: isHovered
                  ? Colors.white
                  : (widget.isDarkMode ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Connection Painter ---

class ConnectionPainter extends CustomPainter {
  final List<Note> notes;
  final List<Connection> connections;
  final Color fallbackLineColor;
  final bool isDarkMode;
  final int _notesFingerprint;
  final int _connectionsFingerprint;

  ConnectionPainter({
    required this.notes,
    required this.connections,
    required this.fallbackLineColor,
    required this.isDarkMode,
    super.repaint,
  })  : _notesFingerprint = Object.hashAll(
          notes.map((note) => Object.hash(note.id, note.colorValue)),
        ),
        _connectionsFingerprint = Object.hashAll(
          connections.map(
              (connection) => Object.hash(connection.fromId, connection.toId)),
        );

  ui.Offset _getCardCenter(Note note) {
    return note.position + const ui.Offset(140, 50);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final notesById = {for (final note in notes) note.id: note};
    for (var conn in connections) {
      final fromNote = notesById[conn.fromId];
      final toNote = notesById[conn.toId];
      if (fromNote == null || toNote == null) continue;

      final start = _getCardCenter(fromNote);
      final end = _getCardCenter(toNote);

      final strokeColor = isDarkMode ? fallbackLineColor : Colors.indigoAccent;

      final paint = Paint()
        ..color = strokeColor.withValues(alpha: 0.8)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.fallbackLineColor != fallbackLineColor ||
        oldDelegate._notesFingerprint != _notesFingerprint ||
        oldDelegate._connectionsFingerprint != _connectionsFingerprint;
  }
}

class DotGridPainter extends CustomPainter {
  final Color color;

  const DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 28.0;
    const radius = 1.15;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final dots = <ui.Offset>[];

    for (var x = spacing / 2; x < size.width; x += spacing) {
      for (var y = spacing / 2; y < size.height; y += spacing) {
        dots.add(ui.Offset(x, y));
      }
    }

    canvas.drawPoints(
      ui.PointMode.points,
      dots,
      paint..strokeWidth = radius * 2,
    );
  }

  @override
  bool shouldRepaint(covariant DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
