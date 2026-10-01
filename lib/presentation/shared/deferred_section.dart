import 'package:flutter/widgets.dart';

/// Construye [child] unos frames DESPUÉS de montarse; mientras tanto ocupa
/// [placeholderHeight].
///
/// Para pantallas largas que se arman enteras dentro de un
/// `SingleChildScrollView` (sin construcción perezosa): lo que queda fuera de
/// pantalla no hace falta en el primer frame, y ese primer frame es justo el
/// que coincide con la transición de entrada. Con todo junto, el costo de las
/// doce secciones del detalle de negocio caía en ese frame y la transición
/// arrancaba trabada.
///
/// [frames] escalona: con 1, 2, 3… cada sección se construye en un frame
/// distinto, en vez de mover el pico entero al segundo frame.
class DeferredSection extends StatefulWidget {
  const DeferredSection({
    super.key,
    required this.child,
    this.frames = 1,
    this.placeholderHeight = 200,
  });

  final Widget child;
  final int frames;

  /// Alto aproximado mientras no se construye. No tiene que ser exacto: la
  /// sección está fuera de pantalla y solo afecta a la barra de scroll.
  final double placeholderHeight;

  @override
  State<DeferredSection> createState() => _DeferredSectionState();
}

class _DeferredSectionState extends State<DeferredSection> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _waitFrames();
  }

  Future<void> _waitFrames() async {
    for (var i = 0; i < widget.frames; i++) {
      // endOfFrame agenda un frame si no hay uno en curso: no se queda
      // esperando a que otra cosa pinte.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return _ready ? widget.child : SizedBox(height: widget.placeholderHeight);
  }
}
