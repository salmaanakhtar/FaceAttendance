class PayrollReview {
  final int unresolved;
  final int unapproved;
  final int missingRates;
  final int negativeNet;
  const PayrollReview(
      {required this.unresolved,
      required this.unapproved,
      required this.missingRates,
      required this.negativeNet});
  factory PayrollReview.fromWorkers(List<Map<String, dynamic>> workers,
          {required int unapproved}) =>
      PayrollReview(
        unresolved: workers.fold(0,
            (sum, w) => sum + ((w['unresolvedShifts'] as num?)?.toInt() ?? 0)),
        unapproved: unapproved,
        missingRates: workers
            .where((w) => w['gross'] == null || w['rate'] == null)
            .length,
        negativeNet: workers.where((w) => (w['net'] as num? ?? 0) < 0).length,
      );
  bool get hasWarnings => unresolved > 0 || unapproved > 0 || negativeNet > 0;
  List<String> get warnings => [
        if (unresolved > 0)
          '$unresolved unfinished shifts are excluded from pay.',
        if (unapproved > 0)
          '$unapproved completed shifts still need attendance approval.',
        if (missingRates > 0)
          '$missingRates workers have invalid pay rates. Fix these before exporting.',
        if (negativeNet > 0)
          '$negativeNet workers have deductions greater than gross pay.',
      ];
}
