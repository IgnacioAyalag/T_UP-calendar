import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/task.dart';
import '../models/group.dart';
import '../helpers/general_helpers.dart';
import '../widgets/group_sheets.dart';
import '../widgets/pulsating_effects.dart';
import 'daily_view.dart';
import 'tasks_page.dart';

class CalendarPage extends StatefulWidget {
  final ValueNotifier<List<Event>> eventsNotifier;
  final ValueNotifier<List<Task>> tasksNotifier;
  final ValueNotifier<List<Group>> groupsNotifier;

  const CalendarPage({
    super.key,
    required this.eventsNotifier,
    required this.tasksNotifier,
    required this.groupsNotifier,
  });

  @override
  CalendarPageState createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage> {
  late DateTime _focusedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
  }

  List<DateTime> _generateDaysInMonth(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final int weekdayOffset = firstDayOfMonth.weekday % 7;
    final List<DateTime> days = [];

    for (int i = weekdayOffset; i > 0; i--) {
      days.add(firstDayOfMonth.subtract(Duration(days: i)));
    }

    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);
    for (int i = 0; i < lastDayOfMonth.day; i++) {
      days.add(firstDayOfMonth.add(Duration(days: i)));
    }

    while (days.length % 7 != 0) {
      days.add(days.last.add(const Duration(days: 1)));
    }
    return days;
  }

  List<Event> _getEventsForDay(DateTime day, List<Event> globalEvents) {
    return globalEvents.where((e) {
      return e.startTime.year == day.year &&
          e.startTime.month == day.month &&
          e.startTime.day == day.day;
    }).toList();
  }

  // Helper method to present creation options from the calendar view
  void _showAddDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.event, color: Colors.blue),
              title: const Text('Add Event'),
              onTap: () {
                Navigator.pop(ctx);
                // Opens the same full event editor used everywhere else in
                // the app (groups, repeat, color, sub-events) instead of a
                // separate, simpler dialog.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyView(
                      currentDate: DateTime.now(),
                      eventsNotifier: widget.eventsNotifier,
                      tasksNotifier: widget.tasksNotifier,
                      groupsNotifier: widget.groupsNotifier,
                      openEventEditorOnLaunch: true,
                    ),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
            ListTile(
              leading: const Icon(Icons.task_alt, color: Colors.green),
              title: const Text('Add Task'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TasksPage(
                      tasksNotifier: widget.tasksNotifier,
                      groupsNotifier: widget.groupsNotifier,
                      openEditorOnLaunch: true,
                    ),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = _generateDaysInMonth(_focusedMonth);
    final monthLabel = DateFormat('MMMM yyyy').format(_focusedMonth);
    final weekLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter categories',
            onPressed: () => showGroupFilterSheet(
              context,
              widget.groupsNotifier,
              () => setState(() {}),
            ),
          ),
        ],
      ),
      // Added missing FloatingActionButton to enable creation flows
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Add Event/Task',
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month - 1,
                        1,
                      );
                    });
                  },
                ),
                Text(
                  monthLabel,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month + 1,
                        1,
                      );
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: weekLabels.map((label) {
                return Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ValueListenableBuilder<List<Event>>(
                valueListenable: widget.eventsNotifier,
                builder: (context, globalEvents, _) {
                  return ValueListenableBuilder<List<Task>>(
                    valueListenable: widget.tasksNotifier,
                    builder: (context, currentTasks, _) {
                      final visibleEvents = globalEvents
                          .where((e) => isItemVisible(
                              e.groupIds, widget.groupsNotifier.value))
                          .toList();
                      final visibleTasks = currentTasks
                          .where((t) => isItemVisible(
                              t.groupIds, widget.groupsNotifier.value))
                          .toList();

                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: days.length,
                        itemBuilder: (context, index) {
                          final day = days[index];
                          final isCurrentMonth =
                              day.month == _focusedMonth.month;
                          final dayEvents =
                              _getEventsForDay(day, visibleEvents);
                          final isToday = day.year == now.year &&
                              day.month == now.month &&
                              day.day == now.day;
                          final dayTasks = visibleTasks.where((task) {
                            if (task.isCompleted) {
                              if (task.completedDate == null) return false;
                              return task.completedDate!.year == day.year &&
                                  task.completedDate!.month == day.month &&
                                  task.completedDate!.day == day.day;
                            } else {
                              final targetDate = task.endDate ?? task.startDate;
                              if (targetDate == null) return false;
                              return targetDate.year == day.year &&
                                  targetDate.month == day.month &&
                                  targetDate.day == day.day;
                            }
                          }).toList();

                          return GestureDetector(
                            onTap: () {
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
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isToday
                                    ? Colors.blue.withAlpha(30)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isToday
                                      ? Colors.blue
                                      : Colors.grey.shade200,
                                  width: isToday ? 1.5 : 1,
                                ),
                                boxShadow: [
                                  if (isCurrentMonth)
                                    BoxShadow(
                                      color: Colors.black.withAlpha(10),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isToday
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isCurrentMonth
                                          ? Colors.black87
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      child: Wrap(
                                        spacing: 3,
                                        runSpacing: 3,
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          ...dayEvents.take(3).map(
                                                (e) => Container(
                                                  width: 5,
                                                  height: 5,
                                                  decoration: BoxDecoration(
                                                    color: e.color,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                          ...dayTasks.take(4).map((task) {
                                            final bool isOverdue =
                                                task.endDate != null &&
                                                    task.endDate!
                                                        .isBefore(todayStart) &&
                                                    !task.isCompleted;
                                            final bool isNotStarted =
                                                task.startDate != null &&
                                                    task.startDate!
                                                        .isAfter(now) &&
                                                    !task.isCompleted;

                                            if (task.isCompleted) {
                                              return Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  color: task.color,
                                                  borderRadius:
                                                      BorderRadius.circular(1),
                                                ),
                                              );
                                            } else if (isOverdue) {
                                              return const PulsatingCalendarIcon(
                                                size: 13.0,
                                              );
                                            } else if (isNotStarted) {
                                              return Icon(
                                                Icons.hourglass_empty_rounded,
                                                size: 9.5,
                                                color: Color.alphaBlend(
                                                  Colors.white.withAlpha(150),
                                                  task.color,
                                                ),
                                              );
                                            } else {
                                              return Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: task.color,
                                                    width: 1.2,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(1),
                                                ),
                                              );
                                            }
                                          }),
                                        ],
                                      ),
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
