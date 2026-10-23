import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/ranitas_game.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const RanitasApp());
}

class RanitasApp extends StatelessWidget {
  const RanitasApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ranitas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(scaffoldBackgroundColor: const Color(0xff081c27)),
    home: const PondPage(),
  );
}

class PondPage extends StatefulWidget {
  const PondPage({super.key});
  @override
  State<PondPage> createState() => _PondPageState();
}

class _PondPageState extends State<PondPage> with WidgetsBindingObserver {
  late final RanitasGame game;
  int? pointer;
  bool holding = false;
  @override
  void initState() {
    super.initState();
    final query = Uri.base.queryParameters;
    game = RanitasGame(
      seed: int.tryParse(query['seed'] ?? ''),
      durationOverride: const bool.fromEnvironment('RANITAS_TEST')
          ? double.tryParse(query['duration'] ?? '')
          : null,
    );
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space &&
        event.logicalKey != LogicalKeyboardKey.enter) {
      return false;
    }
    if (event is KeyDownEvent && !holding) {
      holding = true;
      game.model.press();
    } else if (event is KeyUpEvent && holding) {
      holding = false;
      game.model.release();
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      game.resumeEngine();
      game.ambience.resume();
    } else {
      game.model.cancelPress();
      pointer = null;
      holding = false;
      game.pauseEngine();
      game.ambience.suspend();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    WidgetsBinding.instance.removeObserver(this);
    game.ambience.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        game.renderer.reducedMotion = MediaQuery.disableAnimationsOf(context);
        return SizedBox.expand(
          child: Semantics(
              label:
                  'A peaceful widescreen pond with two little frogs. Tap, hold a little, or hold longer anywhere in the pond to jump. The frogs rest when night arrives.',
              child: Focus(
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event.logicalKey != LogicalKeyboardKey.space &&
                      event.logicalKey != LogicalKeyboardKey.enter) {
                    return KeyEventResult.ignored;
                  }
                  if (event is KeyDownEvent && !holding) {
                    holding = true;
                    game.model.press();
                  }
                  if (event is KeyUpEvent && holding) {
                    holding = false;
                    game.model.release();
                  }
                  return KeyEventResult.handled;
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    if (pointer == null) {
                      pointer = e.pointer;
                      game.model.press();
                    }
                  },
                  onPointerUp: (e) {
                    if (pointer == e.pointer) {
                      pointer = null;
                      game.model.release();
                    }
                  },
                  onPointerCancel: (e) {
                    if (pointer == e.pointer) {
                      pointer = null;
                      game.model.cancelPress();
                    }
                  },
                child: GameWidget(game: game),
              ),
            ),
          ),
        );
      },
    ),
  );
}
