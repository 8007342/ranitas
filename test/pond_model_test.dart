import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ranitas/game/pond_model.dart';

void tap(PondModel model) {
  model.press();
  model.release();
}

void main() {
  test('scene seed preserves explicit seeds and stays stable without one', () {
    for (final seed in [0, 42, -7]) {
      final model = PondModel(seed: seed);
      expect(model.sceneSeed, seed);
      model.update(1);
      tap(model);
      model.update(1);
      expect(model.sceneSeed, seed);
    }
    final model = PondModel();
    final sceneSeed = model.sceneSeed;
    expect(sceneSeed, inInclusiveRange(0, (1 << 30) - 1));
    tap(model);
    model.update(2);
    expect(model.sceneSeed, sceneSeed);
  });

  test('waiting and cancelled gestures never start the timer or frogs', () {
    final model = PondModel(seed: 7);
    model.update(20);
    model.press();
    model.update(2);
    model.cancelPress();
    model.release();
    expect(model.started, isFalse);
    expect(model.elapsed, 0);
    expect(model.progress, 0);
    expect(model.aiEvaluations, 0);
    expect(model.bugs, isEmpty);
    for (final frog in model.frogs) {
      expect(frog.airborne, isFalse);
      expect(frog.x, frog.homeX);
      expect(frog.y, frog.homeY);
    }
  });

  test('hold boundaries choose predictable tap, low and high arcs', () {
    for (final entry in <double, String>{
      0: 'tap',
      .179: 'tap',
      .18: 'low',
      .649: 'low',
      .65: 'high',
    }.entries) {
      final model = PondModel(seed: 4);
      model.press();
      model.update(entry.key);
      model.press(); // Duplicate pointer down must not reset the hold.
      model.release();
      expect(model.frogs[0].action, entry.value);
      expect(model.started, isTrue);
      expect(model.elapsed, 0);
      model.update(1.4);
      expect(model.frogs[0].leafIndex, 1);
      final frog = model.frogs[0];
      final offset = sqrt(pow(frog.x - .685, 2) + pow(frog.y - .72, 2));
      expect(offset, inInclusiveRange(.005 - 1e-9, .015 + 1e-9));
    }
  });

  test(
    'seed and fixed steps reproduce trajectories across frame partitions',
    () {
      final a = PondModel(seed: 88);
      final b = PondModel(seed: 88);
      tap(a);
      tap(b);
      a.update(10);
      for (var i = 0; i < 600; i++) {
        b.update(1 / 60);
      }
      expect(a.elapsed, b.elapsed);
      expect(a.aiEvaluations, 40);
      expect(a.bugs.length, b.bugs.length);
      for (var i = 0; i < a.bugs.length; i++) {
        expect(a.bugs[i].x, b.bugs[i].x);
        expect(a.bugs[i].y, b.bugs[i].y);
      }
      for (var i = 0; i < 2; i++) {
        expect(a.frogs[i].x, b.frogs[i].x);
        expect(a.frogs[i].y, b.frogs[i].y);
      }
    },
  );

  test(
    'long chaotic play stays bounded and returns both frogs home to sleep',
    () {
      final model = PondModel(seed: 42, durationOverride: 45);
      tap(model);
      var previousProgress = 0.0;
      var sawTell = false;
      var sawGust = false;
      for (var i = 0; i < 3600; i++) {
        if (i % 7 == 0) tap(model);
        model.update(1 / 60);
        expect(model.progress, greaterThanOrEqualTo(previousProgress));
        previousProgress = model.progress;
        if (model.windTell > 0) sawTell = true;
        if (model.wind.abs() > .35) {
          expect(sawTell, isTrue);
          sawGust = true;
        }
        expect(
          model.frogs.where((f) => f.airborne || f.swimming).length,
          lessThanOrEqualTo(1),
        );
        final a = model.frogs[0];
        final b = model.frogs[1];
        expect(sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)), greaterThan(.025));
        for (final frog in model.frogs) {
          expect(frog.x, inInclusiveRange(0, 1));
          expect(frog.y, inInclusiveRange(0, 1));
          expect(frog.energy, inInclusiveRange(0, 1));
          expect(frog.asleep, model.sleeping);
        }
        for (final bug in model.bugs) {
          expect(bug.x, inInclusiveRange(0, 1));
          expect(bug.y, inInclusiveRange(0, 1));
          expect(bug.vx.isFinite && bug.vy.isFinite, isTrue);
        }
      }
      expect(sawGust, isTrue);
      expect(model.sleeping, isTrue);
      expect(model.progress, 1);
      for (final frog in model.frogs) {
        expect(frog.leafIndex, frog.index);
        expect(frog.x, closeTo(frog.homeX, .015));
        expect(frog.y, closeTo(frog.homeY, .015));
        expect(frog.swimming || frog.airborne, isFalse);
      }
      final elapsed = model.elapsed;
      tap(model);
      model.update(5);
      expect(model.elapsed, elapsed);
      expect(model.sleeping, isTrue);
    },
  );

  test(
    'species unlock with progression and fireflies belong to dusk/night',
    () {
      final model = List.generate(
        100,
        (seed) => PondModel(seed: seed, durationOverride: 20),
      ).firstWhere((m) => m.cycle == 'dusk' && m.weather == 'clear');
      expect(model.availableSpecies, ['fly', 'mosquito']);
      tap(model);
      model.update(8);
      expect(model.availableSpecies, containsAll(['dragonfly', 'butterfly']));
      expect(model.availableSpecies, isNot(contains('firefly')));
      model.update(4);
      expect(model.period, 'dusk');
      expect(model.availableSpecies, contains('firefly'));
      model.update(8);
      expect(model.period, 'night');
      expect(model.availableSpecies, isNot(contains('butterfly')));
      expect(model.availableSpecies, isNot(contains('ladybug')));
    },
  );

  test('normal duration stays bounded and unattended play finishes', () {
    final model = PondModel(seed: 2);
    tap(model);
    for (var i = 0; i < 370; i++) {
      model.update(1);
      expect(model.duration, inInclusiveRange(180, 360));
    }
    expect(model.sleeping, isTrue);
    expect(model.elapsed, inInclusiveRange(180, 360.02));
  });

  test('wind mishaps recover and do not prevent the ending across seeds', () {
    var swims = 0;
    for (var seed = 0; seed < 12; seed++) {
      final model = PondModel(seed: seed, durationOverride: 80);
      tap(model);
      for (var i = 0; i < 5400; i++) {
        if (i % 6 == 0) tap(model);
        model.update(1 / 60);
        if (model.frogs.any((f) => f.swimming)) swims++;
      }
      expect(model.sleeping, isTrue);
      expect(model.frogs.any((f) => f.swimming), isFalse);
    }
    expect(swims, greaterThan(0));
  });

  test('seeded scene choices cover the intended weights and remain stable', () {
    final biomes = <String>{};
    final weatherCounts = <String, int>{};
    var duskCount = 0;
    for (var seed = 0; seed < 1000; seed++) {
      final a = PondModel(seed: seed);
      final b = PondModel(seed: seed);
      expect([a.biome, a.weather, a.cycle], [b.biome, b.weather, b.cycle]);
      biomes.add(a.biome);
      weatherCounts.update(a.weather, (n) => n + 1, ifAbsent: () => 1);
      if (a.cycle == 'dusk') duskCount++;
    }
    expect(biomes, {'willow', 'blossom', 'cypress'});
    expect(weatherCounts.keys.toSet(), {'clear', 'mist', 'drizzle', 'storm'});
    expect(duskCount, inInclusiveRange(680, 820));
    expect(weatherCounts['clear']! + weatherCounts['mist']!, greaterThan(700));
    expect(weatherCounts['storm']!, lessThan(100));
  });

  test(
    'both cycles preserve the final scene indefinitely with sleeping frogs',
    () {
      for (final cycle in ['dawn', 'dusk']) {
        final model = List.generate(
          100,
          (seed) => PondModel(seed: seed, durationOverride: 20),
        ).firstWhere((m) => m.cycle == cycle && m.weather == 'clear');
        final weather = model.weather;
        expect(model.period, cycle == 'dawn' ? 'night' : 'day');
        expect(model.daylight, cycle == 'dawn' ? 0 : 1);
        tap(model);
        model.update(10);
        expect(model.period, cycle == 'dawn' ? 'dawn' : 'day');
        expect(model.daylight, closeTo(.5, 1e-9));
        if (cycle == 'dawn') {
          expect(model.availableSpecies, contains('firefly'));
          expect(model.availableSpecies, isNot(contains('butterfly')));
        }
        model.update(10);
        // Track the ending at frame resolution: entering sleep never teleports.
        while (!model.sleeping) {
          final positions = model.frogs.map((f) => [f.x, f.y]).toList();
          model.update(1 / 60);
          for (var i = 0; i < 2; i++) {
            final f = model.frogs[i];
            expect((f.x - positions[i][0]).abs(), lessThan(.03));
            expect((f.y - positions[i][1]).abs(), lessThan(.03));
          }
        }
        final positions = model.frogs.map((f) => [f.x, f.y]).toList();
        final phase = model.time;
        model.update(90);
        expect(model.time, greaterThan(phase));
        expect(model.period, cycle == 'dawn' ? 'day' : 'night');
        expect(model.daylight, cycle == 'dawn' ? 1 : 0);
        expect(model.weather, weather);
        expect(model.frogs.map((f) => [f.x, f.y]).toList(), positions);
        expect(
          model.frogs.every((f) => f.asleep && f.leafIndex == f.index),
          isTrue,
        );
        expect(model.bugs, isNotEmpty);
        if (cycle == 'dawn') {
          expect(model.bugs.any((b) => b.species == 'firefly'), isFalse);
        } else {
          expect(
            model.bugs.every(
              (b) => ['firefly', 'mosquito'].contains(b.species),
            ),
            isTrue,
          );
        }
      }
    },
  );

  test('insects emerge gradually only after release and respect rain', () {
    for (final weather in ['clear', 'mist', 'drizzle', 'storm']) {
      final model = List.generate(
        1000,
        (seed) => PondModel(seed: seed, durationOverride: 30),
      ).firstWhere((m) => m.weather == weather);
      model.update(100);
      expect(model.bugs, isEmpty);
      model.press();
      model.update(3);
      expect(model.bugs, isEmpty);
      model.release();
      expect(model.bugs, isEmpty);
      model.update(.81);
      expect(model.bugs.length, 1);
      expect(model.bugs.first.opacity, lessThan(.1));
      model.update(10);
      expect(model.bugs.length, lessThanOrEqualTo(7));
      if (weather == 'storm' || weather == 'drizzle') {
        expect(model.availableSpecies, isNot(contains('butterfly')));
        expect(model.availableSpecies, isNot(contains('firefly')));
        expect(
          model.bugs.every((b) => ['fly', 'mosquito'].contains(b.species)),
          isTrue,
        );
      }
      if (weather == 'storm') {
        expect(model.bugs.length, lessThanOrEqualTo(3));
      }
    }
  });

  test('landing variance is seeded, continuous, and stays on the pad', () {
    final offsets = <double>{};
    for (var seed = 0; seed < 30; seed++) {
      final model = PondModel(seed: seed);
      tap(model);
      final frog = model.frogs[0];
      while (frog.airborne) {
        final x = frog.x;
        final y = frog.y;
        model.update(1 / 60);
        expect((frog.x - x).abs(), lessThan(.02));
        expect((frog.y - y).abs(), lessThan(.02));
      }
      final radius = sqrt(pow(frog.x - .685, 2) + pow(frog.y - .72, 2));
      expect(radius, inInclusiveRange(.005 - 1e-9, .015 + 1e-9));
      offsets.add(radius);
    }
    expect(offsets.length, 30);
  });

  test('rejects invalid deltas and overrides without corrupting state', () {
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => PondModel(durationOverride: value), throwsArgumentError);
    }
    final model = PondModel();
    for (final value in [-1.0, double.nan, double.infinity]) {
      expect(() => model.update(value), throwsArgumentError);
    }
    model.update(0);
    expect(model.time, 0);
  });
}
