import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  group('Editor clipboard', () {
    Future<EditorState> setUpEditor(WidgetTester tester) async {
      FlavorConfig.setup();
      FileManager.documentsDirectory =
          '$tmpDir/editorClipboard/'
          '${FileManager.appRootDirectoryPrefix}';

      await tester.pumpWidget(MaterialApp(home: Editor()));
      final state = tester.state<EditorState>(find.byType(Editor));
      addTearDown(state.cancelAutosaveAndMarkSaved);

      for (var i = 0; i < 20; i++) {
        if (state.coreInfo.pages.firstOrNull?.renderBox != null) break;
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
      }
      expect(state.coreInfo.pages.first.renderBox, isNotNull);
      return state;
    }

    Stroke addStroke(EditorState state, Offset start) {
      final page = state.coreInfo.pages[0];
      final stroke = Stroke(
        color: Stroke.defaultColor,
        pressureEnabled: false,
        options: StrokeOptions(size: 5),
        pageIndex: 0,
        page: page,
        toolId: .fountainPen,
      );
      for (var i = 0; i < 5; i++) {
        stroke.addPoint(start + Offset(i * 10, 0));
      }
      page.insertStroke(stroke);
      return stroke;
    }

    void selectAll(EditorState state, Rect rect) {
      final select = Select.currentSelect;
      state.currentTool = select;
      select.onDragStart(rect.topLeft, 0);
      select.onDragUpdate(rect.topRight);
      select.onDragUpdate(rect.bottomRight);
      select.onDragUpdate(rect.bottomLeft);
      select.onDragEnd(
        state.coreInfo.pages[0].strokes,
        state.coreInfo.pages[0].images,
      );
    }

    testWidgets('copies and pastes strokes onto another page', (tester) async {
      final state = await setUpEditor(tester);
      final original = addStroke(state, const Offset(110, 110));
      selectAll(state, const Rect.fromLTWH(100, 100, 100, 50));

      expect(state.hasClipboard, isFalse);
      state.copySelection();
      expect(state.hasClipboard, isTrue);

      state.pasteClipboard(1, const Offset(300, 400));
      await tester.pump();

      final pasted = state.coreInfo.pages[1].strokes;
      expect(pasted, hasLength(1));
      expect(pasted.single, isNot(same(original)));
      expect(pasted.single.pageIndex, 1);
      expect(pasted.single.points.first.dx, closeTo(310, 0.01));
      expect(pasted.single.points.first.dy, closeTo(410, 0.01));
      expect(original.points.first.dx, closeTo(110, 0.01));
      expect(state.coreInfo.pages[0].strokes, hasLength(1));

      expect(Select.currentSelect.doneSelecting, isTrue);
      expect(Select.currentSelect.selectResult.strokes, pasted);

      state.undo();
      await tester.pump();
      expect(state.coreInfo.pages[1].strokes, isEmpty);
    });

    testWidgets('keeps an empty lasso on a pdf page', (tester) async {
      final state = await setUpEditor(tester);
      final page = state.coreInfo.pages[0];
      page.backgroundImage = PdfEditorImage(
        id: 1,
        assetCache: state.coreInfo.assetCache,
        pdfBytes: Uint8List(0),
        pdfFile: null,
        pdfPage: 0,
        pageIndex: 0,
        pageSize: page.size,
        onMoveImage: null,
        onDeleteImage: null,
        onMiscChange: null,
        naturalSize: const Size(500, 700),
      );

      final select = Select.currentSelect;
      state.currentTool = select;
      state.dragPageIndex = 0;
      Offset global(double x, double y) =>
          page.renderBox!.localToGlobal(Offset(x, y));
      state.onDrawStart(ScaleStartDetails(focalPoint: global(100, 100)));
      state.onDrawUpdate(ScaleUpdateDetails(focalPoint: global(300, 100)));
      state.onDrawUpdate(ScaleUpdateDetails(focalPoint: global(300, 200)));
      state.onDrawEnd(.new());

      expect(select.doneSelecting, isTrue);
      expect(select.selectResult.pageIndex, 0);
    });

    testWidgets('pastes independent copies each time', (tester) async {
      final state = await setUpEditor(tester);
      addStroke(state, const Offset(110, 110));
      selectAll(state, const Rect.fromLTWH(100, 100, 100, 50));
      state.copySelection();

      state.pasteClipboard(1, const Offset(100, 100));
      state.pasteClipboard(1, const Offset(100, 300));
      await tester.pump();

      final pasted = state.coreInfo.pages[1].strokes;
      expect(pasted, hasLength(2));
      expect(pasted[0], isNot(same(pasted[1])));
    });

    testWidgets('finger long press shows the paste menu', (tester) async {
      final state = await setUpEditor(tester);
      addStroke(state, const Offset(110, 110));
      selectAll(state, const Rect.fromLTWH(100, 100, 100, 50));
      state.copySelection();

      final page = state.coreInfo.pages[0];
      final center = page.renderBox!.localToGlobal(const Offset(400, 300));

      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text(t.editor.selectionBar.paste), findsOneWidget);
      await gesture.up();

      await tester.tap(find.text(t.editor.selectionBar.paste));
      await tester.pumpAndSettle();
      expect(page.strokes, hasLength(2));
    });

    for (final (name, kind, move) in [
      ('moving finger', PointerDeviceKind.touch, const Offset(30, 0)),
      ('stylus', PointerDeviceKind.stylus, Offset.zero),
    ]) {
      testWidgets('$name does not show the menu', (tester) async {
        final state = await setUpEditor(tester);
        addStroke(state, const Offset(110, 110));
        selectAll(state, const Rect.fromLTWH(100, 100, 100, 50));
        state.copySelection();

        final page = state.coreInfo.pages[0];
        final center = page.renderBox!.localToGlobal(const Offset(400, 300));

        final gesture = await tester.startGesture(center, kind: kind);
        await gesture.moveBy(move);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text(t.editor.selectionBar.paste), findsNothing);
        await gesture.up();
        await tester.pumpAndSettle();
      });
    }
  });
}
