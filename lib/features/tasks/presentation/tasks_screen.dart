import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../application/tasks_providers.dart';
import '../domain/task.dart';

/// Tasks: the checklist, on its own.
///
/// PaperOS does not implement a general file manager, so tasks are not hidden
/// inside one. They live on a dated checklist reachable from Paper Home — the
/// screen answers "what needs doing today" and the day arrows move the
/// question, nothing more.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _hideCompleted = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Task>> tasks = ref.watch(tasksForDayProvider);
    final DateTime selected = ref.watch(taskDayProvider);
    final TaskActions actions = ref.read(taskActionsProvider);

    final List<Task> visible =
        tasks.value
            ?.where((Task task) => !_hideCompleted || !task.isDone)
            .toList(growable: false) ??
        const <Task>[];

    return Scaffold(
      appBar: PaperTopBar(
        title: 'Tasks',
        subtitle: formatLongDate(selected),
        actions: <Widget>[
          IconButton(
            onPressed: () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous day',
          ),
          IconButton(
            onPressed: () => ref.read(taskDayProvider.notifier).resetToToday(),
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Jump to today',
          ),
          IconButton(
            onPressed: () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next day',
          ),
          IconButton(
            onPressed: () => setState(() => _hideCompleted = !_hideCompleted),
            icon: Icon(
              _hideCompleted
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            tooltip: _hideCompleted ? 'Show completed' : 'Hide completed',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: tasks.when(
              loading: () => const PaperLoading(),
              error: (Object error, StackTrace stack) => PaperErrorView(
                message: 'Your tasks could not be read from storage.',
                onRetry: () => ref.invalidate(tasksForDayProvider),
              ),
              data: (List<Task> all) {
                if (all.isEmpty) {
                  return PaperEmptyState(
                    title: 'No tasks for this day',
                    message:
                        'Add a task, or move to another day with the arrows '
                        'in the top bar.',
                    icon: Icons.checklist_outlined,
                    action: PaperButton(
                      label: 'Add a task',
                      icon: Icons.add,
                      onPressed: () => _addTask(actions, selected),
                    ),
                  );
                }
                if (visible.isEmpty) {
                  return PaperEmptyState(
                    title: 'Nothing to show',
                    message:
                        'Every task on this day is done. Completed items are '
                        'hidden.',
                    icon: Icons.done_all,
                    action: PaperButton(
                      label: 'Show completed',
                      onPressed: () => setState(() => _hideCompleted = false),
                    ),
                  );
                }
                final int doneCount = all.where((Task t) => t.isDone).length;
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: PaperSpace.xxl),
                  itemCount: visible.length + 1,
                  itemBuilder: (BuildContext context, int index) {
                    if (index == visible.length) {
                      return _TaskSummary(total: all.length, done: doneCount);
                    }
                    final Task task = visible[index];
                    return _TaskTile(
                      task: task,
                      day: selected,
                      showRule: index != visible.length - 1,
                    );
                  },
                );
              },
            ),
          ),
          _Composer(day: selected),
        ],
      ),
    );
  }

  void _shiftDay(int delta) {
    final DateTime current = ref.read(taskDayProvider);
    ref
        .read(taskDayProvider.notifier)
        .select(DateTime(current.year, current.month, current.day + delta));
  }

  Future<void> _addTask(TaskActions actions, DateTime day) async {
    final String? title = await showPaperTextPrompt(
      context,
      title: 'New task',
      label: 'What needs doing?',
      confirmLabel: 'Add',
    );
    if (title == null || !mounted) return;
    await actions.create(title, dueDate: day);
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({
    required this.task,
    required this.day,
    required this.showRule,
  });

  final Task task;
  final DateTime day;
  final bool showRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final bool overdue = task.isOverdueOn(day);

    return Column(
      children: <Widget>[
        PaperListTile(
          title: task.title,
          subtitle: _subtitleFor(task, day),
          semanticLabel: '${task.title}, ${_subtitleFor(task, day)}',
          leading: SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: task.isDone,
              onChanged: (bool? value) =>
                  ref.read(taskActionsProvider).setDone(task, value ?? false),
              side: BorderSide(color: palette.ruleStrong, width: 1.2),
              fillColor: WidgetStatePropertyAll<Color>(palette.inverseCanvas),
              checkColor: palette.inverseInk,
              shape: const RoundedRectangleBorder(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          trailing: task.isDone
              ? Text(
                  formatCompactDate(task.completedAt ?? task.createdAt),
                  style: type.caption,
                )
              : overdue
              ? Text('Overdue', style: type.caption)
              : null,
          onLongPress: () => _edit(context, ref),
        ),
        if (showRule) const PaperRule(inset: PaperSpace.gutter),
      ],
    );
  }

  String _subtitleFor(Task task, DateTime day) {
    if (task.isDone) {
      final DateTime? at = task.completedAt;
      return at == null ? 'Done' : 'Done ${formatDayMonth(at)}';
    }
    final DateTime? due = task.dueDate;
    if (due == null) {
      return 'No date · added ${formatDayMonth(task.createdAt)}';
    }
    if (task.isOverdueOn(day)) return 'Overdue · due ${formatDayMonth(due)}';
    if (task.isDueOn(day)) {
      return 'Due today · added ${formatDayMonth(task.createdAt)}';
    }
    return 'Due ${formatDayMonth(due)}';
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final TaskActions actions = ref.read(taskActionsProvider);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: PaperSpace.sm),
              PaperListTile(
                title: 'Rename',
                leading: const Icon(Icons.edit_outlined, size: 20),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final String? title = await showPaperTextPrompt(
                    context,
                    title: 'Rename task',
                    label: 'Title',
                    initialValue: task.title,
                  );
                  if (title != null) await actions.rename(task, title);
                },
              ),
              PaperListTile(
                title: 'Delete',
                leading: const Icon(Icons.delete_outline, size: 20),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final bool confirmed = await confirmDestructiveAction(
                    context,
                    title: 'Delete this task?',
                    message:
                        '"${task.title}" will be removed from this device.',
                    confirmLabel: 'Delete',
                  );
                  if (confirmed) await actions.delete(task);
                },
              ),
              const SizedBox(height: PaperSpace.sm),
            ],
          ),
        );
      },
    );
  }
}

