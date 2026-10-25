/// Insect species table (design D2 of the visual-envelope change).
///
/// Day species keep the original artful habitat rules. Night sets are keyed on
/// continuous `daylight` so they fade in and out with the light rather than at
/// period boundaries. None of this is biological validation.
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

  /// The original daytime predicate, unchanged.
  bool get light => period == 'day' || (period == 'dawn' && progress >= .55);

  /// Night sets appear below this daylight (dusk begins at 0.45 in a dusk
  /// cycle; a dawn cycle still carries them at daylight 0.5).
  static const double nightThreshold = .56;
  bool get dim => daylight < nightThreshold;
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
    this.lightSeeking = false,
    this.maxY = .65,
  });

  final String name;

  /// Cruise speed in normalised screen widths per second.
  final double speed;

  /// Phase advance per second; the renderer flaps on it.
  final double wingRate;

  /// `cruise`, `hover`, `flutter`, `drift`, `bob` or `glide`.
  final String flight;

  /// Soft altitude band (normalised y) the insect is steered back into.
  final (double, double) altitude;

  /// Glow colour (ARGB) for luminous species, or null.
  final int? glow;

  /// Vertical bobbing amplitude added to the target velocity.
  final double bob;

  /// Random-turn gain.
  final double turn;

  /// Moths: steer toward the biome's light source when it has one.
  final bool lightSeeking;

  /// Hard lower screen bound (mayflies may dance just above the water).
  final double maxY;

  final bool Function(HabitatContext c) habitat;

  bool get night => nightNames.contains(name);

  /// Table order matters: day species first so `availableSpecies` keeps its
  /// documented `['fly', 'mosquito']` opening.
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
      habitat: _always,
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
      habitat: _glowbeetle,
    ),
  ];

  static final Map<String, InsectSpecies> byName = {
    for (final s in table) s.name: s,
  };

  static const Set<String> nightNames = {
    'firefly',
    'moth',
    'mayfly',
    'glowbeetle',
  };

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

  /// Night species a biome can show in dry dusk or darkness.
  static List<String> nightSetFor(String biome) => [
    if (fireflyBiomes.contains(biome)) 'firefly',
    if (mothBiomes.contains(biome)) 'moth',
    if (mayflyBiomes.contains(biome) || mayflyDuskBiomes.contains(biome))
      'mayfly',
    if (glowbeetleBiomes.contains(biome)) 'glowbeetle',
  ];

  /// Logical-space light source moths favour, or null.
  static (double, double)? lightSourceFor(String biome) =>
      biome == 'sanctuary' || biome == 'jade_sanctuary'
      ? (114 / 641, 168 / 359)
      : null;

  static bool _always(HabitatContext c) => true;
  static bool _fly(HabitatContext c) => c.weather != 'storm' && c.light;
  static bool _dragonfly(HabitatContext c) =>
      c.dry && c.light && c.progress >= .12;
  static bool _butterfly(HabitatContext c) =>
      c.weather == 'clear' && c.light && c.progress >= .25;
  static bool _ladybug(HabitatContext c) =>
      c.dry && c.light && c.progress >= .38;
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
}
