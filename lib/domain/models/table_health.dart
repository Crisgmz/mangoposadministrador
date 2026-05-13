import '_json_helpers.dart';
import 'business_environment.dart';

/// KPIs agregados de salud de mesas (`get_admin_table_health`).
class TableHealthSummary {
  const TableHealthSummary({
    required this.zombieSessions,
    required this.stuckPayments,
    required this.orphanItems,
    required this.totalUnpaid,
  });

  final int zombieSessions;
  final int stuckPayments;
  final int orphanItems;
  final double totalUnpaid;

  factory TableHealthSummary.fromJson(Map<String, dynamic> json) {
    return TableHealthSummary(
      zombieSessions: parseInt(json['zombie_sessions']),
      stuckPayments: parseInt(json['stuck_payments']),
      orphanItems: parseInt(json['orphan_items']),
      totalUnpaid: parseDouble(json['total_unpaid']),
    );
  }
}

/// Una sesión de mesa abierta hace >24h sin cerrar.
class ZombieTableSession {
  const ZombieTableSession({
    required this.sessionId,
    required this.businessId,
    required this.businessName,
    required this.environment,
    this.tableId,
    this.tableCode,
    this.tableLabel,
    this.tableState,
    required this.openedAt,
    this.customerName,
    this.waiterUserId,
    this.waiterName,
    required this.ageSeconds,
    required this.ordersCount,
    required this.openOrders,
    required this.totalUnpaidEstimated,
  });

  final String sessionId;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String? tableId;
  final String? tableCode;
  final String? tableLabel;
  final String? tableState;
  final DateTime openedAt;
  final String? customerName;
  final String? waiterUserId;
  final String? waiterName;
  final int ageSeconds;
  final int ordersCount;
  final int openOrders;
  final double totalUnpaidEstimated;

  Duration get age => Duration(seconds: ageSeconds);

  /// `Mesa 12` / `Bar 3` / `—` según label/code/null.
  String get tableDisplay {
    if (tableLabel != null && tableLabel!.trim().isNotEmpty) return tableLabel!;
    if (tableCode != null && tableCode!.trim().isNotEmpty) return tableCode!;
    return 'Sin mesa';
  }

  factory ZombieTableSession.fromJson(Map<String, dynamic> json) {
    return ZombieTableSession(
      sessionId: json['session_id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      tableId: json['table_id'] as String?,
      tableCode: json['table_code'] as String?,
      tableLabel: json['table_label'] as String?,
      tableState: json['table_state'] as String?,
      openedAt: parseDate(json['opened_at']) ?? DateTime.now(),
      customerName: json['customer_name'] as String?,
      waiterUserId: json['waiter_user_id'] as String?,
      waiterName: json['waiter_name'] as String?,
      ageSeconds: parseInt(json['age_seconds']),
      ordersCount: parseInt(json['orders_count']),
      openOrders: parseInt(json['open_orders']),
      totalUnpaidEstimated: parseDouble(json['total_unpaid_estimated']),
    );
  }
}

/// Una orden con pago parcial atascada > 1h.
class StuckPayment {
  const StuckPayment({
    required this.orderId,
    required this.sessionId,
    required this.businessId,
    required this.businessName,
    required this.environment,
    this.tableId,
    this.tableCode,
    this.tableLabel,
    required this.orderStatus,
    required this.subtotal,
    required this.discounts,
    required this.tax,
    required this.serviceFee,
    required this.total,
    required this.createdAt,
    required this.ageSeconds,
    required this.paidSoFar,
    required this.remaining,
  });

  final String orderId;
  final String sessionId;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String? tableId;
  final String? tableCode;
  final String? tableLabel;
  final String orderStatus;
  final double subtotal;
  final double discounts;
  final double tax;
  final double serviceFee;
  final double total;
  final DateTime createdAt;
  final int ageSeconds;
  final double paidSoFar;
  final double remaining;

  String get tableDisplay {
    if (tableLabel != null && tableLabel!.trim().isNotEmpty) return tableLabel!;
    if (tableCode != null && tableCode!.trim().isNotEmpty) return tableCode!;
    return 'Sin mesa';
  }

  factory StuckPayment.fromJson(Map<String, dynamic> json) {
    return StuckPayment(
      orderId: json['order_id'] as String,
      sessionId: json['session_id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      tableId: json['table_id'] as String?,
      tableCode: json['table_code'] as String?,
      tableLabel: json['table_label'] as String?,
      orderStatus: (json['order_status'] as String?) ?? '',
      subtotal: parseDouble(json['subtotal']),
      discounts: parseDouble(json['discounts']),
      tax: parseDouble(json['tax']),
      serviceFee: parseDouble(json['service_fee']),
      total: parseDouble(json['total']),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      ageSeconds: parseInt(json['age_seconds']),
      paidSoFar: parseDouble(json['paid_so_far']),
      remaining: parseDouble(json['remaining']),
    );
  }
}

/// Un item huérfano (status activo pero orden/sesión cerrada).
class OrphanOrderItem {
  const OrphanOrderItem({
    required this.itemId,
    required this.orderId,
    required this.productName,
    required this.itemStatus,
    required this.itemCreatedAt,
    required this.orderStatus,
    this.orderClosedAt,
    required this.sessionId,
    required this.businessId,
    required this.businessName,
    required this.environment,
    this.tableCode,
    this.sessionClosedAt,
  });

  final String itemId;
  final String orderId;
  final String productName;
  final String itemStatus;
  final DateTime itemCreatedAt;
  final String orderStatus;
  final DateTime? orderClosedAt;
  final String sessionId;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String? tableCode;
  final DateTime? sessionClosedAt;

  factory OrphanOrderItem.fromJson(Map<String, dynamic> json) {
    return OrphanOrderItem(
      itemId: json['item_id'] as String,
      orderId: json['order_id'] as String,
      productName: (json['product_name'] as String?) ?? '—',
      itemStatus: (json['item_status'] as String?) ?? '',
      itemCreatedAt: parseDate(json['item_created_at']) ?? DateTime.now(),
      orderStatus: (json['order_status'] as String?) ?? '',
      orderClosedAt: parseDate(json['order_closed_at']),
      sessionId: json['session_id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      tableCode: json['table_code'] as String?,
      sessionClosedAt: parseDate(json['session_closed_at']),
    );
  }
}
