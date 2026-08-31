
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:detectco/main.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    required this.isRead,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'DETECT-CO',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString() ?? 'announcement',
      timestamp: DateTime.tryParse(
            json['timestamp']?.toString() ?? '',
          ) ??
          DateTime.now(),
      isRead: json['isRead'] == true,
    );
  }
}

// =====================================================
// NOTIFICATION STORAGE
// =====================================================

class NotificationStorage {
  static const String _key = 'detect_co_notifications';

  // ===================================================
  // GLOBAL UNREAD NOTIFICATION COUNT
  // ===================================================

  static final ValueNotifier<int> unreadCountNotifier =
      ValueNotifier<int>(0);

  // ===================================================
  // LOAD NOTIFICATIONS
  // ===================================================

  static Future<List<AppNotification>> getNotifications() async {
    final prefs = await SharedPreferences.getInstance();

    final String? raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) {
      unreadCountNotifier.value = 0;
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(raw);

      final List<AppNotification> notifications = decoded
          .map(
            (item) => AppNotification.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();

      // Update global unread count.
      unreadCountNotifier.value = notifications
          .where((notification) => !notification.isRead)
          .length;

      return notifications;
    } catch (e) {
      debugPrint('Notification storage error: $e');

      unreadCountNotifier.value = 0;

      return [];
    }
  }

  // ===================================================
  // UPDATE UNREAD COUNT
  // ===================================================

  static Future<void> updateUnreadCount() async {
    final notifications = await getNotifications();

    unreadCountNotifier.value = notifications
        .where((notification) => !notification.isRead)
        .length;
  }

  // ===================================================
  // SAVE NOTIFICATION
  // ===================================================

  static Future<void> saveNotification(
    AppNotification notification,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final notifications = await getNotifications();

    // Prevent duplicate notifications.
    notifications.removeWhere(
      (item) => item.id == notification.id,
    );

    notifications.insert(0, notification);

    // Keep the latest 100 notifications.
    if (notifications.length > 100) {
      notifications.removeRange(
        100,
        notifications.length,
      );
    }

    final encoded = jsonEncode(
      notifications.map((e) => e.toJson()).toList(),
    );

    await prefs.setString(_key, encoded);

    // IMPORTANT:
    // Refresh unread counter immediately.
    unreadCountNotifier.value = notifications
        .where((notification) => !notification.isRead)
        .length;
  }

  // ===================================================
  // DELETE ONE NOTIFICATION
  // ===================================================

  static Future<void> deleteNotification(String id) async {
    final notifications = await getNotifications();

    notifications.removeWhere(
      (item) => item.id == id,
    );

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      jsonEncode(
        notifications.map((e) => e.toJson()).toList(),
      ),
    );

    // IMPORTANT:
    // Refresh unread counter after deletion.
    unreadCountNotifier.value = notifications
        .where((notification) => !notification.isRead)
        .length;
  }

  // ===================================================
  // DELETE ALL
  // ===================================================

  static Future<void> deleteAll() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_key);

    // IMPORTANT:
    // No notifications = zero unread.
    unreadCountNotifier.value = 0;
  }

  // ===================================================
  // MARK ONE AS READ
  // ===================================================

  static Future<void> markAsRead(String id) async {
    final notifications = await getNotifications();

    for (final notification in notifications) {
      if (notification.id == id) {
        notification.isRead = true;
      }
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      jsonEncode(
        notifications.map((e) => e.toJson()).toList(),
      ),
    );

    // IMPORTANT:
    // Refresh unread counter.
    unreadCountNotifier.value = notifications
        .where((notification) => !notification.isRead)
        .length;
  }

  // ===================================================
  // MARK ALL AS READ
  // ===================================================

  static Future<void> markAllAsRead() async {
    final notifications = await getNotifications();

    for (final notification in notifications) {
      notification.isRead = true;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      jsonEncode(
        notifications.map((e) => e.toJson()).toList(),
      ),
    );

    // IMPORTANT:
    // Everything is read.
    unreadCountNotifier.value = 0;
  }
}

// =====================================================
// NOTIFICATION TAB
// =====================================================

class NotificationTab extends StatefulWidget {
  const NotificationTab({super.key});

  @override
  State<NotificationTab> createState() =>
      _NotificationTabState();
}

