import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_chrome.dart';

class PairLedgerScreen extends StatefulWidget {
  const PairLedgerScreen({
    super.key,
    required this.apiService,
    required this.group,
    required this.userA,
    required this.userB,
  });

  final ApiService apiService;
  final Group group;
  final GroupMember userA;
  final GroupMember userB;

  @override
  State<PairLedgerScreen> createState() => _PairLedgerScreenState();
}

class _PairLedgerScreenState extends State<PairLedgerScreen> {
  PairLedgerData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await widget.apiService.getPairLedger(
        groupId: widget.group.id,
        userAId: widget.userA.id,
        userBId: widget.userB.id,
      );

      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Could not load pair ledger.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _exportCsv() async {
    final data = _data;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ledger is still loading. Please try again.')),
      );
      return;
    }

    final fileName = _exportFileName('csv');
    final csv = _buildCsv(data);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    await _shareFile(bytes: bytes, fileName: fileName, mimeType: 'text/csv');
  }

  Future<void> _exportXlsx() async {
    final data = _data;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ledger is still loading. Please try again.')),
      );
      return;
    }

    final bytes = _buildXlsx(data);
    final fileName = _exportFileName('xlsx');
    await _shareFile(
      bytes: bytes,
      fileName: fileName,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(bytes, mimeType: mimeType),
        ],
        fileNameOverrides: [fileName],
        text:
            'Pair ledger export: ${widget.userA.fullName} vs ${widget.userB.fullName}',
        subject: 'Pair Ledger Export',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Could not export file.',
            ),
          ),
        ),
      );
    }
  }

  String _exportFileName(String extension) {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final a = widget.userA.fullName.replaceAll(' ', '_');
    final b = widget.userB.fullName.replaceAll(' ', '_');
    return 'pair_ledger_${a}_vs_${b}_$stamp.$extension';
  }

  String _buildCsv(PairLedgerData data) {
    final rows = <List<String>>[];
    rows.add(['Pair Ledger']);
    rows.add(['Group', widget.group.name]);
    rows.add(['User A', data.userA.fullName]);
    rows.add(['User B', data.userB.fullName]);
    rows.add(['']);

    rows.add(['Totals']);
    rows.add(['Metric', data.userA.fullName, data.userB.fullName]);
    rows.add([
      'Paid',
      '${data.totals.userA.paidCents}',
      '${data.totals.userB.paidCents}'
    ]);
    rows.add([
      'Share',
      '${data.totals.userA.shareCents}',
      '${data.totals.userB.shareCents}'
    ]);
    rows.add([
      'Net',
      '${data.totals.userA.netCents}',
      '${data.totals.userB.netCents}'
    ]);
    rows.add(['Total Expense Cents', '${data.totals.totalExpenseCents}']);
    rows.add(['']);

    rows.add(['Expenses']);
    rows.add([
      'Expense ID',
      'Description',
      'Expense Date',
      'Total Cents',
      '${data.userA.fullName} Paid',
      '${data.userA.fullName} Share',
      '${data.userB.fullName} Paid',
      '${data.userB.fullName} Share',
      'Debtor',
      'Creditor',
      'Transaction Cents',
      'Is Paid'
    ]);
    for (final e in data.expenses) {
      rows.add([
        e.expenseId,
        e.description,
        e.expenseDate?.toIso8601String() ?? '',
        '${e.amountCents}',
        '${e.userA.paidCents}',
        '${e.userA.shareCents}',
        '${e.userB.paidCents}',
        '${e.userB.shareCents}',
        e.transaction.debtorName ?? '',
        e.transaction.creditorName ?? '',
        '${e.transaction.amountCents}',
        '${e.transaction.isPaid}',
      ]);
    }
    rows.add(['']);

    rows.add(['Transactions']);
    rows.add([
      'Expense ID',
      'Description',
      'Debtor',
      'Creditor',
      'Amount Cents',
      'Is Paid',
      'Paid At'
    ]);
    for (final t in data.transactions) {
      rows.add([
        t.expenseId,
        t.description,
        t.debtorName ?? '',
        t.creditorName ?? '',
        '${t.amountCents}',
        '${t.isPaid}',
        t.paidAt?.toIso8601String() ?? '',
      ]);
    }
    rows.add(['']);

    rows.add(['Final Settlement']);
    rows.add([
      'Status',
      data.settlement.status,
      'From',
      data.settlement.fromUserName ?? '',
      'To',
      data.settlement.toUserName ?? '',
      'Amount Cents',
      '${data.settlement.amountCents}'
    ]);

    return rows.map((row) => row.map(_csvCell).join(',')).join('\n');
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Uint8List _buildXlsx(PairLedgerData data) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    _appendExcelRow(sheet, ['Pair Ledger']);
    _appendExcelRow(sheet, ['Group', widget.group.name]);
    _appendExcelRow(sheet, ['User A', data.userA.fullName]);
    _appendExcelRow(sheet, ['User B', data.userB.fullName]);
    _appendExcelRow(sheet, const []);

    _appendExcelRow(sheet, ['Totals']);
    _appendExcelRow(
        sheet, ['Metric', data.userA.fullName, data.userB.fullName]);
    _appendExcelRow(sheet,
        ['Paid', data.totals.userA.paidCents, data.totals.userB.paidCents]);
    _appendExcelRow(sheet,
        ['Share', data.totals.userA.shareCents, data.totals.userB.shareCents]);
    _appendExcelRow(
        sheet, ['Net', data.totals.userA.netCents, data.totals.userB.netCents]);
    _appendExcelRow(
        sheet, ['Total Expense Cents', data.totals.totalExpenseCents]);
    _appendExcelRow(sheet, const []);

    _appendExcelRow(sheet, ['Expenses']);
    _appendExcelRow(sheet, [
      'Expense ID',
      'Description',
      'Expense Date',
      'Total Cents',
      '${data.userA.fullName} Paid',
      '${data.userA.fullName} Share',
      '${data.userB.fullName} Paid',
      '${data.userB.fullName} Share',
      'Debtor',
      'Creditor',
      'Transaction Cents',
      'Is Paid'
    ]);
    for (final e in data.expenses) {
      _appendExcelRow(sheet, [
        e.expenseId,
        e.description,
        e.expenseDate?.toIso8601String() ?? '',
        e.amountCents,
        e.userA.paidCents,
        e.userA.shareCents,
        e.userB.paidCents,
        e.userB.shareCents,
        e.transaction.debtorName ?? '',
        e.transaction.creditorName ?? '',
        e.transaction.amountCents,
        e.transaction.isPaid,
      ]);
    }
    _appendExcelRow(sheet, const []);

    _appendExcelRow(sheet, ['Transactions']);
    _appendExcelRow(sheet, [
      'Expense ID',
      'Description',
      'Debtor',
      'Creditor',
      'Amount Cents',
      'Is Paid',
      'Paid At'
    ]);
    for (final t in data.transactions) {
      _appendExcelRow(sheet, [
        t.expenseId,
        t.description,
        t.debtorName ?? '',
        t.creditorName ?? '',
        t.amountCents,
        t.isPaid,
        t.paidAt?.toIso8601String() ?? '',
      ]);
    }
    _appendExcelRow(sheet, const []);

    _appendExcelRow(sheet, ['Final Settlement']);
    _appendExcelRow(sheet, [
      'Status',
      data.settlement.status,
      'From',
      data.settlement.fromUserName ?? '',
      'To',
      data.settlement.toUserName ?? '',
      'Amount Cents',
      data.settlement.amountCents
    ]);

    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? <int>[]);
  }

  void _appendExcelRow(Sheet sheet, List<Object?> rowValues) {
    sheet.appendRow(rowValues.map(_toCellValue).toList(growable: false));
  }

  CellValue? _toCellValue(Object? value) {
    if (value == null) return null;
    if (value is CellValue) return value;
    if (value is String) return TextCellValue(value);
    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    if (value is DateTime) return DateTimeCellValue.fromDateTime(value);
    return TextCellValue(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final formatter =
        NumberFormat.currency(symbol: '${widget.group.currency} ');
    final dateFmt = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('2-Person Ledger'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'csv') {
                _exportCsv();
              } else if (value == 'xlsx') {
                _exportXlsx();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'csv',
                child: Text('Export CSV'),
              ),
              PopupMenuItem<String>(
                value: 'xlsx',
                child: Text('Export XLSX'),
              ),
            ],
          ),
        ],
      ),
      body: AppChrome(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.only(top: 92, bottom: 24),
            children: [
              Text(
                '${widget.userA.fullName} vs ${widget.userB.fullName}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(widget.group.name,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_data == null)
                const EmptyStateCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Ledger unavailable',
                  subtitle: 'Try refreshing this page.',
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Expenses',
                        value: '${_data!.expenses.length}',
                        caption: 'Only between these two',
                        icon: Icons.receipt_long_rounded,
                        accent: const Color(0xFF26D3B4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Total value',
                        value: formatter
                            .format(_data!.totals.totalExpenseCents / 100),
                        caption: 'Combined expenses',
                        icon: Icons.account_balance_wallet_rounded,
                        accent: const Color(0xFFFF8E5F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                AppPanel(
                  borderRadius: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Totals',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 10),
                      _TotalsLine(
                        label: _data!.userA.fullName,
                        paid: _data!.totals.userA.paidCents,
                        share: _data!.totals.userA.shareCents,
                        net: _data!.totals.userA.netCents,
                        formatter: formatter,
                      ),
                      const SizedBox(height: 8),
                      _TotalsLine(
                        label: _data!.userB.fullName,
                        paid: _data!.totals.userB.paidCents,
                        share: _data!.totals.userB.shareCents,
                        net: _data!.totals.userB.netCents,
                        formatter: formatter,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionTitle('Expenses (one by one)'),
                const SizedBox(height: 10),
                if (_data!.expenses.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.receipt_rounded,
                    title: 'No direct expenses found',
                    subtitle:
                        'No expenses found where both users participated.',
                  )
                else
                  ..._data!.expenses.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppPanel(
                        borderRadius: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              e.expenseDate == null
                                  ? 'Date unavailable'
                                  : dateFmt.format(e.expenseDate!),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total: ${formatter.format(e.amountCents / 100)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            _PartyBreakdownLine(
                              name: e.userA.fullName,
                              paidCents: e.userA.paidCents,
                              shareCents: e.userA.shareCents,
                              formatter: formatter,
                            ),
                            const SizedBox(height: 6),
                            _PartyBreakdownLine(
                              name: e.userB.fullName,
                              paidCents: e.userB.paidCents,
                              shareCents: e.userB.shareCents,
                              formatter: formatter,
                            ),
                            if (e.transaction.amountCents > 0) ...[
                              const SizedBox(height: 10),
                              _InlineTransactionSummary(
                                debtorName:
                                    e.transaction.debtorName ?? 'Unknown',
                                creditorName:
                                    e.transaction.creditorName ?? 'Unknown',
                                amountCents: e.transaction.amountCents,
                                isPaid: e.transaction.isPaid,
                                formatter: formatter,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const SectionTitle('Transactions'),
                const SizedBox(height: 10),
                if (_data!.transactions.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.swap_horiz_rounded,
                    title: 'No pending flow',
                    subtitle:
                        'No transaction entries were created for these expenses.',
                  )
                else
                  ..._data!.transactions.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppPanel(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        borderRadius: 18,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${t.debtorName ?? 'Unknown'} -> ${t.creditorName ?? 'Unknown'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${t.description} • ${t.isPaid ? 'Paid' : 'Pending'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              formatter.format(t.amountCents / 100),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const SectionTitle('Final Settlement'),
                const SizedBox(height: 10),
                AppPanel(
                  borderRadius: 24,
                  child: _data!.settlement.amountCents == 0
                      ? const Text(
                          'Both are settled up. Nobody owes anything.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        )
                      : Text(
                          '${_data!.settlement.fromUserName} owes ${_data!.settlement.toUserName} ${formatter.format(_data!.settlement.amountCents / 100)}',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsLine extends StatelessWidget {
  const _TotalsLine({
    required this.label,
    required this.paid,
    required this.share,
    required this.net,
    required this.formatter,
  });

  final String label;
  final int paid;
  final int share;
  final int net;
  final NumberFormat formatter;

  @override
  Widget build(BuildContext context) {
    final color = net > 0
        ? const Color(0xFF26D3B4)
        : net < 0
            ? const Color(0xFFFF8E5F)
            : const Color(0xFF8CA2AE);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
            'Paid: ${formatter.format(paid / 100)} • Share: ${formatter.format(share / 100)}'),
        const SizedBox(height: 2),
        Text(
          'Net: ${net == 0 ? formatter.format(0) : '${net > 0 ? '+' : '-'} ${formatter.format(net.abs() / 100)}'}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _PartyBreakdownLine extends StatelessWidget {
  const _PartyBreakdownLine({
    required this.name,
    required this.paidCents,
    required this.shareCents,
    required this.formatter,
  });

  final String name;
  final int paidCents;
  final int shareCents;
  final NumberFormat formatter;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$name • paid ${formatter.format(paidCents / 100)} • share ${formatter.format(shareCents / 100)}',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _InlineTransactionSummary extends StatelessWidget {
  const _InlineTransactionSummary({
    required this.debtorName,
    required this.creditorName,
    required this.amountCents,
    required this.isPaid,
    required this.formatter,
  });

  final String debtorName;
  final String creditorName;
  final int amountCents;
  final bool isPaid;
  final NumberFormat formatter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isPaid ? const Color(0x1A26D3B4) : const Color(0x1AFF8E5F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$debtorName owes $creditorName ${formatter.format(amountCents / 100)} (${isPaid ? 'Paid' : 'Pending'})',
      ),
    );
  }
}
