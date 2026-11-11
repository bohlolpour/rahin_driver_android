import 'package:flutter/material.dart';
import '../services/driver_service.dart';
import '../theme/app_theme.dart';

class MessagesScreen extends StatefulWidget {
  final String driverId;

  const MessagesScreen({super.key, required this.driverId});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    final msgs = await DriverService.getMessages(widget.driverId);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
  }

  Future<void> _openMessage(Map<String, dynamic> msg) async {
    final messageId = msg['id']?.toString() ?? '';
    final isRead = msg['isRead'] == true;
    
    // باز کردن دیالوگ پیام
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17191D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.mark_email_read_outlined, color: AppColors.primaryYellow, size: 48),
          title: Text(
            msg['title']?.toString() ?? 'پیام',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Text(
              msg['content']?.toString() ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('بستن', style: TextStyle(color: AppColors.primaryYellow)),
            ),
          ],
        );
      },
    );

    // اگر پیام خوانده نشده بود، آن را خوانده شده علامت بزن
    if (!isRead && messageId.isNotEmpty) {
      final success = await DriverService.markMessageAsRead(messageId, widget.driverId);
      if (success && mounted) {
        await _loadMessages(); // رفرش لیست
      }
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final date = DateTime.parse(raw);
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} - ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17191D),
        foregroundColor: Colors.white,
        title: const Text('پیام‌های من', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
          : _messages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mail_outline, color: Colors.white24, size: 80),
                      SizedBox(height: 16),
                      Text('پیامی وجود ندارد', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primaryYellow,
                  onRefresh: _loadMessages,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isRead = msg['isRead'] == true;
                      return GestureDetector(
                        onTap: () => _openMessage(msg),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isRead 
                                ? const Color(0xFF1A1C21) 
                                : AppColors.primaryYellow.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isRead 
                                  ? Colors.white.withValues(alpha: 0.05) 
                                  : AppColors.primaryYellow.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (isRead ? Colors.white10 : AppColors.primaryYellow).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isRead ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
                                  color: isRead ? Colors.white54 : AppColors.primaryYellow,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      msg['title']?.toString() ?? 'بدون عنوان',
                                      style: TextStyle(
                                        color: isRead ? Colors.white70 : Colors.white,
                                        fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      msg['content']?.toString() ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatDate(msg['createdAt']?.toString()),
                                      style: const TextStyle(color: Colors.white24, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isRead) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}