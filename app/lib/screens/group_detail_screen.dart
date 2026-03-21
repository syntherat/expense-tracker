import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_chrome.dart';
import 'add_expense_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.apiService,
    required this.group,
    required this.user,
  });

  final ApiService apiService;
  final Group group;
  final AppUser user;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  List<GroupMember> _members = [];
  List<GroupBalance> _balances = [];
  List<ExpenseItem> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final details = await widget.apiService.getGroupDetails(widget.group.id);
      final expenses = await widget.apiService.listExpenses(widget.group.id);

      if (!mounted) return;
      setState(() {
        _members = details.members;
        _balances = details.balances;
        _expenses = expenses;
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
              fallback: 'Could not load group details.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _addExpense() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          apiService: widget.apiService,
          group: widget.group,
          members: _members,
          user: widget.user,
        ),
      ),
    );
    await _load();
  }

  Future<void> _refreshInvite() async {
    try {
      final inviteLink = await widget.apiService.refreshInvite(widget.group.id);
      final shareUrl = widget.apiService.buildShareableInviteUrl(inviteLink);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New invite link'),
          content: SelectableText(shareUrl),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Share.share(
                  'Join my expense group: $shareUrl',
                  subject: 'Group invite link',
                );
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            )
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Could not refresh invite link.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openTransactionsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _TransactionsPage(
          apiService: widget.apiService,
          group: widget.group,
          user: widget.user,
          initialExpenses: _expenses,
        ),
      ),
    );

    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter =
        NumberFormat.currency(symbol: '${widget.group.currency} ');
    final byUserId = {for (final b in _balances) b.userId: b};
    final me = _balances
        .where((b) => b.userId == widget.user.id)
        .cast<GroupBalance?>()
        .firstWhere((b) => b != null, orElse: () => null);

    final flows = _computeSettlementFlows(_balances);
    final iOwe = flows.where((f) => f.fromUserId == widget.user.id).toList();
    final owedToMe = flows.where((f) => f.toUserId == widget.user.id).toList();

    final groupSettled = _balances.every((b) => b.netCents == 0);
    final youOwe = iOwe.isNotEmpty || (me != null && me.netCents < 0);
    final youGet = owedToMe.isNotEmpty || (me != null && me.netCents > 0);

    final headerIcon = groupSettled
        ? Icons.check_circle_rounded
        : youOwe
            ? Icons.arrow_upward_rounded
            : youGet
                ? Icons.arrow_downward_rounded
                : Icons.info_outline_rounded;

    final headerLabel = groupSettled
        ? 'Settled'
        : youOwe
            ? 'You owe'
            : youGet
                ? 'You get'
                : 'Open balances';

    final headerColor = groupSettled
        ? const Color(0xFF26D3B4)
        : youOwe
            ? const Color(0xFFFF8E5F)
            : const Color(0xFF26D3B4);

    final summaryText = me == null
        ? 'No balance data yet'
        : groupSettled
            ? 'Everything is settled up.'
            : youOwe
                ? 'You owe ${formatter.format((-me.netCents).abs() / 100)} in this group.'
                : youGet
                    ? 'You should get ${formatter.format(me.netCents.abs() / 100)} back.'
                    : 'You are settled, but other members still have pending balances.';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              onPressed: _refreshInvite,
              icon: const Icon(Icons.link_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('Add expense'),
      ),
      body: AppChrome(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.only(top: 92, bottom: 110),
                  children: [
                    AppPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              InitialAvatar(
                                  seed: widget.group.id,
                                  label: widget.group.name,
                                  radius: 26),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.group.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${_members.length} members • ${widget.group.currency}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium),
                                  ],
                                ),
                              ),
                              StatChip(
                                icon: headerIcon,
                                label: headerLabel,
                                color: headerColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            summaryText,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: MetricCard(
                            title: 'Members',
                            value: '${_members.length}',
                            caption: 'In this group',
                            icon: Icons.groups_rounded,
                            accent: const Color(0xFF26D3B4),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: MetricCard(
                            title: 'Expenses',
                            value: '${_expenses.length}',
                            caption: 'Tracked items',
                            icon: Icons.receipt_long_rounded,
                            accent: const Color(0xFFFF8E5F),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('Who Owes Whom'),
                    const SizedBox(height: 12),
                    if (iOwe.isEmpty && owedToMe.isEmpty)
                      const EmptyStateCard(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'No pending payments for you',
                        subtitle:
                            'You do not owe anyone, and nobody owes you right now.',
                      )
                    else ...[
                      if (iOwe.isNotEmpty)
                        _FlowGroupCard(
                          title: 'You owe',
                          accent: const Color(0xFFFF8E5F),
                          children: iOwe
                              .map(
                                (f) => _FlowLine(
                                  left: 'You',
                                  right: byUserId[f.toUserId]?.fullName ??
                                      'Unknown',
                                  amountCents: f.amountCents,
                                  formatter: formatter,
                                ),
                              )
                              .toList(),
                        ),
                      if (iOwe.isNotEmpty && owedToMe.isNotEmpty)
                        const SizedBox(height: 12),
                      if (owedToMe.isNotEmpty)
                        _FlowGroupCard(
                          title: 'Owed to you',
                          accent: const Color(0xFF26D3B4),
                          children: owedToMe
                              .map(
                                (f) => _FlowLine(
                                  left: byUserId[f.fromUserId]?.fullName ??
                                      'Unknown',
                                  right: 'You',
                                  amountCents: f.amountCents,
                                  formatter: formatter,
                                ),
                              )
                              .toList(),
                        ),
                    ],
                    const SizedBox(height: 24),
                    const SectionTitle('Balances'),
                    const SizedBox(height: 12),
                    ..._balances.map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BalanceTile(balance: b, formatter: formatter),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SectionTitle('Expenses'),
                    const SizedBox(height: 12),
                    if (_expenses.isEmpty)
                      const EmptyStateCard(
                        icon: Icons.receipt_long_rounded,
                        title: 'No expenses added',
                        subtitle: 'Create an expense and it will appear here.',
                      )
                    else
                      ..._expenses.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ExpenseTile(
                            expense: e,
                            formatter: formatter,
                            onTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final wasDeleted = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => _ExpenseDetailPage(
                                    apiService: widget.apiService,
                                    expenseId: e.id,
                                    user: widget.user,
                                    currency: widget.group.currency,
                                  ),
                                ),
                              );
                              if (!mounted) return;
                              await _load();
                              if (wasDeleted == true) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Expense deleted.'),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    const SectionTitle('Transactions'),
                    const SizedBox(height: 12),
                    AppPanel(
                      borderRadius: 24,
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0x331083A8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.receipt_long_rounded,
                                color: Color(0xFF26D3B4)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Group transactions',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Open a separate page to view all payment transactions in this group.',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonalIcon(
                            onPressed: _openTransactionsPage,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Open'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

List<_SettlementFlow> _computeSettlementFlows(List<GroupBalance> balances) {
  final debtors = <_BalanceNode>[];
  final creditors = <_BalanceNode>[];

  for (final b in balances) {
    if (b.netCents < 0) {
      debtors.add(_BalanceNode(userId: b.userId, amountCents: -b.netCents));
    } else if (b.netCents > 0) {
      creditors.add(_BalanceNode(userId: b.userId, amountCents: b.netCents));
    }
  }

  debtors.sort((a, b) => b.amountCents.compareTo(a.amountCents));
  creditors.sort((a, b) => b.amountCents.compareTo(a.amountCents));

  final flows = <_SettlementFlow>[];
  var i = 0;
  var j = 0;

  while (i < debtors.length && j < creditors.length) {
    final debtor = debtors[i];
    final creditor = creditors[j];
    final amount = debtor.amountCents < creditor.amountCents
        ? debtor.amountCents
        : creditor.amountCents;

    if (amount > 0) {
      flows.add(
        _SettlementFlow(
          fromUserId: debtor.userId,
          toUserId: creditor.userId,
          amountCents: amount,
        ),
      );
    }

    debtor.amountCents -= amount;
    creditor.amountCents -= amount;

    if (debtor.amountCents == 0) i++;
    if (creditor.amountCents == 0) j++;
  }

  return flows;
}

class _BalanceNode {
  _BalanceNode({required this.userId, required this.amountCents});

  final String userId;
  int amountCents;
}

class _SettlementFlow {
  const _SettlementFlow({
    required this.fromUserId,
    required this.toUserId,
    required this.amountCents,
  });

  final String fromUserId;
  final String toUserId;
  final int amountCents;
}

class _FlowGroupCard extends StatelessWidget {
  const _FlowGroupCard({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: accent),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _FlowLine extends StatelessWidget {
  const _FlowLine({
    required this.left,
    required this.right,
    required this.amountCents,
    required this.formatter,
  });

  final String left;
  final String right;
  final int amountCents;
  final NumberFormat formatter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_right_alt_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(right, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Text(
            formatter.format(amountCents / 100),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.balance, required this.formatter});

  final GroupBalance balance;
  final NumberFormat formatter;

  @override
  Widget build(BuildContext context) {
    final positive = balance.netCents > 0;
    final zero = balance.netCents == 0;
    final accent = zero
        ? const Color(0xFF8CA2AE)
        : positive
            ? const Color(0xFF26D3B4)
            : const Color(0xFFFF8E5F);

    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderRadius: 24,
      child: Row(
        children: [
          InitialAvatar(
              seed: balance.userId, label: balance.fullName, radius: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(balance.fullName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  zero
                      ? 'Settled'
                      : positive
                          ? 'Should receive'
                          : 'Owes money',
                ),
              ],
            ),
          ),
          Text(
            zero
                ? formatter.format(0)
                : '${positive ? '+' : '-'} ${formatter.format(balance.netCents.abs() / 100)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseDetailPage extends StatefulWidget {
  const _ExpenseDetailPage({
    required this.apiService,
    required this.expenseId,
    required this.user,
    required this.currency,
  });

  final ApiService apiService;
  final String expenseId;
  final AppUser user;
  final String currency;

  @override
  State<_ExpenseDetailPage> createState() => _ExpenseDetailPageState();
}

class _ExpenseDetailPageState extends State<_ExpenseDetailPage> {
  ExpenseDetail? _detail;
  bool _loading = true;
  bool _busy = false;

  bool get _isCreator => _detail?.expense.createdById == widget.user.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail =
          await widget.apiService.getExpenseDetails(widget.expenseId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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
              fallback: 'Could not load expense details.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openAttachment(ExpenseAttachment attachment) async {
    final isImage = attachment.mimeType.startsWith('image/');
    if (isImage) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _ImageAttachmentPage(
            title: attachment.fileName,
            imageUrl: attachment.fileUrl,
          ),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(attachment.fileUrl);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid attachment URL.')),
      );
      return;
    }

    final opened = kIsWeb
        ? await launchUrl(uri, webOnlyWindowName: '_blank')
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open attachment.')),
      );
    }
  }

  Future<void> _deleteExpense() async {
    final detail = _detail;
    if (detail == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          'This will permanently delete "${detail.expense.description}" and all its payment records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6E74),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.apiService.deleteExpense(detail.expense.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Could not delete expense.',
            ),
          ),
        ),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: '${widget.currency} ');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Expense details'),
          actions: [
            if (_isCreator)
              PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteExpense();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded),
                        SizedBox(width: 10),
                        Text('Delete expense'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Transactions'),
            ],
          ),
        ),
        body: AppChrome(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _detail == null
                  ? const Center(child: Text('Expense not found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: TabBarView(
                        children: [
                          ListView(
                            padding: const EdgeInsets.only(top: 92, bottom: 24),
                            children: [
                              AppPanel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _detail!.expense.description,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Added by ${_detail!.expense.createdByName}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatter.format(
                                          _detail!.expense.amountCents / 100),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              const SectionTitle('Who Owes Whom'),
                              const SizedBox(height: 10),
                              ...(() {
                                final flows = _computeExpenseFlows(
                                  _detail!.payers,
                                  _detail!.splits,
                                );
                                if (flows.isEmpty) {
                                  return [
                                    const EmptyStateCard(
                                      icon: Icons.check_circle_outline_rounded,
                                      title: 'This expense is settled',
                                      subtitle:
                                          'No one owes anyone for this expense.',
                                    )
                                  ];
                                }

                                return flows
                                    .map(
                                      (f) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: AppPanel(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                          borderRadius: 18,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  f.fromName,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              const Icon(
                                                  Icons.arrow_right_alt_rounded,
                                                  size: 18),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  f.toName,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                formatter.format(
                                                    f.amountCents / 100),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList();
                              })(),
                              const SizedBox(height: 14),
                              const SectionTitle('Attachments'),
                              const SizedBox(height: 10),
                              if (_detail!.expense.attachments.isEmpty)
                                const EmptyStateCard(
                                  icon: Icons.attach_file_rounded,
                                  title: 'No attachments',
                                  subtitle:
                                      'No files were attached to this expense.',
                                )
                              else
                                ..._detail!.expense.attachments.map(
                                  (a) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => _openAttachment(a),
                                      child: AppPanel(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        borderRadius: 16,
                                        child: Row(
                                          children: [
                                            Icon(
                                              a.mimeType.startsWith('image/')
                                                  ? Icons.image_rounded
                                                  : Icons.description_rounded,
                                              color: const Color(0xFF26D3B4),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(a.fileName,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                  const SizedBox(height: 2),
                                                  Text(a.mimeType,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                                Icons.open_in_new_rounded),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          ListView(
                            padding: const EdgeInsets.only(top: 92, bottom: 24),
                            children: [
                              const SectionTitle('Expense Transactions'),
                              const SizedBox(height: 8),
                              ..._buildPendingRows(context, formatter),
                            ],
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  List<Widget> _buildPendingRows(BuildContext context, NumberFormat formatter) {
    if (_detail == null || _detail!.pendingPayments.isEmpty) {
      return const [Text('No payment tracking rows for this expense.')];
    }

    final isCreator = _detail!.expense.createdById == widget.user.id;
    final pending = _detail!.pendingPayments.where((p) => !p.isPaid).toList();
    final rows = <Widget>[];

    for (final p in _detail!.pendingPayments) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: 16,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.fullName),
                      const SizedBox(height: 2),
                      Text(
                        formatter.format(p.amountCents / 100),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.isPaid
                        ? const Color(0x3326D3B4)
                        : const Color(0x33FF8E5F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    p.isPaid ? 'Paid' : 'Pending',
                    style: TextStyle(
                      color: p.isPaid
                          ? const Color(0xFF26D3B4)
                          : const Color(0xFFFF8E5F),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isCreator) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _busy = true);
                            try {
                              await widget.apiService.markExpensePayment(
                                _detail!.expense.id,
                                p.userId,
                                isPaid: !p.isPaid,
                              );
                              await _load();
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ApiService.readErrorMessage(
                                      e,
                                      fallback:
                                          'Could not update payment status.',
                                    ),
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon: Icon(
                      p.isPaid ? Icons.undo_rounded : Icons.check_rounded,
                    ),
                    tooltip: p.isPaid ? 'Mark unpaid' : 'Mark paid',
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (isCreator && pending.isNotEmpty) {
      rows.add(const SizedBox(height: 10));
      rows.add(
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _busy = true);
                  try {
                    final count = await widget.apiService.sendExpenseReminder(
                      _detail!.expense.id,
                      userIds: pending.map((item) => item.userId).toList(),
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                          content: Text('Reminder sent to $count user(s).')),
                    );
                    await _load();
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          ApiService.readErrorMessage(
                            e,
                            fallback: 'Could not send reminder.',
                          ),
                        ),
                      ),
                    );
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.notifications_active_rounded),
          label: const Text('Send reminder to pending users'),
        ),
      );
    }

    return rows;
  }
}

class _TransactionsPage extends StatefulWidget {
  const _TransactionsPage({
    required this.apiService,
    required this.group,
    required this.user,
    required this.initialExpenses,
  });

  final ApiService apiService;
  final Group group;
  final AppUser user;
  final List<ExpenseItem> initialExpenses;

  @override
  State<_TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<_TransactionsPage> {
  late List<ExpenseItem> _expenses;
  List<_GroupTransactionRow> _transactions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _expenses = List<ExpenseItem>.from(widget.initialExpenses);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final expenses = await widget.apiService.listExpenses(widget.group.id);
      final details = await Future.wait(
        expenses.map((e) => widget.apiService.getExpenseDetails(e.id)),
      );

      final rows = <_GroupTransactionRow>[];
      for (final detail in details) {
        for (final payment in detail.pendingPayments) {
          rows.add(
            _GroupTransactionRow(
              expenseId: detail.expense.id,
              expenseDescription: detail.expense.description,
              createdByName: detail.expense.createdByName,
              userName: payment.fullName,
              amountCents: payment.amountCents,
              isPaid: payment.isPaid,
              paidAt: payment.paidAt,
            ),
          );
        }
      }

      rows.sort((a, b) {
        if (a.isPaid != b.isPaid) {
          return a.isPaid ? 1 : -1; // pending first
        }

        final aTime = a.paidAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.paidAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _transactions = rows;
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
              fallback: 'Could not load transactions.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openExpense(ExpenseItem expense) async {
    final wasDeleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _ExpenseDetailPage(
          apiService: widget.apiService,
          expenseId: expense.id,
          user: widget.user,
          currency: widget.group.currency,
        ),
      ),
    );
    await _refresh();
    if (wasDeleted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter =
        NumberFormat.currency(symbol: '${widget.group.currency} ');

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: AppChrome(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(top: 92, bottom: 24),
            children: [
              Text(
                widget.group.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_transactions.length} transaction entries',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_expenses.isEmpty)
                const EmptyStateCard(
                  icon: Icons.swap_horiz_rounded,
                  title: 'No transactions yet',
                  subtitle: 'Expense payment transactions will appear here.',
                )
              else
                ..._transactions.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      borderRadius: 18,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openExpense(
                          _expenses.firstWhere((e) => e.id == t.expenseId),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: t.isPaid
                                    ? const Color(0x3326D3B4)
                                    : const Color(0x33FF8E5F),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                t.isPaid
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.pending_actions_rounded,
                                color: t.isPaid
                                    ? const Color(0xFF26D3B4)
                                    : const Color(0xFFFF8E5F),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${t.userName} • ${t.isPaid ? 'Paid' : 'Pending'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${t.expenseDescription} (by ${t.createdByName})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageAttachmentPage extends StatelessWidget {
  const _ImageAttachmentPage({required this.title, required this.imageUrl});

  final String title;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return const Text(
                'Could not load image.',
                style: TextStyle(color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.formatter,
    required this.onTap,
  });

  final ExpenseItem expense;
  final NumberFormat formatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AppPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: 24,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF26D3B4), Color(0xFF1083A8)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child:
                  const Icon(Icons.receipt_long_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expense.description,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Added by ${expense.createdByName}'),
                ],
              ),
            ),
            Text(
              formatter.format(expense.amountCents / 100),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

List<_ExpenseFlow> _computeExpenseFlows(
  List<ExpenseLineItem> payers,
  List<ExpenseLineItem> splits,
) {
  final paidMap = <String, int>{};
  final owedMap = <String, int>{};
  final names = <String, String>{};

  for (final p in payers) {
    paidMap[p.userId] = (paidMap[p.userId] ?? 0) + p.amountCents;
    names[p.userId] = p.fullName;
  }

  for (final s in splits) {
    owedMap[s.userId] = (owedMap[s.userId] ?? 0) + s.amountCents;
    names[s.userId] = s.fullName;
  }

  final allIds = <String>{...paidMap.keys, ...owedMap.keys};
  final debtors = <_ExpenseNode>[];
  final creditors = <_ExpenseNode>[];

  for (final id in allIds) {
    final net = (paidMap[id] ?? 0) - (owedMap[id] ?? 0);
    if (net < 0) {
      debtors.add(_ExpenseNode(id: id, amount: -net));
    } else if (net > 0) {
      creditors.add(_ExpenseNode(id: id, amount: net));
    }
  }

  debtors.sort((a, b) => b.amount.compareTo(a.amount));
  creditors.sort((a, b) => b.amount.compareTo(a.amount));

  final flows = <_ExpenseFlow>[];
  var i = 0;
  var j = 0;

  while (i < debtors.length && j < creditors.length) {
    final d = debtors[i];
    final c = creditors[j];
    final amount = d.amount < c.amount ? d.amount : c.amount;

    if (amount > 0) {
      flows.add(
        _ExpenseFlow(
          fromName: names[d.id] ?? 'Unknown',
          toName: names[c.id] ?? 'Unknown',
          amountCents: amount,
        ),
      );
    }

    d.amount -= amount;
    c.amount -= amount;

    if (d.amount == 0) i++;
    if (c.amount == 0) j++;
  }

  return flows;
}

class _ExpenseNode {
  _ExpenseNode({required this.id, required this.amount});

  final String id;
  int amount;
}

class _ExpenseFlow {
  const _ExpenseFlow({
    required this.fromName,
    required this.toName,
    required this.amountCents,
  });

  final String fromName;
  final String toName;
  final int amountCents;
}

class _GroupTransactionRow {
  const _GroupTransactionRow({
    required this.expenseId,
    required this.expenseDescription,
    required this.createdByName,
    required this.userName,
    required this.amountCents,
    required this.isPaid,
    required this.paidAt,
  });

  final String expenseId;
  final String expenseDescription;
  final String createdByName;
  final String userName;
  final int amountCents;
  final bool isPaid;
  final DateTime? paidAt;
}
