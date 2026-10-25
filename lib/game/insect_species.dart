/// Insect species table (design D2 of the visual-envelope change).
///
/// Day species keep the original artful habitat rules. Night sets are keyed on
/// continuous `daylight` so they fade in and out with the light rather than at
/// period boundaries. Each biome also owns one or two *signature* species that
/// appear only there (or in a few related sceneries), and some common species
/// stay away from sceneries they do not suit. Every species is catchable. The
/// habitat rules are artistic impressions drawn from general natural history;
/// none of this is biological validation.
library;

/// What a habitat predicate may look at. Built by `PondModel` each query.
class HabitatContext {
  const HabitatContext({
    required this.biome,
    required this.daylight,
    required this.progress,
    required this.period,
    required this.cycle,
    required this.weather,
    required this.rainIntensity,
  });

  final String biome;
  final double daylight;
  final double progress;
  final String period;
  final String cycle;
  final String weather;
  final double rainIntensity;

  /// Fog drizzle is too fine to ground insects; only real rain does.
  bool get dry =>
      weather == 'clear' || (weather == 'mist' && rainIntensity < .2);

  /// Light rain: surface skaters and damp-loving species keep flying until
  /// the rain gets heavy (intensity 0.5 and above).
  bool get notPouring => dry || rainIntensity < .5;

  /// The original daytime predicate, unchanged.
  bool get light => period == 'day' || (period == 'dawn' && progress >= .55);

  /// Night sets appear below this daylight (dusk begins at 0.45 in a dusk
  /// cycle; a dawn cycle still carries them at daylight 0.5).
  static const double nightThreshold = .56;
  bool get dim => daylight < nightThreshold;

  /// Warm part of the day: full day into early dusk (cicada hours).
  bool get warm => daylight >= .3 && progress >= .1;

  bool get cave => InsectSpecies.caveBiomes.contains(biome);
}

class InsectSpecies {
  const InsectSpecies({
    required this.name,
    required this.speed,
    required this.wingRate,
    required this.flight,
    required this.altitude,
    required this.habitat,
    this.glow,
    this.bob = .008,
    this.turn = 1.8,
    this.vertical = .55,
    this.lightSeeking = false,
    this.maxY = .65,
    this.spawnInBand = false,
    this.voice,
  });

  final String name;

  /// Cruise speed in normalised screen widths per second.
  final double speed;

  /// Phase advance per second; the renderer flaps on it.
  final double wingRate;

  /// `cruise`, `hover`, `flutter`, `drift`, `bob`, `glide`, `skate`, `hop`
  /// or `swarm`. Descriptive; the motion itself comes from the numbers below.
  final String flight;

  /// Soft altitude band (normalised y) the insect is steered back into.
  final (double, double) altitude;

  /// Glow colour (ARGB) for luminous species, or null.
  final int? glow;

  /// Vertical bobbing amplitude added to the target velocity.
  final double bob;

  /// Random-turn gain.
  final double turn;

  /// Share of the heading's vertical component that becomes climb or dive.
  /// Surface skaters keep this near zero so they stay on the water.
  final double vertical;

  /// Moths: steer toward the biome's light source when it has one.
  final bool lightSeeking;

  /// Hard lower screen bound (mayflies may dance just above the water).
  final double maxY;

  /// Spawn inside the altitude band rather than the generic 0.2–0.6 airspace.
  /// Night sets and all signature species do; the original day species keep
  /// their old spawn heights.
  final bool spawnInBand;

  /// Ambient voice name in `web/ambience.js`, or null for a silent species.
  /// The voice plays only while the species is present on screen.
  final String? voice;

  final bool Function(HabitatContext c) habitat;

  bool get night => nightNames.contains(name);

