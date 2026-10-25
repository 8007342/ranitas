import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/insect_species.dart';
import 'package:ranitas/game/pond_model.dart';
import 'package:ranitas/game/pond_renderer.dart';
import 'package:ranitas/game/rain_envelope.dart';
import 'package:ranitas/game/scene_grade.dart';

Future<ui.Image> _loadAssetImage(String relativePath) async {
  final bytes = await rootBundle.load(relativePath);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

PondModel _firstWith(bool Function(PondModel m) where, {int seeds = 2000}) =>
    List.generate(
      seeds,
      (seed) => PondModel(seed: seed, durationOverride: 20),
    ).firstWhere(where);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rain intensity envelope (D1)', () {
    test('storm and drizzle stay in their bands and move slowly', () {
      for (var seed = 0; seed < 60; seed++) {
        for (final kind in ['storm', 'drizzle']) {
          final env = RainEnvelope(seed: seed, weather: kind);
          var previous = env.at(0);
          var lowest = previous;
          var highest = previous;
          var hadDownpour = previous > .85;
          for (var i = 1; i <= 360 * 60; i++) {
            final v = env.at(i / 60);
            expect(v, inInclusiveRange(0.0, 1.0));
            expect(
              (v - previous).abs(),
              lessThanOrEqualTo(.05 / 60 + 1e-9),
              reason: '$kind seed=$seed t=${i / 60}',
            );
            previous = v;
            lowest = min(lowest, v);
            highest = max(highest, v);
            if (v > .85) hadDownpour = true;
          }
          expect(lowest, greaterThanOrEqualTo(RainEnvelope.lullMin - 1e-9));
          if (kind == 'storm') {
            expect(
              highest - lowest,
              greaterThanOrEqualTo(.4),
              reason: 'storm seed=$seed span',
            );
            expect(hadDownpour, isTrue, reason: 'storm seed=$seed downpour');
          } else {
            expect(highest, lessThanOrEqualTo(.55 + 1e-9));
          }
        }
      }
    });

    test('clear sessions are dry; mist only sheds fine fog drizzle', () {
      final clear = RainEnvelope(seed: 7, weather: 'clear');
      expect(clear.isDry, isTrue);
      for (var t = 0.0; t < 600; t += 7.3) {
        expect(clear.at(t), 0);
      }
      final fog = RainEnvelope(seed: 7, weather: 'mist');
      for (var t = 0.0; t < 600; t += 7.3) {
        expect(fog.at(t), lessThanOrEqualTo(RainEnvelope.fogDrizzleMax));
      }
      // Fog thickens toward night and only thick fog drizzles.
      expect(RainEnvelope.mistDensityFor(1), lessThan(RainEnvelope.mistDensityFor(0)));
      expect(RainEnvelope.fogDrizzleGate(RainEnvelope.mistDensityFor(1)), 0);
      expect(RainEnvelope.fogDrizzleGate(RainEnvelope.mistDensityFor(0)), 1);
      final dry = _firstWith((m) => m.weather == 'clear');
      dry.press();
      dry.release();
      dry.update(30);
      expect(dry.rainIntensity, 0);
      expect(dry.raindrops, isEmpty);
      expect(dry.cloudDarkening, 0);
      expect(dry.insectShelter, 1);
    });

    test('a seed reproduces the envelope across update partitions', () {
      final a = RainEnvelope(seed: 99, weather: 'storm');
      final b = RainEnvelope(seed: 99, weather: 'storm');
      // Sample b far ahead first, then compare at the same times.
      b.at(1700);
      for (var t = 0.0; t < 1800; t += 2.37) {
        expect(a.at(t), b.at(t));
      }
      final m1 = _firstWith((m) => m.weather == 'storm');
      final m2 = PondModel(seed: m1.sceneSeed, durationOverride: 20);
      for (var i = 0; i < 100; i++) {
        m1.update(1 / 60);
      }
      for (var i = 0; i < 5; i++) {
        m2.update(20 / 60);
      }
      expect(m1.rainIntensity, closeTo(m2.rainIntensity, 1e-9));
      expect(m1.weather, 'storm');
      expect(m1.raindrops, isNotEmpty);
    });

    test('derived quantities follow intensity', () {
      expect(RainEnvelope.shelterFor(0), 1);
      expect(RainEnvelope.shelterFor(.3), closeTo(.55, 1e-9));
      expect(RainEnvelope.shelterFor(1), closeTo(.25, 1e-9));
      expect(RainEnvelope.shelterFor(.15), greaterThan(.55));
      expect(RainEnvelope.cloudFor(0), 0);
      expect(RainEnvelope.cloudFor(1), 1);
      expect(RainEnvelope.audioLabel('clear', .9), 'clear');
      expect(RainEnvelope.audioLabel('storm', .3), 'drizzle');
      expect(RainEnvelope.audioLabel('storm', .8), 'storm');
      expect(RainEnvelope.audioLabel('drizzle', .5), 'drizzle');
    });
  });

  group('insect species table (D2)', () {
    test('every biome has a night set and only its own species', () {
      const expected = {
        'willow': {'firefly', 'mayfly'},
        'blossom': {'mayfly'},
        'cypress': {'firefly'},
        'maple': {'moth'},
        'sanctuary': {'moth'},
        'grotto': {'glowbeetle'},
        'alpine': {'firefly', 'moth'},
        'lotus': {'firefly', 'mayfly'},
        'firefly': {'firefly'},
        'autumn_mist': {'moth'},
        'jade_sanctuary': {'moth'},
        'crystal_grotto': {'glowbeetle'},
      };
      for (final biome in PondModel.biomes) {
        final dusk = HabitatContext(
          biome: biome,
          daylight: .4,
          progress: .6,
          period: 'dusk',
          cycle: 'dusk',
          weather: 'clear',
          rainIntensity: 0,
        );
        final night = HabitatContext(
          biome: biome,
          daylight: 0,
          progress: 1,
          period: 'night',
          cycle: 'dusk',
          weather: 'mist',
          rainIntensity: 0,
        );
        final noon = HabitatContext(
          biome: biome,
          daylight: 1,
          progress: 0,
          period: 'day',
          cycle: 'dusk',
          weather: 'clear',
          rainIntensity: 0,
        );
        final rain = HabitatContext(
          biome: biome,
          daylight: 0,
          progress: 1,
          period: 'night',
          cycle: 'dusk',
          weather: 'drizzle',
          rainIntensity: .3,
        );
        Set<String> nightAt(HabitatContext c) => {
          for (final s in InsectSpecies.table)
            if (s.night && s.habitat(c)) s.name,
        };
        expect(nightAt(dusk), expected[biome], reason: '$biome at dusk');
        expect(
          nightAt(night),
          biome == 'willow' ? {'firefly'} : expected[biome],
          reason: '$biome at night (willow mayflies are dusk only)',
        );
        expect(nightAt(noon), isEmpty, reason: '$biome at noon');
        expect(nightAt(rain), isEmpty, reason: '$biome in rain');
        expect(
          InsectSpecies.nightSetFor(biome).toSet(),
          expected[biome],
          reason: '$biome declared set',
        );
      }
    });

    test('grotto glow beetles emerge and no fireflies; sanctuary moths', () {
      final grotto = _firstWith(
        (m) =>
            m.biome == 'grotto' && m.cycle == 'dusk' && m.weather == 'clear',
      );
      grotto.press();
      grotto.release();
      grotto.update(20);
      expect(grotto.daylight, 0);
      expect(grotto.availableSpecies, contains('glowbeetle'));
      expect(grotto.availableSpecies, isNot(contains('firefly')));
      grotto.update(60);
      expect(grotto.bugs.any((b) => b.species == 'glowbeetle'), isTrue);
      expect(grotto.bugs.any((b) => b.species == 'firefly'), isFalse);

      final sanctuary = _firstWith(
        (m) =>
            m.biome == 'sanctuary' &&
            m.cycle == 'dusk' &&
            (m.weather == 'clear' || m.weather == 'mist'),
      );
      sanctuary.press();
      sanctuary.release();
      sanctuary.update(13);
      expect(sanctuary.period, 'dusk');
      expect(sanctuary.availableSpecies, contains('moth'));
      sanctuary.update(80);
      final moths = sanctuary.bugs.where((b) => b.species == 'moth').toList();
      expect(moths, isNotEmpty);
      final lantern = InsectSpecies.lightSourceFor('sanctuary')!;
      final mean =
          moths
              .map(
                (b) => sqrt(
                  pow(b.x - lantern.$1, 2) + pow(b.y - lantern.$2, 2),
                ),
              )
              .reduce((a, b) => a + b) /
          moths.length;
      expect(mean, lessThan(.3), reason: 'moths favour the lantern airspace');
    });

    test('mayflies stay low over the water and day rules are unchanged', () {
      final lotus = _firstWith(
        (m) => m.biome == 'lotus' && m.cycle == 'dusk' && m.weather == 'clear',
      );
      expect(lotus.availableSpecies, ['fly', 'mosquito']);
      lotus.press();
      lotus.release();
      lotus.update(8);
      expect(lotus.availableSpecies, containsAll(['dragonfly', 'butterfly']));
      lotus.update(12);
      for (var i = 0; i < 90; i++) {
        lotus.update(1);
        for (final b in lotus.bugs.where((b) => b.species == 'mayfly')) {
          expect(b.y, lessThanOrEqualTo(.72));
          expect(b.y, greaterThanOrEqualTo(.12));
        }
      }
      expect(lotus.bugs.any((b) => b.species == 'mayfly'), isTrue);
      final mayflyY = lotus.bugs
          .where((b) => b.species == 'mayfly')
          .map((b) => b.y)
          .reduce((a, b) => a + b);
      final count = lotus.bugs.where((b) => b.species == 'mayfly').length;
      expect(mayflyY / count, greaterThan(.45));
    });
  });

  group('time-of-day grade (D3)', () {
    test('day is the identity and the grade warms then darkens', () {
      final day = SceneGrade.matrixFor(daylight: 1, biome: 'willow');
      expect(SceneGrade.isIdentity(day), isTrue);
      final sunset = SceneGrade.matrixFor(daylight: .6, biome: 'willow');
      final grey = SceneGrade.apply(sunset, (128, 128, 128));
      expect(grey.$1, greaterThan(grey.$2));
      expect(grey.$2, greaterThan(grey.$3));
      final night = SceneGrade.matrixFor(daylight: 0, biome: 'willow');
      final cool = SceneGrade.apply(night, (128, 128, 128));
      expect(cool.$3, greaterThan(cool.$1));
    });

    test('mean luminance falls monotonically and smoothly after sunset', () {
      for (final biome in PondModel.biomes) {
        final dayLum = SceneGrade.meanLuminance(
          SceneGrade.matrixFor(daylight: 1, biome: biome),
        );
        var previous = dayLum;
        // 1/60 s steps over a 180 s dusk are at most 1/10800 daylight apart;
        // sample 2000 steps so each is a sizeable fraction of that budget.
        for (var i = 1; i <= 2000; i++) {
          final d = 1 - i / 2000;
          final lum = SceneGrade.meanLuminance(
            SceneGrade.matrixFor(daylight: d, biome: biome),
          );
          if (d <= SceneGrade.sunsetAt) {
            expect(lum, lessThanOrEqualTo(previous + 1e-9), reason: '$biome $d');
          }
          expect((lum - previous).abs(), lessThan(.01), reason: '$biome $d');
          previous = lum;
        }
        // Night lands near the old flat wash, which kept about half of the
        // daylight luminance on a mid-grey.
        expect(previous / dayLum, inInclusiveRange(.40, .60), reason: biome);
      }
    });

    test('biome night keys differ and clouds darken further', () {
      final indigo = SceneGrade.apply(
        SceneGrade.matrixFor(daylight: 0, biome: 'willow'),
        (160, 160, 160),
      );
      final teal = SceneGrade.apply(
        SceneGrade.matrixFor(daylight: 0, biome: 'grotto'),
        (160, 160, 160),
      );
      final warm = SceneGrade.apply(
        SceneGrade.matrixFor(daylight: 0, biome: 'sanctuary'),
        (160, 160, 160),
      );
      expect(teal.$2, greaterThan(indigo.$2));
      expect(warm.$1, greaterThan(indigo.$1));
      final clear = SceneGrade.meanLuminance(
        SceneGrade.matrixFor(daylight: .8, biome: 'maple'),
      );
      final cloudy = SceneGrade.meanLuminance(
        SceneGrade.matrixFor(daylight: .8, biome: 'maple', cloud: 1),
      );
      expect(cloudy, lessThan(clear * .8));
      final storm = _firstWith((m) => m.weather == 'storm');
      expect(SceneGrade.filterFor(storm), isNotNull);
      final noon = _firstWith(
        (m) => m.weather == 'clear' && m.cycle == 'dusk',
      );
      expect(SceneGrade.filterFor(noon), isNull);
    });
  });

  test('emissive masks exist for the lit backdrops and render at night', () async {
    final out = Directory('build/scene-checks')..createSync(recursive: true);
    for (final biome in ['grotto', 'sanctuary']) {
      final probe = _firstWith(
        (m) => m.biome == biome && m.cycle == 'dusk' && m.weather == 'clear',
      );
      final backdrop = await _loadAssetImage(
        'assets/images/${probe.backdropAsset}',
      );
      final maskName = 'emissive-${probe.backdropAsset}';
      final mask = await _loadAssetImage('assets/images/$maskName');
      expect(mask.width, 2752);
      expect(mask.height, 1536);
      final renderer = PondRenderer()
        ..backdrop = backdrop
        ..emissive = mask;
      probe.press();
      probe.release();
      probe.update(25);
      expect(probe.daylight, 0);
      expect(probe.richness, 1);
      final recorder = ui.PictureRecorder();
      renderer.render(ui.Canvas(recorder), const ui.Size(641, 359), probe);
      final picture = recorder.endRecording();
      final image = await picture.toImage(641, 359);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(png, isNotNull);
      File('${out.path}/$biome-emissive-night.png').writeAsBytesSync(
        png!.buffer.asUint8List(),
      );
      image.dispose();
      picture.dispose();
      renderer.dispose();
      mask.dispose();
      backdrop.dispose();
    }
  });
}
