import 'package:cloud_functions/cloud_functions.dart';

enum InvoiceVerdict { ok, suspicious, overpriced }

extension InvoiceVerdictX on InvoiceVerdict {
  String get label {
    switch (this) {
      case InvoiceVerdict.ok:
        return 'Plausibel';
      case InvoiceVerdict.suspicious:
        return 'Auffällig';
      case InvoiceVerdict.overpriced:
        return 'Überhöht';
    }
  }
}

class InvoiceAnalysis {
  const InvoiceAnalysis({
    required this.verdict,
    required this.reasoning,
    required this.suggestedMin,
    required this.suggestedMax,
    required this.flags,
    required this.confidence,
  });

  final InvoiceVerdict verdict;
  final String reasoning;
  final double suggestedMin;
  final double suggestedMax;
  final List<String> flags;
  final double confidence;

  static InvoiceVerdict _parseVerdict(String? v) {
    switch (v) {
      case 'overpriced':
        return InvoiceVerdict.overpriced;
      case 'suspicious':
        return InvoiceVerdict.suspicious;
      default:
        return InvoiceVerdict.ok;
    }
  }

  factory InvoiceAnalysis.fromMap(Map<String, dynamic> m) => InvoiceAnalysis(
        verdict: _parseVerdict(m['verdict'] as String?),
        reasoning: m['reasoning'] as String? ?? '',
        suggestedMin: (m['suggestedMin'] as num?)?.toDouble() ?? 0,
        suggestedMax: (m['suggestedMax'] as num?)?.toDouble() ?? 0,
        flags: (m['flags'] as List<dynamic>? ?? [])
            .map((f) => f.toString())
            .toList(),
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
      );
}

class InvoiceAiService {
  InvoiceAiService._();
  static final instance = InvoiceAiService._();

  final _fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
      .httpsCallable('analyzeInvoice');

  /// Returns null on error — callers should handle gracefully.
  Future<InvoiceAnalysis?> analyzeInvoice({
    required String ticketTitle,
    required String ticketCategory,
    required String tradeCategory,
    required String contractorName,
    required double amount,
    required List<Map<String, dynamic>> positions,
  }) async {
    try {
      final result = await _fn.call(<String, dynamic>{
        'ticketTitle': ticketTitle,
        'ticketCategory': ticketCategory,
        'tradeCategory': tradeCategory,
        'contractorName': contractorName,
        'amount': amount,
        'positions': positions,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return InvoiceAnalysis.fromMap(data);
    } catch (e) {
      return null;
    }
  }
}
