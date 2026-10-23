/// Silent implementation for platforms without browser JavaScript interop.
///
/// Native synthesis is not implemented. A MethodChannel bridge would also need
/// registered platform handlers and a native audio engine; see docs/audio.md.
class PondAmbience {
  void update(
    double progress,
    double richness,
    String weather,
    bool sleeping,
  ) {}
  void suspend() {}
  void resume() {}
  void dispose() {}
}
