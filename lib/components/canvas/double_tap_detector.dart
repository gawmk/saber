import 'package:flutter/gestures.dart';

/// Detects double taps from raw pointer events.
///
/// Unlike [DoubleTapGestureRecognizer], this doesn't join the gesture arena,
/// so other gestures (e.g. single taps) aren't delayed while waiting to see
/// if a second tap follows.
///
/// A tap is invalidated if it moves more than [kTouchSlop],
/// or if another pointer touches down during it (e.g. a pinch).
class PassiveDoubleTapDetector {
  new({required this.onDoubleTap});

  /// Called when a double tap is detected.
  final void Function() onDoubleTap;

  final _activePointers = <int>{};

  PointerDownEvent? _currentDown;

  PointerUpEvent? _firstTapUp;

  /// Handles a [PointerDownEvent] that should be considered for double taps.
  void handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) return reset();

    final firstTapUp = _firstTapUp;
    if (firstTapUp != null &&
        (event.timeStamp - firstTapUp.timeStamp > kDoubleTapTimeout ||
            (event.position - firstTapUp.position).distance > kDoubleTapSlop)) {
      _firstTapUp = null;
    }

    _currentDown = event;
  }

  /// Handles a [PointerMoveEvent] that should be considered for double taps.
  void handlePointerMove(PointerMoveEvent event) {
    final currentDown = _currentDown;
    if (currentDown == null || currentDown.pointer != event.pointer) return;
    if ((event.position - currentDown.position).distance > kTouchSlop) {
      reset();
    }
  }

  /// Handles a [PointerUpEvent] that should be considered for double taps.
  void handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    final currentDown = _currentDown;
    if (currentDown == null || currentDown.pointer != event.pointer) return;
    _currentDown = null;

    if (_firstTapUp == null) {
      _firstTapUp = event;
    } else {
      _firstTapUp = null;
      onDoubleTap();
    }
  }

  /// Handles a [PointerCancelEvent] that should be considered for double taps.
  void handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    reset();
  }

  /// Forgets any in-progress tap, so the next tap is treated as a first tap.
  void reset() {
    _currentDown = null;
    _firstTapUp = null;
  }
}
