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

class PairLedgerUser {
  final String id;
  final String fullName;

  PairLedgerUser({required this.id, required this.fullName});

  factory PairLedgerUser.fromJson(Map<String, dynamic> json) {
    return PairLedgerUser(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
    );
  }
}

class PairLedgerPartyTotals {
  final int paidCents;
  final int shareCents;
  final int netCents;

  PairLedgerPartyTotals({
    required this.paidCents,
    required this.shareCents,
    required this.netCents,
  });

  factory PairLedgerPartyTotals.fromJson(Map<String, dynamic> json) {
    return PairLedgerPartyTotals(
      paidCents: _asInt(json['paidCents']),
      shareCents: _asInt(json['shareCents']),
      netCents: _asInt(json['netCents']),
    );
  }
}

class PairLedgerExpenseParty extends PairLedgerPartyTotals {
  final String id;
  final String fullName;

  PairLedgerExpenseParty({
    required this.id,
    required this.fullName,
    required super.paidCents,
    required super.shareCents,
    required super.netCents,
  });

  factory PairLedgerExpenseParty.fromJson(Map<String, dynamic> json) {
    return PairLedgerExpenseParty(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      paidCents: _asInt(json['paidCents']),
      shareCents: _asInt(json['shareCents']),
      netCents: _asInt(json['netCents']),
    );
  }
}

class PairLedgerExpenseTransaction {
  final String? debtorId;
  final String? debtorName;
  final String? creditorId;
  final String? creditorName;
  final int amountCents;
  final bool isPaid;
  final DateTime? paidAt;

  PairLedgerExpenseTransaction({
    required this.debtorId,
    required this.debtorName,
    required this.creditorId,
    required this.creditorName,
    required this.amountCents,
    required this.isPaid,
    required this.paidAt,
  });

  factory PairLedgerExpenseTransaction.fromJson(Map<String, dynamic> json) {
    return PairLedgerExpenseTransaction(
      debtorId: json['debtorId'] as String?,
      debtorName: json['debtorName'] as String?,
      creditorId: json['creditorId'] as String?,
      creditorName: json['creditorName'] as String?,
      amountCents: _asInt(json['amountCents']),
      isPaid: json['isPaid'] as bool? ?? false,
      paidAt: _asDate(json['paidAt']),
    );
  }
}

class PairLedgerExpense {
  final String expenseId;
  final String description;
  final int amountCents;
  final String currency;
  final DateTime? expenseDate;
  final DateTime? createdAt;
  final String createdById;
  final String createdByName;
  final PairLedgerExpenseParty userA;
  final PairLedgerExpenseParty userB;
  final PairLedgerExpenseTransaction transaction;

  PairLedgerExpense({
    required this.expenseId,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.expenseDate,
    required this.createdAt,
    required this.createdById,
    required this.createdByName,
    required this.userA,
    required this.userB,
    required this.transaction,
  });

  factory PairLedgerExpense.fromJson(Map<String, dynamic> json) {
    return PairLedgerExpense(
      expenseId: json['expenseId'] as String,
      description: json['description'] as String,
      amountCents: _asInt(json['amountCents']),
      currency: json['currency'] as String,
      expenseDate: _asDate(json['expenseDate']),
      createdAt: _asDate(json['createdAt']),
      createdById: json['createdById'] as String,
      createdByName: json['createdByName'] as String,
      userA: PairLedgerExpenseParty.fromJson(
          json['userA'] as Map<String, dynamic>),
      userB: PairLedgerExpenseParty.fromJson(
          json['userB'] as Map<String, dynamic>),
      transaction: PairLedgerExpenseTransaction.fromJson(
        json['transaction'] as Map<String, dynamic>,
      ),
    );
  }
}

class PairLedgerTransaction {
  final String expenseId;
  final String description;
  final DateTime? expenseDate;
  final String? debtorId;
  final String? debtorName;
  final String? creditorId;
  final String? creditorName;
  final int amountCents;
  final bool isPaid;
  final DateTime? paidAt;

  PairLedgerTransaction({
    required this.expenseId,
    required this.description,
    required this.expenseDate,
    required this.debtorId,
    required this.debtorName,
    required this.creditorId,
    required this.creditorName,
    required this.amountCents,
    required this.isPaid,
    required this.paidAt,
  });

  factory PairLedgerTransaction.fromJson(Map<String, dynamic> json) {
    return PairLedgerTransaction(
      expenseId: json['expenseId'] as String,
      description: json['description'] as String,
      expenseDate: _asDate(json['expenseDate']),
      debtorId: json['debtorId'] as String?,
      debtorName: json['debtorName'] as String?,
      creditorId: json['creditorId'] as String?,
      creditorName: json['creditorName'] as String?,
      amountCents: _asInt(json['amountCents']),
      isPaid: json['isPaid'] as bool? ?? false,
      paidAt: _asDate(json['paidAt']),
    );
  }
}

class PairLedgerSettlement {
  final String? fromUserId;
  final String? fromUserName;
  final String? toUserId;
  final String? toUserName;
  final int amountCents;
  final String status;

  PairLedgerSettlement({
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amountCents,
    required this.status,
  });

  factory PairLedgerSettlement.fromJson(Map<String, dynamic> json) {
    return PairLedgerSettlement(
      fromUserId: json['fromUserId'] as String?,
      fromUserName: json['fromUserName'] as String?,
      toUserId: json['toUserId'] as String?,
      toUserName: json['toUserName'] as String?,
      amountCents: _asInt(json['amountCents']),
      status: (json['status'] as String?) ?? 'settled',
    );
  }
}

class PairLedgerTotals {
  final int totalExpenseCents;
  final PairLedgerPartyTotals userA;
  final PairLedgerPartyTotals userB;

  PairLedgerTotals({
    required this.totalExpenseCents,
    required this.userA,
    required this.userB,
  });

  factory PairLedgerTotals.fromJson(Map<String, dynamic> json) {
    return PairLedgerTotals(
      totalExpenseCents: _asInt(json['totalExpenseCents']),
      userA:
          PairLedgerPartyTotals.fromJson(json['userA'] as Map<String, dynamic>),
      userB:
          PairLedgerPartyTotals.fromJson(json['userB'] as Map<String, dynamic>),
    );
  }
}

class PairLedgerData {
  final PairLedgerUser userA;
  final PairLedgerUser userB;
  final List<PairLedgerExpense> expenses;
  final List<PairLedgerTransaction> transactions;
  final PairLedgerTotals totals;
  final PairLedgerSettlement settlement;

  PairLedgerData({
    required this.userA,
    required this.userB,
    required this.expenses,
    required this.transactions,
    required this.totals,
    required this.settlement,
  });

  factory PairLedgerData.fromJson(Map<String, dynamic> json) {
    final users = json['users'] as Map<String, dynamic>;
    return PairLedgerData(
      userA: PairLedgerUser.fromJson(users['userA'] as Map<String, dynamic>),
      userB: PairLedgerUser.fromJson(users['userB'] as Map<String, dynamic>),
      expenses: ((json['expenses'] as List<dynamic>?) ?? const [])
          .map((item) =>
              PairLedgerExpense.fromJson(item as Map<String, dynamic>))
          .toList(),
      transactions: ((json['transactions'] as List<dynamic>?) ?? const [])
          .map((item) =>
              PairLedgerTransaction.fromJson(item as Map<String, dynamic>))
          .toList(),
      totals: PairLedgerTotals.fromJson(json['totals'] as Map<String, dynamic>),
      settlement: PairLedgerSettlement.fromJson(
          json['settlement'] as Map<String, dynamic>),
    );
  }
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
