// Stub para plataformas que NO son web (mobile / desktop). Lanzado solo si
// alguien intenta llamar `pickImageFromWeb` fuera de web — el callsite real
// (settings_page.dart) lo usa desde el wizard de upload de logo, que por
// ahora es web-only.
//
// Si en el futuro queremos soportar mobile/desktop, reemplazar esto por una
// implementación con `image_picker` o `file_selector`. Mientras tanto el
// build no rompe en Android/iOS.

import 'dart:typed_data';

class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;

  String? get extension {
    final i = filename.lastIndexOf('.');
    if (i < 0 || i == filename.length - 1) return null;
    return filename.substring(i + 1).toLowerCase();
  }
}

Future<PickedImage?> pickImageFromWeb({int? maxBytes}) async {
  throw UnsupportedError(
    'pickImageFromWeb solo está disponible en Flutter Web. '
    'Para mobile/desktop, integrar `image_picker` o `file_selector`.',
  );
}

Future<PickedImage?> pickFileFromWeb({
  required String accept,
  int? maxBytes,
}) async {
  throw UnsupportedError(
    'pickFileFromWeb solo está disponible en Flutter Web.',
  );
}
