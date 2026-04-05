import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const _routes = [
    '/home',
    '/quran',
    '/chat',
    '/daily-ayah',
    '/bookmarks',
    '/posts',
    '/settings',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncIndex();
  }

  void _syncIndex() {
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) {
        if (_currentIndex != i) {
          setState(() => _currentIndex = i);
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: AppColors.navBarDecoration,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: List.generate(_routes.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _NavItem(
                          icon: _iconFor(index, false),
                          activeIcon: _iconFor(index, true),
                          label: _labelFor(index),
                          isSelected: _currentIndex == index,
                          onTap: () {
                            if (index != _currentIndex) {
                              HapticFeedback.selectionClick();
                              setState(() => _currentIndex = index);
                              context.go(_routes[index]);
                            }
                          },
                        ),
                      );
                    }),
                  ),
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
        return active
            ? Icons.auto_stories_rounded
            : Icons.auto_stories_outlined;
      case 4:
        return active ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded;
      case 5:
        return active ? Icons.forum_rounded : Icons.forum_outlined;
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
        return 'Reflect';
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
        constraints: const BoxConstraints(minWidth: 74),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: isSelected
            ? BoxDecoration(
                color: AppColors.gold10,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold15),
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.transparent),
              ),
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
