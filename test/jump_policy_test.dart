import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/jump_policy.dart';

void main() {
  test('exported Dart matches all five held-out JS parity cases', () {
    final manifest = jsonDecode(
      File('assets/policy/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(JumpPolicy.actions, ['tap', 'low', 'high']);
    expect(JumpPolicy.actions, manifest['actions']);
    final cases = manifest['parityCases'] as List<dynamic>;
    expect(cases, hasLength(5));
    for (final entry in cases) {
      final x = (entry['features'] as List)
          .cast<num>()
          .map((n) => n.toDouble())
          .toList();
      final expected = (entry['scores'] as List)
          .cast<num>()
          .map((n) => n.toDouble())
          .toList();
      final actual = JumpPolicy.scores(x);
      expect(actual, hasLength(3));
      for (var k = 0; k < 3; k++) {
        expect(actual[k], closeTo(expected[k], 1e-12));
        expect(actual[k].isFinite, isTrue);
        expect(actual[k], inInclusiveRange(0.0, 1.0));
      }
      expect(actual.reduce((a, b) => a + b), closeTo(1, 1e-12));
      var best = 0;
      for (var k = 1; k < 3; k++) {
        if (expected[k] > expected[best]) best = k;
      }
      expect(JumpPolicy.choose(x), JumpPolicy.actions[best]);
    }
  });

  test(
    'invalid features fall back to low; extreme finite input stays bounded',
    () {
      for (final x in <List<double>>[
        [],
        List.filled(7, 0),
        List.filled(9, 0),
        [double.nan, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, double.infinity, 0, 0, 0],
      ]) {
        expect(JumpPolicy.scores(x), [0, 1, 0]);
        expect(JumpPolicy.choose(x), 'low');
      }
      expect(
        JumpPolicy.suggest(
          frogX: double.nan,
          frogY: .7,
          bugX: .5,
          bugY: .4,
          bugVx: 0,
          bugVy: 0,
          energy: 1,
          wind: 0,
        ),
        'low',
      );
      final p = JumpPolicy.scores(List.filled(8, double.maxFinite));
      expect(p.every((x) => x.isFinite && x >= 0 && x <= 1), isTrue);
      expect(p.reduce((a, b) => a + b), closeTo(1, 1e-12));
    },
  );

  test('encoder uses documented normalized coordinate order', () {
    expect(
      JumpPolicy.encode(
        frogX: .75,
        frogY: .75,
        bugX: .4,
        bugY: .45,
        bugVx: .075,
        bugVy: -.04,
        energy: .75,
        wind: -.5,
      ),
      everyElement(isA<double>()),
    );
    final x = JumpPolicy.encode(
      frogX: .75,
      frogY: .75,
      bugX: .4,
      bugY: .45,
      bugVx: .075,
      bugVy: -.04,
      energy: .75,
      wind: -.5,
    );
    const expected = [.5, .5, -.5, .5, .5, -.5, .5, -.5];
    for (var i = 0; i < 8; i++) {
      expect(x[i], closeTo(expected[i], 1e-12));
    }
  });
}
