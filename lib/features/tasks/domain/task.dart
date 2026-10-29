import 'package:flutter/foundation.dart';

/// A single checklist item.
///
/// Tasks are intentionally date-scoped rather than project-scoped: the Paper
/// Home screen asks one question — "what is due today?" — and any richer model
/// would be answering a question PaperOS does not have.
@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.isDone,
    required this.dueDate,
    required this.createdAt,
    required this.completedAt,
  });

  final String id;
  final String title;
  final bool isDone;

  /// Local calendar day the task belongs to, or null for an undated task.
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool isDueOn(DateTime day) {
    final DateTime? due = dueDate;
    if (due == null) return false;
    return due.year == day.year && due.month == day.month && due.day == day.day;
  }

  bool isOverdueOn(DateTime day) {
    final DateTime? due = dueDate;
    if (due == null || isDone) return false;
    final DateTime today = DateTime(day.year, day.month, day.day);
    final DateTime target = DateTime(due.year, due.month, due.day);
    return target.isBefore(today);
  }

  Task copyWith({
    String? title,
    bool? isDone,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      createdAt: createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  @override
  bool operator ==(Object other) => other is Task && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
