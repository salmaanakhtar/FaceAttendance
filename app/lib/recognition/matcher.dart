/// Pure embedding matching logic — deterministic and unit tested.
library;

import 'dart:math' as math;

import '../config.dart';

double cosineSimilarity(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

List<double> l2Normalize(List<double> v) {
  var norm = 0.0;
  for (final x in v) {
    norm += x * x;
  }
  norm = math.sqrt(norm);
  if (norm == 0) return List.filled(v.length, 0);
  return v.map((x) => x / norm).toList();
}

/// Average of several embeddings, re-normalized (fused enrollment template).
List<double> fuseEmbeddings(List<List<double>> embeddings) {
  if (embeddings.isEmpty) return const [];
  final n = embeddings.first.length;
  final sum = List<double>.filled(n, 0);
  for (final e in embeddings) {
    for (var i = 0; i < n && i < e.length; i++) {
      sum[i] += e[i];
    }
  }
  return l2Normalize(sum);
}

class MatchResult {
  final String? employeeId;
  final double score;
  final double margin;
  final bool ambiguous;
  MatchResult({this.employeeId, required this.score, required this.margin, required this.ambiguous});

  bool get matched => employeeId != null && !ambiguous;
}

/// Nearest-neighbour match with acceptance threshold + ambiguity margin.
MatchResult matchEmbedding(
  List<double> query,
  Map<String, List<double>> templates, {
  double acceptThreshold = kAcceptThreshold,
  double ambiguityMargin = kAmbiguityMargin,
}) {
  String? bestId;
  var bestScore = -2.0;
  var secondScore = -2.0;
  for (final entry in templates.entries) {
    final s = cosineSimilarity(query, entry.value);
    if (s > bestScore) {
      secondScore = bestScore;
      bestScore = s;
      bestId = entry.key;
    } else if (s > secondScore) {
      secondScore = s;
    }
  }
  if (bestId == null) return MatchResult(score: -1, margin: 0, ambiguous: false);
  final margin = bestScore - secondScore;
  final ambiguous = margin < ambiguityMargin;
  final accepted = bestScore >= acceptThreshold;
  return MatchResult(
    employeeId: accepted ? bestId : null,
    score: bestScore,
    margin: margin,
    ambiguous: ambiguous && accepted,
  );
}

/// Employee "last direction" cache decision: device-side action hint.
/// The server stays authoritative; this only optimizes the first prompt.
String? hintDirection({required String? lastDirection, required bool? isCurrentlyIn}) {
  if (isCurrentlyIn == true) return 'out';
  if (isCurrentlyIn == false) return 'in';
  if (lastDirection == 'in') return 'out';
  if (lastDirection == 'out') return 'in';
  return 'in';
}
