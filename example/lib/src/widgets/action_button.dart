import 'package:flutter/material.dart';

class ActionButton extends StatefulWidget {
  final String? title;
  final String subTitle;
  final IconData? icon;
  final bool checked;
  final bool number;
  final Color? fillColor;
  final Function()? onPressed;
  final Function()? onLongPress;

  const ActionButton(
      {super.key,
      this.title,
      this.subTitle = '',
      this.icon,
      this.onPressed,
      this.onLongPress,
      this.checked = false,
      this.number = false,
      this.fillColor});

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    Color buttonColor = widget.fillColor ?? 
      (widget.checked ? colorScheme.primary : colorScheme.surface);
    Color textColor = widget.fillColor != null 
      ? Colors.white 
      : (widget.checked ? colorScheme.onPrimary : colorScheme.onSurface);
    Color iconColor = widget.fillColor != null 
      ? Colors.white 
      : (widget.checked ? colorScheme.onPrimary : colorScheme.primary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Material(
                color: buttonColor,
                borderRadius: BorderRadius.circular(widget.number ? 32 : 28),
                elevation: widget.checked ? 6 : 2,
                shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
                child: InkWell(
                  onTap: widget.onPressed,
                  onLongPress: widget.onLongPress,
                  onTapDown: (_) => _animationController.forward(),
                  onTapUp: (_) => _animationController.reverse(),
                  onTapCancel: () => _animationController.reverse(),
                  borderRadius: BorderRadius.circular(widget.number ? 32 : 28),
                  child: Container(
                    width: widget.number ? 64 : 56,
                    height: widget.number ? 64 : 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.number ? 32 : 28),
                      border: widget.checked ? null : Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: widget.number
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                '${widget.title}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              if (widget.subTitle.isNotEmpty)
                                Text(
                                  widget.subTitle.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w400,
                                    color: textColor.withValues(alpha: 0.7),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                            ],
                          )
                        : Icon(
                            widget.icon,
                            size: 24,
                            color: iconColor,
                          ),
                  ),
                ),
              ),
            );
          },
        ),
        if (!widget.number && widget.title != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            child: Text(
              widget.title!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ),
      ],
    );
  }
}
