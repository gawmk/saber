import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  group('pressureEraser', () {
    Future<EditorState> setUpEditor(
      WidgetTester tester, {
      required bool enabled,
    }) async {
      FlavorConfig.setup();
      FileManager.documentsDirectory =
          '$tmpDir/pressureEraser/'
          '${FileManager.appRootDirectoryPrefix}';
      stows.pressureEraser.value = enabled;
      stows.pressureEraserThreshold.value = 0.85;
      stows.pressureEraserDelay.value = 400;
      stows.disableEraserAfterUse.value = false;

      await tester.pumpWidget(MaterialApp(home: Editor()));
      final state = tester.state<EditorState>(find.byType(Editor));
      addTearDown(state.cancelAutosaveAndMarkSaved);

      for (var i = 0; i < 20; i++) {
        if (state.coreInfo.pages.firstOrNull?.renderBox != null) break;
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
      }
      expect(state.coreInfo.pages.first.renderBox, isNotNull);

      state.currentTool = Pen.currentPen;
      return state;
    }

    Offset startDrawing(EditorState state, double pressure) {
      final page = state.coreInfo.pages[0];
      final focalPoint = page.renderBox!.localToGlobal(
        Offset(page.size.width / 2, page.size.height / 2),
      );
      state.updatePointerData(PointerDeviceKind.stylus, pressure);
      state.dragPageIndex = 0;
      state.onDrawStart(ScaleStartDetails(focalPoint: focalPoint));
      return focalPoint;
    }

    testWidgets('activates on firm stationary press, reverts on release', (
      tester,
    ) async {
      final state = await setUpEditor(tester, enabled: true);

      startDrawing(state, 0.95);
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.currentTool, isA<Eraser>());
      expect(Pen.currentStroke, isNull);

      state.onDrawEnd(.new());
      await tester.pump();
      expect(state.currentTool, isA<Pen>());
    });

    testWidgets('does nothing when disabled', (tester) async {
      final state = await setUpEditor(tester, enabled: false);

      startDrawing(state, 0.95);
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.currentTool, isA<Pen>());

      state.onDrawEnd(.new());
      await tester.pump();
    });

    testWidgets('does nothing with light pressure', (tester) async {
      final state = await setUpEditor(tester, enabled: true);

      startDrawing(state, 0.5);
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.currentTool, isA<Pen>());

      state.onDrawEnd(.new());
      await tester.pump();
    });

    testWidgets('respects the firmness setting', (tester) async {
      final state = await setUpEditor(tester, enabled: true);
      stows.pressureEraserThreshold.value = 0.95;

      startDrawing(state, 0.9);
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.currentTool, isA<Pen>());

      state.onDrawEnd(.new());
      await tester.pump();
    });

    testWidgets('respects the hold time setting', (tester) async {
      final state = await setUpEditor(tester, enabled: true);
      stows.pressureEraserDelay.value = 700;

      startDrawing(state, 0.95);
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.currentTool, isA<Pen>());
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.currentTool, isA<Eraser>());

      state.onDrawEnd(.new());
      await tester.pump();
      expect(state.currentTool, isA<Pen>());
    });

    testWidgets('does nothing when the pen keeps moving', (tester) async {
      final state = await setUpEditor(tester, enabled: true);

      var focalPoint = startDrawing(state, 0.95);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        focalPoint += const Offset(20, 0);
        state.onDrawUpdate(ScaleUpdateDetails(focalPoint: focalPoint));
      }
      expect(state.currentTool, isA<Pen>());

      state.onDrawEnd(.new());
      await tester.pump();
    });
  });
}
