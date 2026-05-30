import 'dart:async';

/// Debouncer simple — ejecuta `run` solo si pasan `duration` ms sin que
/// llegue otro `run`. Útil para inputs de búsqueda que no deben ejecutar
/// query/setState en cada keystroke.
///
/// Ejemplo:
/// ```dart
/// final _debouncer = Debouncer(const Duration(milliseconds: 250));
/// // ...
/// onChanged: (v) => _debouncer.run(() => setState(() => _query = v)),
/// ```
///
/// Llamar `.dispose()` en el `State.dispose()` del widget que lo usa.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Cancela el callback pendiente (si existe) sin ejecutarlo.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
