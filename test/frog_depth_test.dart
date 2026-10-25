import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/pond_model.dart';

/// Frog depth motion (openspec/changes/visual-envelope/specs/frog-depth-motion).
void main() {
  test('view buckets: side within 35° of horizontal, away up, toward down', () {
    expect(FrogState.viewFor(100, 0), 'side');
    expect(FrogState.viewFor(-100, 0), 'side');
    // 2.5× depth weighting: 20 px of rise over 100 px is already 26.6°, 30 px is 36.9°.
    expect(FrogState.viewFor(100, -20), 'side');
    expect(FrogState.viewFor(100, -30), 'away');
    expect(FrogState.viewFor(100, 30), 'toward');
    expect(FrogState.viewFor(-100, -30), 'away');
    expect(FrogState.viewFor(-100, 30), 'toward');
    expect(FrogState.viewFor(0, -10), 'away');
    expect(FrogState.viewFor(0, 10), 'toward');
    // 143° is still a turned view; 146° (27 px of rise) is a side view again.
    expect(FrogState.viewFor(-100, -30), 'away');
    expect(FrogState.viewFor(-100, -27), 'side');
    expect(FrogState.viewFor(-100, -20), 'side');
  });

  test('view poses extend the 10 side states without breaking them', () {
    final frog = FrogState(0, .3, .7);
    for (final pose in [
      'idle',
      'charging',
      'landing',
      'launching',
      'ascending',
      'chomping',
      'falling',
      'swallowing',
      'sleeping',
      'swimming',
    ]) {
      expect(frog.viewPose(pose), pose);
    }
    frog.view = 'away';
    expect(frog.viewPose('launching'), 'away_launch');
    expect(frog.viewPose('ascending'), 'away_ascend');
    expect(frog.viewPose('falling'), 'away_fall');
    expect(frog.viewPose('chomping'), 'away_fall');
    expect(frog.viewPose('landing'), 'back_idle');
    expect(frog.viewPose('idle'), 'idle');
    expect(frog.viewPose('sleeping'), 'sleeping');
    frog.view = 'toward';
    expect(frog.viewPose('launching'), 'toward_launch');
    expect(frog.viewPose('ascending'), 'toward_ascend');
    expect(frog.viewPose('falling'), 'toward_fall');
    expect(frog.viewPose('chomping'), 'toward_chomp');
    expect(frog.viewPose('landing'), 'landing');
  });

  test('frog scale is quantised perspective at the ground point', () {
    final m = PondModel(seed: 4);
    for (final frog in m.frogs) {
      final s = m.frogScale(frog);
      expect(s * 16, (s * 16).roundToDouble());
      expect(s, closeTo(m.perspectiveAt(frog.y * 359), 1 / 32 + 1e-9));
      expect(s, inInclusiveRange(.5, 1.0625));
    }
  });

  test('jumping away shrinks monotonically and lands at the target scale; duration is unchanged', () {
    var away = 0;
    var toward = 0;
    for (var seed = 0; seed < 300 && (away < 5 || toward < 5); seed++) {
      final m = PondModel(seed: seed);
      final frog = m.frogs[0];
      m.press();
      m.release();
      if (frog.view == 'side') continue;
      final farther = m.pads[1].y < m.pads[0].y;
      expect(frog.view, farther ? 'away' : 'toward');
      if (farther) {
        away++;
      } else {
        toward++;
      }
      var previous = m.frogScale(frog);
      var frames = 0;
      while (frog.airborne) {
        m.update(1 / 60);
        frames++;
        final s = m.frogScale(frog);
        if (farther) {
          expect(s, lessThanOrEqualTo(previous), reason: 'seed=$seed');
        } else {
          expect(s, greaterThanOrEqualTo(previous), reason: 'seed=$seed');
        }
        previous = s;
      }
      // Tap flights last 0.68 s whatever the depth change.
      expect(frames, inInclusiveRange(40, 42));
      // Landed at the target pad's scale (the perch sits up to 5 px off centre).
      expect(
        m.frogScale(frog),
        closeTo(m.perspectiveAt(m.pads[1].y * 359), 1 / 16 + .03),
      );
      expect(m.frogScale(frog), closeTo(m.perspectiveAt(frog.y * 359), 1 / 32 + 1e-9));
    }
    expect(away, greaterThanOrEqualTo(5));
    expect(toward, greaterThanOrEqualTo(5));
  });

  test('arc height follows the perspective of the ground point', () {
    // A tap arc peaks at 0.13 × perspective(ground y) for frog 0, so flights at
    // different depths peak at different heights while lasting the same time.
    var lowest = double.infinity;
    var highest = 0.0;
    for (var seed = 0; seed < 60; seed++) {
      final m = PondModel(seed: seed);
      m.press();
      m.release();
      final frog = m.frogs[0];
      var peak = 0.0;
      var groundAtPeak = 0.0;
      while (frog.airborne) {
        m.update(1 / 60);
        if (frog.altitude > peak) {
          peak = frog.altitude;
          groundAtPeak = frog.groundY;
        }
      }
      expect(peak, closeTo(.13 * m.perspectiveAt(groundAtPeak * 359), .002));
      if (peak < lowest) lowest = peak;
      if (peak > highest) highest = peak;
    }
    expect(lowest / highest, lessThan(.92));
  });
}
