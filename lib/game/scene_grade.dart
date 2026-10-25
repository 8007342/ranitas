import 'dart:ui' as ui;

import 'pond_model.dart';

/// Continuous time-of-day colour grade (design D3 of the visual-envelope
/// change): a 4×5 colour matrix interpolated across four keyframes keyed on
/// `daylight`, with per-biome night keys and rain cloud darkening.
///
/// The matrix is linear in its keyframes, so interpolating matrices is the same
/// as interpolating graded colours, and the mean luminance of any swatch moves
/// linearly between keys. Offsets (fifth column) are in 0–255 units as
/// `ColorFilter.matrix` expects.
class SceneGrade {
  SceneGrade._();

  static const double lumR = .2126;
  static const double lumG = .7152;
  static const double lumB = .0722;

  /// Daylight positions of the keyframes, from day to night.
  static const double sunsetAt = .6;
  static const double duskAt = .3;

  static const List<double> identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// Sunset: warm, barely darker. R×1.04 G×0.90 B×0.80.
  static final List<double> sunset = key(scale: (1.04, .90, .80));

  /// Dusk: 30 % desaturated, cool. R×0.62 G×0.66 B×0.86.
  static final List<double> dusk = key(scale: (.62, .66, .86), desaturate: .3);

  /// Shared indigo night: 50 % desaturated, R×0.34 G×0.42 B×0.66, blue lift.
  /// The lift keeps the mean darkness close to the old `#101f48` wash.
  static final List<double> night = key(
    scale: (.34, .42, .66),
    desaturate: .5,
    lift: (4, 8, 22),
  );

  /// Grottos keep their teal at night.
  static final List<double> nightTeal = key(
    scale: (.28, .48, .60),
    desaturate: .45,
    lift: (2, 14, 18),
  );

  /// Sanctuaries keep a lantern warmth at night.
  static final List<double> nightWarm = key(
    scale: (.44, .40, .52),
    desaturate: .45,
    lift: (12, 8, 12),
  );

  static List<double> nightKeyFor(String biome) => switch (biome) {
    'grotto' || 'crystal_grotto' => nightTeal,
    'sanctuary' || 'jade_sanctuary' => nightWarm,
    _ => night,
  };

  /// Builds a key: desaturate by [desaturate] (luminance-preserving), scale
  /// channels by [scale], then add [lift] in 0–255 units.
  static List<double> key({
    required (double, double, double) scale,
    double desaturate = 0,
    (double, double, double) lift = (0, 0, 0),
  }) {
    final s = desaturate;
    final scales = [scale.$1, scale.$2, scale.$3];
    final lifts = [lift.$1, lift.$2, lift.$3];
    const lums = [lumR, lumG, lumB];
    final out = <double>[];
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        out.add(scales[r] * ((1 - s) * (r == c ? 1 : 0) + s * lums[c]));
      }
      out
        ..add(0)
        ..add(lifts[r]);
    }
    out.addAll(const [0, 0, 0, 1, 0]);
    return out;
  }

  static List<double> lerp(List<double> a, List<double> b, double t) =>
      List<double>.generate(20, (i) => a[i] + (b[i] - a[i]) * t);

  /// Applies [outer] after [inner] (both 4×5 with offsets in 0–255 units).
  static List<double> compose(List<double> outer, List<double> inner) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += outer[r * 5 + k] * inner[k * 5 + c];
        }
        out[r * 5 + c] = sum;
      }
      var offset = outer[r * 5 + 4];
      for (var k = 0; k < 4; k++) {
        offset += outer[r * 5 + k] * inner[k * 5 + 4];
      }
      out[r * 5 + 4] = offset;
    }
    return out;
  }

  /// Rain clouds: up to 28 % darker and 25 % duller at full intensity.
  static List<double> cloudKey(double cloud) {
    final c = cloud.clamp(0.0, 1.0);
    final k = 1 - .28 * c;
    return key(scale: (k, k, k), desaturate: .25 * c);
  }

  /// The grade matrix for a scene state. Day with no cloud is the identity.
  static List<double> matrixFor({
    required double daylight,
    required String biome,
    double cloud = 0,
  }) {
    final d = daylight.clamp(0.0, 1.0);
    final List<double> m;
    if (d >= sunsetAt) {
      m = lerp(sunset, identity, (d - sunsetAt) / (1 - sunsetAt));
    } else if (d >= duskAt) {
      m = lerp(dusk, sunset, (d - duskAt) / (sunsetAt - duskAt));
    } else {
      m = lerp(nightKeyFor(biome), dusk, d / duskAt);
    }
    return cloud > 0 ? compose(cloudKey(cloud), m) : m;
  }

  static bool isIdentity(List<double> m) {
    for (var i = 0; i < 20; i++) {
      if ((m[i] - identity[i]).abs() > 1e-9) return false;
    }
    return true;
  }

  /// A `ColorFilter` for the backdrop and painted layers, or null when the
  /// grade is the identity (so daytime draws stay unfiltered).
  static ui.ColorFilter? filterFor(PondModel model) {
    final m = matrixFor(
      daylight: model.daylight,
      biome: model.biome,
      cloud: model.cloudDarkening,
    );
    return isIdentity(m) ? null : ui.ColorFilter.matrix(m);
  }

  /// Grades one colour (channels 0–255, clamped like the GPU does).
  static (double, double, double) apply(
    List<double> m,
    (double, double, double) rgb,
  ) {
    final (r, g, b) = rgb;
    double ch(int row) =>
        (m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 4])
            .clamp(0.0, 255.0);
    return (ch(0), ch(1), ch(2));
  }

  static double luminance((double, double, double) rgb) =>
      (lumR * rgb.$1 + lumG * rgb.$2 + lumB * rgb.$3) / 255;

  /// A small palette standing in for a backdrop: sky, water, foliage, rock,
  /// blossom and a lantern. Used to reason about mean darkness without pixels.
  static const List<(double, double, double)> swatch = [
    (214, 170, 160),
    (96, 160, 150),
    (60, 110, 70),
    (90, 80, 100),
    (230, 180, 200),
    (255, 220, 150),
    (128, 128, 128),
  ];

  /// Mean graded luminance of [swatch] in `[0, 1]`.
  static double meanLuminance(List<double> m) {
    var sum = 0.0;
    for (final c in swatch) {
      sum += luminance(apply(m, c));
    }
    return sum / swatch.length;
  }
}
