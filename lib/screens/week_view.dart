import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/task.dart';
import '../models/group.dart';
import '../helpers/general_helpers.dart';
import '../widgets/group_sheets.dart';
import 'daily_view.dart';
import 'calendar_page.dart';

class WeekView extends StatefulWidget {
  final DateTime initialDate;
  final ValueNotifier<List<Event>> eventsNotifier;
  final ValueNotifier<List<Task>> tasksNotifier;
  final ValueNotifier<List<Group>> groupsNotifier;

  const WeekView({
    super.key,
    required this.initialDate,
    required this.eventsNotifier,
    required this.tasksNotifier,
    required this.groupsNotifier,
  });

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  late DateTime _weekStart;
  bool _navigating = false;

  // --- Pinch-to-zoom -------------------------------------------------------
  // Two independent pinch gestures, tracked with raw pointer events so they
  // never compete with the existing long-press-drag zoom or with each other:
  //  - Pinch-in anywhere on the screen zooms out to Month.
  //  - Pinch-out over a specific day row zooms into that Day.
  final Map<int, Offset> _weekPinchPointers = {};
  double? _weekPinchStartDistance;
  bool _weekPinchTriggered = false;

  final Map<int, Offset> _dayPinchPointers = {};
  double? _dayPinchStartDistance;
  bool _dayPinchTriggered = false;

  double _pinchDistance(Map<int, Offset> pointers) {
    final pts = pointers.values.toList();
    return (pts[0] - pts[1]).distance.clamp(1.0, double.infinity);
  }

  void _onWeekPinchDown(PointerDownEvent event) {
    _weekPinchPointers[event.pointer] = event.localPosition;
    if (_weekPinchPointers.length == 2) {
      _weekPinchStartDistance = _pinchDistance(_weekPinchPointers);
      _weekPinchTriggered = false;
      HapticFeedback.selectionClick();
    }
  }

  void _onWeekPinchMove(PointerMoveEvent event) {
    if (!_weekPinchPointers.containsKey(event.pointer)) return;
    _weekPinchPointers[event.pointer] = event.localPosition;
    if (_weekPinchPointers.length != 2 ||
        _weekPinchStartDistance == null ||
        _weekPinchTriggered) {
      return;
    }
    final ratio = _pinchDistance(_weekPinchPointers) / _weekPinchStartDistance!;
    if (ratio < 0.7) {
      _weekPinchTriggered = true;
      _zoomToMonth();
    }
  }

  void _onWeekPinchEnd(PointerEvent event) {
    _weekPinchPointers.remove(event.pointer);
    if (_weekPinchPointers.length < 2) {
      _weekPinchStartDistance = null;
      _weekPinchTriggered = false;
    }
  }

  void _onDayCellPinchDown(PointerDownEvent event) {
    _dayPinchPointers[event.pointer] = event.localPosition;
    if (_dayPinchPointers.length == 2) {
      _dayPinchStartDistance = _pinchDistance(_dayPinchPointers);
      _dayPinchTriggered = false;
      HapticFeedback.selectionClick();
    }
  }

  void _onDayCellPinchMove(PointerMoveEvent event, DateTime day) {
    if (!_dayPinchPointers.containsKey(event.pointer)) return;
    _dayPinchPointers[event.pointer] = event.localPosition;
    if (_dayPinchPointers.length != 2 ||
        _dayPinchStartDistance == null ||
        _dayPinchTriggered) {
      return;
    }
    final ratio = _pinchDistance(_dayPinchPointers) / _dayPinchStartDistance!;
    if (ratio > 1.35) {
      _dayPinchTriggered = true;
      _zoomToDay(day);
    }
  }

