import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/task.dart';
import '../models/group.dart';
import '../helpers/general_helpers.dart';
import '../helpers/storage_helper.dart';
import '../helpers/notification_service.dart';
import 'daily_view.dart';
import 'tasks_page.dart';
import 'calendar_page.dart';
import '../widgets/group_sheets.dart';

class MainApp extends StatefulWidget {
  @override
  _MainAppAppState createState() => _MainAppAppState();
}

class _MainAppAppState extends State<MainApp> {
  final _eventsNotifier = ValueNotifier<List<Event>>([]);
  final _tasksNotifier = ValueNotifier<List<Task>>([]);
  final _groupsNotifier = ValueNotifier<List<Group>>([]);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    await NotificationService.instance.init();

    final loadedEvents = await StorageHelper.loadEvents();
    final loadedTasks = await StorageHelper.loadTasks();
    final loadedGroups = await StorageHelper.loadGroups();
    debugPrint(
      '[Storage] Loaded ${loadedEvents.length} events, ${loadedTasks.length} tasks, ${loadedGroups.length} groups',
    );

    _eventsNotifier.value = loadedEvents;
    _tasksNotifier.value = loadedTasks;
    _groupsNotifier.value = loadedGroups;

    // Auto-save on every future change, from anywhere in the app
    _previousEventIds = loadedEvents.map((e) => e.id).toSet();
    _eventsNotifier.addListener(_onEventsChanged);
    _tasksNotifier.addListener(_onTasksChanged);
    _groupsNotifier.addListener(() {
      debugPrint('[Storage] Saving ${_groupsNotifier.value.length} groups');
      StorageHelper.saveGroups(_groupsNotifier.value);
    });

    // Re-schedule every saved event's reminder on startup, since scheduled
    // OS-level alarms don't survive an app reinstall/data wipe and won't
    // otherwise exist the first time this app version runs.
    for (final event in loadedEvents) {
      NotificationService.instance.scheduleEventReminder(event);
    }

    // Set up the persistent notification and run an initial expiring-soon
    // check against whatever was already saved.
    _onTasksChanged();

    if (mounted) setState(() => _isLoading = false);
  }

  // Tracks event ids from the previous snapshot so deleted events have
  // their reminders cancelled, not just left scheduled forever.
  Set<String> _previousEventIds = {};

  void _onEventsChanged() {
    final current = _eventsNotifier.value;
    debugPrint('[Storage] Saving ${current.length} events');
    StorageHelper.saveEvents(current);

    final currentIds = current.map((e) => e.id).toSet();
    final removedIds = _previousEventIds.difference(currentIds);
    for (final id in removedIds) {
      NotificationService.instance.cancelEventReminder(id);
    }
    // Re-schedule everything still present — cheap no-op for unchanged
    // events (cancel+reschedule with the same data) and correctly picks up
    // edits to the time or the reminder setting itself.
    for (final event in current) {
      NotificationService.instance.scheduleEventReminder(event);
    }
    _previousEventIds = currentIds;
  }

  void _onTasksChanged() {
    debugPrint('[Storage] Saving ${_tasksNotifier.value.length} tasks');
    StorageHelper.saveTasks(_tasksNotifier.value);

    NotificationService.instance
        .refreshPersistentDailyTasksNotification(_tasksNotifier.value);

    NotificationService.instance
        .checkExpiringSoonTasks(_tasksNotifier.value)
        .then((notifiedIds) {
      if (notifiedIds.isEmpty) return;
      // Mark these tasks so the same alert doesn't fire again, then persist
      // that flag (without re-triggering this same listener in a loop).
      for (final task in _tasksNotifier.value) {
        if (notifiedIds.contains(task.id)) task.expiringSoonNotified = true;
      }
      StorageHelper.saveTasks(_tasksNotifier.value);
    });
  }

  @override
  void dispose() {
    _eventsNotifier.dispose();
    _tasksNotifier.dispose();
    _groupsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomePage(
      eventsNotifier: _eventsNotifier,
      tasksNotifier: _tasksNotifier,
      groupsNotifier: _groupsNotifier,
    );
  }
}

class HomePage extends StatefulWidget {
  final ValueNotifier<List<Event>> eventsNotifier;
  final ValueNotifier<List<Task>> tasksNotifier;
  final ValueNotifier<List<Group>> groupsNotifier;

