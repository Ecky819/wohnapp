import 'package:cloud_functions/cloud_functions.dart';

/// Result of an AI ticket analysis.
class TicketAnalysis {
  const TicketAnalysis({
    required this.ticketCategory,
    required this.tradeCategory,
    required this.priority,
    required this.reasoning,
    required this.confidence,
  });

  /// 'damage' | 'maintenance'
  final String ticketCategory;

  /// 'plumbing' | 'electrical' | 'heating' | 'general'
  final String tradeCategory;

  /// 'normal' | 'high'
  final String priority;

  /// Short German explanation
  final String reasoning;

  /// 0.0 – 1.0
  final double confidence;

  factory TicketAnalysis.fromMap(Map<Object?, Object?> map) {
    return TicketAnalysis(
      ticketCategory: map['ticketCategory'] as String? ?? 'damage',
      tradeCategory: map['tradeCategory'] as String? ?? 'general',
      priority: map['priority'] as String? ?? 'normal',
      reasoning: map['reasoning'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class AiAnalysisService {
  AiAnalysisService._();
  static final instance = AiAnalysisService._();

  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Calls the `analyzeTicket` Cloud Function.
  /// Returns `null` if the function is unavailable (graceful degradation).
  Future<TicketAnalysis?> analyzeTicket({
    required String title,
    required String description,
    String? imageUrl,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'analyzeTicket',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final result = await callable.call<Map<Object?, Object?>>({
        'title': title,
        'description': description,
        if (imageUrl != null) 'imageUrl': imageUrl,
      });

      return TicketAnalysis.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      // Graceful degradation — log and return null so keyword fallback kicks in
      // ignore: avoid_print
      print('AiAnalysisService: ${e.code} – ${e.message}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('AiAnalysisService unexpected error: $e');
      return null;
    }
  }
}
