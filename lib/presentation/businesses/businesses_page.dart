import 'package:flutter/material.dart';

import '../dashboard/widgets/business_table.dart';
import '../shared/page_header.dart';

class BusinessesPage extends StatelessWidget {
  const BusinessesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Negocios',
          title: 'Listado completo',
          subtitle: 'Todos los negocios registrados en la plataforma.',
        ),
        SizedBox(height: 24),
        BusinessTable(),
      ],
    );
  }
}
