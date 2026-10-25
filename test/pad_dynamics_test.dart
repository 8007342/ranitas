import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/pond_model.dart';

/// Lily pad dynamics (openspec/changes/visual-envelope/specs/lily-pad-dynamics).
void main() {
  List<PadState> allPads(PondModel m) => [...m.pads, ...m.ambientPads];

  test('seeded layouts differ across seeds, repeat per seed and fit the basin', () {
    final layouts = <String>{};
    for (var seed = 0; seed < 100; seed++) {
      final a = PondModel(seed: seed);
      final b = PondModel(seed: seed);
      expect(
        allPads(a).map((p) => [p.x, p.y, p.baseRx, p.sectionRadius]).toList(),
        allPads(b).map((p) => [p.x, p.y, p.baseRx, p.sectionRadius]).toList(),
      );
      layouts.add(
        '${a.biome}:${a.pads[0].x.toStringAsFixed(4)},${a.pads[0].y.toStringAsFixed(4)},${a.pads[0].baseRx.toStringAsFixed(2)}',
      );
      expect(a.ambientPads.length, inInclusiveRange(5, 9));
      expect(a.pads[0].baseRx, inInclusiveRange(30, 40));
      expect(a.pads[1].baseRx, inInclusiveRange(30, 40));
      expect(a.pads[0].sectionRadius, inInclusiveRange(10, 14));
      expect(a.pads[1].sectionRadius, inInclusiveRange(10, 14));

      // Hero 0 left of the basin middle, hero 1 right of it, at its own depth.
      final mid0 =
          (a.basin.leftX(a.pads[0].y * 359) + a.basin.rightX(a.pads[0].y * 359)) /
          2;
      final mid1 =
          (a.basin.leftX(a.pads[1].y * 359) + a.basin.rightX(a.pads[1].y * 359)) /
          2;
      expect(a.pads[0].x * 641, lessThan(mid0));
      expect(a.pads[1].x * 641, greaterThan(mid1));

      final pads = allPads(a);
      for (final p in pads) {
        final px = p.x * 641;
        final py = p.y * 359;
        expect(p.baseRx, inInclusiveRange(9.5, 40));
        expect(py - p.radiusY, greaterThanOrEqualTo(a.basin.topY));
        expect(py + p.radiusY, lessThanOrEqualTo(a.basin.bottomY));
        expect(px - p.radiusX, greaterThanOrEqualTo(a.basin.leftX(py)));
        expect(px + p.radiusX, lessThanOrEqualTo(a.basin.rightX(py)));
        expect(p.homeX, p.x);
        expect(p.homeY, p.y);
        expect(p.sectionRadius, greaterThanOrEqualTo(1));
      }
      // Sections never overlap: the swept boxes clear each other on an axis.
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
    // Hero layouts vary with the seed, not only with the biome.
    expect(layouts.length, greaterThan(PondModel.biomes.length * 4));
  });

  test('landing slide: 3–12 px along the jump, settled under 0.1 px/s in 3 s', () {
    var measured = 0;
    for (var seed = 0; seed < 300 && measured < 20; seed++) {
      final m = PondModel(seed: seed);
      final pad = m.pads[1];
      final travel = (pad.x + m.perchOffsetX(0, 1) - m.pads[0].x) * 641;
      // A clearly sideways hop onto a pad with a full-size section.
      if (travel.abs() < 80 || pad.sectionRadius < 12) continue;
      measured++;
      m.press();
      m.release();
      final frog = m.frogs[0];
      expect(frog.action, 'tap');
      final before = [pad.vx, pad.vy];
      while (frog.airborne) {
        m.update(1 / 60);
      }
      expect(frog.leafIndex, 1);
      final direction = travel.sign;
      expect(pad.vx * direction, greaterThan(before[0] * direction));

      // Integrate the slide (velocity relative to the water) for 3 s while a
      // jittered hold keeps the other frog from jumping onto this pad.
      var slide = 0.0;
      var speed = double.infinity;
      for (var frame = 0; frame < 180; frame++) {
        slide += pad.vx * direction / 60;
        speed = sqrt(pad.vx * pad.vx + pad.vy * pad.vy);
        final dx = (pad.x - pad.homeX) * 641;
        final dy = (pad.y - pad.homeY) * 359;
        expect(sqrt(dx * dx + dy * dy),
            lessThanOrEqualTo(pad.sectionRadius + 1e-6));
        m.cancelPress();
        m.press();
        m.update(1 / 60);
      }
      expect(slide, inInclusiveRange(3, 12), reason: 'seed=$seed');
      expect(speed, lessThan(.1), reason: 'seed=$seed');
    }
    expect(measured, 20);
  });

  test('takeoff recoils the source pad against the jump', () {
    final m = PondModel(seed: 3);
    final source = m.pads[0];
    final direction = (m.pads[1].x - m.pads[0].x).sign;
    m.press();
    m.release();
    expect(source.vx * direction, lessThan(0));
  });

  test('pad motion is a pure function of the seeded timeline across partitions', () {
    for (final seed in [5, 17, 29]) {
      final a = PondModel(seed: seed);
      final b = PondModel(seed: seed);
      for (var second = 0; second < 40; second++) {
        if (second % 5 == 0) {
          a.press();
          a.release();
          b.press();
          b.release();
        }
        a.update(1);
        for (var frame = 0; frame < 60; frame++) {
          b.update(1 / 60);
        }
        final pa = allPads(a);
        final pb = allPads(b);
        for (var i = 0; i < pa.length; i++) {
          expect([pa[i].x, pa[i].y, pa[i].vx, pa[i].vy, pa[i].radiusX, pa[i].yaw],
              [pb[i].x, pb[i].y, pb[i].vx, pb[i].vy, pb[i].radiusX, pb[i].yaw],
              reason: 'seed=$seed t=$second pad $i');
        }
      }
    }
  });

  test('current is bounded, seeded and deterministic in time', () {
    final m = PondModel(seed: 9);
    final other = PondModel(seed: 10);
    var differs = false;
    for (final pad in allPads(m)) {
      final (cx, cy) = m.currentAt(pad);
      final speed = sqrt(cx * cx + cy * cy);
      final cap = pad.isAmbient ? 2.0 : 1.2;
      expect(speed, inInclusiveRange(.8 * (pad.isAmbient ? 1 : .6) - 1e-9, cap + 1e-9));
      final (dx, dy) = m.currentAt(pad);
      expect([dx, dy], [cx, cy]);
      final (ox, oy) = other.currentAt(pad);
      if ((ox - cx).abs() > 1e-6 || (oy - cy).abs() > 1e-6) differs = true;
    }
    expect(differs, isTrue);
  });

  test('receding pad shrinks monotonically by no more than 8 % over 8 px', () {
    final m = PondModel(seed: 21);
    final pad = m.pads[1];
    pad.y = (m.basin.topY + .7 * (m.basin.bottomY - m.basin.topY)) / 359;
    m.projectPad(pad);
    var previousRx = pad.radiusX;
    var previousRy = pad.radiusY;
    final startRx = pad.radiusX;
    for (var step = 0; step < 16; step++) {
      pad.y -= .5 / 359;
      m.projectPad(pad);
      expect(pad.radiusX, lessThanOrEqualTo(previousRx));
      expect(pad.radiusY, lessThanOrEqualTo(previousRy));
      expect(pad.radiusY * 2, (pad.radiusY * 2).roundToDouble());
      previousRx = pad.radiusX;
      previousRy = pad.radiusY;
    }
    expect(pad.radiusX, greaterThanOrEqualTo(startRx * .92));
    expect(m.perspectiveAt(m.basin.topY), closeTo(.56, 1e-9));
    expect(m.perspectiveAt(m.basin.bottomY), closeTo(1.04, 1e-9));
    expect(m.perspectiveAt(m.basin.topY - 50), closeTo(.56, 1e-9));
  });

  test('perched frogs ride their pads and land on a moving pad without a jump', () {
    for (final seed in [1, 2, 8]) {
      final m = PondModel(seed: seed);
      final frog = m.frogs[0];
      final home = m.pads[0];
      // Riding: the frog keeps its pad-relative offset while the pad drifts.
      home.vx = 6;
      for (var i = 0; i < 30; i++) {
        m.update(1 / 60);
        expect(frog.x, closeTo(home.x + frog.perchDx, 1e-9));
        expect(frog.y, closeTo(home.y + frog.perchDy, 1e-9));
      }
      expect(home.x, isNot(home.homeX));

      // Landing on a target pad sliding at 10 px/s.
      final target = m.pads[1];
      m.press();
      m.release();
      target.vx = 10;
      target.vy = 2;
      while (frog.airborne) {
        final x = frog.x;
        final y = frog.y;
        if (frog.jumpPhase < .5) {
          target.vx = 10;
          target.vy = 2;
        }
        m.update(1 / 60);
        expect((frog.x - x).abs(), lessThan(.03), reason: 'seed=$seed');
        expect((frog.y - y).abs(), lessThan(.03), reason: 'seed=$seed');
      }
      expect(frog.leafIndex, 1);
      final dx = (frog.x - target.x) * 641;
      final dy = (frog.y - target.y) * 359;
      expect(dx.abs(), lessThanOrEqualTo(target.radiusX));
      expect(dy.abs(), lessThanOrEqualTo(target.radiusY + 6));
      expect(frog.x, closeTo(target.x + frog.perchDx, 1e-9));
    }
  });
}
