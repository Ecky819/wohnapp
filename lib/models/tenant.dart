import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Tenant {
  const Tenant({
    required this.id,
    required this.name,
    this.primaryColorHex,
    this.accentColorHex,
    this.logoUrl,
    this.contactEmail,
    this.contactPhone,
    this.address,
    this.imprintUrl,
    // SEPA / Bankverbindung
    this.bankAccountHolder,
    this.bankIban,
    this.bankBic,
    // Integrationen
    this.erpWebhookUrl,
    this.erpWebhookSecret,
    this.datevConsultantNumber,
    this.datevClientNumber,
  });

  final String id;
  final String name;
  final String? primaryColorHex;
  final String? accentColorHex;
  final String? logoUrl;
  final String? contactEmail;
  final String? contactPhone;
  final String? address;
  final String? imprintUrl;
  final String? bankAccountHolder;
  final String? bankIban;
  final String? bankBic;
  final String? erpWebhookUrl;
  final String? erpWebhookSecret;
  final String? datevConsultantNumber;
  final String? datevClientNumber;

  /// Converts a stored hex string (e.g. '#6366F1' or '6366F1') to a Color.
  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : null;
  }

  Color get primaryColor =>
      _hexToColor(primaryColorHex) ?? const Color(0xFF6366F1); // Indigo default

  Color get accentColor =>
      _hexToColor(accentColorHex) ?? primaryColor;

  factory Tenant.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Tenant(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      primaryColorHex: data['primaryColorHex'] as String?,
      accentColorHex: data['accentColorHex'] as String?,
      logoUrl: data['logoUrl'] as String?,
      contactEmail: data['contactEmail'] as String?,
      contactPhone: data['contactPhone'] as String?,
      address: data['address'] as String?,
      imprintUrl: data['imprintUrl'] as String?,
      bankAccountHolder: data['bankAccountHolder'] as String?,
      bankIban: data['bankIban'] as String?,
      bankBic: data['bankBic'] as String?,
      erpWebhookUrl: data['erpWebhookUrl'] as String?,
      erpWebhookSecret: data['erpWebhookSecret'] as String?,
      datevConsultantNumber: data['datevConsultantNumber'] as String?,
      datevClientNumber: data['datevClientNumber'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        if (primaryColorHex != null) 'primaryColorHex': primaryColorHex,
        if (accentColorHex != null) 'accentColorHex': accentColorHex,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (contactEmail != null) 'contactEmail': contactEmail,
        if (contactPhone != null) 'contactPhone': contactPhone,
        if (address != null) 'address': address,
        if (imprintUrl != null) 'imprintUrl': imprintUrl,
        if (bankAccountHolder != null) 'bankAccountHolder': bankAccountHolder,
        if (bankIban != null) 'bankIban': bankIban,
        if (bankBic != null) 'bankBic': bankBic,
        if (erpWebhookUrl != null) 'erpWebhookUrl': erpWebhookUrl,
        if (erpWebhookSecret != null) 'erpWebhookSecret': erpWebhookSecret,
        if (datevConsultantNumber != null) 'datevConsultantNumber': datevConsultantNumber,
        if (datevClientNumber != null) 'datevClientNumber': datevClientNumber,
      };
}