  /// Table order matters: the original day species first so
  /// `availableSpecies` keeps its documented `['fly', 'mosquito']` opening in
  /// the sceneries that have mosquitoes; then the night sets; then the
  /// signature species in biome order.
  static const List<InsectSpecies> table = [
    InsectSpecies(
      name: 'fly',
      speed: .07,
      wingRate: 5,
      flight: 'cruise',
      altitude: (.22, .58),
      habitat: _fly,
    ),
    InsectSpecies(
      name: 'mosquito',
      speed: .07,
      wingRate: 13,
      flight: 'cruise',
      altitude: (.22, .58),
      habitat: _mosquito,
    ),
    InsectSpecies(
      name: 'dragonfly',
      speed: .12,
      wingRate: 5,
      flight: 'hover',
      altitude: (.22, .58),
      habitat: _dragonfly,
    ),
    InsectSpecies(
      name: 'butterfly',
      speed: .045,
      wingRate: 5,
      flight: 'flutter',
      altitude: (.22, .58),
      habitat: _butterfly,
    ),
    InsectSpecies(
      name: 'ladybug',
      speed: .07,
      wingRate: 5,
      flight: 'cruise',
      altitude: (.22, .58),
      habitat: _ladybug,
    ),
    InsectSpecies(
      name: 'firefly',
      speed: .07,
      wingRate: 5,
      flight: 'drift',
      altitude: (.25, .6),
      glow: 0xffffeaa6,
      spawnInBand: true,
      habitat: _firefly,
    ),
    InsectSpecies(
      name: 'moth',
      speed: .055,
      wingRate: 6,
      flight: 'flutter',
      altitude: (.18, .5),
      bob: .014,
      lightSeeking: true,
      spawnInBand: true,
      habitat: _moth,
    ),
    InsectSpecies(
      name: 'mayfly',
      speed: .05,
      wingRate: 9,
      flight: 'bob',
      altitude: (.5, .68),
      bob: .03,
      turn: 2.4,
      maxY: .72,
      spawnInBand: true,
      habitat: _mayfly,
    ),
    InsectSpecies(
      name: 'glowbeetle',
      speed: .04,
      wingRate: 5,
      flight: 'glide',
      altitude: (.3, .62),
      glow: 0xff5ef2e8,
      bob: .004,
      turn: .9,
      spawnInBand: true,
      habitat: _glowbeetle,
    ),
    // Night singers (part of the night sets).
    InsectSpecies(
      name: 'cricket',
      speed: .035,
      wingRate: 2.6,
      flight: 'hop',
      altitude: (.52, .66),
      bob: .028,
      turn: 1.2,
      vertical: .2,
      maxY: .7,
      spawnInBand: true,
      voice: 'cricket',
      habitat: _cricket,
    ),
    InsectSpecies(
      name: 'katydid',
      speed: .05,
      wingRate: 6,
      flight: 'flutter',
      altitude: (.15, .45),
      bob: .012,
      turn: 1.4,
      spawnInBand: true,
      voice: 'katydid',
      habitat: _katydid,
    ),
    // Signature day and all-hours species.
    InsectSpecies(
      name: 'waterstrider',
      speed: .06,
      wingRate: 1.5,
      flight: 'skate',
      altitude: (.57, .68),
      bob: 0,
      turn: 3.2,
      vertical: .08,
      maxY: .72,
      spawnInBand: true,
      habitat: _waterstrider,
    ),
    InsectSpecies(
      name: 'whirligig',
      speed: .05,
      wingRate: 2,
      flight: 'skate',
      altitude: (.58, .68),
      bob: 0,
      turn: 4.2,
      vertical: .12,
      maxY: .72,
      spawnInBand: true,
      habitat: _whirligig,
    ),
    InsectSpecies(
      name: 'damselfly',
      speed: .08,
      wingRate: 7,
      flight: 'hover',
      altitude: (.3, .62),
      bob: .01,
      turn: 2,
      spawnInBand: true,
      habitat: _damselfly,
    ),
    InsectSpecies(
      name: 'bee',
      speed: .085,
      wingRate: 14,
      flight: 'cruise',
      altitude: (.2, .5),
      bob: .01,
      turn: 2.2,
      spawnInBand: true,
      voice: 'bee',
      habitat: _bee,
    ),
    InsectSpecies(
      name: 'cicada',
      speed: .09,
      wingRate: 8,
      flight: 'cruise',
      altitude: (.14, .4),
      bob: .006,
      turn: 1.2,
      spawnInBand: true,
      voice: 'cicada',
      habitat: _cicada,
    ),
    InsectSpecies(
      name: 'cranefly',
      speed: .035,
      wingRate: 7,
      flight: 'drift',
      altitude: (.3, .6),
      bob: .02,
      turn: 2.6,
      spawnInBand: true,
      habitat: _cranefly,
    ),
    InsectSpecies(
      name: 'stonefly',
      speed: .045,
      wingRate: 4,
      flight: 'cruise',
      altitude: (.45, .66),
      bob: .006,
      turn: 1.6,
      vertical: .35,
      maxY: .7,
      spawnInBand: true,
      habitat: _stonefly,
    ),
    InsectSpecies(
      name: 'cavecricket',
      speed: .035,
      wingRate: 2.2,
      flight: 'hop',
      altitude: (.5, .66),
      bob: .026,
      turn: 1.3,
      vertical: .2,
      maxY: .7,
      spawnInBand: true,
      habitat: _cavecricket,
    ),
    InsectSpecies(
      name: 'jewelbeetle',
      speed: .06,
      wingRate: 5,
      flight: 'cruise',
      altitude: (.2, .5),
      bob: .008,
      turn: 1.6,
      spawnInBand: true,
      habitat: _jewelbeetle,
    ),
    InsectSpecies(
      name: 'fungusgnat',
      speed: .03,
      wingRate: 15,
      flight: 'swarm',
      altitude: (.3, .6),
      glow: 0xff7fe9e4,
      bob: .016,
      turn: 3.4,
      spawnInBand: true,
      habitat: _fungusgnat,
    ),
  ];