  const HomePage({
    required this.eventsNotifier,
    required this.tasksNotifier,
    required this.groupsNotifier,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

// A simple saved filter: which groups to include and/or a date range.
// Either, both, or neither beyond groups can be set.
class _TaskCardView {
  List<String> groupIds;
  DateTime? fromDate;
  DateTime? toDate;

  _TaskCardView({List<String>? groupIds, this.fromDate, this.toDate})
      : groupIds = groupIds ?? [];

  Map<String, dynamic> toJson() => {
        'groupIds': groupIds,
        'fromDate': fromDate?.toIso8601String(),
        'toDate': toDate?.toIso8601String(),
      };

  factory _TaskCardView.fromJson(Map<String, dynamic> json) => _TaskCardView(
        groupIds: List<String>.from(json['groupIds'] ?? []),
        fromDate:
            json['fromDate'] != null ? DateTime.parse(json['fromDate']) : null,
        toDate: json['toDate'] != null ? DateTime.parse(json['toDate']) : null,
      );

  bool matches(Task t) {
    if (groupIds.isNotEmpty && !t.groupIds.any(groupIds.contains)) return false;
    if (fromDate != null) {
      final end = t.endDate ?? t.startDate;
      if (end == null || end.isBefore(fromDate!)) return false;
    }
    if (toDate != null) {
      final start = t.startDate ?? t.endDate;
      final toEnd =
          DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59);
      if (start == null || start.isAfter(toEnd)) return false;
    }
    return true;
  }
}

const _cardShape =
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)));
TextStyle _sectionLabel() => TextStyle(
    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700);

// Generic, encouraging phrases shown when there isn't enough history yet, or
// when the real stats available right now aren't flattering.
const _genericPrompts = [
  "What's the plan?",
  'Ready to get things done?',
  'Writing down your tasks makes you more likely to finish them.',
  'One step at a time.',
  "Let's make today count.",
  'A clear plan beats a full memory.',
  'Small tasks add up to big progress.',
];

// Builds the one-line welcome message under the greeting: a real, flattering
// stat about past usage when one is available, otherwise a generic prompt.
// Picked fresh on every call (the caller decides when that happens).
String _buildWelcomeMessage(List<Task> tasks, List<Event> events) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));
  final weekFromNow = todayStart.add(const Duration(days: 7));

  final candidates = <String>[];

  // Candidate: an event today or within the next week.
  final upcoming = events
      .where(
          (e) => e.startTime.isAfter(now) && e.startTime.isBefore(weekFromNow))
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (upcoming.isNotEmpty) {
    final next = upcoming.first;
    final isToday = !next.startTime.isBefore(todayStart) &&
        next.startTime.isBefore(todayEnd);
    final whenLabel =
        isToday ? 'today' : 'this ${DateFormat('EEEE').format(next.startTime)}';
    final title = next.title.isEmpty ? 'an event' : next.title;
    candidates.add("Don't forget you have $title $whenLabel.");
  }

  // Candidate: total completed task count — only worth bragging about above 0.
  final completedCount = tasks.where((t) => t.isCompleted).length;
  if (completedCount > 0) {
    candidates.add(completedCount == 1
        ? "You've completed 1 task already."
        : "You've completed $completedCount tasks already.");
  }

  // Candidate: on-time completion rate — only shown when it's actually a good
  // look (a flattering percentage, with enough of a sample to mean something).
  final completedWithDueDate = tasks
      .where(
          (t) => t.isCompleted && t.endDate != null && t.completedDate != null)
      .toList();
  if (completedWithDueDate.length >= 3) {
    final onTime = completedWithDueDate
        .where((t) => !t.completedDate!.isAfter(t.endDate!))
        .length;
    final pct = (onTime / completedWithDueDate.length * 100).round();
    if (pct >= 50) {
      candidates.add('$pct% of your tasks are done on time.');
    }
  }

  if (candidates.isEmpty) {
    return _genericPrompts[Random().nextInt(_genericPrompts.length)];
  }
  return candidates[Random().nextInt(candidates.length)];
}

