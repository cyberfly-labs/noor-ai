import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/chat_provider.dart';

class ChatHistoryPage extends ConsumerStatefulWidget {
  const ChatHistoryPage({super.key});

  @override
  ConsumerState<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends ConsumerState<ChatHistoryPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(chatProvider.notifier).loadMessages());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Text(
                    'Chat',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const Spacer(),
                  if (state.messages.isNotEmpty)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        color: AppColors.textMuted,
                        padding: EdgeInsets.zero,
                        onPressed: () => _confirmClear(context),
                      ),
                    ),
                ],
              ),
            ),

            // ── Messages ───────────────────────────────
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                  : state.messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 80),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) {
                            final msg = state.messages[index];
                            final isUser = msg.role == 'user';
                            final timeStr = DateFormat.jm().format(msg.createdAt);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: [
                                  if (!isUser) ...[
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.gold10,
                                        border: Border.all(color: AppColors.gold20),
                                      ),
                                      child: const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.gold),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: isUser ? AppColors.gold10 : AppColors.surfaceLight,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                                          bottomRight: Radius.circular(isUser ? 4 : 16),
                                        ),
                                        border: Border.all(
                                          color: isUser ? AppColors.gold15 : AppColors.divider,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (isUser)
                                            Text(
                                              msg.content,
                                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                            )
                                          else
                                            MarkdownBody(
                                              data: msg.content,
                                              styleSheet: MarkdownStyleSheet(
                                                p: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                                                strong: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          const SizedBox(height: 4),
                                          Text(
                                            timeStr,
                                            style: TextStyle(fontSize: 10, color: AppColors.textMuted60),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isUser) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.surfaceLight,
                                        border: Border.all(color: AppColors.divider),
                                      ),
                                      child: const Icon(Icons.person_rounded, size: 14, color: AppColors.textMuted),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceLight,
              border: Border.all(color: AppColors.divider),
            ),
            child: Icon(Icons.chat_bubble_outline_rounded, size: 30, color: AppColors.textMuted50),
          ),
          const SizedBox(height: 20),
          const Text(
            'No conversations yet',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Start by asking Noor a question',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear History', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will permanently delete all conversations.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(chatProvider.notifier).clearHistory();
              Navigator.pop(ctx);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
