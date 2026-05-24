import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/material.dart';

class PlayerProfileCard extends StatefulWidget {
  const PlayerProfileCard({
    super.key,
    required this.playerName,
    required this.subtitle,
    required this.onTap,
    this.uuid,
  });

  final String playerName;
  final String subtitle;
  final VoidCallback onTap;
  final String? uuid;

  @override
  State<PlayerProfileCard> createState() => _PlayerProfileCardState();
}

class _PlayerProfileCardState extends State<PlayerProfileCard> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return AnimatedScale(
      scale: _scale,
      duration: AppSettings.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _scale = 0.97),
          onTapUp: (_) => setState(() => _scale = 1.0),
          onTapCancel: () => setState(() => _scale = 1.0),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.uuid != null && widget.uuid!.isNotEmpty
                      ? Image.network(
                          'https://crafatar.com/avatars/${widget.uuid}?size=64&overlay',
                          fit: BoxFit.cover,
                          errorBuilder: (BuildContext context, Object error,
                              StackTrace? stackTrace) {
                            return Image.network(
                              'https://minotar.net/avatar/${widget.playerName}/64.png',
                              fit: BoxFit.cover,
                              errorBuilder: (BuildContext context, Object error,
                                  StackTrace? stackTrace) {
                                return Icon(
                                  Icons.person_rounded,
                                  color: colors.primary,
                                  size: 34,
                                );
                              },
                            );
                          },
                        )
                      : Image.network(
                          'https://minotar.net/avatar/${widget.playerName}/64.png',
                          fit: BoxFit.cover,
                          errorBuilder: (BuildContext context, Object error,
                              StackTrace? stackTrace) {
                            return Icon(
                              Icons.person_rounded,
                              color: colors.primary,
                              size: 34,
                            );
                          },
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
