import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/pack_player_screen.dart';
import 'package:telinha_segura/kid/room_transition.dart';

void main() {
  test('one motion scale: 90, 150, 220, 300, 400, 1000 and 2000 ms', () {
    expect(Motion.press, const Duration(milliseconds: 90));
    expect(Motion.quick, const Duration(milliseconds: 150));
    expect(Motion.change, const Duration(milliseconds: 220));
    expect(Motion.room, const Duration(milliseconds: 300));
    expect(Motion.band, const Duration(milliseconds: 400));
    expect(Motion.opening, const Duration(milliseconds: 1000));
    expect(Motion.hold, const Duration(milliseconds: 2000));
  });

  test('the mascot\'s own beats and the loops keep their named lengths', () {
    expect(Motion.blink, const Duration(milliseconds: 160));
    expect(Motion.release, const Duration(milliseconds: 160));
    expect(Motion.fallAsleep, const Duration(milliseconds: 600));
    expect(Motion.breath, const Duration(milliseconds: 1400));
    expect(Motion.gaze, const Duration(milliseconds: 1800));
  });

  test('the curves in use, named by what they do', () {
    expect(Motion.settle, Curves.easeOutCubic);
    expect(Motion.travel, Easing.standard);
    expect(Motion.shut, Curves.easeOut);
    expect(Motion.sway, Curves.easeInOut);
    expect(Motion.wipe, const Cubic(.2, .7, .2, 1));
    expect(Motion.pop, const Cubic(.3, 1.5, .5, 1));
    expect(Motion.spring, const Cubic(.3, 1.4, .5, 1));
  });

  test('every animation takes its length from the scale', () {
    expect(BandTransition.duration, Motion.band);
    expect(BandTransition.curve, Motion.settle);
    expect(RoomTransition.duration, Motion.room);
    expect(RoomTransition.curve, Motion.travel);
    expect(PackPlayerScreen.fade, Motion.change);
    expect(MascotUnderNote.fade, Motion.quick);
    expect(HoldToExit.hold, Motion.hold);
    // The confirmation wink keeps its own, longer, beat.
    expect(PerchedTevi.winkDuration, const Duration(milliseconds: 1400));
  });
}