class _TaskSummary extends ConsumerWidget {
  const _TaskSummary({required this.total, required this.done});

  final int total;
  final int done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        PaperSpace.lg,
        PaperSpace.gutter,
        PaperSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$done of $total done', style: PaperTypography.of(context).meta),
          const SizedBox(height: PaperSpace.sm),
          PaperProgressBar(value: total == 0 ? 0 : done / total),
          if (done > 0) ...<Widget>[
            const SizedBox(height: PaperSpace.md),
            PaperTextAction(
              label: 'Clear completed',
              onPressed: () => ref.read(taskActionsProvider).clearCompleted(),
            ),
          ],
        ],
      ),
    );
  }
}

/// The composer. A text field pinned above the destination bar, because adding
/// a task is the only thing a user does on this screen often enough to deserve
/// a permanent affordance.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.day});

  final DateTime day;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String text = _controller.text;
    if (text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final Task? created = await ref
        .read(taskActionsProvider)
        .create(text, dueDate: widget.day);
    if (!mounted) return;
    setState(() => _busy = false);
    // Only clear on success: a lost keystroke is worse than a redundant one.
    if (created != null) {
      _controller.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.rule)),
      ),
      padding: EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        PaperSpace.sm,
        PaperSpace.sm,
        MediaQuery.viewInsetsOf(context).bottom + PaperSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              style: type.input,
              cursorColor: palette.ink,
              textInputAction: TextInputAction.done,
              onSubmitted: (String _) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Add a task',
                hintStyle: type.input.copyWith(color: palette.inkFaint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: PaperSpace.sm,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Add task',
          ),
        ],
      ),
    );
  }
}
