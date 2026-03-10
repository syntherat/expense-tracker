import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_chrome.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({
    super.key,
    required this.apiService,
    required this.group,
    required this.members,
    required this.user,
  });

  final ApiService apiService;
  final Group group;
  final List<GroupMember> members;
  final AppUser user;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  bool _saving = false;
  XFile? _attachment;

  Set<String> _selectedPayerIds = {};
  Map<String, double> _payerAmounts = {};

  String _splitMode = 'equally';
  Set<String> _includedSplitMemberIds = {};
  Map<String, double> _unequalAmounts = {};
  Map<String, double> _percentageValues = {};
  Map<String, double> _adjustmentValues = {};

  @override
  void initState() {
    super.initState();
    _selectedPayerIds = {widget.user.id};
    _includedSplitMemberIds = widget.members.map((m) => m.id).toSet();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _attachment = file);
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    if (description.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid description and amount')),
      );
      return;
    }

    final amountCents = (amount * 100).round();
    final payers = _buildPayers(amountCents);
    final splits = _buildSplits(amountCents);

    if (payers == null || splits == null) {
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.apiService.addExpense(
        groupId: widget.group.id,
        description: description,
        amountCents: amountCents,
        payers: payers,
        splits: splits,
        attachment: _attachment,
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Failed to add expense',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _memberName(String id) {
    for (final member in widget.members) {
      if (member.id == id) return member.fullName;
    }
    return 'Unknown';
  }

  List<Map<String, dynamic>>? _buildPayers(int amountCents) {
    if (_selectedPayerIds.isEmpty) {
      _showError('Select at least one payer.');
      return null;
    }

    final payerIds = _selectedPayerIds.toList();
    if (payerIds.length == 1) {
      return [
        {
          'userId': payerIds.first,
          'amountCents': amountCents,
        }
      ];
    }

    final explicitValues = <String, int>{};
    var explicitTotal = 0;
    for (final id in payerIds) {
      final value = ((_payerAmounts[id] ?? 0) * 100).round();
      if (value > 0) {
        explicitValues[id] = value;
        explicitTotal += value;
      }
    }

    if (explicitValues.isNotEmpty && explicitTotal != amountCents) {
      _showError('Paid amounts must add up to total expense.');
      return null;
    }

    if (explicitValues.isEmpty) {
      final base = amountCents ~/ payerIds.length;
      final remainder = amountCents % payerIds.length;
      final generated = <Map<String, dynamic>>[];

      for (var i = 0; i < payerIds.length; i++) {
        generated.add({
          'userId': payerIds[i],
          'amountCents': base + (i == 0 ? remainder : 0),
        });
      }
      return generated;
    }

    return explicitValues.entries
        .map((entry) => {
              'userId': entry.key,
              'amountCents': entry.value,
            })
        .toList();
  }

  List<Map<String, dynamic>>? _buildSplits(int amountCents) {
    switch (_splitMode) {
      case 'equally':
        final ids = _includedSplitMemberIds.toList();
        if (ids.isEmpty) {
          _showError('Select at least one member to split with.');
          return null;
        }

        final base = amountCents ~/ ids.length;
        final remainder = amountCents % ids.length;
        return [
          for (var i = 0; i < ids.length; i++)
            {
              'userId': ids[i],
              'amountCents': base + (i == 0 ? remainder : 0),
            }
        ];

      case 'unequally':
        final rows = <Map<String, dynamic>>[];
        var total = 0;
        for (final member in widget.members) {
          final cents = ((_unequalAmounts[member.id] ?? 0) * 100).round();
          if (cents > 0) {
            rows.add({'userId': member.id, 'amountCents': cents});
            total += cents;
          }
        }
        if (rows.isEmpty || total != amountCents) {
          _showError('Unequal split amounts must total the full expense.');
          return null;
        }
        return rows;

      case 'percentages':
        final active = <String, double>{};
        var percentTotal = 0.0;
        for (final member in widget.members) {
          final p = _percentageValues[member.id] ?? 0;
          if (p > 0) {
            active[member.id] = p;
            percentTotal += p;
          }
        }

        if (active.isEmpty || (percentTotal - 100).abs() > 0.01) {
          _showError('Percentages must add up to exactly 100.');
          return null;
        }

        final rows = <Map<String, dynamic>>[];
        var built = 0;
        var firstId = '';

        for (final entry in active.entries) {
          firstId = firstId.isEmpty ? entry.key : firstId;
          final cents = ((amountCents * entry.value) / 100).round();
          rows.add({'userId': entry.key, 'amountCents': cents});
          built += cents;
        }

        final diff = amountCents - built;
        if (diff != 0 && firstId.isNotEmpty) {
          for (final row in rows) {
            if (row['userId'] == firstId) {
              row['amountCents'] = (row['amountCents'] as int) + diff;
              break;
            }
          }
        }

        return rows;

      case 'adjustment':
        final ids = widget.members.map((m) => m.id).toList();
        if (ids.isEmpty) {
          _showError('No members available for split.');
          return null;
        }

        final n = ids.length;
        final equal = amountCents / n;
        var adjTotal = 0.0;
        for (final id in ids) {
          adjTotal += (_adjustmentValues[id] ?? 0) * 100;
        }

        final rows = <Map<String, dynamic>>[];
        var built = 0;
        for (final id in ids) {
          final adj = (_adjustmentValues[id] ?? 0) * 100;
          final raw = equal + adj - (adjTotal / n);
          final cents = raw.round();
          if (cents < 0) {
            _showError(
                'Adjustment generated negative split for ${_memberName(id)}.');
            return null;
          }
          rows.add({'userId': id, 'amountCents': cents});
          built += cents;
        }

        final diff = amountCents - built;
        if (diff != 0) {
          rows[0]['amountCents'] = (rows[0]['amountCents'] as int) + diff;
        }
        return rows;

      default:
        _showError('Unsupported split mode selected.');
        return null;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choosePayers() async {
    final selected = await Navigator.push<_WhoPaidSelectionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _WhoPaidScreen(
          members: widget.members,
          initialSelectedPayerIds: _selectedPayerIds,
          currentUserId: widget.user.id,
        ),
      ),
    );

    if (selected == null) {
      return;
    }

    if (selected.isMultiple) {
      await _chooseMultiplePayersDetails(
        initialSelected: selected.selectedPayerIds,
      );
      return;
    }

    setState(() {
      _selectedPayerIds = selected.selectedPayerIds;
      _payerAmounts = {};
    });
  }

  Future<void> _chooseMultiplePayersDetails({
    required Set<String> initialSelected,
  }) async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final totalCents = (amount * 100).round();

    final result = await Navigator.push<Map<String, double>>(
      context,
      MaterialPageRoute(
        builder: (_) => _EnterPaidAmountsScreen(
          members: widget.members,
          totalCents: totalCents,
          currency: widget.group.currency,
          initialAmounts: Map<String, double>.from(_payerAmounts),
          initialSelectedIds: initialSelected,
        ),
      ),
    );

    if (result == null) return;

    final payers = result.keys.where((id) => (result[id] ?? 0) > 0).toSet();
    setState(() {
      _selectedPayerIds = payers.isEmpty ? {widget.user.id} : payers;
      _payerAmounts = result;
    });
  }

  Future<void> _chooseSplitMode() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final totalCents = (amount * 100).round();

    final result = await Navigator.push<_AdjustSplitResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _AdjustSplitScreen(
          members: widget.members,
          totalCents: totalCents,
          currency: widget.group.currency,
          initialMode: _splitMode,
          initialIncludedIds: _includedSplitMemberIds,
          initialUnequal: _unequalAmounts,
          initialPercentages: _percentageValues,
          initialAdjustments: _adjustmentValues,
        ),
      ),
    );

    if (result == null) return;
    setState(() {
      _splitMode = result.mode;
      _includedSplitMemberIds = result.includedIds;
      _unequalAmounts = result.unequalAmounts;
      _percentageValues = result.percentages;
      _adjustmentValues = result.adjustments;
    });
  }

  String get _payerLabel {
    if (_selectedPayerIds.length == 1) {
      final singleId = _selectedPayerIds.first;
      if (singleId == widget.user.id) return 'Paid by you';
      return 'Paid by ${_memberName(singleId)}';
    }
    return 'Paid by ${_selectedPayerIds.length} people';
  }

  String get _splitLabel {
    switch (_splitMode) {
      case 'equally':
        return 'Split equally';
      case 'unequally':
        return 'Split unequally';
      case 'percentages':
        return 'Split by %';
      case 'adjustment':
        return 'Split by adjustment';
      default:
        return 'Split equally';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: AppChrome(
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Add a shared expense for ${widget.group.name}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'This starter flow pays from you and splits equally among current members.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'What was this for?',
                      prefixIcon: Icon(Icons.receipt_long_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (${widget.group.currency})',
                      prefixIcon: const Icon(Icons.currency_rupee_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101920),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF25333E)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0x3326D3B4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.attach_file_rounded,
                              color: Color(0xFF26D3B4)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_attachment?.name ?? 'No receipt selected',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              const Text(
                                  'Upload a bill, photo, or proof of payment.'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: const Color(0xFF2E414E)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.photo_library_outlined, size: 18),
                                  SizedBox(width: 6),
                                  Text('Choose'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _choosePayers,
                        child: StatChip(
                            icon: Icons.person_rounded,
                            label: _payerLabel,
                            color: const Color(0xFFFF8E5F)),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _chooseSplitMode,
                        child: StatChip(
                            icon: Icons.group_work_rounded,
                            label: _splitLabel,
                            color: const Color(0xFF26D3B4)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Saving expense...' : 'Save expense'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhoPaidSelectionResult {
  const _WhoPaidSelectionResult({
    required this.selectedPayerIds,
    required this.isMultiple,
  });

  final Set<String> selectedPayerIds;
  final bool isMultiple;
}

class _WhoPaidScreen extends StatefulWidget {
  const _WhoPaidScreen({
    required this.members,
    required this.initialSelectedPayerIds,
    required this.currentUserId,
  });

  final List<GroupMember> members;
  final Set<String> initialSelectedPayerIds;
  final String currentUserId;

  @override
  State<_WhoPaidScreen> createState() => _WhoPaidScreenState();
}

class _WhoPaidScreenState extends State<_WhoPaidScreen> {
  late bool _multiple;
  String? _singleSelectedId;
  late Set<String> _multipleSelectedIds;

  @override
  void initState() {
    super.initState();
    _multiple = widget.initialSelectedPayerIds.length > 1;
    _singleSelectedId = _multiple
        ? null
        : (widget.initialSelectedPayerIds.isEmpty
            ? widget.currentUserId
            : widget.initialSelectedPayerIds.first);
    _multipleSelectedIds = widget.initialSelectedPayerIds.length > 1
        ? Set<String>.from(widget.initialSelectedPayerIds)
        : {widget.currentUserId};
  }

  void _submit() {
    if (_multiple) {
      Navigator.pop(
        context,
        _WhoPaidSelectionResult(
          selectedPayerIds: _multipleSelectedIds,
          isMultiple: true,
        ),
      );
      return;
    }

    final selected = _singleSelectedId ?? widget.currentUserId;
    Navigator.pop(
      context,
      _WhoPaidSelectionResult(
        selectedPayerIds: {selected},
        isMultiple: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Who paid?'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.members.length,
              itemBuilder: (context, index) {
                final member = widget.members[index];
                final selected = !_multiple && _singleSelectedId == member.id;
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  onTap: () {
                    setState(() {
                      _multiple = false;
                      _singleSelectedId = member.id;
                    });
                  },
                  leading: InitialAvatar(
                    seed: member.id,
                    label: member.fullName,
                    radius: 26,
                  ),
                  title: Text(
                    member.fullName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded,
                          color: Color(0xFF26D3B4))
                      : null,
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFF26343D)),
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            onTap: () {
              setState(() {
                _multiple = true;
                if (_multipleSelectedIds.length < 2) {
                  _multipleSelectedIds = {widget.currentUserId};
                }
              });
            },
            title: Text(
              'Multiple people',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            trailing: _multiple
                ? const Icon(Icons.check_rounded, color: Color(0xFF26D3B4))
                : null,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Adjust split (full-screen, tabbed)
// ──────────────────────────────────────────────

class _AdjustSplitResult {
  const _AdjustSplitResult({
    required this.mode,
    required this.includedIds,
    required this.unequalAmounts,
    required this.percentages,
    required this.adjustments,
  });

  final String mode;
  final Set<String> includedIds;
  final Map<String, double> unequalAmounts;
  final Map<String, double> percentages;
  final Map<String, double> adjustments;
}

class _AdjustSplitScreen extends StatefulWidget {
  const _AdjustSplitScreen({
    required this.members,
    required this.totalCents,
    required this.currency,
    required this.initialMode,
    required this.initialIncludedIds,
    required this.initialUnequal,
    required this.initialPercentages,
    required this.initialAdjustments,
  });

  final List<GroupMember> members;
  final int totalCents;
  final String currency;
  final String initialMode;
  final Set<String> initialIncludedIds;
  final Map<String, double> initialUnequal;
  final Map<String, double> initialPercentages;
  final Map<String, double> initialAdjustments;

  @override
  State<_AdjustSplitScreen> createState() => _AdjustSplitScreenState();
}

class _AdjustSplitScreenState extends State<_AdjustSplitScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    ('equally', 'Equally'),
    ('unequally', 'Unequally'),
    ('percentages', 'By percentages'),
    ('adjustment', 'By adjustment'),
  ];

  late TabController _tabController;
  late Set<String> _includedIds;
  late final Map<String, TextEditingController> _unequalCtrl;
  late final Map<String, TextEditingController> _percentCtrl;
  late final Map<String, TextEditingController> _adjCtrl;

  double _unequalTotal = 0;
  double _percentTotal = 0;

  @override
  void initState() {
    super.initState();
    final modeIdx = _tabs.indexWhere((t) => t.$1 == widget.initialMode);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: modeIdx < 0 ? 0 : modeIdx,
    );

    _includedIds = Set<String>.from(widget.initialIncludedIds);
    if (_includedIds.isEmpty) {
      _includedIds = widget.members.map((m) => m.id).toSet();
    }

    _unequalCtrl = {};
    _percentCtrl = {};
    _adjCtrl = {};
    for (final m in widget.members) {
      final uv = widget.initialUnequal[m.id] ?? 0.0;
      final pv = widget.initialPercentages[m.id] ?? 0.0;
      final av = widget.initialAdjustments[m.id] ?? 0.0;

      final uc =
          TextEditingController(text: uv > 0 ? uv.toStringAsFixed(2) : '');
      final pc =
          TextEditingController(text: pv > 0 ? pv.toStringAsFixed(2) : '');
      final ac =
          TextEditingController(text: av != 0 ? av.toStringAsFixed(2) : '');

      uc.addListener(
          () => setState(() => _unequalTotal = _sumCtrl(_unequalCtrl)));
      pc.addListener(
          () => setState(() => _percentTotal = _sumCtrl(_percentCtrl)));

      _unequalCtrl[m.id] = uc;
      _percentCtrl[m.id] = pc;
      _adjCtrl[m.id] = ac;
    }

    _unequalTotal = _sumCtrl(_unequalCtrl);
    _percentTotal = _sumCtrl(_percentCtrl);
  }

  double _sumCtrl(Map<String, TextEditingController> map) =>
      map.values.fold(0.0, (s, c) => s + (double.tryParse(c.text) ?? 0.0));

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in [
      ..._unequalCtrl.values,
      ..._percentCtrl.values,
      ..._adjCtrl.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _sym {
    switch (widget.currency.toUpperCase()) {
      case 'INR':
        return '\u20B9';
      case 'USD':
        return '\$';
      case 'EUR':
        return '\u20AC';
      case 'GBP':
        return '\u00A3';
      default:
        return widget.currency;
    }
  }

  void _submit() {
    final mode = _tabs[_tabController.index].$1;
    Navigator.pop(
      context,
      _AdjustSplitResult(
        mode: mode,
        includedIds: Set<String>.from(_includedIds),
        unequalAmounts: {
          for (final m in widget.members)
            m.id: double.tryParse(_unequalCtrl[m.id]!.text) ?? 0.0
        },
        percentages: {
          for (final m in widget.members)
            m.id: double.tryParse(_percentCtrl[m.id]!.text) ?? 0.0
        },
        adjustments: {
          for (final m in widget.members)
            m.id: double.tryParse(_adjCtrl[m.id]!.text) ?? 0.0
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sym = _sym;
    final total = widget.totalCents / 100.0;
    final equalCount = _includedIds.length;
    final equalPerPerson = equalCount > 0 ? total / equalCount : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust split'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF26D3B4),
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF8FA2AE),
          dividerColor: const Color(0xFF26343D),
          tabs: [for (final t in _tabs) Tab(text: t.$2)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEquallyTab(sym, total, equalPerPerson, equalCount),
          _buildUnequallyTab(sym, total),
          _buildPercentagesTab(sym, total),
          _buildAdjustmentTab(sym, total, equalPerPerson),
        ],
      ),
    );
  }

  // ── Equally ────────────────────────────────────────────────────────────────

  Widget _buildEquallyTab(
      String sym, double total, double perPerson, int count) {
    return Column(
      children: [
        _modeHeader(
          title: 'Split equally',
          subtitle: 'Select which people owe an equal share.',
        ),
        Expanded(
          child: ListView(
            children: [
              for (final m in widget.members)
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  leading:
                      InitialAvatar(seed: m.id, label: m.fullName, radius: 24),
                  title: Text(m.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: GestureDetector(
                    onTap: () => setState(() {
                      if (_includedIds.contains(m.id)) {
                        if (_includedIds.length > 1) _includedIds.remove(m.id);
                      } else {
                        _includedIds.add(m.id);
                      }
                    }),
                    child: _checkbox(_includedIds.contains(m.id)),
                  ),
                ),
            ],
          ),
        ),
        _equallyFooter(sym, perPerson, count),
      ],
    );
  }

  Widget _equallyFooter(String sym, double perPerson, int count) {
    final allSelected = _includedIds.length == widget.members.length;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF26343D))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '~$sym${perPerson.toStringAsFixed(2)}/person',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Text(
                  '($count ${count == 1 ? 'person' : 'people'})',
                  style:
                      const TextStyle(color: Color(0xFF8FA2AE), fontSize: 13),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              if (allSelected) {
                _includedIds = {widget.members.first.id};
              } else {
                _includedIds = widget.members.map((m) => m.id).toSet();
              }
            }),
            child: Row(
              children: [
                const Text('All',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(width: 8),
                _checkbox(allSelected),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Unequally ──────────────────────────────────────────────────────────────

  Widget _buildUnequallyTab(String sym, double total) {
    final entered = _unequalTotal;
    final left = total - entered;
    final over = left < -0.005;
    return Column(
      children: [
        _modeHeader(
          title: 'Split by exact amounts',
          subtitle: 'Specify exactly how much each person owes.',
        ),
        Expanded(
          child: ListView(
            children: [
              for (final m in widget.members)
                _amountRow(
                  member: m,
                  ctrl: _unequalCtrl[m.id]!,
                  subtitle: null,
                  prefix: sym,
                ),
            ],
          ),
        ),
        _totalFooter(
          label:
              '$sym${entered.toStringAsFixed(2)} of $sym${total.toStringAsFixed(2)}',
          sub: over
              ? '$sym${(-left).toStringAsFixed(2)} over'
              : '$sym${left.toStringAsFixed(2)} left',
          over: over,
        ),
      ],
    );
  }

  // ── By percentages ─────────────────────────────────────────────────────────

  Widget _buildPercentagesTab(String sym, double total) {
    final entered = _percentTotal;
    final left = 100.0 - entered;
    final over = left < -0.005;
    return Column(
      children: [
        _modeHeader(
          title: 'Split by percentages',
          subtitle:
              'Enter the percentage split that\'s fair for your situation.',
        ),
        Expanded(
          child: ListView(
            children: [
              for (final m in widget.members)
                _amountRow(
                  member: m,
                  ctrl: _percentCtrl[m.id]!,
                  subtitle: () {
                    final pct =
                        double.tryParse(_percentCtrl[m.id]!.text) ?? 0.0;
                    return '$sym${(total * pct / 100).toStringAsFixed(2)}';
                  }(),
                  suffix: '%',
                ),
            ],
          ),
        ),
        _totalFooter(
          label: '${entered.toStringAsFixed(0)}% of 100%',
          sub: over
              ? '${(-left).toStringAsFixed(0)}% over'
              : '${left.toStringAsFixed(0)}% left',
          over: over,
        ),
      ],
    );
  }

  // ── By adjustment ──────────────────────────────────────────────────────────

  Widget _buildAdjustmentTab(String sym, double total, double basePerPerson) {
    return Column(
      children: [
        _modeHeader(
          title: 'Split by adjustment',
          subtitle:
              'Enter adjustments to reflect who owes extra; the remainder is distributed equally.',
        ),
        Expanded(
          child: ListView(
            children: [
              for (final m in widget.members)
                _amountRow(
                  member: m,
                  ctrl: _adjCtrl[m.id]!,
                  subtitle: '$sym${basePerPerson.toStringAsFixed(2)}',
                  prefix: '+',
                  hintText: '0.00',
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _checkbox(bool checked) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: checked ? const Color(0xFF26D3B4) : Colors.transparent,
        border: Border.all(
          color: checked ? const Color(0xFF26D3B4) : const Color(0xFF8FA2AE),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.black)
          : null,
    );
  }

  Widget _modeHeader({required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF8FA2AE), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _amountRow({
    required GroupMember member,
    required TextEditingController ctrl,
    required String? subtitle,
    String? prefix,
    String? suffix,
    String hintText = '0.00',
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading:
          InitialAvatar(seed: member.id, label: member.fullName, radius: 24),
      title: Text(member.fullName,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: const TextStyle(color: Color(0xFF8FA2AE), fontSize: 13))
          : null,
      trailing: SizedBox(
        width: 110,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (prefix != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(prefix,
                    style: const TextStyle(
                        color: Color(0xFF8FA2AE), fontSize: 15)),
              ),
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: hintText,
                  border: const UnderlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.only(bottom: 2),
                ),
              ),
            ),
            if (suffix != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(suffix,
                    style: const TextStyle(
                        color: Color(0xFF8FA2AE), fontSize: 15)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _totalFooter({
    required String label,
    required String sub,
    required bool over,
  }) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF26343D))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(
              color: over ? const Color(0xFFE57373) : const Color(0xFF8FA2AE),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Enter paid amounts (full-screen, multiple payers)
// ──────────────────────────────────────────────

class _EnterPaidAmountsScreen extends StatefulWidget {
  const _EnterPaidAmountsScreen({
    required this.members,
    required this.totalCents,
    required this.currency,
    required this.initialAmounts,
    required this.initialSelectedIds,
  });

  final List<GroupMember> members;
  final int totalCents;
  final String currency;
  final Map<String, double> initialAmounts;
  final Set<String> initialSelectedIds;

  @override
  State<_EnterPaidAmountsScreen> createState() =>
      _EnterPaidAmountsScreenState();
}

class _EnterPaidAmountsScreenState extends State<_EnterPaidAmountsScreen> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, double> _amounts;

  @override
  void initState() {
    super.initState();
    _amounts = {};
    _controllers = {};
    for (final member in widget.members) {
      final initial = widget.initialAmounts[member.id] ?? 0.0;
      _amounts[member.id] = initial;
      final ctrl = TextEditingController(
        text: initial > 0 ? initial.toStringAsFixed(2) : '',
      );
      ctrl.addListener(() {
        final val = double.tryParse(ctrl.text) ?? 0.0;
        setState(() => _amounts[member.id] = val);
      });
      _controllers[member.id] = ctrl;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalEntered => _amounts.values.fold(0.0, (sum, v) => sum + v);
  double get _total => widget.totalCents / 100.0;

  String get _sym {
    switch (widget.currency.toUpperCase()) {
      case 'INR':
        return '\u20B9'; // ₹
      case 'USD':
        return '\$';
      case 'EUR':
        return '\u20AC'; // €
      case 'GBP':
        return '\u00A3'; // £
      case 'JPY':
      case 'CNY':
        return '\u00A5'; // ¥
      default:
        return widget.currency;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = _sym;
    final entered = _totalEntered;
    final total = _total;
    final left = total - entered;
    final overPaid = left < -0.005;
    final exact = left.abs() < 0.005;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter paid amounts'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: () =>
                Navigator.pop(context, Map<String, double>.from(_amounts)),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.members.length,
              itemBuilder: (context, index) {
                final member = widget.members[index];
                final ctrl = _controllers[member.id]!;
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  leading: InitialAvatar(
                    seed: member.id,
                    label: member.fullName,
                    radius: 24,
                  ),
                  title: Text(
                    member.fullName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  trailing: SizedBox(
                    width: 130,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          sym,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: const Color(0xFF8FA2AE),
                                  ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: const InputDecoration(
                              hintText: '0.00',
                              border: UnderlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.only(bottom: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFF26343D)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Text(
                  '$sym${entered.toStringAsFixed(2)} of $sym${total.toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  exact
                      ? '${sym}0.00 left'
                      : overPaid
                          ? '$sym${(-left).toStringAsFixed(2)} over'
                          : '$sym${left.toStringAsFixed(2)} left',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: overPaid
                            ? const Color(0xFFE57373)
                            : const Color(0xFF8FA2AE),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
