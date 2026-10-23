import 'dart:js_interop';

@JS('window.ranitasAudio')
external _RanitasAudio? get _audio;

extension type _RanitasAudio(JSObject _) implements JSObject {
  external void update(
    JSNumber progress,
    JSNumber richness,
    JSString weather,
    JSBoolean sleeping,
  );
  external void suspend();
  external void resume();
  external void dispose();
}

/// Bridge to web/ambience.js. The page owns one shared audio context.
class PondAmbience {
  bool _disposed = false;

  void update(double progress, double richness, String weather, bool sleeping) {
    if (_disposed) return;
    _audio?.update(progress.toJS, richness.toJS, weather.toJS, sleeping.toJS);
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
