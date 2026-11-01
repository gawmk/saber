import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/double_tap_detector.dart';

void main() {
  late int doubleTaps;
  late PassiveDoubleTapDetector detector;

  setUp(() {
    doubleTaps = 0;
    detector = PassiveDoubleTapDetector(onDoubleTap: () => doubleTaps++);
  });

  void tap({
    int pointer = 1,
    required int downMs,
    required int upMs,
    Offset position = const Offset(100, 100),
  }) {
    detector.handlePointerDown(
      PointerDownEvent(
        pointer: pointer,
        timeStamp: Duration(milliseconds: downMs),
        position: position,
      ),
    );
    detector.handlePointerUp(
      PointerUpEvent(
        pointer: pointer,
        timeStamp: Duration(milliseconds: upMs),
        position: position,
      ),
    );
  }

  test('Two quick taps are a double tap', () {
    tap(pointer: 1, downMs: 0, upMs: 50);
    expect(doubleTaps, 0);
    tap(pointer: 2, downMs: 150, upMs: 200);
    expect(doubleTaps, 1);
  });

  test('Three quick taps are only one double tap', () {
    tap(pointer: 1, downMs: 0, upMs: 50);
    tap(pointer: 2, downMs: 150, upMs: 200);
    tap(pointer: 3, downMs: 300, upMs: 350);
    expect(doubleTaps, 1);
  });

  test('Two slow taps are not a double tap', () {
    tap(pointer: 1, downMs: 0, upMs: 50);
    tap(pointer: 2, downMs: 1000, upMs: 1050);
    expect(doubleTaps, 0);
  });

  test('Two distant taps are not a double tap', () {
    tap(pointer: 1, downMs: 0, upMs: 50);
    tap(
      pointer: 2,
      downMs: 150,
      upMs: 200,
      position: const Offset(100, 100 + kDoubleTapSlop + 1),
    );
    expect(doubleTaps, 0);
  });

  test('A tap that moves is not part of a double tap', () {
    tap(pointer: 1, downMs: 0, upMs: 50);
    detector.handlePointerDown(
      const PointerDownEvent(
        pointer: 2,
        timeStamp: Duration(milliseconds: 150),
        position: Offset(100, 100),
      ),
    );
    detector.handlePointerMove(
      const PointerMoveEvent(
        pointer: 2,
        timeStamp: Duration(milliseconds: 175),
        position: Offset(100, 100 + kTouchSlop + 1),
      ),
    );
    detector.handlePointerUp(
      const PointerUpEvent(
        pointer: 2,
        timeStamp: Duration(milliseconds: 200),
        position: Offset(100, 100 + kTouchSlop + 1),
      ),
    );
    expect(doubleTaps, 0);
  });

  test('A multi-finger gesture is not part of a double tap', () {
    tap(pointer: 1, downMs: 0, upMs: 50);
    detector.handlePointerDown(
      const PointerDownEvent(
        pointer: 2,
        timeStamp: Duration(milliseconds: 150),
        position: Offset(100, 100),
      ),
    );
    detector.handlePointerDown(
      const PointerDownEvent(
        pointer: 3,
        timeStamp: Duration(milliseconds: 160),
        position: Offset(150, 100),
      ),
    );
    detector.handlePointerUp(
      const PointerUpEvent(
        pointer: 2,
        timeStamp: Duration(milliseconds: 200),
        position: Offset(100, 100),
      ),
    );
    detector.handlePointerUp(
      const PointerUpEvent(
        pointer: 3,
        timeStamp: Duration(milliseconds: 210),
        position: Offset(150, 100),
      ),
    );
    expect(doubleTaps, 0);
  });

  test('A cancelled tap is not part of a double tap', () {
    tap(pointer: 1, downMs: 0, upMs: 50);
    detector.handlePointerDown(
      const PointerDownEvent(
        pointer: 2,
        timeStamp: Duration(milliseconds: 150),
        position: Offset(100, 100),
      ),
    );
    detector.handlePointerCancel(
      const PointerCancelEvent(
        pointer: 2,
        timeStamp: Duration(milliseconds: 200),
        position: Offset(100, 100),
      ),
    );
    tap(pointer: 3, downMs: 250, upMs: 300);
    expect(doubleTaps, 0);
  });
}
