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

PondModel _firstWith(bool Function(PondModel m) where, {int seeds = 2000}) {
  for (var seed = 0; seed < seeds; seed++) {
    final model = PondModel(seed: seed, durationOverride: 20);
    if (where(model)) return model;
  }
  throw StateError('no seed below $seeds matched');
}

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
        'cypress': {'firefly', 'katydid'},
        'maple': {'moth', 'cricket'},
        'sanctuary': {'moth'},
        'grotto': {'glowbeetle'},
        'alpine': {'firefly', 'moth'},
        'lotus': {'firefly', 'mayfly'},
        'firefly': {'firefly', 'katydid'},
        'autumn_mist': {'moth', 'cricket'},
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

  group('signature insects per scenery (D2)', () {
    // A broad sweep of light and weather so "never appears" means never.
    final contexts = <String, List<HabitatContext>>{
      for (final biome in PondModel.biomes)
        biome: [
          for (final weather in ['clear', 'mist', 'drizzle', 'storm'])
            for (final rain in [0.0, .1, .3, .6, .95])
              for (final (daylight, progress, period, cycle) in [
                (1.0, 0.0, 'day', 'dusk'),
                (1.0, .3, 'day', 'dusk'),
                (.8, .5, 'day', 'dusk'),
                (.4, .6, 'dusk', 'dusk'),
                (.1, .9, 'night', 'dusk'),
                (0.0, 1.0, 'night', 'dusk'),
                (0.0, 0.0, 'night', 'dawn'),
                (.5, .5, 'dawn', 'dawn'),
                (.7, .7, 'dawn', 'dawn'),
                (1.0, 1.0, 'day', 'dawn'),
              ])
                HabitatContext(
                  biome: biome,
                  daylight: daylight,
                  progress: progress,
                  period: period,
                  cycle: cycle,
                  weather: weather,
                  rainIntensity: weather == 'clear' ? 0 : rain,
                ),
        ],
    };
    Set<String> everAvailable(String biome, String species) => {
      for (final c in contexts[biome]!)
        if (InsectSpecies.byName[species]!.habitat(c)) biome,
    };

    test('every biome has one or two signature species of its own', () {
      for (final biome in PondModel.biomes) {
        final signature = InsectSpecies.signatureFor(biome);
        expect(signature, isNotEmpty, reason: biome);
        // Each signature species of a biome actually shows up there…
        for (final s in signature) {
          expect(everAvailable(biome, s), {biome}, reason: '$s in $biome');
        }
        // …and at least one of them is found in no more than three sceneries.
        expect(
          signature.any((s) => InsectSpecies.biomesOf(s).length <= 3),
          isTrue,
          reason: '$biome needs a species rare to it: $signature',
        );
      }
    });

    test('signature species never appear outside their sceneries', () {
      for (final species in InsectSpecies.signatureNames) {
        final home = InsectSpecies.biomesOf(species);
        expect(home.length, lessThan(PondModel.biomes.length), reason: species);
        for (final biome in PondModel.biomes) {
          expect(
            everAvailable(biome, species),
            home.contains(biome) ? {biome} : <String>{},
            reason: '$species in $biome',
          );
        }
      }
      // Truly unique to one scenery.
      expect(InsectSpecies.biomesOf('stonefly'), {'alpine'});
      expect(InsectSpecies.biomesOf('jewelbeetle'), {'jade_sanctuary'});
      expect(InsectSpecies.biomesOf('fungusgnat'), {'crystal_grotto'});
    });

    test('common species stay away from sceneries they do not suit', () {
      for (final biome in ['alpine', 'grotto', 'crystal_grotto']) {
        expect(everAvailable(biome, 'mosquito'), isEmpty, reason: biome);
      }
      for (final biome in ['grotto', 'crystal_grotto', 'autumn_mist']) {
        expect(everAvailable(biome, 'butterfly'), isEmpty, reason: biome);
      }
      for (final biome in ['grotto', 'crystal_grotto']) {
        expect(everAvailable(biome, 'dragonfly'), isEmpty, reason: biome);
      }
      for (final biome in ['cypress', 'firefly', 'lotus', 'grotto']) {
        expect(everAvailable(biome, 'ladybug'), isEmpty, reason: biome);
      }
      // The baseline survives where it fits.
      expect(everAvailable('willow', 'mosquito'), {'willow'});
      expect(everAvailable('blossom', 'butterfly'), {'blossom'});
      expect(everAvailable('lotus', 'dragonfly'), {'lotus'});
    });

    test('every scenery keeps at least one species in every weather and hour', () {
      for (final biome in PondModel.biomes) {
        for (final c in contexts[biome]!) {
          final available = [
            for (final s in InsectSpecies.table)
              if (s.habitat(c)) s.name,
          ];
          expect(
            available,
            isNotEmpty,
            reason: '$biome ${c.weather} ${c.rainIntensity} ${c.period}',
          );
        }
      }
    });

    test('voiced species are declared and the presence string is compact', () {
      for (final name in InsectSpecies.voicedNames) {
        expect(InsectSpecies.byName[name]!.voice, name);
      }
      for (final s in InsectSpecies.table) {
        if (s.voice != null) expect(InsectSpecies.voicedNames, contains(s.voice));
      }
      final maple = _firstWith(
        (m) => m.biome == 'maple' && m.cycle == 'dusk' && m.weather == 'clear',
      );
      maple.press();
      maple.release();
      maple.update(5);
      // Daylight: cicadas may sing, crickets may not.
      expect(maple.availableSpecies, contains('cicada'));
      expect(maple.availableSpecies, isNot(contains('cricket')));
      maple.update(90);
      expect(maple.daylight, 0);
      expect(maple.availableSpecies, contains('cricket'));
      expect(maple.bugs.any((b) => b.species == 'cricket'), isTrue);
      final presence = maple.speciesPresence;
      expect(presence, matches(RegExp(r'^([a-z]+:\d+)(,[a-z]+:\d+)*$')));
      expect(presence, contains('cricket:'));
      expect(presence, isNot(contains('cicada:')));
      for (final part in presence.split(',')) {
        final count = int.parse(part.split(':')[1]);
        expect(
          count,
          maple.bugs
              .where(
                (b) =>
                    b.alive &&
                    b.opacity >= .25 &&
                    InsectSpecies.byName[b.species]!.voice == part.split(':')[0],
              )
              .length,
        );
      }
      final willow = _firstWith(
        (m) => m.biome == 'willow' && m.cycle == 'dusk' && m.weather == 'clear',
      );
      willow.press();
      willow.release();
      willow.update(40);
      expect(willow.speciesPresence, isEmpty, reason: 'willow has no singers');
    });

    test('skaters keep to the water surface and residents fly in storms', () {
      // Long afternoons across several lotus ponds, so the claim does not
      // hinge on one seed's spawn luck.
      var lotusPonds = 0;
      var withStriders = 0;
      for (var seed = 0; seed < 4000 && lotusPonds < 6; seed++) {
        final probe = PondModel(seed: seed, durationOverride: 120);
        if (probe.biome != 'lotus' ||
            probe.cycle != 'dusk' ||
            probe.weather != 'clear') {
          continue;
        }
        lotusPonds++;
        probe.press();
        probe.release();
        probe.update(6);
        var sawStrider = false;
        for (var i = 0; i < 60; i++) {
          probe.update(1);
          for (final b in probe.bugs.where((b) => b.species == 'waterstrider')) {
            sawStrider = true;
            if (b.opacity < 1) continue;
            expect(b.y, greaterThan(.5), reason: 'striders stay on the water');
            expect(b.y, lessThanOrEqualTo(.72));
          }
        }
        if (sawStrider) withStriders++;
      }
      expect(lotusPonds, 6);
      expect(withStriders, greaterThanOrEqualTo(3),
          reason: 'striders arrive in most lotus afternoons');

      final alpine = _firstWith(
        (m) => m.biome == 'alpine' && m.weather == 'storm',
        seeds: 6000,
      );
      alpine.press();
      alpine.release();
      alpine.update(60);
      expect(alpine.availableSpecies, isNot(contains('mosquito')));
      expect(alpine.availableSpecies, contains('stonefly'));
      expect(alpine.bugs.any((b) => b.species == 'stonefly'), isTrue);

      final grotto = _firstWith(
        (m) => m.biome == 'grotto' && m.weather == 'storm',
        seeds: 6000,
      );
      grotto.press();
      grotto.release();
      grotto.update(60);
      expect(grotto.availableSpecies, contains('cavecricket'));
      expect(grotto.bugs, isNotEmpty);
    });

    test('signature biomes stay deterministic across update partitions', () {
      for (final biome in ['alpine', 'crystal_grotto', 'cypress', 'blossom']) {
        final seed = List.generate(
          3000,
          (s) => s,
        ).firstWhere((s) => PondModel(seed: s, durationOverride: 20).biome == biome);
        final a = PondModel(seed: seed, durationOverride: 20);
        final b = PondModel(seed: seed, durationOverride: 20);
        for (final m in [a, b]) {
          m.press();
          m.release();
        }
        for (var second = 0; second < 40; second++) {
          a.update(1);
          for (var frame = 0; frame < 60; frame++) {
            b.update(1 / 60);
          }
          List<Object> bugsOf(PondModel m) => [
            for (final bug in m.bugs)
              [bug.species, bug.x, bug.y, bug.vx, bug.vy, bug.opacity],
          ];
          expect(bugsOf(a), bugsOf(b), reason: '$biome second=$second');
          expect(a.speciesPresence, b.speciesPresence);
        }
        expect(a.bugs, isNotEmpty);
      }
    });

    test('every species renders as a procedural sprite', () async {
      final model = _firstWith((m) => m.biome == 'willow');
      model.press();
      model.release();
      model.update(2);
      model.bugs.clear();
      var i = 0;
      for (final s in InsectSpecies.table) {
        for (final variant in [0, 1]) {
          model.bugs.add(
            BugState(
              x: .1 + (i % 8) * .11,
              y: .2 + (i ~/ 8) * .1,
              vx: 0,
              vy: 0,
              phase: i * .7,
              species: s.name,
              variant: variant,
            ),
          );
          i++;
        }
      }
      final renderer = PondRenderer();
      final recorder = ui.PictureRecorder();
      renderer.render(ui.Canvas(recorder), const ui.Size(641, 359), model);
      final picture = recorder.endRecording();
      final image = await picture.toImage(641, 359);
      expect(image.width, 641);
      image.dispose();
      picture.dispose();
      renderer.dispose();
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
