import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A persistent, copyable toast notification that stays visible until dismissed.
///
/// Stitch style: bottom-anchored surface-container card with leading icon,
/// copy action, and close button. Uses [colorScheme] for theming.
class AppToast {
  static final AppToast _instance = AppToast._internal();
  factory AppToast() => _instance;
  AppToast._internal();

  static AppToast get instance => _instance;

  /// Shows a persistent toast with selectable text.
  ///
  /// [message] - The message to display.
  /// [icon] - Optional icon (defaults to error icon for errors, info icon otherwise).
  /// [backgroundColor] - Optional background color.
  /// [foregroundColor] - Optional foreground color.
  void showToast({
    required BuildContext context,
    required String message,
    IconData? icon,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final effectiveIcon = icon ?? Icons.error_outline;
    final effectiveBgColor =
        backgroundColor ?? cs.errorContainer;
    final effectiveFgColor =
        foregroundColor ?? cs.onErrorContainer;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => _ToastOverlay(
        message: message,
        icon: effectiveIcon,
        backgroundColor: effectiveBgColor,
        foregroundColor: effectiveFgColor,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  const _ToastOverlay({
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay> {
  bool _isCopied = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.foregroundColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.foregroundColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.foregroundColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      widget.message,
                      style: TextStyle(
                        color: widget.foregroundColor,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: widget.message));
                      setState(() {
                        _isCopied = true;
                      });
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) {
                          setState(() {
                            _isCopied = false;
                          });
                        }
                      });
                    },
                    icon: Icon(
                      _isCopied ? Icons.check : Icons.copy_rounded,
                      color: widget.foregroundColor,
                      size: 18,
                    ),
                    label: Text(
                      _isCopied ? 'Copied' : 'Copy',
                      style: TextStyle(
                        color: widget.foregroundColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: widget.foregroundColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: widget.foregroundColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: widget.foregroundColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows an error toast.
void showErrorToast({required BuildContext context, required String message}) {
  AppToast.instance.showToast(
    context: context,
    message: message,
    icon: Icons.error_outline,
  );
}

/// Shows an info toast.
void showInfoToast({required BuildContext context, required String message}) {
  AppToast.instance.showToast(
    context: context,
    message: message,
    icon: Icons.info_outline,
  );
}
