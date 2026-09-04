import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// --- Models ---

enum ViewMode { list, canvas }

class Note {
  final String id;
  String title;
  String content; // Short preview / abstract
  String documentBody; // Full long-form document content
  ui.Offset position;
  int colorValue;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.documentBody = '',
    required this.position,
    this.colorValue = 0xFF121212,
  });
}

class Connection {
  final String fromId;
  final String toId;

  Connection(this.fromId, this.toId);
}

const double gridSize = 20.0;

final List<Color> noteColors = [
  const Color(0xFF121212),
  const Color(0xFF1E3A8A),
  const Color(0xFF065F46),
  const Color(0xFF831843),
  const Color(0xFF7C2D12),
  const Color(0xFF4C1D95),
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
      return Note(
        id: map['id'] as String,
        title: map['title'] as String,
        content: map['content'] as String,
        documentBody: (map['documentBody'] as String?) ?? '',
        position: ui.Offset(
          (map['dx'] as num).toDouble(),
          (map['dy'] as num).toDouble(),
        ),
        colorValue: (map['colorValue'] as int?) ?? 0xFF121212,
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
}

// --- App Entry Point ---

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // FFI initialization is only needed for Desktop (Windows/Mac/Linux)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      textTheme: GoogleFonts.dmSansTextTheme(),
    ),
    home: const ObsidianNoteApp(),
  ));
}

class ObsidianNoteApp extends StatefulWidget {
  const ObsidianNoteApp({super.key});

  @override
  State<ObsidianNoteApp> createState() => _ObsidianNoteAppState();
}

class _ObsidianNoteAppState extends State<ObsidianNoteApp> {
  ViewMode activeMode = ViewMode.canvas;
  bool isDarkMode = true;

  List<Note> notes = [];
  List<Connection> connections = [];

  int? editingIndex;
  String? connectingFromId;

