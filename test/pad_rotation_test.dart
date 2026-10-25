import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/pond_model.dart';

/// Pad size tiers and in-plane rotation
/// (openspec/changes/visual-envelope/specs/lily-pad-dynamics).
void main() {
  List<PadState> allPads(PondModel m) => [...m.pads, ...m.ambientPads];

  test('size tiers over 300 seeds: large leaves, an occasional super pad, no overlaps', () {
    var supers = 0;
    var large = 0;
    var ambient = 0;
    for (var seed = 0; seed < 300; seed++) {
      final m = PondModel(seed: seed);
      final superPads = m.ambientPads.where((p) => p.isSuper).toList();
      expect(superPads.length, lessThanOrEqualTo(1), reason: 'seed=$seed');
      expect(m.ambientPads.length, inInclusiveRange(4, 9));
      for (final p in m.ambientPads) {
        ambient++;
        if (p.isSuper) {
          supers++;
          expect(p.baseRx, inInclusiveRange(42, 54));
          expect(p.hasLotus, isFalse);
          // Decorative: behind both heroes, clear of the jump lane for ever.
          for (final hero in m.pads) {
            expect(
              p.y * 359 + p.radiusY + p.sectionRadius,
              lessThan(hero.y * 359 - hero.radiusY - hero.sectionRadius),
              reason: 'seed=$seed super pad reaches the jump lane',
            );
          }
        } else {
          expect(p.baseRx, inInclusiveRange(9.5, 28));
          if (p.baseRx >= 21) large++;
        }
      }
      for (final hero in m.pads) {
        expect(hero.isSuper, isFalse);
        expect(hero.baseRx, inInclusiveRange(30, 40));
      }
      // Jumps stay hero ↔ hero.
      for (final frog in m.frogs) {
        expect(frog.leafIndex, lessThan(2));
      }

      final pads = allPads(m);
      for (final p in pads) {
        final px = p.x * 641;
        final py = p.y * 359;
        expect(py - p.radiusY, greaterThanOrEqualTo(m.basin.topY));
        expect(py + p.radiusY, lessThanOrEqualTo(m.basin.bottomY));
        expect(px - p.radiusX, greaterThanOrEqualTo(m.basin.leftX(py)));
        expect(px + p.radiusX, lessThanOrEqualTo(m.basin.rightX(py)));
      }
      for (var i = 0; i < pads.length; i++) {
        for (var j = i + 1; j < pads.length; j++) {
          final p = pads[i];
          final q = pads[j];
          final dx = (p.x - q.x).abs() * 641;
          final dy = (p.y - q.y).abs() * 359;
          final clearX =
              dx >= p.radiusX + q.radiusX + p.sectionRadius + q.sectionRadius;
          final clearY =
              dy >= p.radiusY + q.radiusY + p.sectionRadius + q.sectionRadius;
          expect(clearX || clearY, isTrue,
              reason: 'seed=$seed pads ${p.index}/${q.index}');
        }
      }
    }
    // Print the measured distribution next to the contract.
    // ignore: avoid_print
    print('PAD SIZES seeds=0..299 super=$supers worlds, large=$large/$ambient ambient');
    // About one world in four or five grows a super pad.
    expect(supers, inInclusiveRange(45, 90));
    // Roughly one ambient leaf in ten is large.
    expect(large / ambient, inInclusiveRange(.06, .2));
  });

  test('yaw stays bounded and smooth, keeps turning, and agrees across partitions', () {
    for (final seed in [3, 11, 42]) {
      final a = PondModel(seed: seed);
      final b = PondModel(seed: seed);
      final turned = List.filled(allPads(a).length, 0.0);
      for (var second = 0; second < 60; second++) {
        if (second % 7 == 0) {
          a.press();
          a.release();
          b.press();
          b.release();
        }
        for (var frame = 0; frame < 60; frame++) {
          final before = allPads(a).map((p) => p.yaw).toList();
          a.update(1 / 60);
          var i = 0;
          for (final p in allPads(a)) {
            expect(p.yaw, inInclusiveRange(-pi, pi), reason: 'seed=$seed');
            expect(p.yawVelocity.abs(), lessThanOrEqualTo(1.2));
            var step = p.yaw - before[i];
            if (step > pi) step -= 2 * pi;
            if (step < -pi) step += 2 * pi;
            expect(step.abs(), lessThanOrEqualTo(1.2 / 60 + 1e-9),
                reason: 'seed=$seed pad ${p.index} jumped');
            turned[i] += step;
            i++;
          }
        }
        b.update(1);
        final pa = allPads(a);
        final pb = allPads(b);
        for (var i = 0; i < pa.length; i++) {
          expect(pa[i].yaw, pb[i].yaw, reason: 'seed=$seed t=$second pad $i');
          expect(pa[i].yawVelocity, pb[i].yawVelocity);
        }
      }
      // Pads visibly turn over a minute: at least one makes a quarter turn.
      expect(turned.map((t) => t.abs()).reduce(max), greaterThan(pi / 2),
          reason: 'seed=$seed');
    }
  });

  test('rotation continues through sleep', () {
    final m = PondModel(seed: 5, durationOverride: 8);
    m.press();
    m.release();
    m.update(30);
    expect(m.sleeping, isTrue);
    final before = allPads(m).map((p) => p.yaw).toList();
    m.update(20);
    var moved = 0;
    for (var i = 0; i < before.length; i++) {
      if ((allPads(m)[i].yaw - before[i]).abs() > .02) moved++;
    }
    expect(moved, greaterThan(before.length ~/ 2));
  });

  test('a landing turns the pad gently, never into a spin', () {
    var kicks = 0;
    for (var seed = 0; seed < 60; seed++) {
      final m = PondModel(seed: seed);
      m.press();
      m.release();
      final frog = m.frogs[0];
      final pad = m.pads[1];
      var before = pad.yawVelocity;
      while (frog.airborne) {
        before = pad.yawVelocity;
        m.update(1 / 60);
      }
      final kick = (pad.yawVelocity - before).abs();
      expect(kick, lessThanOrEqualTo(.6 + 1e-9), reason: 'seed=$seed');
      if (kick > .02) kicks++;
    }
    expect(kicks, greaterThan(40));
  });

  test('perched frogs keep their perch inside a rotating pad', () {
    for (final seed in [1, 6, 13]) {
      final m = PondModel(seed: seed);
      final frog = m.frogs[1];
      final pad = m.pads[1];
      pad.yawVelocity = 1.0;
      for (var frame = 0; frame < 240; frame++) {
        final x = frog.x;
        final y = frog.y;
        m.update(1 / 60);
        pad.yawVelocity = 1.0;
        expect(frog.airborne, isFalse);
        expect(frog.x, closeTo(pad.x + frog.perchDx, 1e-9));
        expect(frog.y, closeTo(pad.y + frog.perchDy, 1e-9));
        // Rides the slide only: no per-frame jitter from the rotation.
        expect((frog.x - x).abs() * 641, lessThan(.5));
        expect((frog.y - y).abs() * 359, lessThan(.5));
        final dx = (frog.x - pad.x) * 641 / pad.radiusX;
        final dy = (frog.y - pad.y) * 359 / pad.radiusY;
        expect(dx * dx + dy * dy, lessThanOrEqualTo(1.0), reason: 'seed=$seed');
      }
    }
  });

  test('slit angle follows the yaw and the current has a bounded vorticity', () {
    final m = PondModel(seed: 2);
    for (final pad in allPads(m)) {
      expect(pad.slitAngle, pad.phase + pad.yaw);
      expect(m.vorticityAt(pad).abs(), lessThan(1.0));
      final again = m.vorticityAt(pad);
      expect(again, m.vorticityAt(pad));
    }
  });
}
