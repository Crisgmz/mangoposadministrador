/// Categoría curada para clasificar la nota. Refleja `admin_customer_notes.category`.
enum NoteCategory {
  general,
  billingIssue,
  featureRequest,
  complaint,
  compliment,
  churnRisk,
  churnReason,
  salesFollowup,
  training,
  incident,
}

extension NoteCategoryX on NoteCategory {
  static NoteCategory fromText(String? raw) {
    switch (raw) {
      case 'billing_issue':
        return NoteCategory.billingIssue;
      case 'feature_request':
        return NoteCategory.featureRequest;
      case 'complaint':
        return NoteCategory.complaint;
      case 'compliment':
        return NoteCategory.compliment;
      case 'churn_risk':
        return NoteCategory.churnRisk;
      case 'churn_reason':
        return NoteCategory.churnReason;
      case 'sales_followup':
        return NoteCategory.salesFollowup;
      case 'training':
        return NoteCategory.training;
      case 'incident':
        return NoteCategory.incident;
      case 'general':
      default:
        return NoteCategory.general;
    }
  }

  String get raw {
    switch (this) {
      case NoteCategory.general:
        return 'general';
      case NoteCategory.billingIssue:
        return 'billing_issue';
      case NoteCategory.featureRequest:
        return 'feature_request';
      case NoteCategory.complaint:
        return 'complaint';
      case NoteCategory.compliment:
        return 'compliment';
      case NoteCategory.churnRisk:
        return 'churn_risk';
      case NoteCategory.churnReason:
        return 'churn_reason';
      case NoteCategory.salesFollowup:
        return 'sales_followup';
      case NoteCategory.training:
        return 'training';
      case NoteCategory.incident:
        return 'incident';
    }
  }

  String get label {
    switch (this) {
      case NoteCategory.general:
        return 'General';
      case NoteCategory.billingIssue:
        return 'Problema de cobro';
      case NoteCategory.featureRequest:
        return 'Pedido de feature';
      case NoteCategory.complaint:
        return 'Queja';
      case NoteCategory.compliment:
        return 'Elogio';
      case NoteCategory.churnRisk:
        return 'Riesgo de churn';
      case NoteCategory.churnReason:
        return 'Razón de churn';
      case NoteCategory.salesFollowup:
        return 'Seguimiento de venta';
      case NoteCategory.training:
        return 'Entrenamiento';
      case NoteCategory.incident:
        return 'Incidente';
    }
  }
}

class CustomerNote {
  const CustomerNote({
    required this.id,
    required this.businessId,
    required this.authorId,
    required this.authorName,
    required this.isOwn,
    required this.category,
    required this.body,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String businessId;
  final String authorId;
  final String? authorName;
  final bool isOwn;
  final NoteCategory category;
  final String body;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get wasEdited =>
      updatedAt.difference(createdAt).inSeconds > 5;

  factory CustomerNote.fromJson(Map<String, dynamic> json) {
    return CustomerNote(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String?,
      isOwn: (json['is_own'] as bool?) ?? false,
      category: NoteCategoryX.fromText(json['category'] as String?),
      body: (json['body'] as String?) ?? '',
      pinned: (json['pinned'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
