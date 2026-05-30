// Entry point con conditional export:
//   - En Flutter Web (`dart.library.html` disponible) → implementación real
//     en `_web.dart` que usa el DOM directamente.
//   - En cualquier otra plataforma (mobile / desktop / tests) → stub que
//     lanza `UnsupportedError` si se llama.
//
// Los callsites (`settings_page.dart`) importan SIEMPRE este archivo
// (`web_file_picker.dart`) — no tienen que saber qué plataforma corre.

export 'web_file_picker_stub.dart'
  if (dart.library.html) 'web_file_picker_web.dart';
