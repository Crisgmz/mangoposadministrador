// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Selección de archivos en Flutter Web sin depender del plugin `file_picker`
// (que tiene un `LateInitializationError` conocido en algunas versiones del
// SDK al inicializarse en web).
//
// Usa la API del DOM directamente (`FileUploadInputElement` + `FileReader`)
// que está garantizada para correr en cualquier browser sin setup adicional.
//
// NOTA: este archivo importa `dart:html` y SOLO compila en web. `dart:html`
// está marcado deprecated en favor de `package:web` + `dart:js_interop`,
// pero sigue funcionando 100% y es mucho más simple para este caso. Cuando
// el package `web` esté más maduro y necesitemos multi-plataforma, migramos.

import 'dart:async';
import 'dart:html' as html;
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

/// Abre el picker nativo del browser. Devuelve null si el usuario cancela.
/// `maxBytes` valida el tamaño antes de leer; null = sin límite.
Future<PickedImage?> pickImageFromWeb({
  int? maxBytes,
}) {
  return pickFileFromWeb(
    accept: 'image/png,image/jpeg,image/jpg,image/webp,image/svg+xml',
    maxBytes: maxBytes,
  );
}

/// Igual que [pickImageFromWeb] pero para cualquier tipo: [accept] es el
/// atributo del `<input type=file>` (ej. `.p12,.pfx`).
Future<PickedImage?> pickFileFromWeb({
  required String accept,
  int? maxBytes,
}) async {
  final input = html.FileUploadInputElement()
    ..accept = accept
    ..multiple = false;

  final completer = Completer<PickedImage?>();

  // Manejar el change dentro de una función async aparte. Si algo arroja,
  // lo capturamos y lo propagamos al completer en lugar de dejarlo flotando.
  Future<void> handleChange() async {
    try {
      await input.onChange.first;
      final files = input.files;
      if (files == null || files.isEmpty) {
        completer.complete(null);
        return;
      }
      final file = files.first;
      if (maxBytes != null && file.size > maxBytes) {
        completer.completeError(
          StateError(
            'Archivo demasiado grande (${(file.size / 1024).toStringAsFixed(0)} KB). '
            'Máximo ${(maxBytes / 1024).toStringAsFixed(0)} KB.',
          ),
        );
        return;
      }
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final result = reader.result;
      if (result is! Uint8List) {
        completer.complete(null);
        return;
      }
      completer.complete(PickedImage(
        bytes: result,
        filename: file.name,
        mimeType: file.type.isNotEmpty ? file.type : 'application/octet-stream',
      ));
    } catch (e, s) {
      if (!completer.isCompleted) completer.completeError(e, s);
    }
  }

  // Lanza el handler en background; click dispara el picker del SO.
  unawaited(handleChange());
  input.click();

  return completer.future;
}

/// Descarga [content] como archivo con el diálogo del browser.
void downloadTextFileFromWeb(
  String content,
  String filename, {
  String mimeType = 'text/plain',
}) {
  final blob = html.Blob([content], '$mimeType;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

/// Descarga [bytes] (un PDF, por ejemplo) con el diálogo del browser.
void downloadBytesFromWeb(
  Uint8List bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
