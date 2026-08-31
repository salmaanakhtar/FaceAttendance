/// Admin console data models (mirror the backend DTOs).
library;

class Employee {
  final String id;
  final String employeeCode;
  final String name;
  final String? email;
  final String status;
  final bool enrolled;
  final Map<String, dynamic> schedule;
  final String? enrolledAt;

  Employee({
    required this.id,
    required this.employeeCode,
    required this.name,
    this.email,
    this.status = 'active',
    this.enrolled = false,
    this.schedule = const {},
    this.enrolledAt,
  });

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as String,
        employeeCode: j['employeeCode'] as String,
        name: j['name'] as String,
        email: j['email'] as String?,
        status: j['status'] as String? ?? 'active',
        enrolled: j['enrolled'] as bool? ?? false,
        schedule: (j['schedule'] as Map<String, dynamic>?) ?? {},
        enrolledAt: j['enrolledAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeCode': employeeCode,
        'name': name,
        'email': email,
        'status': status,
        'enrolled': enrolled,
        'schedule': schedule,
        'enrolledAt': enrolledAt,
      };
}

class AttendanceSession {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String workDate;
  final String? checkInAt;
  final String? checkOutAt;
  final String checkInSource;
  final String checkOutSource;
  final String status;
  final int breakMinutes;
  final int workedMinutes;
  final int lateMinutes;
  final int earlyMinutes;
  final int overtimeMinutes;
  final bool isLate;
  final bool isEarly;
  final bool hasOvertime;
  final String? note;
  final bool corrected;

  AttendanceSession({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.workDate,
    this.checkInAt,
    this.checkOutAt,
    this.checkInSource = 'auto',
    this.checkOutSource = 'auto',
    this.status = 'open',
    this.breakMinutes = 0,
    this.workedMinutes = 0,
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.overtimeMinutes = 0,
    this.isLate = false,
    this.isEarly = false,
    this.hasOvertime = false,
    this.note,
    this.corrected = false,
  });

  factory AttendanceSession.fromJson(Map<String, dynamic> j) => AttendanceSession(
        id: j['id'] as String,
        employeeId: j['employeeId'] as String,
        employeeName: j['employeeName'] as String,
        employeeCode: j['employeeCode'] as String,
        workDate: j['workDate'] as String,
        checkInAt: j['checkInAt'] as String?,
        checkOutAt: j['checkOutAt'] as String?,
        checkInSource: j['checkInSource'] as String? ?? 'auto',
        checkOutSource: j['checkOutSource'] as String? ?? 'auto',
        status: j['status'] as String? ?? 'open',
        breakMinutes: (j['breakMinutes'] as num?)?.toInt() ?? 0,
        workedMinutes: (j['workedMinutes'] as num?)?.toInt() ?? 0,
        lateMinutes: (j['lateMinutes'] as num?)?.toInt() ?? 0,
        earlyMinutes: (j['earlyMinutes'] as num?)?.toInt() ?? 0,
        overtimeMinutes: (j['overtimeMinutes'] as num?)?.toInt() ?? 0,
        isLate: j['isLate'] as bool? ?? false,
        isEarly: j['isEarly'] as bool? ?? false,
        hasOvertime: j['hasOvertime'] as bool? ?? false,
        note: j['note'] as String?,
        corrected: j['corrected'] as bool? ?? false,
      );

  String get hoursText => workedMinutes == 0 && checkOutAt == null
      ? ''
      : '${workedMinutes ~/ 60}h ${workedMinutes % 60}m';
}

class CorrectionEntry {
  final String id;
  final String? sessionId;
  final String employeeId;
  final String field;
  final dynamic oldValue;
  final dynamic newValue;
  final String admin;
  final String reason;
  final String createdAt;
  final Map<String, dynamic>? details;

  CorrectionEntry({
    required this.id,
    this.sessionId,
    required this.employeeId,
    required this.field,
    this.oldValue,
    this.newValue,
    required this.admin,
    required this.reason,
    required this.createdAt,
    this.details,
  });

  factory CorrectionEntry.fromJson(Map<String, dynamic> j) => CorrectionEntry(
        id: j['id'] as String,
        sessionId: j['sessionId'] as String?,
        employeeId: j['employeeId'] as String,
        field: j['field'] as String,
        oldValue: j['oldValue'],
        newValue: j['newValue'],
        admin: j['admin'] as String,
        reason: j['reason'] as String,
        createdAt: j['createdAt'] as String,
        details: j['details'] as Map<String, dynamic>?,
      );
}

class AuditEvent {
  final String id;
  final String actorType;
  final String? actorId;
  final String action;
  final String? targetType;
  final String? targetId;
  final String createdAt;
  final Map<String, dynamic>? details;

  AuditEvent({
    required this.id,
    required this.actorType,
    this.actorId,
    required this.action,
    this.targetType,
    this.targetId,
    required this.createdAt,
    this.details,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(
        id: (j['id'] as num?)?.toString() ?? '',
        actorType: j['actorType'] as String? ?? '',
        actorId: j['actorId'] as String?,
        action: j['action'] as String,
        targetType: j['targetType'] as String?,
        targetId: j['targetId'] as String?,
        createdAt: j['createdAt'] as String,
        details: j['details'] as Map<String, dynamic>?,
      );
}

String formatLocal(String? iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final l = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

String formatLocalDate(String? iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final l = dt.toLocal();
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[l.month - 1]} ${l.day}, ${l.year}';
}