  late TextEditingController titleController;
  late TextEditingController contentController;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController();
    contentController = TextEditingController();
    _loadFromDatabase();
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    super.dispose();
  }

  Future<void> _loadFromDatabase() async {
    final loadedNotes = await DBHelper.fetchNotes();
    final loadedConnections = await DBHelper.fetchConnections();

    if (loadedNotes.isEmpty) {
      final n1 = Note(
        id: '1',
        title: 'Main Architecture',
        content: 'Core project structure and specs.',
        documentBody: '## System Design\n\nThis is a long-form document embedded within the node.\n\nYou can write detailed project documentation, guides, or essays here.',
        position: const ui.Offset(300, 300),
        colorValue: 0xFF1E3A8A,
      );
      final n2 = Note(
        id: '2',
        title: 'Database Schema',
        content: 'Local SQLite tables.',
        documentBody: '### SQLite Configuration\n- Notes table\n- Connections table',
        position: const ui.Offset(640, 200),
        colorValue: 0xFF065F46,
      );
      final c1 = Connection('1', '2');

      await DBHelper.insertNote(n1);
      await DBHelper.insertNote(n2);
      await DBHelper.insertConnection(c1);

      setState(() {
        notes = [n1, n2];
        connections = [c1];
      });
    } else {
      setState(() {
        notes = loadedNotes;
        connections = loadedConnections;
      });
    }
  }

  void _startEditing(int index) {
    setState(() {
      editingIndex = index;
      titleController.text = notes[index].title;
      contentController.text = notes[index].content;
    });
  }

  void _saveEditing(int index) async {
    final note = notes[index];
    setState(() {
      note.title = titleController.text;
      note.content = contentController.text;
      editingIndex = null;
    });

    await DBHelper.updateNote(note);
  }

  void _changeNoteColor(Note note, Color color) async {
    setState(() {
      note.colorValue = color.value;
    });
    await DBHelper.updateNote(note);
  }

  void _openDocumentEditor(Note note) {
    final docController = TextEditingController(text: note.documentBody);
    final docTitleController = TextEditingController(text: note.title);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Document Workspace',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Scaffold(
          backgroundColor: isDarkMode ? const Color(0xFF0F0F10) : const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: isDarkMode ? const Color(0xFF18181B) : Colors.white,
            elevation: 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: isDarkMode ? Colors.white : Colors.black),
              onPressed: () {
                note.title = docTitleController.text;
                note.documentBody = docController.text;
                DBHelper.updateNote(note);
                setState(() {});
                Navigator.pop(context);
              },
            ),
            title: TextField(
              controller: docTitleController,
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Document Title...',
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.check, color: Colors.cyanAccent),
                label: const Text('Save Document', style: TextStyle(color: Colors.cyanAccent)),
                onPressed: () {
                  note.title = docTitleController.text;
                  note.documentBody = docController.text;
                  DBHelper.updateNote(note);
                  setState(() {});
                  Navigator.pop(context);
                },
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: TextField(
                controller: docController,
                maxLines: null,
                expands: true,
                style: TextStyle(
                  color: isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black87,
                  fontSize: 16,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type your long-form document here...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.white30 : Colors.black.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _addNote() async {
    final newNote = Note(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Idea',
      content: 'Short card overview...',
      documentBody: '',
      position: const ui.Offset(400, 400),
      colorValue: 0xFF121212,
    );

    setState(() {
      notes.add(newNote);
    });

    await DBHelper.insertNote(newNote);
  }

  void _deleteNote(int index) async {
    final noteId = notes[index].id;
    setState(() {
      notes.removeAt(index);
      connections.removeWhere((c) => c.fromId == noteId || c.toId == noteId);
      if (editingIndex == index) editingIndex = null;
    });

    await DBHelper.deleteNote(noteId);
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

        await DBHelper.insertConnection(newConnection);
      } else {
        setState(() => connectingFromId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isDarkMode ? const Color(0xFF000000) : const Color(0xFFF1F5F9);
    final sidebarColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final primaryIconColor = isDarkMode ? Colors.cyanAccent : const Color(0xFF0284C7);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: activeMode == ViewMode.canvas
                ? _buildCanvasView()
                : SafeArea(child: _buildListView()),
          ),
          Positioned(
            left: 20,
            top: 40,
            bottom: 40,
            child: Container(
              width: 60,
              decoration: BoxDecoration(
                color: sidebarColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.black12,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Icon(
                    activeMode == ViewMode.canvas
                        ? Icons.hub_rounded
                        : Icons.view_list_rounded,
                    color: primaryIconColor,
                  ),
                  const SizedBox(height: 8),
                  RotatedBox(
                    quarterTurns: 1,
                    child: Switch(
                      value: activeMode == ViewMode.list,
                      activeColor: primaryIconColor,
                      onChanged: (bool isList) {
                        setState(() {
                          activeMode = isList ? ViewMode.list : ViewMode.canvas;
                        });
                      },
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.add_rounded, color: primaryIconColor, size: 28),
                    onPressed: _addNote,
                    tooltip: 'Add Note',
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasView() {
    final canvasBg = isDarkMode ? const Color(0xFF000000) : const Color(0xFFF8FAFC);
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtextColor = isDarkMode ? Colors.white70 : Colors.black54;
    final accentColor = isDarkMode ? Colors.cyanAccent : const Color(0xFF0284C7);

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
          border: Border.all(
            color: accentColor.withOpacity(0.3),
            width: 2.0,
          ),
        ),
        child: Stack(
          children: [
            CustomPaint(
              size: const Size(2500, 2500),
              painter: ConnectionPainter(
                notes: notes,
                connections: connections,
                fallbackLineColor: accentColor.withOpacity(0.7),
              ),
            ),
            ...notes.asMap().entries.map((entry) {
              final index = entry.key;
              final note = entry.value;
              final isEditing = editingIndex == index;
              final isConnectingSource = connectingFromId == note.id;
              final cardBg = Color(note.colorValue);
              final hasDocument = note.documentBody.isNotEmpty;

              return Positioned(
                left: note.position.dx,
                top: note.position.dy,
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onDoubleTap: () => _openDocumentEditor(note),
                    onPanUpdate: (details) {
                      setState(() {
                        note.position += details.delta;
                      });
                    },
                    onPanEnd: (_) {
                      final snappedX = (note.position.dx / gridSize).round() * gridSize;
                      final snappedY = (note.position.dy / gridSize).round() * gridSize;

                      setState(() {
                        note.position = ui.Offset(snappedX, snappedY);
                      });

                      DBHelper.updateNote(note);
                    },
                    onSecondaryTap: () => _handleRightClickConnect(note.id),
                    onLongPress: () => _handleRightClickConnect(note.id),
                    child: Container(
                      width: 240,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isConnectingSource
                              ? Colors.amberAccent
                              : isEditing
                                  ? accentColor
                                  : (isDarkMode ? const Color(0xFF3F3F46) : Colors.black12),
                          width: (isConnectingSource || isEditing) ? 2.0 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.08),
                            blurRadius: 10,
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
                                  controller: titleController,
                                  style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Title',
                                    hintStyle: TextStyle(
                                      color: isDarkMode ? Colors.white38 : Colors.black38,
                                    ),
                                  ),
                                ),
                                TextField(
                                  controller: contentController,
                                  maxLines: null,
                                  style: TextStyle(color: subtextColor, fontSize: 13),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Short Summary',
                                    hintStyle: TextStyle(
                                      color: isDarkMode ? Colors.white38 : Colors.black38,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: noteColors.map((color) {
                                    return GestureDetector(
                                      onTap: () => _changeNoteColor(note, color),
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: note.colorValue == color.value
                                                ? accentColor
                                                : Colors.white38,
                                            width: note.colorValue == color.value ? 2 : 1,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.article_outlined, size: 20),
                                      color: accentColor,
                                      tooltip: 'Open Full Document',
                                      onPressed: () => _openDocumentEditor(note),
                                    ),
                                    TextButton(
                                      onPressed: () => _saveEditing(index),
                                      child: Text('Save', style: TextStyle(color: accentColor)),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : InkWell(
                              onTap: () => _startEditing(index),
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          note.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => _deleteNote(index),
                                        child: Icon(
                                          Icons.close,
                                          color: isDarkMode ? Colors.white38 : Colors.black38,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    note.content,
                                    style: TextStyle(color: subtextColor, fontSize: 13),
                                  ),
                                  if (hasDocument) ...[
                                    const SizedBox(height: 12),
                                    InkWell(
                                      onTap: () => _openDocumentEditor(note),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: accentColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.description, size: 12, color: accentColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Document attached',
                                              style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                    ),
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
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtextColor = isDarkMode ? Colors.white70 : Colors.black54;
    final accentColor = isDarkMode ? Colors.cyanAccent : const Color(0xFF0284C7);

    return Padding(
      padding: const EdgeInsets.only(left: 100.0, right: 32.0, top: 32.0),
      child: ListView.builder(
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          final isEditing = editingIndex == index;
          final cardBg = Color(note.colorValue);

          return Card(
            color: cardBg,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isEditing
                    ? accentColor
                    : (isDarkMode ? const Color(0xFF3F3F46) : Colors.black12),
                width: isEditing ? 2.0 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _openDocumentEditor(note),
                title: Text(
                  note.title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                ),
                subtitle: Text(
                  note.content,
                  style: TextStyle(color: subtextColor),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.article_outlined, color: accentColor),
                      onPressed: () => _openDocumentEditor(note),
                      tooltip: 'Open Document Workspace',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: isDarkMode ? Colors.white38 : Colors.black38,
                      ),
                      onPressed: () => _deleteNote(index),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Connection Custom Painter ---

class ConnectionPainter extends CustomPainter {
  final List<Note> notes;
  final List<Connection> connections;
  final Color fallbackLineColor;

  ConnectionPainter({
    required this.notes,
    required this.connections,
    required this.fallbackLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var conn in connections) {
      final fromIndex = notes.indexWhere((n) => n.id == conn.fromId);
      final toIndex = notes.indexWhere((n) => n.id == conn.toId);

      if (fromIndex == -1 || toIndex == -1) continue;

      final fromNote = notes[fromIndex];
      final toNote = notes[toIndex];

      final start = fromNote.position + const ui.Offset(120, 40);
      final end = toNote.position + const ui.Offset(120, 40);

      final colorFrom = Color(fromNote.colorValue);
      final colorTo = Color(toNote.colorValue);

      Color strokeColor;

      if (fromNote.colorValue == 0xFF121212 && toNote.colorValue == 0xFF121212) {
        strokeColor = fallbackLineColor;
      } else if (fromNote.colorValue == 0xFF121212) {
        strokeColor = colorTo;
      } else if (toNote.colorValue == 0xFF121212) {
        strokeColor = colorFrom;
      } else {
        strokeColor = Color.lerp(colorFrom, colorTo, 0.5) ?? fallbackLineColor;
      }

      final paint = Paint()
        ..color = strokeColor.withOpacity(1.0)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}