// One day's worth of activity for the heatmap: how many tasks were completed
// that day, and how many events started that day.
class _DayActivity {
  final DateTime day;
  final int tasksCompleted;
  final int eventsHeld;
  _DayActivity(this.day, this.tasksCompleted, this.eventsHeld);
  int get total => tasksCompleted + eventsHeld;
}

// Builds the last 30 days (oldest first, today last) with their activity
// counts, for the GitHub-style heatmap card.
List<_DayActivity> _buildActivityHistory(List<Task> tasks, List<Event> events) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);

  return List.generate(30, (i) {
    final day = todayStart.subtract(Duration(days: 29 - i));
    final dayEnd = day.add(const Duration(days: 1));

    final tasksCompleted = tasks.where((t) {
      final cd = t.completedDate;
      return cd != null && !cd.isBefore(day) && cd.isBefore(dayEnd);
    }).length;

    final eventsHeld = events
        .where(
            (e) => !e.startTime.isBefore(day) && e.startTime.isBefore(dayEnd))
        .length;

    return _DayActivity(day, tasksCompleted, eventsHeld);
  });
}

// Maps an activity count to one of 5 intensity buckets (0 = none, 4 = most
// active), the same way GitHub's contribution graph buckets commit counts
// rather than using a literal continuous gradient.
int _heatmapBucket(int count, int maxCount) {
  if (count == 0 || maxCount == 0) return 0;
  final ratio = count / maxCount;
  if (ratio <= 0.25) return 1;
  if (ratio <= 0.5) return 2;
  if (ratio <= 0.75) return 3;
  return 4;
}

// Uses the app's own theme color (Colors.blue) instead of an unrelated
// palette, scaling from a light tint (barely active) to the full theme
// blue (most active that day).
Color _heatmapColor(int bucket) {
  final colors = [
    Color(0xFFEBEDF0), // none
    Colors.blue.shade100,
    Colors.blue.shade300,
    Colors.blue.shade500,
    Colors.blue.shade700,
  ];
  return colors[bucket];
}

class _HomePageState extends State<HomePage> {
  final List<_TaskCardView> _customViews = [];
  final _taskPageController = PageController();
  int _currentTaskPage = 0;

  // Which cards appear in the body, and in what order. Defaults to the
  // original order; loaded from storage if the user has rearranged before.
  List<String> _cardOrder = ['heatmap', 'day', 'tasks'];
  bool _editingLayout = false;

  @override
  void initState() {
    super.initState();
    _loadCustomViews();
    _loadCardOrder();
  }

  Future<void> _loadCardOrder() async {
    final saved = await StorageHelper.loadHomeCardOrder();
    if (!mounted || saved == null) return;
    // Guard against a stale saved order (e.g. from an older app version)
    // missing a card id or containing an unknown one — fall back to default
    // rather than silently dropping a card from the screen.
    final isValid = saved.length == _cardOrder.length &&
        saved.toSet().containsAll(_cardOrder);
    if (!isValid) return;
    setState(() => _cardOrder = saved);
  }

  void _saveCardOrder() {
    StorageHelper.saveHomeCardOrder(_cardOrder);
  }

