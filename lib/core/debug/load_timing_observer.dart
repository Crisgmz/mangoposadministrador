import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cronómetro de cargas: imprime cuánto tarda cada provider en pasar de
/// "cargando" a tener datos.
///
/// Sirve para separar dos cosas que desde afuera se ven igual ("la pantalla
/// carga lento"): el tiempo que tarda el servidor en responder y el tiempo que
/// tarda la app en dibujar. Sale una línea por carga:
///
/// ```
/// [carga] FutureProvider<List<BusinessOverview>>  1843 ms
/// ```
///
/// Solo corre en debug: en release no se instala (ver `main.dart`).
class LoadTimingObserver extends ProviderObserver {
  const LoadTimingObserver();

  /// Cronómetro por provider vivo. La clave es la identidad del provider, así
  /// que los `.family` (uno por negocio, por ejemplo) no se pisan entre sí.
  static final Map<int, Stopwatch> _running = {};

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    _onValue(provider, value);
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    _onValue(provider, newValue);
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    _running.remove(identityHashCode(provider));
  }

  void _onValue(ProviderBase<Object?> provider, Object? value) {
    if (value is! AsyncValue) return;

    // Arranca al entrar en "cargando" sin dato previo. Un refresco que
    // mantiene el dato viejo (hasValue) no cuenta: nadie está esperando.
    if (value.isLoading && !value.hasValue) {
      _running[identityHashCode(provider)] = Stopwatch()..start();
      return;
    }

    final watch = _running.remove(identityHashCode(provider));
    if (watch == null) return;
    watch.stop();

    final label = provider.name ?? provider.runtimeType.toString();
    final failed = value.hasError ? '  ← ERROR' : '';
    debugPrint('[carga] $label  ${watch.elapsedMilliseconds} ms$failed');
  }
}
