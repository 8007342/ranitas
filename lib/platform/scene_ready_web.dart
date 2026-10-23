import 'dart:js_interop';

@JS('window.ranitasReady')
external JSFunction? get _ready;
void sceneReady() => _ready?.callAsFunction();
