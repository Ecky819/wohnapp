import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invoice.dart';

class InvoiceRepository {
  InvoiceRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('invoices');

  // ─── Streams ──────────────────────────────────────────────────────────────

  Stream<List<Invoice>> watchForTicket(String ticketId) {
    return _col
        .where('ticketId', isEqualTo: ticketId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Invoice.fromFirestore).toList());
  }

  Stream<List<Invoice>> watchPending(String tenantId) {
    return _col
        .where('tenantId', isEqualTo: tenantId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Invoice.fromFirestore).toList());
  }

  Stream<List<Invoice>> watchAll(String tenantId) {
    return _col
        .where('tenantId', isEqualTo: tenantId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Invoice.fromFirestore).toList());
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  Future<String> createInvoice(Invoice invoice) async {
    final ref = await _col.add({
      ...invoice.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updatePdfUrl(String invoiceId, String pdfUrl) async {
    await _col.doc(invoiceId).update({'pdfUrl': pdfUrl});
  }

  Future<void> approveInvoice(String invoiceId) async {
    await _col.doc(invoiceId).update({
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectInvoice(String invoiceId, String reason) async {
    await _col.doc(invoiceId).update({
      'status': 'rejected',
      'rejectionReason': reason,
    });
  }

  Future<void> markExported(List<String> invoiceIds) async {
    final batch = _db.batch();
    for (final id in invoiceIds) {
      batch.update(_col.doc(id), {'status': 'exported'});
    }
    await batch.commit();
  }

  // ─── One-shot fetch for export ─────────────────────────────────────────────

  Future<List<Invoice>> fetchApproved(
    String tenantId, {
    DateTime? from,
    DateTime? to,
  }) async {
    Query<Map<String, dynamic>> q = _col
        .where('tenantId', isEqualTo: tenantId)
        .where('status', whereIn: ['approved', 'exported'])
        .orderBy('createdAt', descending: false);

    if (from != null) {
      q = q.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      q = q.where('createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(to));
    }

    final snap = await q.get();
    return snap.docs.map(Invoice.fromFirestore).toList();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepository(FirebaseFirestore.instance);
});

final invoicesForTicketProvider =
    StreamProvider.family<List<Invoice>, String>((ref, ticketId) {
  return ref.read(invoiceRepositoryProvider).watchForTicket(ticketId);
});

final pendingInvoicesProvider =
    StreamProvider.family<List<Invoice>, String>((ref, tenantId) {
  return ref.read(invoiceRepositoryProvider).watchPending(tenantId);
});