  Future<void> _loadCustomViews() async {
    final saved = await StorageHelper.loadTaskViews();
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _customViews.addAll(saved.map(_TaskCardView.fromJson));
    });
  }

  void _saveCustomViews() {
    StorageHelper.saveTaskViews(_customViews.map((v) => v.toJson()).toList());
  }

  @override
  void dispose() {
    _taskPageController.dispose();
    super.dispose();
  }

  void _openTasksPage() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TasksPage(
            tasksNotifier: widget.tasksNotifier,
            groupsNotifier: widget.groupsNotifier,
          ),
        ),
      ).then((_) => setState(() {}));

  Future<void> _openAddViewSheet() async {
    final groups = widget.groupsNotifier.value;
    final selectedGroupIds = <String>{};
    DateTime? fromDate, toDate;
    final fmt = DateFormat('MMM d, yyyy');

    Future<void> pickDate(StateSetter setSheetState, bool isFrom) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: (isFrom ? fromDate : toDate) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) {
        setSheetState(() => isFrom ? fromDate = picked : toDate = picked);
      }
    }

    final result = await showModalBottomSheet<_TaskCardView>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text('New Task View',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text(
                    'Pick categories and/or a date range. You can use just one, or both.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  SizedBox(height: 16),
                  Text('Categories', style: _sectionLabel()),
                  SizedBox(height: 6),
                  if (groups.isEmpty)
                    Text('No categories yet.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: groups.map((g) {
                        final selected = selectedGroupIds.contains(g.id);
                        return GestureDetector(
                          onTap: () => setSheetState(
                            () => selected
                                ? selectedGroupIds.remove(g.id)
                                : selectedGroupIds.add(g.id),
                          ),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? g.color.withAlpha((0.18 * 255).round())
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    selected ? g.color : Colors.grey.shade300,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: g.color, shape: BoxShape.circle),
                              ),
                              SizedBox(width: 6),
                              Text(g.name,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  SizedBox(height: 18),
                  Text('Date range', style: _sectionLabel()),
                  SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickDate(setSheetState, true),
                        child: Text(
                            fromDate == null ? 'From' : fmt.format(fromDate!)),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickDate(setSheetState, false),
                        child:
                            Text(toDate == null ? 'To' : fmt.format(toDate!)),
                      ),
                    ),
                    if (fromDate != null || toDate != null)
                      IconButton(
                        icon: Icon(Icons.clear, size: 18),
                        tooltip: 'Clear dates',
                        onPressed: () => setSheetState(() {
                          fromDate = null;
                          toDate = null;
                        }),
                      ),
                  ]),
                  SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text('Cancel'),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (selectedGroupIds.isEmpty &&
                                fromDate == null &&
                                toDate == null)
                            ? null
                            : () => Navigator.pop(
                                  sheetCtx,
                                  _TaskCardView(
                                    groupIds: selectedGroupIds.toList(),
                                    fromDate: fromDate,
                                    toDate: toDate,
                                  ),
                                ),
                        child: Text('Save View'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != null) {
      setState(() => _customViews.add(result));
      _saveCustomViews();
    }
  }

  String _viewLabel(_TaskCardView view) {
    final groups = widget.groupsNotifier.value;
    final fmt = DateFormat('MMM d');
    final parts = <String>[];

    if (view.groupIds.isNotEmpty) {
      final names = view.groupIds
          .map((id) => groups
              .firstWhere((g) => g.id == id,
                  orElse: () => Group(id: '', name: '', color: Colors.grey))
              .name)
          .where((n) => n.isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) parts.add(names);
    }
    if (view.fromDate != null || view.toDate != null) {
      final from = view.fromDate != null ? fmt.format(view.fromDate!) : '…';
      final to = view.toDate != null ? fmt.format(view.toDate!) : '…';
      parts.add('$from - $to');
    }
    return parts.isEmpty ? 'Custom view' : parts.join(' • ');
  }

  Widget _taskRow(Task task, DateTime now, DateTime todayStart) {
    final subInfo = task.subtasks.isNotEmpty
        ? ' (${task.subtasks.where((s) => s.isCompleted).length}/${task.subtasks.length})'
        : '';
    final isOverdue = task.endDate != null &&
        task.endDate!.isBefore(todayStart) &&
        !task.isCompleted;
    final isNotStarted = task.startDate != null &&
        task.startDate!.isAfter(now) &&
        !task.isCompleted;

    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isOverdue ? Colors.red.shade700 : task.color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '${task.name}$subInfo',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
              color: task.isCompleted
                  ? Colors.grey.shade400
                  : (isOverdue ? Colors.red.shade800 : Colors.black87),
              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isOverdue) ...[
          SizedBox(width: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(4)),
            child: Text('⚠️ OVERDUE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ]),
    );

    return isNotStarted ? Opacity(opacity: 0.45, child: row) : row;
  }

  Widget _taskCardBody(
      String title, List<Task> tasks, DateTime now, DateTime todayStart) {
    final total = tasks.length;
    final done = tasks.where((t) => t.isCompleted).length;
    final progress = total == 0 ? 0.0 : done / total;

    return Row(children: [
      Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 90,
          height: 90,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 7,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(
                total == 0 ? Colors.grey.shade400 : Colors.blue),
          ),
        ),
        Text(total == 0 ? '0%' : '${(progress * 100).round()}%',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: total == 0 ? Colors.grey.shade500 : Colors.blue)),
      ]),
      SizedBox(width: 28),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Divider(height: 12, thickness: 1),
            if (total == 0)
              Text('No tasks here yet.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
            else
              ...tasks.take(4).map((t) => _taskRow(t, now, todayStart)),
          ],
        ),
      ),
    ]);
  }

  // Shared shell for every page in the task PageView: a tappable card,
  // with an optional close button overlaid (used by custom views only).
  Widget _pageCard({
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onClose,
    bool highlighted = false,
  }) {
    final shape = highlighted
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.blue.shade100),
          )
        : _cardShape;

    final cardContent = onClose == null
        ? Padding(padding: const EdgeInsets.all(24.0), child: child)
        : Stack(children: [
            Padding(padding: const EdgeInsets.all(24.0), child: child),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onClose();
                },
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  child:
                      Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                ),
              ),
            ),
          ]);

    final card = Card(
      elevation: 2,
      color: highlighted ? Colors.blue.shade50 : null,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? cardContent
          : InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: cardContent,
            ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: card,
    );
  }

  Widget _buildActivityHeatmapCard() {
    return ValueListenableBuilder<List<Task>>(
      valueListenable: widget.tasksNotifier,
      builder: (context, tasks, _) {
        return ValueListenableBuilder<List<Event>>(
          valueListenable: widget.eventsNotifier,
          builder: (context, events, __) {
            final history = _buildActivityHistory(tasks, events);
            final maxCount =
                history.fold<int>(0, (m, d) => d.total > m ? d.total : m);

            const columns = 10;
            final rows = List.generate(
                3, (r) => history.sublist(r * columns, r * columns + columns));

            return _activityHeatmapCardBody(history, maxCount, rows);
          },
        );
      },
    );
  }

  Widget _activityHeatmapCardBody(
      List<_DayActivity> history, int maxCount, List<List<_DayActivity>> rows) {
    return Card(
      elevation: 2,
      shape: _cardShape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          _showActivityHeatmapDialog(history, maxCount);
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Last 30 days',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 10),
                    ...rows.map((week) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: week
                                .map((d) => Padding(
                                      padding: const EdgeInsets.only(right: 3),
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: _heatmapColor(_heatmapBucket(
                                              d.total, maxCount)),
                                          borderRadius:
                                              BorderRadius.circular(2.5),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        )),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _showActivityHeatmapDialog(List<_DayActivity> history, int maxCount) {
    showDialog(
      context: context,
      builder: (ctx) {
        _DayActivity? selected = history.last;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activity',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Last 30 days — tap a day for details',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    SizedBox(height: 16),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: history.map((d) {
                        final isSelected = selected?.day == d.day;
                        return GestureDetector(
                          onTap: () => setDialogState(() => selected = d),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _heatmapColor(
                                  _heatmapBucket(d.total, maxCount)),
                              borderRadius: BorderRadius.circular(4),
                              border: isSelected
                                  ? Border.all(
                                      color: Colors.blueAccent, width: 2)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 18),
                    if (selected != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('EEEE, MMMM d').format(selected!.day),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 6),
                            Text(
                              selected!.total == 0
                                  ? 'Nothing done this day.'
                                  : '${selected!.tasksCompleted} task${selected!.tasksCompleted == 1 ? '' : 's'} completed · ${selected!.eventsHeld} event${selected!.eventsHeld == 1 ? '' : 's'}',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDayCard(DateTime now) {
    return Card(
      elevation: 2,
      shape: _cardShape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DailyView(
                currentDate: now,
                eventsNotifier: widget.eventsNotifier,
                tasksNotifier: widget.tasksNotifier,
                groupsNotifier: widget.groupsNotifier,
              ),
            ),
          ).then((_) => setState(() {}));
        },
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(DateFormat('EEEE').format(now),
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue)),
            SizedBox(height: 8),
            Text(DateFormat('MMMM d, yyyy').format(now),
                style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
            SizedBox(height: 8),
            Text("Tap to open today's schedule",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ]),
        ),
      ),
    );
  }

  Widget _buildTasksCard(DateTime now, DateTime todayStart, int pageCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 230,
          child: ValueListenableBuilder<List<Task>>(
            valueListenable: widget.tasksNotifier,
            builder: (context, currentTasks, _) {
              final visibleTasks = currentTasks
                  .where((t) =>
                      isItemVisible(t.groupIds, widget.groupsNotifier.value))
                  .toList();

              return PageView.builder(
                controller: _taskPageController,
                onPageChanged: (i) => setState(() => _currentTaskPage = i),
                itemCount: pageCount,
                itemBuilder: (context, pageIndex) {
                  if (pageIndex == pageCount - 1) {
                    return _pageCard(
                      onTap: _openAddViewSheet,
                      highlighted: true,
                      child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_circle_outline,
                              size: 28, color: Colors.blue),
                          SizedBox(height: 8),
                          Text('+ add new view',
                              style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ]),
                      ),
                    );
                  }

                  if (pageIndex == 0) {
                    return _pageCard(
                      onTap: _openTasksPage,
                      child: _taskCardBody(
                          'My Tasks', visibleTasks, now, todayStart),
                    );
                  }

                  final view = _customViews[pageIndex - 1];
                  return _pageCard(
                    onTap: _openTasksPage,
                    onClose: () {
                      setState(() => _customViews.removeAt(pageIndex - 1));
                      _saveCustomViews();
                    },
                    child: _taskCardBody(
                      _viewLabel(view),
                      visibleTasks.where(view.matches).toList(),
                      now,
                      todayStart,
                    ),
                  );
                },
              );
            },
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageCount, (i) {
            final active = i == _currentTaskPage;
            return Container(
              margin: EdgeInsets.symmetric(horizontal: 3),
              width: active ? 8 : 6,
              height: active ? 8 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Colors.blue : Colors.grey.shade300,
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // Pages: [0] = all tasks, [1..n] = saved custom views, [last] = add-new
    final pageCount = _customViews.length + 2;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Planner'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_editingLayout ? Icons.check : Icons.swap_vert),
            tooltip: _editingLayout ? 'Done arranging' : 'Rearrange cards',
            onPressed: () => setState(() => _editingLayout = !_editingLayout),
          ),
          IconButton(
            icon: Icon(Icons.add_circle_outline),
            tooltip: 'Create category',
            onPressed: () => showInlineGroupCreator(
                context, widget.groupsNotifier, (_) => setState(() {})),
          ),
          IconButton(
            icon: Icon(Icons.filter_list_rounded),
            tooltip: 'Filter categories',
            onPressed: () => showGroupFilterSheet(
                context, widget.groupsNotifier, () => setState(() {})),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome back!',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
                height: 1.1,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _buildWelcomeMessage(
                  widget.tasksNotifier.value, widget.eventsNotifier.value),
              style: TextStyle(
                fontSize: 17,
                color: Colors.grey.shade700,
                height: 1.3,
              ),
            ),
            if (_editingLayout) ...[
              SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.blue.shade700),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Drag cards to reorder them.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 14),
            Expanded(
              child: _editingLayout
                  ? ReorderableListView(
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        setState(() {
                          final id = _cardOrder.removeAt(oldIndex);
                          _cardOrder.insert(newIndex, id);
                        });
                        _saveCardOrder();
                        HapticFeedback.mediumImpact();
                      },
                      children: _cardOrder
                          .map((id) => Padding(
                                key: ValueKey(id),
                                padding: const EdgeInsets.only(bottom: 14),
                                child: ReorderableDragStartListener(
                                  index: _cardOrder.indexOf(id),
                                  child: AbsorbPointer(
                                    child: _buildCardById(
                                        id, now, todayStart, pageCount),
                                  ),
                                ),
                              ))
                          .toList(),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _cardOrder
                          .map((id) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _buildCardById(
                                    id, now, todayStart, pageCount),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CalendarPage(
              eventsNotifier: widget.eventsNotifier,
              tasksNotifier: widget.tasksNotifier,
              groupsNotifier: widget.groupsNotifier,
            ),
          ),
        ).then((_) => setState(() {})),
        tooltip: 'Open Calendar',
        child: Icon(Icons.calendar_today),
      ),
    );
  }

  Widget _buildCardById(
      String id, DateTime now, DateTime todayStart, int pageCount) {
    switch (id) {
      case 'heatmap':
        return _buildActivityHeatmapCard();
      case 'day':
        return _buildDayCard(now);
      case 'tasks':
        return _buildTasksCard(now, todayStart, pageCount);
      default:
        return const SizedBox.shrink();
    }
  }
}
