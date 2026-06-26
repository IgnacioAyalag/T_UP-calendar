import 'package:flutter/material.dart';
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

class _HomePageState extends State<HomePage> {
  final List<_TaskCardView> _customViews = [];
  final _taskPageController = PageController();
  int _currentTaskPage = 0;

  @override
  void initState() {
    super.initState();
    _loadCustomViews();
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
    final card = Card(
      elevation: 2,
      color: highlighted ? Colors.blue.shade50 : null,
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.blue.shade100),
            )
          : _cardShape,
      child: onClose == null
          ? Padding(padding: const EdgeInsets.all(24.0), child: child)
          : Stack(children: [
              Padding(padding: const EdgeInsets.all(24.0), child: child),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Icon(Icons.close,
                        size: 16, color: Colors.grey.shade400),
                  ),
                ),
              ),
            ]),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: onTap == null ? card : GestureDetector(onTap: onTap, child: card),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DailyView(
                    currentDate: now,
                    eventsNotifier: widget.eventsNotifier,
                    tasksNotifier: widget.tasksNotifier,
                    groupsNotifier: widget.groupsNotifier,
                  ),
                ),
              ).then((_) => setState(() {})),
              child: Card(
                elevation: 2,
                shape: _cardShape,
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
                        style: TextStyle(
                            fontSize: 18, color: Colors.grey.shade600)),
                    SizedBox(height: 8),
                    Text("Tap to open today's schedule",
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400)),
                  ]),
                ),
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              height: 230,
              child: ValueListenableBuilder<List<Task>>(
                valueListenable: widget.tasksNotifier,
                builder: (context, currentTasks, _) {
                  final visibleTasks = currentTasks
                      .where((t) => isItemVisible(
                          t.groupIds, widget.groupsNotifier.value))
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
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
}
