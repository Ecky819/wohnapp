import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Rundes Logo des Mandanten — zeigt Bild wenn vorhanden, sonst farbige Initiale.
class TenantLogoAvatar extends StatelessWidget {
  const TenantLogoAvatar({
    super.key,
    required this.name,
    required this.primaryColor,
    this.logoUrl,
    this.radius = 18,
  });

  final String name;
  final Color primaryColor;
  final String? logoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: primaryColor.withValues(alpha: 0.1),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: logoUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (_, __) => _Initials(
              name: name,
              color: primaryColor,
              radius: radius,
            ),
            errorWidget: (_, __, ___) => _Initials(
              name: name,
              color: primaryColor,
              radius: radius,
            ),
          ),
        ),
      );
    }
    return _Initials(name: name, color: primaryColor, radius: radius);
  }
}

class _Initials extends StatelessWidget {
  const _Initials({
    required this.name,
    required this.color,
    required this.radius,
  });
  final String name;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}
