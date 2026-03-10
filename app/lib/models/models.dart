class AppUser {
  final String id;
  final String fullName;
  final String phone;

  AppUser({required this.id, required this.fullName, required this.phone});

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
    );
  }
}

class Group {
  final String id;
  final String name;
  final String currency;

  Group({required this.id, required this.name, required this.currency});

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String,
    );
  }
}

class GroupMember {
  final String id;
  final String fullName;

  GroupMember({required this.id, required this.fullName});

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
    );
  }
}

class GroupBalance {
  final String userId;
  final String fullName;
  final int netCents;

  GroupBalance({
    required this.userId,
    required this.fullName,
    required this.netCents,
  });

  factory GroupBalance.fromJson(Map<String, dynamic> json) {
    return GroupBalance(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      netCents: _asInt(json['net_cents']),
    );
  }
}

class ExpenseItem {
  final String id;
  final String description;
  final int amountCents;
  final String currency;
  final String createdById;
  final String createdByName;
  final List<ExpenseAttachment> attachments;

  ExpenseItem({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.createdById,
    required this.createdByName,
    this.attachments = const [],
  });

  factory ExpenseItem.fromJson(Map<String, dynamic> json) {
    return ExpenseItem(
      id: json['id'] as String,
      description: json['description'] as String,
      amountCents: _asInt(json['amount_cents']),
      currency: json['currency'] as String,
      createdById: json['created_by'] as String,
      createdByName: json['created_by_name'] as String,
      attachments: ((json['attachments'] as List<dynamic>?) ?? const [])
          .map((item) =>
              ExpenseAttachment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ExpenseAttachment {
  final String id;
  final String fileName;
  final String fileUrl;
  final String mimeType;
  final int sizeBytes;

  ExpenseAttachment({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory ExpenseAttachment.fromJson(Map<String, dynamic> json) {
    return ExpenseAttachment(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      fileUrl: json['fileUrl'] as String,
      mimeType: json['mimeType'] as String,
      sizeBytes: _asInt(json['sizeBytes']),
    );
  }
}

class ExpenseLineItem {
  final String userId;
  final String fullName;
  final int amountCents;

  ExpenseLineItem({
    required this.userId,
    required this.fullName,
    required this.amountCents,
  });

  factory ExpenseLineItem.fromJson(Map<String, dynamic> json) {
    return ExpenseLineItem(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      amountCents: _asInt(json['amount_cents']),
    );
  }
}

class ExpenseDetail {
  final ExpenseItem expense;
  final List<ExpenseLineItem> payers;
  final List<ExpenseLineItem> splits;
  final List<ExpensePendingPayment> pendingPayments;

  ExpenseDetail({
    required this.expense,
    required this.payers,
    required this.splits,
    required this.pendingPayments,
  });
}

class ExpensePendingPayment {
  final String userId;
  final String fullName;
  final int amountCents;
  final bool isPaid;
  final DateTime? paidAt;
  final DateTime? reminderSentAt;

  ExpensePendingPayment({
    required this.userId,
    required this.fullName,
    required this.amountCents,
    required this.isPaid,
    required this.paidAt,
    required this.reminderSentAt,
  });

  factory ExpensePendingPayment.fromJson(Map<String, dynamic> json) {
    return ExpensePendingPayment(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      amountCents: _asInt(json['amount_cents']),
      isPaid: json['is_paid'] as bool? ?? false,
      paidAt: json['paid_at'] == null
          ? null
          : DateTime.tryParse(json['paid_at'] as String),
      reminderSentAt: json['reminder_sent_at'] == null
          ? null
          : DateTime.tryParse(json['reminder_sent_at'] as String),
    );
  }
}

class InvitePreview {
  final String token;
  final bool isActive;
  final bool isExpired;
  final DateTime? expiresAt;
  final String groupId;
  final String groupName;
  final String currency;
  final int memberCount;

  InvitePreview({
    required this.token,
    required this.isActive,
    required this.isExpired,
    required this.expiresAt,
    required this.groupId,
    required this.groupName,
    required this.currency,
    required this.memberCount,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as Map<String, dynamic>;
    return InvitePreview(
      token: json['token'] as String,
      isActive: json['isActive'] as bool,
      isExpired: json['isExpired'] as bool,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt'] as String),
      groupId: group['id'] as String,
      groupName: group['name'] as String,
      currency: group['currency'] as String,
      memberCount: _asInt(group['memberCount']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
