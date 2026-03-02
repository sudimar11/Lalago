import 'dart:async';

import 'package:brgy/constants.dart';
import 'package:brgy/main.dart';
import 'package:brgy/utils/admin_permission_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';

/// User role management with pagination, filters, search, and inline editor.
class UserRoleManagementPage extends StatefulWidget {
  const UserRoleManagementPage({super.key});

  @override
  State<UserRoleManagementPage> createState() => _UserRoleManagementPageState();
}

class _UserRoleManagementPageState extends State<UserRoleManagementPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  String? _roleFilter;
  bool? _activeFilter;
  List<_UserRow> _users = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  final int _pageSize = 50;
  final Set<String> _selectedIds = {};

  bool get _canEdit => canEditRoles(MyAppState.currentUser);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_searchQuery != _searchController.text.trim()) {
        setState(() {
          _searchQuery = _searchController.text.trim();
          _loadFirstPage();
        });
      }
    });
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _users = [];
      _lastDoc = null;
      _hasMore = true;
      _isLoading = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final snapshot = await _fetchUsersPage();
      final rows = snapshot.docs.map((d) => _UserRow.fromDoc(d)).toList();

      List<_UserRow> filtered = rows;
      if (_searchQuery.isNotEmpty) {
        final lower = _searchQuery.toLowerCase();
        filtered = rows.where((r) {
          return r.email.toLowerCase().contains(lower) ||
              r.displayName.toLowerCase().contains(lower) ||
              r.phone.toLowerCase().contains(lower) ||
              r.userId.toLowerCase().contains(lower);
        }).toList();
      }

      if (mounted) {
        setState(() {
          _users.addAll(filtered);
          if (snapshot.docs.isNotEmpty) {
            _lastDoc = snapshot.docs.last;
          }
          _hasMore = snapshot.docs.length == _pageSize;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        try {
          final snapshot = await _fetchUsersPageSimple();
          final rows = snapshot.docs.map((d) => _UserRow.fromDoc(d)).toList();
          List<_UserRow> filtered = rows;
          if (_searchQuery.isNotEmpty) {
            final lower = _searchQuery.toLowerCase();
            filtered = rows.where((r) {
              return r.email.toLowerCase().contains(lower) ||
                  r.displayName.toLowerCase().contains(lower) ||
                  r.phone.toLowerCase().contains(lower) ||
                  r.userId.toLowerCase().contains(lower);
            }).toList();
          }
          if (mounted) {
            setState(() {
              _users.addAll(filtered);
              _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
              _hasMore = snapshot.docs.length == _pageSize;
              _isLoading = false;
              _error = null;
            });
          }
        } catch (e2) {
          if (mounted) {
            setState(() {
              _error = e.toString();
              _isLoading = false;
            });
          }
        }
      }
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchUsersPage() async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection(USERS)
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (_roleFilter != null) q = q.where('role', isEqualTo: _roleFilter);
    if (_activeFilter != null) q = q.where('active', isEqualTo: _activeFilter);

    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);

    return q.get();
  }

  /// Fallback: simple query without orderBy/filters (no index required).
  Future<QuerySnapshot<Map<String, dynamic>>> _fetchUsersPageSimple() async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection(USERS)
        .limit(_pageSize);

    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);

    return q.get();
  }

  String _roleDisplay(String role) {
    if (role == USER_ROLE_VENDOR) return 'Restaurant';
    return role.isNotEmpty ? role : '-';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Role Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh users',
            onPressed: _isLoading ? null : _loadFirstPage,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Audit logs',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AuditLogViewerPage(),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildFilters(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: _selectedIds.isNotEmpty && _canEdit ? 70 : 0,
              ),
              child: _users.isEmpty && !_isLoading
                  ? const Center(child: Text('No users found'))
                  : isWide
                      ? _buildTable()
                      : _buildList(),
            ),
          ),
          if (_hasMore && _users.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: _isLoading ? null : _loadMore,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load more'),
              ),
            ),
        ],
      ),
          if (_selectedIds.isNotEmpty && _canEdit) _buildBatchBar(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 200,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search email, name, phone, ID',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          DropdownButton<String?>(
            value: _roleFilter,
            hint: const Text('Role'),
            isDense: true,
            items: [
              const DropdownMenuItem(value: null, child: Text('All roles')),
              ...['customer', 'driver', 'vendor', 'admin', 'teacher']
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(_roleDisplay(r)),
                      )),
            ],
            onChanged: (v) => setState(() {
              _roleFilter = v;
              _loadFirstPage();
            }),
          ),
          FilterChip(
            label: const Text('Active'),
            selected: _activeFilter == true,
            onSelected: (_) => setState(() {
              _activeFilter = _activeFilter == true ? null : true;
              _loadFirstPage();
            }),
          ),
          if (_canEdit) ...[
            FilterChip(
              label: Text('Select all (${_users.length})'),
              onSelected: (_) => setState(() {
                for (final u in _users) _selectedIds.add(u.userId);
              }),
            ),
            FilterChip(
              label: const Text('Clear selection'),
              onSelected: (_) => setState(() => _selectedIds.clear()),
            ),
          ],
          FilterChip(
            label: const Text('Suspended'),
            selected: _activeFilter == false,
            onSelected: (_) => setState(() {
              _activeFilter = _activeFilter == false ? null : false;
              _loadFirstPage();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            children: [
              Text('${_selectedIds.length} selected'),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _batchChangeRole,
                child: const Text('Change role'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _selectedIds.clear()),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _batchChangeRole() async {
    if (_selectedIds.isEmpty) return;
    String? newRole;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Batch change role'),
          content: DropdownButton<String>(
            value: newRole,
            hint: const Text('Select new role'),
            isExpanded: true,
            items: ['customer', 'driver', 'vendor', 'admin', 'teacher']
                .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(_roleDisplay(r)),
                    ))
                .toList(),
            onChanged: (v) {
              newRole = v;
              setDialogState(() {});
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: newRole == null ? null : () => Navigator.pop(ctx),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (newRole == null || !mounted) return;

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('batchUpdateUserRoles');
      final result = await callable.call(<String, dynamic>{
        'targetUserIds': _selectedIds.toList(),
        'newRole': newRole,
      });
      final data = result.data as Map<String, dynamic>? ?? {};
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated ${data['successCount'] ?? 0}; '
              'failed: ${data['failureCount'] ?? 0}',
            ),
          ),
        );
        setState(() => _selectedIds.clear());
        _loadFirstPage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          if (_canEdit)
            DataColumn(
              label: Checkbox(
                value: _users.isNotEmpty &&
                    _users.every((u) => _selectedIds.contains(u.userId)),
                tristate: true,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    for (final u in _users) _selectedIds.add(u.userId);
                  } else {
                    for (final u in _users) _selectedIds.remove(u.userId);
                  }
                }),
              ),
            ),
          const DataColumn(label: Text('Email')),
          const DataColumn(label: Text('Name')),
          const DataColumn(label: Text('Phone')),
          const DataColumn(label: Text('Role')),
          const DataColumn(label: Text('Status')),
          const DataColumn(label: Text('Actions')),
        ],
        rows: _users.map((u) {
          return DataRow(
            cells: [
              if (_canEdit)
                DataCell(Checkbox(
                  value: _selectedIds.contains(u.userId),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedIds.add(u.userId);
                    } else {
                      _selectedIds.remove(u.userId);
                    }
                  }),
                )),
              DataCell(Text(u.email, overflow: TextOverflow.ellipsis)),
              DataCell(Text(u.displayName, overflow: TextOverflow.ellipsis)),
              DataCell(Text(u.phone)),
              DataCell(_canEdit
                  ? DropdownButton<String>(
                      value: u.role.isEmpty ? 'customer' : u.role,
                      isDense: true,
                      items: [
                        USER_ROLE_CUSTOMER,
                        USER_ROLE_DRIVER,
                        USER_ROLE_VENDOR,
                        USER_ROLE_ADMIN,
                        USER_ROLE_TEACHER,
                      ].map((r) => DropdownMenuItem(value: r, child: Text(_roleDisplay(r)))).toList(),
                      onChanged: (v) => v != null ? _changeRole(u, v) : null,
                    )
                  : Text(_roleDisplay(u.role))),
              DataCell(Text(u.active ? 'Active' : 'Suspended')),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _showUserDetail(u),
                    child: const Text('View'),
                  ),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final u = _users[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: _canEdit
                ? Checkbox(
                    value: _selectedIds.contains(u.userId),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedIds.add(u.userId);
                      } else {
                        _selectedIds.remove(u.userId);
                      }
                    }),
                  )
                : null,
            title: Text(u.displayName),
            subtitle: Text('${u.email} · ${_roleDisplay(u.role)}'),
            trailing: _canEdit
                ? DropdownButton<String>(
                    value: u.role.isEmpty ? 'customer' : u.role,
                    isDense: true,
                    items: [
                      USER_ROLE_CUSTOMER,
                      USER_ROLE_DRIVER,
                      USER_ROLE_VENDOR,
                      USER_ROLE_ADMIN,
                      USER_ROLE_TEACHER,
                    ].map((r) => DropdownMenuItem(value: r, child: Text(_roleDisplay(r)))).toList(),
                    onChanged: (v) => v != null ? _changeRole(u, v) : null,
                  )
                : null,
            onTap: () => _showUserDetail(u),
          ),
        );
      },
    );
  }

  Future<void> _changeRole(_UserRow user, String newRole) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change role'),
        content: Text(
          'Change ${user.displayName} to ${_roleDisplay(newRole)}?\n\n'
          'This updates app access and permissions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('updateUserRole');
      await callable.call(<String, dynamic>{
        'targetUserId': user.userId,
        'newRole': newRole,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role updated')),
        );
        _loadFirstPage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showUserDetail(_UserRow user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => UserDetailSheet(userId: user.userId),
    );
  }
}

