/// Quintic entrances have zero velocity and acceleration at either end.
class Awakening {
  Awakening._();
  static double reveal(double seconds, double start, double end) {
    final x = ((seconds - start) / (end - start)).clamp(0.0, 1.0);
    return (x * x * x * (x * (x * 6 - 15) + 10)).clamp(0.0, 1.0);
  }

  static double water(double s) => reveal(s, 0, 110);
  static double breeze(double s) => reveal(s, 10, 130);
  static double foliage(double s) => reveal(s, 25, 155);
  static double weather(double s) => reveal(s, 35, 170);
  static double wildlife(double s) => reveal(s, 55, 175);
  static double distant(double s) => reveal(s, 100, 180);
  static double glow(double s) => reveal(s, 65, 180);
}
