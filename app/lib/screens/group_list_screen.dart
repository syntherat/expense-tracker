import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_chrome.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({
    super.key,
    required this.apiService,
    required this.user,
    required this.onOpenGroup,
    required this.onLogout,
  });

  final ApiService apiService;
  final AppUser user;
  final ValueChanged<Group> onOpenGroup;
  final Future<void> Function() onLogout;

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  List<Group> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groups = await widget.apiService.listGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
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
              fallback: 'Could not load groups.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final currencyController = TextEditingController(text: 'INR');

    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a new group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Group name',
                prefixIcon: Icon(Icons.luggage_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: currencyController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Currency code',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (nameController.text.trim(), currencyController.text.trim()),
            ),
            child: const Text('Create'),
          )
        ],
      ),
    );

    if (result == null || result.$1.isEmpty || result.$2.length != 3) return;

    try {
      final (group, inviteLink) =
          await widget.apiService.createGroup(result.$1, result.$2);
      final shareUrl = widget.apiService.buildShareableInviteUrl(inviteLink);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite link ready'),
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111B23),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF26343D)),
            ),
            child: SelectableText(
              shareUrl,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, letterSpacing: 0.4),
            ),
          ),
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
              child: const Text('Done'),
            )
          ],
        ),
      );

      setState(() => _groups = [group, ..._groups]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Could not create group.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _joinGroup() async {
    final tokenController = TextEditingController();
    final token = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a group'),
        content: TextField(
          controller: tokenController,
          decoration: const InputDecoration(
            labelText: 'Invite link or token',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, tokenController.text.trim()),
            child: const Text('Join'),
          )
        ],
      ),
    );

    if (token == null || token.isEmpty) return;
    try {
      await widget.apiService.joinGroupByInvite(token);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Could not join group.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _shareGroupInvite(Group group) async {
    try {
      final inviteLink = await widget.apiService.refreshInvite(group.id);
      final shareUrl = widget.apiService.buildShareableInviteUrl(inviteLink);

      await Share.share(
        'Join my expense group "${group.name}": $shareUrl',
        subject: 'Group invite link',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Could not share invite link.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      await widget.apiService.logout();
    } catch (_) {
      // Even if the network call fails, clear local auth state so user can sign in again.
    }

    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final greetingName = widget.user.fullName.split(' ').first;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton.filledTonal(
            onPressed: _confirmAndLogout,
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton.filledTonal(
            onPressed: _joinGroup,
            icon: const Icon(Icons.group_add_rounded),
          ),
        )
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New group'),
      ),
      body: AppChrome(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.only(top: 88, bottom: 110),
            children: [
              Text(
                'Hey, $greetingName',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: const Color(0xFF9BB0BC)),
              ),
              const SizedBox(height: 6),
              Text(
                'Your expense groups',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      title: 'Groups',
                      value: '${_groups.length}',
                      caption: 'Active circles',
                      icon: Icons.diversity_3_rounded,
                      accent: const Color(0xFF26D3B4),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: MetricCard(
                      title: 'Profile',
                      value: widget.user.phone,
                      caption: 'Signed in',
                      icon: Icons.phone_rounded,
                      accent: const Color(0xFFFF8E5F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const SectionTitle('Recent groups'),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_groups.isEmpty)
                const EmptyStateCard(
                  icon: Icons.hiking_rounded,
                  title: 'No groups yet',
                  subtitle:
                      'Create your first trip group or join one with an invite token.',
                )
              else
                ..._groups.map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _GroupTile(
                      group: group,
                      onTap: () => widget.onOpenGroup(group),
                      onShare: () => _shareGroupInvite(group),
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

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.onTap,
    required this.onShare,
  });

  final Group group;
  final VoidCallback onTap;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: AppPanel(
          child: Row(
            children: [
              InitialAvatar(seed: group.id, label: group.name, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.currency_exchange_rounded,
                            size: 16, color: Color(0xFF8CA2AE)),
                        const SizedBox(width: 6),
                        Text(group.currency,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF101920),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_rounded, color: Colors.white),
                  tooltip: 'Share invite',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF101920),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.chevron_right_rounded,
                    color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