  void _onDayCellPinchEnd(PointerEvent event) {
    _dayPinchPointers.remove(event.pointer);
    if (_dayPinchPointers.length < 2) {
      _dayPinchStartDistance = null;
      _dayPinchTriggered = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Weeks start on Sunday, matching the month grid's week labels elsewhere
    // in the app (Sun, Mon, Tue, ...).
    final d = widget.initialDate;
    final startOfDay = DateTime(d.year, d.month, d.day);
    _weekStart = startOfDay.subtract(Duration(days: startOfDay.weekday % 7));
  }

  void _shiftWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
    });
  }

  List<Event> _eventsForDay(DateTime day, List<Event> events) {
    final dayEnd = day.add(const Duration(days: 1));
    return events.where((e) => e.startTime.isBefore(dayEnd) && e.endTime.isAfter(day)).toList();
  }

  List<Task> _tasksForDay(DateTime day, List<Task> tasks) {
    final dayEnd = day.add(const Duration(days: 1));
    return tasks.where((t) {
      if (t.isCompleted) {
        return t.completedDate != null && !t.completedDate!.isBefore(day) && t.completedDate!.isBefore(dayEnd);
      }
      final due = t.endDate ?? t.startDate;
      return due != null && !due.isBefore(day) && due.isBefore(dayEnd);
    }).toList();
  }

  void _openDay(DateTime day) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyView(
          currentDate: day,
          eventsNotifier: widget.eventsNotifier,
          tasksNotifier: widget.tasksNotifier,
          groupsNotifier: widget.groupsNotifier,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _zoomToMonth() {
    if (_navigating) return;
    _navigating = true;
    HapticFeedback.mediumImpact();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarPage(
          eventsNotifier: widget.eventsNotifier,
          tasksNotifier: widget.tasksNotifier,
          groupsNotifier: widget.groupsNotifier,
        ),
      ),
    );
  }

  void _zoomToDay(DateTime day) {
    if (_navigating) return;
    _navigating = true;
    HapticFeedback.mediumImpact();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DailyView(
          currentDate: day,
          eventsNotifier: widget.eventsNotifier,
          tasksNotifier: widget.tasksNotifier,
          groupsNotifier: widget.groupsNotifier,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekLabel =
        '${DateFormat('MMM d').format(days.first)} - ${DateFormat('MMM d, yyyy').format(days.last)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Week'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_month),
            tooltip: 'Month view',
            onPressed: _zoomToMonth,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter categories',
            onPressed: () => showGroupFilterSheet(context, widget.groupsNotifier, () => setState(() {})),
          ),
        ],
      ),
      body: Listener(
        // Two-finger pinch-in anywhere zooms out to Month (see handlers
        // above). Pinch-out to zoom into a specific Day is handled per-cell
        // below.
        onPointerDown: _onWeekPinchDown,
        onPointerMove: _onWeekPinchMove,
        onPointerUp: _onWeekPinchEnd,
        onPointerCancel: _onWeekPinchEnd,
        child: GestureDetector(
        // Long-press-drag zoom, the same gesture used in Daily View: drag
        // up/left a real distance anywhere on the screen to zoom out to
        // Month. Zooming into a specific Day is handled per-cell below.
        onLongPressStart: (_) => HapticFeedback.selectionClick(),
        onLongPressMoveUpdate: (details) {
          if (details.offsetFromOrigin.dy < -60 || details.offsetFromOrigin.dx < -60) {
            _zoomToMonth();
          }
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shiftWeek(-1),
                  ),
                  Text(weekLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shiftWeek(1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<Event>>(
                valueListenable: widget.eventsNotifier,
                builder: (context, allEvents, _) {
                  return ValueListenableBuilder<List<Task>>(
                    valueListenable: widget.tasksNotifier,
                    builder: (context, allTasks, __) {
                      final visibleEvents = allEvents
                          .where((e) => isItemVisible(e.groupIds, widget.groupsNotifier.value))
                          .toList();
                      final visibleTasks = allTasks
                          .where((t) => isItemVisible(t.groupIds, widget.groupsNotifier.value))
                          .toList();

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          children: days.map((day) {
                            final isToday = day == todayStart;
                            final dayEvents = _eventsForDay(day, visibleEvents)
                              ..sort((a, b) => a.startTime.compareTo(b.startTime));
                            final dayTasks = _tasksForDay(day, visibleTasks);

                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _openDay(day),
                                onLongPressStart: (_) => HapticFeedback.selectionClick(),
                                onLongPressMoveUpdate: (details) {
                                  if (details.offsetFromOrigin.dy > 60 ||
                                      details.offsetFromOrigin.dx > 60) {
                                    _zoomToDay(day);
                                  }
                                },
                                child: Listener(
                                  onPointerDown: _onDayCellPinchDown,
                                  onPointerMove: (details) =>
                                      _onDayCellPinchMove(details, day),
                                  onPointerUp: _onDayCellPinchEnd,
                                  onPointerCancel: _onDayCellPinchEnd,
                                  child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 3),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isToday ? Colors.blue.withAlpha(20) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isToday ? Colors.blue : Colors.grey.shade200,
                                      width: isToday ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 52,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              DateFormat('EEE').format(day),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isToday ? Colors.blue.shade700 : Colors.grey.shade500,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              '${day.day}',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                                color: isToday ? Colors.blue : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: (dayEvents.isEmpty && dayTasks.isEmpty)
                                            ? Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  'Nothing scheduled',
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                                ),
                                              )
                                            : SingleChildScrollView(
                                                child: Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    ...dayEvents.take(4).map((e) => _previewChip(e.title, e.color)),
                                                    ...dayTasks.take(4).map(
                                                          (t) => _previewChip(
                                                            t.name,
                                                            t.color,
                                                            struckThrough: t.isCompleted,
                                                          ),
                                                        ),
                                                    if (dayEvents.length + dayTasks.length > 8)
                                                      Text(
                                                        '+${dayEvents.length + dayTasks.length - 8} more',
                                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _previewChip(String label, Color color, {bool struckThrough = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Colors.black87,
          decoration: struckThrough ? TextDecoration.lineThrough : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}