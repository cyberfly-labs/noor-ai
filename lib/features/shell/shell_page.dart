import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class ShellPage extends StatefulWidget {
  final Widget child;

  const ShellPage({super.key, required this.child});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _currentIndex = 0;

  static const _routes = ['/home', '/quran', '/chat', '/daily-ayah', '/bookmarks', '/posts', '/settings'];

  @override
  Widget build(BuildContext context) {
    // Sync index with current route
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) {
        if (_currentIndex != i) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _currentIndex = i);
          });
        }
        break;
      }
    }

    return Scaffold(
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.85),
              border: Border(
                top: BorderSide(color: AppColors.divider.withValues(alpha: 0.6), width: 0.5),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(_routes.length, (index) {
                    return _NavItem(
                      icon: _iconFor(index, false),
                      activeIcon: _iconFor(index, true),
                      label: _labelFor(index),
                      isSelected: _currentIndex == index,
                      onTap: () {
                        if (index != _currentIndex) {
                          setState(() => _currentIndex = index);
                          context.go(_routes[index]);
                        }
                      },
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(int index, bool active) {
    switch (index) {
      case 0:
        return active ? Icons.mic_rounded : Icons.mic_none_rounded;
      case 1:
        return active ? Icons.menu_book_rounded : Icons.menu_book_outlined;
      case 2:
        return active ? Icons.chat_rounded : Icons.chat_outlined;
      case 3:
        return active ? Icons.auto_stories_rounded : Icons.auto_stories_outlined;
      case 4:
        return active ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded;
      case 5:
        return active ? Icons.article_rounded : Icons.article_outlined;
      case 6:
        return active ? Icons.settings_rounded : Icons.settings_outlined;
      default:
        return Icons.circle;
    }
  }

  String _labelFor(int index) {
    switch (index) {
      case 0:
        return 'Ask';
      case 1:
        return 'Quran';
      case 2:
        return 'Chat';
      case 3:
        return 'Daily';
      case 4:
        return 'Saved';
      case 5:
        return 'Posts';
      case 6:
        return 'Settings';
      default:
        return '';
    }
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: isSelected
            ? BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 22,
              color: isSelected ? AppColors.gold : AppColors.textMuted,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.gold : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