  static final Map<String, InsectSpecies> byName = {
    for (final s in table) s.name: s,
  };

  /// Night sets: dry dusk or darkness only.
  static const Set<String> nightNames = {
    'firefly',
    'moth',
    'mayfly',
    'glowbeetle',
    'cricket',
    'katydid',
  };

  /// Species with an ambient voice in `web/ambience.js`.
  static const Set<String> voicedNames = {
    'cricket',
    'katydid',
    'bee',
    'cicada',
  };

  static const Set<String> caveBiomes = {'grotto', 'crystal_grotto'};

  static const Set<String> fireflyBiomes = {
    'willow',
    'cypress',
    'firefly',
    'lotus',
    'alpine',
  };
  static const Set<String> mothBiomes = {
    'sanctuary',
    'jade_sanctuary',
    'maple',
    'autumn_mist',
    'alpine',
  };
  static const Set<String> mayflyBiomes = {'lotus', 'blossom'};

  /// Mayflies swarm here through dusk only (daylight 0.2–0.56).
  static const Set<String> mayflyDuskBiomes = {'willow'};
  static const Set<String> glowbeetleBiomes = {'grotto', 'crystal_grotto'};

  /// Autumn grass sings: field crickets chirp at night.
  static const Set<String> cricketBiomes = {'maple', 'autumn_mist'};

  /// Bayou trees rasp at night.
  static const Set<String> katydidBiomes = {'cypress', 'firefly'};

  /// Still, open, sunlit water.
  static const Set<String> waterstriderBiomes = {
    'willow',
    'lotus',
    'blossom',
    'sanctuary',
    'jade_sanctuary',
  };

  /// Dark, tannin water.
  static const Set<String> whirligigBiomes = {'willow', 'cypress', 'firefly'};

  /// Flower-rimmed ponds.
  static const Set<String> damselflyBiomes = {
    'lotus',
    'blossom',
    'jade_sanctuary',
  };

  /// Blossom and garden ponds by day; alpine meadows have bumblebees.
  static const Set<String> beeBiomes = {
    'blossom',
    'sanctuary',
    'jade_sanctuary',
    'alpine',
  };

  /// Warm wooded garden ponds: the Japanese sceneries.
  static const Set<String> cicadaBiomes = {
    'maple',
    'sanctuary',
    'jade_sanctuary',
  };

  /// Damp, foggy banks.
  static const Set<String> craneflyBiomes = {'autumn_mist', 'cypress'};

  /// Where mosquitoes stay away: the cold tarn and the caves.
  static const Set<String> mosquitoFreeBiomes = {
    'alpine',
    'grotto',
    'crystal_grotto',
  };

  /// Where butterflies stay away: the caves and the cold autumn fog.
  static const Set<String> butterflyFreeBiomes = {
    'grotto',
    'crystal_grotto',
    'autumn_mist',
  };

  /// Ladybugs want gardens and meadows, not bayous, caves or lotus water.
  static const Set<String> ladybugFreeBiomes = {
    'grotto',
    'crystal_grotto',
    'cypress',
    'firefly',
    'lotus',
  };

  /// Night species a biome can show in dry dusk or darkness.
  static List<String> nightSetFor(String biome) => [
    if (fireflyBiomes.contains(biome)) 'firefly',
    if (mothBiomes.contains(biome)) 'moth',
    if (mayflyBiomes.contains(biome) || mayflyDuskBiomes.contains(biome))
      'mayfly',
    if (glowbeetleBiomes.contains(biome)) 'glowbeetle',
    if (cricketBiomes.contains(biome)) 'cricket',
    if (katydidBiomes.contains(biome)) 'katydid',
  ];

  /// Signature species of a biome: the ones that appear there and in at most
  /// a few related sceneries (never in all twelve).
  static List<String> signatureFor(String biome) => [
    for (final s in table)
      if (signatureNames.contains(s.name) && biomesOf(s.name).contains(biome))
        s.name,
  ];

  static const Set<String> signatureNames = {
    'cricket',
    'katydid',
    'waterstrider',
    'whirligig',
    'damselfly',
    'bee',
    'cicada',
    'cranefly',
    'stonefly',
    'cavecricket',
    'jewelbeetle',
    'fungusgnat',
  };

