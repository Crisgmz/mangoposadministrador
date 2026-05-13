import 'package:flutter/material.dart';

import '../dashboard/widgets/alerts_panel.dart';
import '../shared/page_header.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          kicker: 'Alertas',
          title: 'Centro de alertas',
          subtitle:
              'Eventos que requieren atención del operador en este momento.',
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: const SizedBox(
            height: 600,
            child: AlertsPanel(),
          ),
        ),
      ],
    );
  }
}
