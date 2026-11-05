import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/card_charge_result.dart';
import '../../domain/models/membership_invoice.dart';
import '../../domain/models/invoice_payment_result.dart';
import '../../domain/models/payment_record.dart';

/// Repositorio de facturación de membresías. Llama a las RPCs creadas en
/// `0004_membership_billing.sql`.
class BillingRepository {
  BillingRepository(this._client);

  final SupabaseClient _client;

  Future<List<MembershipInvoice>> overview() async {
    final raw = await _client.rpc('get_billing_overview') as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(MembershipInvoice.fromJson)
        .toList(growable: false);
  }

  Future<BillingMetrics> metrics({BusinessEnvironment? env}) async {
    final raw = await _client.rpc(
      'get_billing_metrics',
      params: {'p_env': env?.raw},
    ) as List<dynamic>;
    if (raw.isEmpty) {
      return const BillingMetrics(
        mrr: 0,
        totalPaid: 0,
        totalPending: 0,
        totalExpired: 0,
        countPending: 0,
        countExpired: 0,
      );
    }
    return BillingMetrics.fromJson(raw.first as Map<String, dynamic>);
  }

  Future<List<MembershipInvoice>> forBusiness(String businessId) async {
    final raw = await _client.rpc(
      'get_business_invoices',
      params: {'p_business_id': businessId},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(MembershipInvoice.fromJson)
        .toList(growable: false);
  }

  Future<MembershipInvoice> generate(String businessId) async {
    final raw = await _client.rpc(
      'generate_membership_invoice',
      params: {'p_business_id': businessId},
    );
    return MembershipInvoice.fromJson(raw as Map<String, dynamic>);
  }

  Future<MembershipInvoice> markPaid(
    String invoiceId, {
    required String method,
    String? reference,
  }) async {
    final raw = await _client.rpc(
      'mark_invoice_paid',
      params: {
        'p_invoice_id': invoiceId,
        'p_method': method,
        'p_reference': reference,
      },
    );
    return MembershipInvoice.fromJson(raw as Map<String, dynamic>);
  }

  /// Marca varias facturas como pagadas (migración 0044). Si alguna cubre la
  /// fecha del próximo cobro con tarjeta, el servidor corre ese cobro al fin
  /// del período pagado para no cobrar dos veces el mismo mes.
  ///
  /// Con [dryRun] no escribe nada y devuelve exactamente lo que pasaría: es la
  /// misma función del servidor, revertida. La UI lo usa como vista previa.
  ///
  /// [totals] (factura → total) cobra otro precio: el servidor cambia el monto
  /// de esas facturas en la misma transacción del pago (migración 0053).
  Future<InvoicePaymentResult> markInvoicesPaid({
    required List<String> invoiceIds,
    required String method,
    String? reference,
    DateTime? paidAt,
    bool dryRun = false,
    Map<String, double> totals = const {},
  }) async {
    final raw = await _client.rpc(
      'admin_mark_invoices_paid',
      params: {
        'p_invoice_ids': invoiceIds,
        'p_method': method,
        'p_reference': reference,
        'p_paid_at': paidAt?.toUtc().toIso8601String(),
        'p_dry_run': dryRun,
        // Sin precios cambiados no se manda: sirve también sin la 0053.
        if (totals.isNotEmpty) 'p_totals': totals,
      },
    );
    return InvoicePaymentResult.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Edita una factura pendiente o vencida (migración 0053). Solo se cambia lo
  /// que no es null; [notes] vacío borra las notas.
  Future<void> updateInvoice(
    String invoiceId, {
    double? total,
    DateTime? dueDate,
    String? notes,
  }) async {
    await _client.rpc(
      'admin_update_invoice',
      params: {
        'p_invoice_id': invoiceId,
        'p_total': total,
        'p_due_date': dueDate == null
            ? null
            : '${dueDate.year.toString().padLeft(4, '0')}-'
                '${dueDate.month.toString().padLeft(2, '0')}-'
                '${dueDate.day.toString().padLeft(2, '0')}',
        'p_notes': notes,
      },
    );
  }

  /// Cobra a la tarjeta principal del negocio, en UN cargo, las facturas
  /// elegidas (migración 0054). [requestKey] identifica el pedido: repetirlo
  /// (reintento de red) no cobra dos veces.
  Future<CardChargeResult> chargeInvoicesToCard({
    required List<String> invoiceIds,
    required String requestKey,
    Map<String, double> totals = const {},
  }) {
    return _cardCharge({
      'action': 'charge',
      'invoice_ids': invoiceIds,
      'request_key': requestKey,
      if (totals.isNotEmpty) 'totals': totals,
    });
  }

  /// Consulta a Azul un cobro que quedó sin confirmar.
  Future<CardChargeResult> verifyCardCharge(String chargeId) {
    return _cardCharge({'action': 'verify', 'charge_id': chargeId});
  }

  Future<CardChargeResult> _cardCharge(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('admin-azul-charge-invoices', body: body);
      final data = res.data;
      if (data is! Map) throw const CardChargeException('Respuesta inesperada del servidor.');
      return CardChargeResult.fromJson(Map<String, dynamic>.from(data));
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is Map) {
        final err = Map<String, dynamic>.from(details['error'] as Map);
        final detail = err['detail'];
        throw CardChargeException(
          (err['message'] as String?) ?? 'Error ${e.status}',
          code: err['code'] as String?,
          chargeId: detail is Map ? detail['charge_id'] as String? : null,
        );
      }
      if (e.status == 404) {
        throw const CardChargeException(
          'La función admin-azul-charge-invoices no está publicada.',
          code: 'function_not_found',
        );
      }
      throw CardChargeException('Error ${e.status}${e.reasonPhrase != null ? ' ${e.reasonPhrase}' : ''}');
    }
  }