class _NotificationTabState extends State<NotificationTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<AppNotification> notifications = [];

  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
    );

    _loadNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ===================================================
  // LOAD NOTIFICATIONS
  // ===================================================

  Future<void> _loadNotifications() async {
    final result =
        await NotificationStorage.getNotifications();

    if (!mounted) return;

    setState(() {
      notifications = result;
      isLoading = false;
    });
  }

  // ===================================================
  // DELETE ONE
  // ===================================================

  Future<void> _deleteNotification(
    AppNotification notification,
  ) async {
    await NotificationStorage.deleteNotification(
      notification.id,
    );

    if (!mounted) return;

    setState(() {
      notifications.removeWhere(
        (item) => item.id == notification.id,
      );
    });
  }

  // ===================================================
  // DELETE ALL
  // ===================================================

  Future<void> _deleteAllNotifications() async {
    if (notifications.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDarkMode =
            isDarkModeNotifier.value;

        return AlertDialog(
          backgroundColor:
              isDarkMode
                  ? const Color(0xFF303030)
                  : Colors.white,
          title: Text(
            'Remove all notifications?',
            style: TextStyle(
              color:
                  isDarkMode
                      ? Colors.white
                      : Colors.black,
            ),
          ),
          content: Text(
            'This will permanently remove all notifications.',
            style: TextStyle(
              color:
                  isDarkMode
                      ? Colors.white70
                      : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text(
                'Remove All',
                style: TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await NotificationStorage.deleteAll();

    if (!mounted) return;

    setState(() {
      notifications.clear();
    });
  }

  // ===================================================
  // MARK AS READ
  // ===================================================

  Future<void> _markAsRead(
    AppNotification notification,
  ) async {
    if (notification.isRead) return;

    await NotificationStorage.markAsRead(
      notification.id,
    );

    if (!mounted) return;

    setState(() {
      notification.isRead = true;
    });
  }

  // ===================================================
  // FORMAT DATE
  // ===================================================

  String _formatDate(DateTime date) {
    final now = DateTime.now();

    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }

    return '${date.month}/${date.day}/${date.year}';
  }

  // ===================================================
  // FILTER
  // ===================================================

  List<AppNotification> _getNotifications(
    String type,
  ) {
    return notifications.where((notification) {
      if (type == 'announcement') {
        return notification.type == 'announcement';
      }

      return notification.type == 'alert';
    }).toList();
  }

  // ===================================================
  // NOTIFICATION LIST
  // ===================================================

  Widget _buildNotificationList(
    List<AppNotification> items,
    bool isDarkMode,
  ) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 60,
              color:
                  isDarkMode
                      ? Colors.grey[600]
                      : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              'No notifications yet',
              style: TextStyle(
                fontSize: 16,
                color:
                    isDarkMode
                        ? Colors.grey[400]
                        : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: 12,
        bottom: 20,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final notification = items[index];

        return Dismissible(
          key: Key(notification.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius:
                  BorderRadius.circular(14),
            ),
            alignment: Alignment.centerRight,
            padding:
                const EdgeInsets.only(right: 20),
            child: const Icon(
              Icons.delete,
              color: Colors.white,
            ),
          ),
          onDismissed: (_) {
            _deleteNotification(notification);
          },
          child: GestureDetector(
            onTap: () =>
                _markAsRead(notification),
            child: Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 5,
              ),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: notification.isRead
                    ? isDarkMode
                        ? const Color(0xFF2C2C2C)
                        : Colors.grey.shade100
                    : isDarkMode
                        ? const Color(0xFF263B63)
                        : const Color(0xFFE8F0FF),
                borderRadius:
                    BorderRadius.circular(14),
                border: Border.all(
                  color: notification.isRead
                      ? Colors.transparent
                      : const Color(0xFF4A7FF7),
                  width:
                      notification.isRead ? 0 : 1.5,
                ),
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          notification.type ==
                                  'alert'
                              ? Colors.red
                                  .withOpacity(0.15)
                              : const Color(
                                  0xFF4A7FF7,
                                ).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      notification.type ==
                              'alert'
                          ? Icons.warning_rounded
                          : Icons.campaign_rounded,
                      color:
                          notification.type ==
                                  'alert'
                              ? Colors.red
                              : const Color(
                                  0xFF4A7FF7,
                                ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      notification
                                              .isRead
                                          ? FontWeight.w500
                                          : FontWeight.bold,
                                  color:
                                      isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
                                ),
                              ),
                            ),

                            if (!notification.isRead)
                              Container(
                                width: 9,
                                height: 9,
                                decoration:
                                    const BoxDecoration(
                                  color:
                                      Color(
                                    0xFF4A7FF7,
                                  ),
                                  shape:
                                      BoxShape.circle,
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        Text(
                          notification.body,
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          _formatDate(
                            notification.timestamp,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDarkMode
                                    ? Colors.grey[500]
                                    : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color:
                          isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600],
                    ),
                    onPressed: () =>
                        _deleteNotification(
                      notification,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===================================================
  // BUILD
  // ===================================================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (
        context,
        isDarkMode,
        child,
      ) {
        final announcements =
            _getNotifications('announcement');

        final alerts =
            _getNotifications('alert');

        return Scaffold(
          backgroundColor:
              isDarkMode
                  ? const Color(0xFF212121)
                  : Colors.white,

          body: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================

              Container(
                width: double.infinity,
                color: isDarkMode
                    ? const Color(0xFF212121)
                    : const Color.fromARGB(
                        255,
                        72,
                        119,
                        247,
                      ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onDoubleTap: () {
                            isDarkModeNotifier
                                    .value =
                                !isDarkModeNotifier
                                    .value;
                          },
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Image.asset(
                              "assets/icon/detect-co_logo.png",
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        const Text(
                          'Notification',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        const Spacer(),

                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                          onSelected: (value) {
                            if (value ==
                                'mark_all') {
                              NotificationStorage
                                  .markAllAsRead()
                                  .then((_) {
                                _loadNotifications();
                              });
                            }

                            if (value ==
                                'delete_all') {
                              _deleteAllNotifications();
                            }
                          },
                          itemBuilder: (context) {
                            return [
                              const PopupMenuItem(
                                value: 'mark_all',
                                child: Text(
                                  'Mark all as read',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete_all',
                                child: Text(
                                  'Remove all notifications',
                                ),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================================
              // TABS
              // =================================================

              Container(
                color: isDarkMode
                    ? const Color(0xFF303030)
                    : Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor:
                      const Color(0xFF4A7FF7),
                  unselectedLabelColor:
                      isDarkMode
                          ? Colors.grey[400]
                          : Colors.grey[600],
                  indicatorColor:
                      const Color(0xFF4A7FF7),
                  tabs: const [
                    Tab(
                      icon:
                          Icon(Icons.campaign),
                      text: 'Announcements',
                    ),
                    Tab(
                      icon:
                          Icon(Icons.warning),
                      text: 'Alerts',
                    ),
                  ],
                ),
              ),

              // =================================================
              // NOTIFICATIONS
              // =================================================

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNotificationList(
                      announcements,
                      isDarkMode,
                    ),
                    _buildNotificationList(
                      alerts,
                      isDarkMode,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