  /// Biomes a signature or night species can appear in at all.
  static Set<String> biomesOf(String species) => switch (species) {
    'firefly' => fireflyBiomes,
    'moth' => mothBiomes,
    'mayfly' => {...mayflyBiomes, ...mayflyDuskBiomes},
    'glowbeetle' => glowbeetleBiomes,
    'cricket' => cricketBiomes,
    'katydid' => katydidBiomes,
    'waterstrider' => waterstriderBiomes,
    'whirligig' => whirligigBiomes,
    'damselfly' => damselflyBiomes,
    'bee' => beeBiomes,
    'cicada' => cicadaBiomes,
    'cranefly' => craneflyBiomes,
    'stonefly' => const {'alpine'},
    'cavecricket' => caveBiomes,
    'jewelbeetle' => const {'jade_sanctuary'},
    'fungusgnat' => const {'crystal_grotto'},
    _ => const {},
  };

  /// Logical-space light source moths favour, or null.
  static (double, double)? lightSourceFor(String biome) =>
      biome == 'sanctuary' || biome == 'jade_sanctuary'
      ? (114 / 641, 168 / 359)
      : null;

  // Common species and their absences.
  static bool _fly(HabitatContext c) => c.weather != 'storm' && c.light;
  static bool _mosquito(HabitatContext c) =>
      !mosquitoFreeBiomes.contains(c.biome);
  static bool _dragonfly(HabitatContext c) =>
      c.dry && c.light && c.progress >= .12 && !c.cave;
  static bool _butterfly(HabitatContext c) =>
      c.weather == 'clear' &&
      c.light &&
      c.progress >= .25 &&
      !butterflyFreeBiomes.contains(c.biome);
  static bool _ladybug(HabitatContext c) =>
      c.dry &&
      c.light &&
      c.progress >= .38 &&
      !ladybugFreeBiomes.contains(c.biome);

  // Night sets.
  static bool _firefly(HabitatContext c) =>
      c.dry && c.dim && fireflyBiomes.contains(c.biome);
  static bool _moth(HabitatContext c) =>
      c.dry && c.dim && mothBiomes.contains(c.biome);
  static bool _mayfly(HabitatContext c) =>
      c.dry &&
      c.dim &&
      (mayflyBiomes.contains(c.biome) ||
          (mayflyDuskBiomes.contains(c.biome) && c.daylight >= .2));
  static bool _glowbeetle(HabitatContext c) =>
      c.dry && c.dim && glowbeetleBiomes.contains(c.biome);
  static bool _cricket(HabitatContext c) =>
      c.dry && c.dim && cricketBiomes.contains(c.biome);
  static bool _katydid(HabitatContext c) =>
      c.dry && c.dim && katydidBiomes.contains(c.biome);

  // Signature species.
  /// Skaters work the surface from first light to late dusk; heavy rain
  /// drives them to the reeds.
  static bool _waterstrider(HabitatContext c) =>
      waterstriderBiomes.contains(c.biome) &&
      c.notPouring &&
      c.daylight >= .2 &&
      c.progress >= .05;

  /// Whirligigs spin at any hour on dark water, until the rain pours.
  static bool _whirligig(HabitatContext c) =>
      whirligigBiomes.contains(c.biome) && c.notPouring && c.progress >= .05;
  static bool _damselfly(HabitatContext c) =>
      damselflyBiomes.contains(c.biome) &&
      c.dry &&
      c.light &&
      c.progress >= .12;
  static bool _bee(HabitatContext c) =>
      beeBiomes.contains(c.biome) && c.dry && c.light && c.progress >= .1;

  /// Cicadas sing on warm afternoons into early dusk, never in a storm.
  static bool _cicada(HabitatContext c) =>
      cicadaBiomes.contains(c.biome) && c.weather != 'storm' && c.warm;

  /// Craneflies like damp air: fog, drizzle and dusk suit them; downpours do
  /// not.
  static bool _cranefly(HabitatContext c) =>
      craneflyBiomes.contains(c.biome) &&
      c.notPouring &&
      c.weather != 'storm' &&
      c.progress >= .05;

  /// Stoneflies are cold-water insects: the tarn's resident in any weather,
  /// at any hour.
  static bool _stonefly(HabitatContext c) => c.biome == 'alpine';

  /// Cave crickets never see the weather or the sun.
  static bool _cavecricket(HabitatContext c) => c.cave;
  static bool _jewelbeetle(HabitatContext c) =>
      c.biome == 'jade_sanctuary' && c.dry && c.light && c.progress >= .2;

  /// Fungus gnats hang in the still cave air above the glowing shelves.
  static bool _fungusgnat(HabitatContext c) =>
      c.biome == 'crystal_grotto' && c.progress >= .08;
}