  Future<MembershipInvoice> voidInvoice(
    String invoiceId, {
    required String reason,
  }) async {
    final raw = await _client.rpc(
      'void_invoice',
      params: {'p_invoice_id': invoiceId, 'p_reason': reason},
    );
    return MembershipInvoice.fromJson(raw as Map<String, dynamic>);
  }

  Future<int> expireOverdue() async {
    final raw = await _client.rpc('expire_overdue_invoices');
    return raw is int ? raw : int.tryParse(raw.toString()) ?? 0;
  }

  /// Todos los pagos recibidos: cobros con tarjeta aprobados y facturas
  /// pagadas a mano (migración 0049).
  Future<List<PaymentRecord>> payments({int limit = 2000}) async {
    final raw = await _client.rpc(
      'admin_list_payments',
      params: {'p_limit': limit},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((r) => PaymentRecord.fromJson(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }
}

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(supabaseProvider));
});

final billingOverviewProvider = FutureProvider<List<MembershipInvoice>>((ref) {
  return ref.watch(billingRepositoryProvider).overview();
});

/// Lista de facturas filtrada por entorno seleccionado.
final filteredBillingOverviewProvider =
    Provider<AsyncValue<List<MembershipInvoice>>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(billingOverviewProvider).whenData((rows) {
    if (env == null) return rows;
    return rows.where((i) => i.environment == env).toList(growable: false);
  });
});

/// Métricas filtradas server-side por entorno seleccionado.
final billingMetricsProvider = FutureProvider<BillingMetrics>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(billingRepositoryProvider).metrics(env: env);
});

final businessInvoicesProvider =
    FutureProvider.family<List<MembershipInvoice>, String>((ref, businessId) {
  return ref.watch(billingRepositoryProvider).forBusiness(businessId);
});

/// Pagos de todos los negocios (pestaña Pagos de Facturación).
final paymentsProvider = FutureProvider<List<PaymentRecord>>((ref) {
  return ref.watch(billingRepositoryProvider).payments();
});

/// Pagos filtrados por el entorno seleccionado.
final filteredPaymentsProvider =
    Provider<AsyncValue<List<PaymentRecord>>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(paymentsProvider).whenData((rows) {
    if (env == null) return rows;
    return rows.where((p) => p.environment == env).toList(growable: false);
  });
});

/// Último pago de cada negocio (business_id → pago), con tarjeta o manual.
final lastPaymentByBusinessProvider =
    Provider<AsyncValue<Map<String, LastPayment>>>((ref) {
  return ref.watch(paymentsProvider).whenData(lastPaymentByBusiness);
});

/// Facturas por cobrar (pendientes o vencidas) de cada negocio, de la más
/// vieja a la más nueva: así salen en el diálogo de pago.
final payableInvoicesByBusinessProvider =
    Provider<AsyncValue<Map<String, List<MembershipInvoice>>>>((ref) {
  return ref.watch(billingOverviewProvider).whenData((rows) {
    final out = <String, List<MembershipInvoice>>{};
    for (final i in rows.where((i) => i.isPayable)) {
      (out[i.businessId] ??= []).add(i);
    }
    for (final list in out.values) {
      list.sort((a, b) => a.periodStart.compareTo(b.periodStart));
    }
    return out;
  });
});
