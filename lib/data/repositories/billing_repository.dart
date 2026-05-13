import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/membership_invoice.dart';

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
