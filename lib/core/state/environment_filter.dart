import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/business_environment.dart';

/// Filtro global de entorno aplicado a TODAS las pantallas.
/// `null` = "Todos" (no filtrar).
final environmentFilterProvider =
    StateProvider<BusinessEnvironment?>((ref) => BusinessEnvironment.production);
