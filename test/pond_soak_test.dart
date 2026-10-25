import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/pond_model.dart';

void gesture(PondModel pond) {
  pond.press();
  pond.release();
}

List<Object> snapshot(PondModel p) => [
  p.time,
  p.elapsed,
  p.progress,
  p.sleeping,
  p.started,
  p.pressing,
  p.weather,
  p.cycle,
  p.period,
  p.aiEvaluations,
  for (final f in p.frogs)
    [f.x, f.y, f.airborne, f.swimming, f.asleep, f.leafIndex, f.tongue],
  for (final b in p.bugs) [b.x, b.y, b.vx, b.vy, b.species, b.alive],
];

void checkGeometry(PondModel p, String context) {
  expect(p.frogs.length, 2, reason: context);
  for (final f in p.frogs) {
    for (final v in [f.x, f.y, f.tongueX, f.tongueY, f.energy]) {
      expect(v.isFinite, isTrue, reason: context);
    }
    expect(f.x, inInclusiveRange(0, 1), reason: context);
    expect(f.y, inInclusiveRange(0, 1), reason: context);
  }
  for (final b in p.bugs) {
    expect(
      [b.x, b.y, b.vx, b.vy, b.opacity].every((v) => v.isFinite),
      isTrue,
      reason: context,
    );
    expect(b.x, inInclusiveRange(0, 1), reason: context);
    expect(b.y, inInclusiveRange(0, 1), reason: context);
  }
}

void main() {
  test('100 seeds wait without input; omitted updates and zero delta do not advance', () {
    for (var seed = 0; seed < 100; seed++) {
      final p = PondModel(seed: seed);
      p.update(60);
      expect(p.started, isFalse);
      expect(p.elapsed, 0);
      expect(p.progress, 0);
      expect(p.bugs, isEmpty);
      expect(p.frogs.every((f) => !f.airborne && !f.swimming), isTrue);
      final before = snapshot(p);
      // A paused host omits update calls; the model has no wall-clock input.
      for (var i = 0; i < 100; i++) {
        p.update(0);
      }
      expect(snapshot(p), before);
      gesture(p);
      p.update(10);
      final active = snapshot(p);
      p.update(0);
      expect(snapshot(p), active);
    }
  });

  test('only a completed or auto-launched gesture starts play; cancellation clears charge', () {
    final p = PondModel(seed: 1);
    p.press();
    p.update(.15);
    expect(p.started, isFalse);
    expect(p.elapsed, 0);
    p.cancelPress();
    p.release();
    expect(p.started, isFalse);
    expect(p.pressing, isFalse);
    gesture(p);
    p.update(1);
    expect(p.started, isTrue);
    expect(p.elapsed, closeTo(1, 1 / 60));
  });

  test('a thousand busy gestures while a frog is in the air are ignored', () {
    final burst = PondModel(seed: 1);
    gesture(burst);
    burst.update(.1);
    for (var i = 0; i < 1000; i++) {
      gesture(burst);
    }
    var launches = 1;
    var airborne = true;
    var phase = burst.frogs.first.jumpPhase;
    for (var i = 0; i < 600; i++) {
      burst.update(1 / 60);
      final next = burst.frogs.first.airborne;
      final nextPhase = burst.frogs.first.jumpPhase;
      if (next && (!airborne || nextPhase + 1e-8 < phase)) launches++;
      airborne = next;
      phase = nextPhase;
    }
    expect(
      launches,
      1,
      reason: 'Queued gestures while a frog is in the air are ignored',
    );
  });

  test('seeded input trace agrees across render partitions', () {
    for (var seed = 0; seed < 12; seed++) {
      final a = PondModel(seed: seed);
      final b = PondModel(seed: seed);
      for (var second = 0; second < 490; second++) {
        if (second % 7 == 0) {
          gesture(a);
          gesture(b);
        }
        a.update(1);
        for (var frame = 0; frame < 60; frame++) {
          b.update(1 / 60);
        }
        expect(snapshot(a), snapshot(b), reason: 'seed=$seed second=$second');
      }
    }
  });

  test('100 seeds full sessions and 30 minutes after synchronized sleep stay bounded', () {
    final worlds = <String>{};
    var maxAwake = 0;
    var maxSleeping = 0;
    final maximaByWeather = <String, int>{};

    for (var seed = 0; seed < 100; seed++) {
      final p = PondModel(seed: seed);
      worlds.add('${p.weather}/${p.cycle}');
      // Rain shelter follows the seeded intensity envelope, so the budget is
      // 18 × the most generous shelter seen so far (insects are not culled
      // when the rain thickens again), with a margin for the 0.8 s check grid.
      var maxShelter = p.insectShelter;
      int cap() => (18 * maxShelter).ceil() + 2;
      gesture(p);
      var previousProgress = 0.0;

      for (var second = 0; second < 366; second++) {
        // Alternate idle sessions and sustained input without a catch quota.
        if (seed.isEven && second % 2 == 0) {
          gesture(p);
        }
        p.update(1);
        maxShelter = max(maxShelter, p.insectShelter);
        checkGeometry(p, 'seed=$seed t=$second');
        expect(p.rainIntensity, inInclusiveRange(0, 1));
        expect(p.bugs.length, lessThanOrEqualTo(cap()));
        maximaByWeather.update(
          p.weather,
          (n) => n < p.bugs.length ? p.bugs.length : n,
          ifAbsent: () => p.bugs.length,
        );
        expect(p.progress, greaterThanOrEqualTo(previousProgress));
        previousProgress = p.progress;
        expect(p.duration, inInclusiveRange(180, 360));

        if (!p.sleeping && p.bugs.length > maxAwake) maxAwake = p.bugs.length;
      }

      expect(p.sleeping, isTrue, reason: 'seed=$seed sleep deadline');
      expect(
        p.frogs.every((f) => f.asleep && !f.airborne && !f.swimming),
        isTrue,
      );
      final positions = p.frogs.map((f) => [f.x, f.y, f.leafIndex]).toList();
      final elapsed = p.elapsed;
      final ai = p.aiEvaluations;
      final endpoint = p.daylight;
      for (var second = 0; second < 1800; second++) {
        gesture(p);
        p.update(1);
        maxShelter = max(maxShelter, p.insectShelter);
        checkGeometry(p, 'seed=$seed sleep+$second');
        expect(p.bugs.length, lessThanOrEqualTo(cap()));
        maximaByWeather.update(
          p.weather,
          (n) => n < p.bugs.length ? p.bugs.length : n,
          ifAbsent: () => p.bugs.length,
        );
        if (p.bugs.length > maxSleeping) maxSleeping = p.bugs.length;
        expect(p.sleeping, isTrue);
        expect(p.pressing, isFalse);
        expect(p.elapsed, elapsed);
        expect(p.aiEvaluations, ai);
        expect(p.daylight, endpoint);
        expect(p.frogs.map((f) => [f.x, f.y, f.leafIndex]).toList(), positions);
      }
    }
    // Print measured maxima even if a contract assertion below fails.
    // ignore: avoid_print
    print(
      'SOAK seeds=0..99 worlds=$worlds maxAwake=$maxAwake maxSleeping=$maxSleeping weatherMaxima=$maximaByWeather',
    );
    expect(worlds, {
      for (final w in ['clear', 'mist', 'drizzle', 'storm'])
        for (final c in ['dawn', 'dusk']) '$w/$c',
    });
    expect(
      maxAwake,
      lessThanOrEqualTo(18),
      reason: 'Maximum intended emergence density',
    );
    expect(
      maxSleeping,
      lessThanOrEqualTo(18),
      reason: '30-minute post-sleep list cap',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
