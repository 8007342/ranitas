import 'dart:js_interop';

@JS('window.ranitasAudio')
external _RanitasAudio? get _audio;

extension type _RanitasAudio(JSObject _) implements JSObject {
  external void update(
    JSNumber progress,
    JSNumber richness,
    JSString weather,
    JSBoolean sleeping,
    JSNumber rainIntensity,
    JSString species,
    JSNumber elapsedSeconds,
  );
  external void suspend();
  external void resume();
  external void dispose();
}

/// Bridge to web/ambience.js. The page owns one shared audio context.
class PondAmbience {
  bool _disposed = false;

  /// [rainIntensity] (0–1) lets storm thunder follow the downpours; [species]
  /// is the model's compact `voice:count,…` presence string for the insect
  /// voices. Both are optional on the JavaScript side, so an older script
  /// ignores them.
  void update(
    double progress,
    double richness,
    String weather,
    bool sleeping, {
    double rainIntensity = 0,
    String species = '',
    double elapsedSeconds = 0,
  }) {
    if (_disposed) return;
    _audio?.update(
      progress.toJS,
      richness.toJS,
      weather.toJS,
      sleeping.toJS,
      rainIntensity.toJS,
      species.toJS,
      elapsedSeconds.toJS,
    );
  }

  void suspend() {
    if (!_disposed) _audio?.suspend();
  }

  void resume() {
    if (!_disposed) _audio?.resume();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _audio?.dispose();
  }
}