class _UserRow {
  final String userId;
  final String email;
  final String displayName;
  final String phone;
  final String role;
  final bool active;
  final Timestamp? createdAt;
  final Timestamp? lastOnlineTimestamp;

  _UserRow({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.phone,
    required this.role,
    required this.active,
    this.createdAt,
    this.lastOnlineTimestamp,
  });

  static _UserRow fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final fn = d['firstName'] ?? '';
    final ln = d['lastName'] ?? '';
    final name = '${fn} ${ln}'.trim();
    return _UserRow(
      userId: doc.id,
      email: d['email'] ?? '',
      displayName: name.isEmpty ? 'Unknown' : name,
      phone: d['phoneNumber'] ?? '',
      role: d['role'] ?? d['userLevel'] ?? '',
      active: d['active'] ?? true,
      createdAt: d['createdAt'] as Timestamp?,
      lastOnlineTimestamp: d['lastOnlineTimestamp'] as Timestamp?,
    );
  }
}

/// User detail sheet with full info, order summary, wallet, actions.
class UserDetailSheet extends StatefulWidget {
  const UserDetailSheet({super.key, required this.userId});

  final String userId;

  @override
  State<UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<UserDetailSheet> {
  Map<String, dynamic>? _userData;
  int _orderCount = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(USERS)
          .doc(widget.userId)
          .get();
      int orderCount = 0;
      if (userDoc.exists) {
        final snapshot = await FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('authorID', isEqualTo: widget.userId)
            .count()
            .get();
        orderCount = snapshot.count ?? 0;
      }
      if (mounted) {
        setState(() {
          _userData = userDoc.data();
          _orderCount = orderCount;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleActive() async {
    final d = _userData;
    if (d == null) return;
    final active = d['active'] ?? true;
    try {
      await FirebaseFirestore.instance
          .collection(USERS)
          .doc(widget.userId)
          .update({'active': !active});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(active ? 'User suspended' : 'User activated')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _userData?['email'] as String? ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email on file')),
      );
      return;
    }
    try {
      await auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _roleDisplay(String? role) {
    if (role == null || role.isEmpty) return '-';
    return role == USER_ROLE_VENDOR ? 'Restaurant' : role;
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = canEditRoles(MyAppState.currentUser);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return Center(
            child: SelectableText(_error!, style: const TextStyle(color: Colors.red)),
          );
        }
        final d = _userData;
        if (d == null) {
          return const Center(child: Text('User not found'));
        }

        final role = d['role'] ?? d['userLevel'] ?? '';
        final wallet = d['wallet_amount'];
        final fcmTokens = d['fcmTokens'] as List? ?? [d['fcmToken']];
        final tokenCount = fcmTokens.where((t) => t != null && t.toString().isNotEmpty).length;

        return ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _row('Email', d['email'] ?? '-'),
            _row('Phone', d['phoneNumber'] ?? '-'),
            _row('Role', _roleDisplay(role)),
            _row('Status', (d['active'] ?? true) ? 'Active' : 'Suspended'),
            _row('Created', _formatTimestamp(d['createdAt'])),
            _row('Last online', _formatTimestamp(d['lastOnlineTimestamp'])),
            _row('Orders', '$_orderCount'),
            if (role == USER_ROLE_DRIVER && wallet != null)
              _row('Wallet', wallet.toString()),
            _row('FCM tokens', '$tokenCount'),
            const SizedBox(height: 16),
            if (canEdit) ...[
              ElevatedButton.icon(
                onPressed: _toggleActive,
                icon: Icon((d['active'] ?? true) ? Icons.block : Icons.check_circle),
                label: Text((d['active'] ?? true) ? 'Suspend' : 'Activate'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _resetPassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Reset password'),
              ),
              const SizedBox(height: 8),
            ],
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AuditLogViewerPage(targetUserId: widget.userId),
                  ),
                );
              },
              icon: const Icon(Icons.history),
              label: const Text('View audit logs'),
            ),
          ],
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '-';
    if (ts is Timestamp) {
      return ts.toDate().toString().substring(0, 19);
    }
    return ts.toString();
  }
}

