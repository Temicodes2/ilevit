import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:obsidian_note_app/main.dart';

void main() {
  test('note streak counts consecutive local calendar days', () {
    final today = DateTime(2026, 10, 10);
    expect(
      calculateNoteStreak(
        {'2026-10-10', '2026-10-09', '2026-10-08'},
        today,
      ),
      3,
    );
    expect(calculateNoteStreak({'2026-10-09'}, today), 1);
    expect(
      calculateNoteStreak({'2026-10-10', '2026-10-08'}, today),
      1,
    );
    expect(calculateNoteStreak({'2026-10-07'}, today), 0);
  });

  testWidgets('board editor returns updated name and selected color',
      (tester) async {
    BoardDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<BoardDraft>(
                  context: context,
                  builder: (_) => const BoardEditorDialog(
                    title: 'Customize board',
                    initialName: 'Old name',
                    initialColorValue: 0xFF22D3EE,
                    actionLabel: 'Save changes',
                  ),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New name');
    await tester.tap(find.byTooltip('Violet'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(result?.name, 'New name');
    expect(result?.colorValue, 0xFFA78BFA);
  });

  group('ConnectionPainter', () {
    late List<Note> notes;

    setUp(() {
      notes = [
        Note(
          id: 'first',
          title: 'First',
          content: '',
          position: const Offset(20, 40),
        ),
        Note(
          id: 'second',
          title: 'Second',
          content: '',
          position: const Offset(180, 40),
        ),
      ];
    });

    tearDown(() {
      for (final note in notes) {
        note.dispose();
      }
    });

    ConnectionPainter painter(List<Connection> connections) {
      return ConnectionPainter(
        notes: notes,
        connections: connections,
        fallbackLineColor: Colors.cyanAccent,
        isDarkMode: true,
      );
    }

    test('does not repaint when graph visuals are unchanged', () {
      final current = painter([Connection('first', 'second')]);
      final next = painter([Connection('first', 'second')]);

      expect(next.shouldRepaint(current), isFalse);
    });

    test('repaints when graph connections change', () {
      final current = painter([]);
      final next = painter([Connection('first', 'second')]);

      expect(next.shouldRepaint(current), isTrue);
    });
  });

  test('dot grid only repaints when its color changes', () {
    const current = DotGridPainter(color: Colors.white);
    const unchanged = DotGridPainter(color: Colors.white);
    const changed = DotGridPainter(color: Colors.cyanAccent);

    expect(unchanged.shouldRepaint(current), isFalse);
    expect(changed.shouldRepaint(current), isTrue);
  });

  testWidgets('note move menu lists destination boards', (tester) async {
    const destinationBoardId = 'destination';
    String? movedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardMoveButton(
            boards: [
              Board(
                id: 'default',
                name: 'My first board',
                colorValue: 0xFF22D3EE,
              ),
              Board(
                id: destinationBoardId,
                name: 'Studio projects',
                colorValue: 0xFFA78BFA,
              ),
            ],
            currentBoardId: 'default',
            isLocked: false,
            onMove: (boardId) => movedTo = boardId,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Move note to another board'));
    await tester.pumpAndSettle();
    expect(find.text('Studio projects'), findsOneWidget);
    expect(find.text('My first board'), findsNothing);
    await tester.tap(find.text('Studio projects'));
    await tester.pumpAndSettle();

    expect(movedTo, destinationBoardId);
  });

  testWidgets('locked notes cannot be moved to another board', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardMoveButton(
            boards: [
              Board(
                id: 'default',
                name: 'My first board',
                colorValue: 0xFF22D3EE,
              ),
              Board(
                id: 'destination',
                name: 'Studio projects',
                colorValue: 0xFFA78BFA,
              ),
            ],
            currentBoardId: 'default',
            isLocked: true,
            onMove: (_) {},
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byType(PopupMenuButton<String>),
          )
          .enabled,
      isFalse,
    );
    expect(
      find.byTooltip('Unlock note to move it to another board'),
      findsOneWidget,
    );
  });

  testWidgets('list notes expand into an editor and save title changes',
      (tester) async {
    final note = Note(
      id: 'editable',
      title: 'Original title',
      content: 'A note preview',
      position: Offset.zero,
    );
    var saved = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: ListView(
            children: [
              ListNoteCard(
                note: note,
                isDarkMode: true,
                cardColor: const Color(0xFF1E1E22),
                boards: [
                  Board(
                    id: 'default',
                    name: 'My first board',
                    colorValue: 0xFF22D3EE,
                  ),
                ],
                onDelete: () {},
                onToggleLock: () async {},
                onMoveToBoard: (_) {},
                onPersist: (_) async {},
                onSaved: () => saved = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Original title'));
    await tester.pumpAndSettle();
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Updated title');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(note.title, 'Updated title');
    expect(saved, isTrue);

    note.dispose();
  });

  testWidgets('locking a list note prevents editing but still allows unlocking',
      (tester) async {
    final note = Note(
      id: 'locked-list-note',
      title: 'Protected note',
      content: 'Protected content',
      position: Offset.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: Scaffold(
          body: ListView(
            children: [
              ListNoteCard(
                note: note,
                isDarkMode: true,
                cardColor: const Color(0xFF1E1E22),
                boards: [
                  Board(
                    id: 'default',
                    name: 'My first board',
                    colorValue: 0xFF22D3EE,
                  ),
                ],
                onDelete: () {},
                onToggleLock: () async {
                  note.isLocked = !note.isLocked;
                },
                onMoveToBoard: (_) {},
                onPersist: (_) async {},
                onSaved: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Protected note'));
    await tester.pumpAndSettle();
    expect(find.byType(QuillEditor), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Saved before locking');
    await tester.tap(find.byTooltip('Lock note'));
    await tester.pumpAndSettle();
    expect(note.isLocked, isTrue);
    expect(note.title, 'Saved before locking');
    expect(find.byType(QuillEditor), findsNothing);

    await tester.tap(find.text('Saved before locking'));
    await tester.pumpAndSettle();
    expect(find.byType(QuillEditor), findsNothing);

    await tester.tap(find.byTooltip('Unlock note'));
    await tester.pumpAndSettle();
    expect(note.isLocked, isFalse);

    note.dispose();
  });

  testWidgets('locked canvas notes cannot be dragged or opened for editing',
      (tester) async {
    final note = Note(
      id: 'locked-canvas-note',
      title: 'Locked canvas note',
      content: 'Do not move me',
      position: const Offset(20, 20),
      isLocked: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CanvasNoteCard(
                note: note,
                index: 0,
                isDarkMode: true,
                isConnectingSource: false,
                cardColor: const Color(0xFF1E1E22),
                boards: [
                  Board(
                    id: 'default',
                    name: 'My first board',
                    colorValue: 0xFF22D3EE,
                  ),
                ],
                onMoveToBoard: (_) {},
                onToggleLock: () {},
                onChangeColor: (_) {},
                onDeleteNote: () {},
                onConnect: (_) {},
                onSaved: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.text('Locked canvas note'), const Offset(100, 80));
    await tester.pumpAndSettle();
    expect(note.position, const Offset(20, 20));
    expect(find.byType(QuillEditor), findsNothing);

    note.dispose();
  });

  testWidgets('screen switch uses a subtle fade, slide, and scale transition',
      (tester) async {
    var screen = 'Canvas';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => screen = 'List'),
                  child: const Text('Switch screen'),
                ),
                Expanded(
                  child: ScreenSwitcher(
                    screenKey: screen,
                    child: Text(screen),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Switch screen'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsWidgets);
    expect(find.text('Canvas'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Canvas'), findsNothing);
    expect(find.text('List'), findsOneWidget);
  });
}
