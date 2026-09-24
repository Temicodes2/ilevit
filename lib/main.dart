import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// --- Note & Connection Models ---

enum ViewMode { canvas, list, dashboard }

class Note {
  final String id;
  String title;
  String content;
  String documentBody;
  late final ValueNotifier<Offset> positionNotifier;
  int colorValue;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.documentBody = '',
    required Offset position,
    this.colorValue = 0xFF1E1E22,
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
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            title TEXT,
            content TEXT,
            documentBody TEXT,
            dx REAL,
            dy REAL,
            colorValue INTEGER
          )
        ''');
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
          await db.execute('ALTER TABLE notes ADD COLUMN documentBody TEXT DEFAULT ""');
        }
      },
    );
  }

  static Future<List<Note>> fetchNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes');
    return maps.map((map) {
      final rawContent = map['content'] as String;
      final cleanContent = rawContent == 'Click to add content...' ? '' : rawContent;
      return Note(
        id: map['id'] as String,
        title: map['title'] as String,
        content: cleanContent,
        documentBody: (map['documentBody'] as String?) ?? '',
        position: ui.Offset(
          (map['dx'] as num).toDouble(),
          (map['dy'] as num).toDouble(),
        ),
        colorValue: (map['colorValue'] as int?) ?? 0xFF1E1E22,
      );
    }).toList();
  }

  static Future<void> insertNote(Note note) async {
    final db = await database;
    await db.insert(
      'notes',
      {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'documentBody': note.documentBody,
        'dx': note.position.dx,
        'dy': note.position.dy,
        'colorValue': note.colorValue,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update(
      'notes',
      {
        'title': note.title,
        'content': note.content,
        'documentBody': note.documentBody,
        'dx': note.position.dx,
        'dy': note.position.dy,
        'colorValue': note.colorValue,
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  static Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    await db.delete('connections', where: 'fromId = ? OR toId = ?', whereArgs: [id, id]);
  }

  static Future<List<Connection>> fetchConnections() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('connections');
    return maps.map((map) => Connection(map['fromId'] as String, map['toId'] as String)).toList();
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
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

class _ObsidianNoteAppState extends State<ObsidianNoteApp> {
  ViewMode activeMode = ViewMode.canvas;

  List<Note> notes = [];
  List<Connection> connections = [];

  int cachedTotalWords = 0;
  Set<String> cachedConnectedNoteIds = {};

  String? connectingFromId;

  final ChangeNotifier canvasRepaintNotifier = ChangeNotifier();

  @override
  void initState() {
    super.initState();
    _loadFromDatabase();
  }

  @override
  void dispose() {
    for (var note in notes) {
      note.dispose();
    }
    canvasRepaintNotifier.dispose();
    super.dispose();
  }

  void _recalculateMetrics() {
    cachedConnectedNoteIds = connections.expand((c) => [c.fromId, c.toId]).toSet();
    cachedTotalWords = notes.fold<int>(0, (sum, note) {
      final docText = note.content;
      return sum +
          note.title.split(' ').where((w) => w.isNotEmpty).length +
          docText.split(' ').where((w) => w.isNotEmpty).length;
    });
  }

  Future<void> _loadFromDatabase() async {
    final loadedNotes = await DBHelper.fetchNotes();
    final loadedConnections = await DBHelper.fetchConnections();

    if (loadedNotes.isEmpty) {
      final n1 = Note(
        id: '1',
        title: 'Main Architecture',
        content: 'Core project structure and specs.',
        documentBody: '',
        position: const ui.Offset(300, 300),
        colorValue: 0xFF1E293B,
      );
      final n2 = Note(
        id: '2',
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

      notes = [n1, n2];
      connections = [c1];
    } else {
      notes = loadedNotes;
      connections = loadedConnections;
    }

    _attachListeners();
    _recalculateMetrics();
    setState(() {});
  }

  void _attachListeners() {
    for (var note in notes) {
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
    final index = darkNoteColors.indexWhere((c) => c.value == storedColorValue);
    if (index != -1 && index < lightNoteColors.length) {
      return lightNoteColors[index];
    }
    return const Color(0xFFF1F5F9);
  }

  void _changeNoteColor(Note note, Color color) async {
    final darkValue = widget.isDarkMode
        ? color.value
        : darkNoteColors[lightNoteColors.indexOf(color)].value;

    setState(() {
      note.colorValue = darkValue;
    });
    await DBHelper.updateNote(note);
  }

  void _addNote() async {
    final newNote = Note(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Untitled Note',
      content: '',
      documentBody: '',
      position: const ui.Offset(400, 400),
      colorValue: darkNoteColors[0].value,
    );

    newNote.positionNotifier.addListener(_onNoteMoved);

    setState(() {
      notes.add(newNote);
    });

    _recalculateMetrics();
    await DBHelper.insertNote(newNote);
  }

  void _deleteNote(int index) async {
    final note = notes[index];
    note.positionNotifier.removeListener(_onNoteMoved);

    setState(() {
      notes.removeAt(index);
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
    return Scaffold(
      backgroundColor: widget.isDarkMode ? const Color(0xFF0F0F12) : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBodyView()),
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
    final barBg = widget.isDarkMode
        ? const Color(0xFF18181B).withOpacity(0.85)
        : Colors.white.withOpacity(0.9);
    final borderColor = widget.isDarkMode
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.08);
    final inactiveIconColor = widget.isDarkMode
        ? Colors.white.withOpacity(0.4)
        : Colors.black.withOpacity(0.4);

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
              color: Colors.black.withOpacity(widget.isDarkMode ? 0.3 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.bubble_chart_rounded,
                color: activeMode == ViewMode.canvas ? Colors.cyanAccent : inactiveIconColor,
                size: 20,
              ),
              onPressed: () => setState(() => activeMode = ViewMode.canvas),
              tooltip: 'Canvas View',
            ),
            const SizedBox(height: 4),
            IconButton(
              icon: Icon(
                Icons.view_list_rounded,
                color: activeMode == ViewMode.list ? Colors.cyanAccent : inactiveIconColor,
                size: 20,
              ),
              onPressed: () => setState(() => activeMode = ViewMode.list),
              tooltip: 'List View',
            ),
            const SizedBox(height: 4),
            IconButton(
              icon: Icon(
                Icons.dashboard_rounded,
                color: activeMode == ViewMode.dashboard ? Colors.cyanAccent : inactiveIconColor,
                size: 20,
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
                widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: widget.isDarkMode ? Colors.amberAccent : Colors.indigoAccent,
                size: 20,
              ),
              onPressed: widget.onToggleTheme,
              tooltip: widget.isDarkMode ? 'Light Mode' : 'Dark Mode',
            ),
            const SizedBox(height: 4),
            IconButton(
              icon: Icon(
                Icons.add_rounded,
                color: widget.isDarkMode ? Colors.white : Colors.black87,
                size: 22,
              ),
              onPressed: _addNote,
              tooltip: 'New Note',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasView() {
    final canvasBg = widget.isDarkMode ? const Color(0xFF0F0F12) : const Color(0xFFF1F5F9);
    const accentColor = Colors.cyanAccent;

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
            color: widget.isDarkMode ? Colors.cyanAccent.withOpacity(0.6) : Colors.indigo.withOpacity(0.6),
            width: 3.0,
          ),
        ),
        child: Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: const Size(2500, 2500),
                painter: ConnectionPainter(
                  notes: notes,
                  connections: connections,
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
                  children: connections.map((conn) {
                    final fromIndex = notes.indexWhere((n) => n.id == conn.fromId);
                    final toIndex = notes.indexWhere((n) => n.id == conn.toId);

                    if (fromIndex == -1 || toIndex == -1) {
                      return const SizedBox.shrink();
                    }

                    final fromNote = notes[fromIndex];
                    final toNote = notes[toIndex];

                    final start = fromNote.position + const ui.Offset(140, 50);
                    final end = toNote.position + const ui.Offset(140, 50);
                    final mid = ui.Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

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
                    note: note,
                    index: index,
                    isDarkMode: widget.isDarkMode,
                    isConnectingSource: connectingFromId == note.id,
                    cardColor: _getNoteColor(note.colorValue),
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
    );
  }

  Widget _buildListView() {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);

    return Padding(
      padding: const EdgeInsets.only(left: 90.0, right: 32.0, top: 32.0),
      child: ListView.builder(
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          final cardBg = _getNoteColor(note.colorValue);
          final displayContent = note.content.trim();
          final hasContent = displayContent.isNotEmpty && displayContent != 'Click to add content...';

          return Card(
            color: cardBg,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              onTap: () {
                setState(() => activeMode = ViewMode.canvas);
              },
              title: Text(
                note.title,
                style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
              ),
              subtitle: Text(
                hasContent ? displayContent : 'Click to add content...',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasContent ? textColor.withOpacity(0.6) : textColor.withOpacity(0.3),
                  fontStyle: hasContent ? FontStyle.normal : FontStyle.italic,
                ),
              ),
              trailing: IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: textColor.withOpacity(0.3)),
                onPressed: () => _deleteNote(index),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboardView() {
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final cardBg = widget.isDarkMode ? const Color(0xFF18181B) : Colors.white;
    final border = Border.all(
      color: widget.isDarkMode ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 90.0, right: 32.0, top: 32.0, bottom: 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Workspace Dashboard',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Analytics and deep insights into your visual canvas knowledge graph.',
            style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatCard('Total Notes', notes.length.toString(), Icons.notes_rounded, cardBg, border, textColor),
              const SizedBox(width: 16),
              _buildStatCard('Connected Notes', cachedConnectedNoteIds.length.toString(), Icons.hub_outlined, cardBg, border, textColor),
              const SizedBox(width: 16),
              _buildStatCard('Connections', connections.length.toString(), Icons.timeline_rounded, cardBg, border, textColor),
              const SizedBox(width: 16),
              _buildStatCard('Total Words', cachedTotalWords.toString(), Icons.short_text_rounded, cardBg, border, textColor),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: border),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recent Canvas Nodes', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 16)),
                      const SizedBox(height: 12),
                      ...notes.take(5).map((note) {
                        final displayContent = note.content.trim();
                        final hasContent = displayContent.isNotEmpty && displayContent != 'Click to add content...';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _getNoteColor(note.colorValue),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(note.title, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                                  Text(
                                    hasContent ? displayContent : 'No text body...',
                                    style: TextStyle(
                                      color: hasContent ? textColor.withOpacity(0.6) : textColor.withOpacity(0.3),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.map_rounded, size: 18, color: Colors.cyanAccent),
                                onPressed: () {
                                  setState(() => activeMode = ViewMode.canvas);
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: border),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        onPressed: () {
                          _addNote();
                          setState(() => activeMode = ViewMode.canvas);
                        },
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('Add Note on Canvas'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor.withOpacity(0.2)),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        onPressed: () => setState(() => activeMode = ViewMode.canvas),
                        icon: const Icon(Icons.map_rounded),
                        label: const Text('Return to Canvas View'),
                      ),
                    ],
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color bg, BoxBorder border, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: border),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.cyanAccent, size: 22),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.6))),
          ],
        ),
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

  void _save() {
    setState(() {
      final textTitle = _titleController.text.trim();
      widget.note.title = textTitle.isEmpty ? 'Untitled Note' : textTitle;

      final plainText = _quillController.document.toPlainText().trim();
      if (plainText.isEmpty || plainText == 'Click to add content...') {
        widget.note.content = '';
        widget.note.documentBody = '';
      } else {
        widget.note.content = plainText;
        widget.note.documentBody = jsonEncode(_quillController.document.toDelta().toJson());
      }

      isEditing = false;
    });
    DBHelper.updateNote(widget.note);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Colors.cyanAccent;
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = widget.isDarkMode ? Colors.white.withOpacity(0.6) : const Color(0xFF475569);

    final cardBorderColor = widget.isConnectingSource
        ? Colors.amberAccent
        : (widget.isDarkMode ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.12));
    final palette = widget.isDarkMode ? darkNoteColors : lightNoteColors;

    final displayContent = widget.note.content.trim();
    final hasContent = displayContent.isNotEmpty && displayContent != 'Click to add content...';

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onSecondaryTap: () => widget.onConnect(widget.note.id),
        onLongPress: () => widget.onConnect(widget.note.id),
        onPanUpdate: (details) {
          widget.note.position += details.delta;
        },
        onPanEnd: (_) {
          const double gridSize = 20.0;

          final snappedX = (widget.note.position.dx / gridSize).round() * gridSize;
          final snappedY = (widget.note.position.dy / gridSize).round() * gridSize;

          widget.note.position = ui.Offset(snappedX, snappedY);
          DBHelper.updateNote(widget.note);
        },
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cardBorderColor,
              width: widget.isConnectingSource ? 2.0 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(widget.isDarkMode ? 0.4 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
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
                      style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 15),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Untitled Note',
                        hintStyle: TextStyle(color: textColor.withOpacity(0.3)),
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
                        color: widget.isDarkMode ? Colors.black12 : Colors.white24,
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
                            ? widget.note.colorValue == color.value
                            : darkNoteColors[palette.indexOf(color)].value == widget.note.colorValue;

                        return GestureDetector(
                          onTap: () => widget.onChangeColor(color),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? accentColor : Colors.black12,
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
                        onPressed: _save,
                        child: const Text('Save', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                )
              : InkWell(
                  onTap: () => setState(() => isEditing = true),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
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
                          GestureDetector(
                            onTap: widget.onDeleteNote,
                            child: Icon(
                              Icons.close_rounded,
                              color: textColor.withOpacity(0.3),
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasContent ? displayContent : 'Click to add content...',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasContent ? subTextColor : subTextColor.withOpacity(0.4),
                          fontSize: 13,
                          height: 1.4,
                          fontStyle: hasContent ? FontStyle.normal : FontStyle.italic,
                        ),
                      ),
                    ],
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
                      color: Colors.redAccent.withOpacity(0.4),
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

  ConnectionPainter({
    required this.notes,
    required this.connections,
    required this.fallbackLineColor,
    required this.isDarkMode,
    Listenable? repaint,
  }) : super(repaint: repaint);

  ui.Offset _getCardCenter(Note note) {
    return note.position + const ui.Offset(140, 50);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var conn in connections) {
      final fromIndex = notes.indexWhere((n) => n.id == conn.fromId);
      final toIndex = notes.indexWhere((n) => n.id == conn.toId);

      if (fromIndex == -1 || toIndex == -1) continue;

      final fromNote = notes[fromIndex];
      final toNote = notes[toIndex];

      final start = _getCardCenter(fromNote);
      final end = _getCardCenter(toNote);

      final strokeColor = isDarkMode ? fallbackLineColor : Colors.indigoAccent;

      final paint = Paint()
        ..color = strokeColor.withOpacity(0.8)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) => true;
}