/// Audit log viewer with filters and pagination.
class AuditLogViewerPage extends StatefulWidget {
  const AuditLogViewerPage({super.key, this.targetUserId, this.adminId});

  final String? targetUserId;
  final String? adminId;

  @override
  State<AuditLogViewerPage> createState() => _AuditLogViewerPageState();
}

class _AuditLogViewerPageState extends State<AuditLogViewerPage> {
  final TextEditingController _adminIdController = TextEditingController();
  final TextEditingController _targetUserIdController = TextEditingController();
  String? _actionFilter;
  List<_AuditRow> _logs = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    if (widget.targetUserId != null) {
      _targetUserIdController.text = widget.targetUserId!;
    }
    if (widget.adminId != null) {
      _adminIdController.text = widget.adminId!;
    }
    _loadFirst();
  }

  @override
  void dispose() {
    _adminIdController.dispose();
    _targetUserIdController.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _logs = [];
      _lastDoc = null;
      _hasMore = true;
      _isLoading = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      final adminId = _adminIdController.text.trim();
      final targetUserId = _targetUserIdController.text.trim();
      if (adminId.isNotEmpty) q = q.where('adminId', isEqualTo: adminId);
      if (targetUserId.isNotEmpty) {
        q = q.where('targetUserId', isEqualTo: targetUserId);
      }
      if (_actionFilter != null) {
        q = q.where('action', isEqualTo: _actionFilter);
      }

      if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);

      final snapshot = await q.get();
      final rows = snapshot.docs
          .map((d) => _AuditRow.fromDoc(d))
          .toList();

      if (mounted) {
        setState(() {
          _logs.addAll(rows);
          if (snapshot.docs.isNotEmpty) _lastDoc = snapshot.docs.last;
          _hasMore = snapshot.docs.length == _pageSize;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Logs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _adminIdController,
                    decoration: const InputDecoration(
                      hintText: 'Admin ID',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _targetUserIdController,
                    decoration: const InputDecoration(
                      hintText: 'Target user ID',
                      isDense: true,
                    ),
                  ),
                ),
                DropdownButton<String?>(
                  value: _actionFilter,
                  hint: const Text('Action'),
                  isDense: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    const DropdownMenuItem(
                      value: 'role_change',
                      child: Text('role_change'),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _actionFilter = v;
                    _loadFirst();
                  }),
                ),
                ElevatedButton(
                  onPressed: () => _loadFirst(),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: _logs.isEmpty && !_isLoading
                ? const Center(child: Text('No audit logs'))
                : isWide
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Action')),
                            DataColumn(label: Text('Admin')),
                            DataColumn(label: Text('Target')),
                            DataColumn(label: Text('Old')),
                            DataColumn(label: Text('New')),
                            DataColumn(label: Text('Time')),
                          ],
                          rows: _logs
                              .map((r) => DataRow(
                                    cells: [
                                      DataCell(Text(r.action)),
                                      DataCell(Text(r.adminId)),
                                      DataCell(Text(r.targetUserId)),
                                      DataCell(Text(r.oldRole ?? '-')),
                                      DataCell(Text(r.newRole ?? '-')),
                                      DataCell(Text(r.timestamp)),
                                    ],
                                  ))
                              .toList(),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (_, i) {
                          final r = _logs[i];
                          return ListTile(
                            title: Text(r.action),
                            subtitle: Text(
                              '${r.adminId} → ${r.targetUserId}\n'
                              '${r.oldRole ?? '-'} → ${r.newRole ?? '-'} · ${r.timestamp}',
                            ),
                          );
                        },
                      ),
          ),
          if (_hasMore && _logs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: _isLoading ? null : _loadMore,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load more'),
              ),
            ),
        ],
      ),
    );
  }
}

class _AuditRow {
  final String action;
  final String adminId;
  final String targetUserId;
  final String? oldRole;
  final String? newRole;
  final String timestamp;

  _AuditRow({
    required this.action,
    required this.adminId,
    required this.targetUserId,
    this.oldRole,
    this.newRole,
    required this.timestamp,
  });

  static _AuditRow fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    dynamic ts = d['timestamp'];
    String tsStr = '-';
    if (ts != null) {
      if (ts is Timestamp) {
        tsStr = ts.toDate().toString().substring(0, 19);
      } else {
        tsStr = ts.toString();
      }
    }
    return _AuditRow(
      action: d['action'] ?? '-',
      adminId: d['adminId'] ?? '-',
      targetUserId: d['targetUserId'] ?? '-',
      oldRole: d['oldRole']?.toString(),
      newRole: d['newRole']?.toString(),
      timestamp: tsStr,
    );
  }
}
