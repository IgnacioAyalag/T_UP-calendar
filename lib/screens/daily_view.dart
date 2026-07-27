import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/task.dart';
import '../models/group.dart';
import '../models/repeat_config.dart';
import '../helpers/general_helpers.dart';
import '../helpers/repeat_helpers.dart';
import '../widgets/repeat_config_sheet.dart';
import '../widgets/group_assignment_section.dart';
import '../widgets/group_sheets.dart';
import '../widgets/color_picker.dart';
import '../widgets/pulsating_effects.dart';
import '../widgets/hour_grid_painter.dart';
import 'week_view.dart';

// --- DAILY VIEW ---

// Groups overlapping items into side-by-side "columns" so simultaneous
// events/sub-events render next to each other instead of stacking.
// Returns (columnIndexOf, columnCountOf) keyed by item identity.
(Map<T, int>, Map<T, int>) _assignOverlapColumns<T>(
  List<T> items,
  DateTime Function(T) startOf,
  DateTime Function(T) endOf,
) {
  bool overlaps(T a, T b) =>
      startOf(a).isBefore(endOf(b)) && endOf(a).isAfter(startOf(b));

  // Step 1: group all mutually-overlapping items into clusters.
  final List<List<T>> clusters = [];
  for (final item in items) {
    final intersecting =
        clusters.where((c) => c.any((other) => overlaps(item, other))).toList();
    if (intersecting.isEmpty) {
      clusters.add([item]);
    } else {
      final joint = <T>[];
      for (final c in intersecting) {
        joint.addAll(c);
        clusters.remove(c);
      }
      joint.add(item);
      clusters.add(joint);
    }
  }

  // Step 2: within each cluster, greedily assign each item to the first
  // column where it doesn't collide with anything already placed there.
  final columnOf = <T, int>{};
  final columnCountOf = <T, int>{};
  for (final cluster in clusters) {
    final List<List<T>> tracks = [];
    for (final item in cluster) {
      int trackIdx = 0;
      while (trackIdx < tracks.length &&
          tracks[trackIdx].any((o) => overlaps(item, o))) {
        trackIdx++;
      }
      if (trackIdx == tracks.length) {
        tracks.add([item]);
      } else {
        tracks[trackIdx].add(item);
      }
      columnOf[item] = trackIdx;
    }
    for (final item in cluster) {
      columnCountOf[item] = tracks.length;
    }
  }
  return (columnOf, columnCountOf);
}

class DailyView extends StatefulWidget {
  final DateTime currentDate;
  final ValueNotifier<List<Event>> eventsNotifier;
  final ValueNotifier<List<Task>> tasksNotifier;
  final ValueNotifier<List<Group>> groupsNotifier;
  final bool openEventEditorOnLaunch;

  const DailyView({
    required this.currentDate,
    required this.eventsNotifier,
    required this.tasksNotifier,
    required this.groupsNotifier,
    this.openEventEditorOnLaunch = false,
  });

  @override
  _DailyViewState createState() => _DailyViewState();
}

class _DailyViewState extends State<DailyView> {
  late DateTime _visibleDate;
  late DateTime _timelineBaseDate;
  late ScrollController _scrollController;
  late PageController _horizontalPageController;
  int _activeHorizontalTab = 0;
  double _horizontalDragRemainder = 0.0;
  double _hourHeight = 85.0;
  static const double _minHourHeight = 18.0;
  static const double _maxHourHeight = 320.0;
  double? _scaleGestureStartHourHeight;
  double? _scaleGestureStartScrollOffset;
  double? _scaleGestureFocalDy;
  bool _navigatingToWeek = false;

  // --- Two-finger pinch-to-zoom on the timeline ---------------------------
  // Tracked with raw pointer events (a Listener, not GestureDetector's
  // onScale family) so it can't lose the gesture arena to the ListView's own
  // vertical-drag scrolling — Listener never participates in arena
  // disambiguation, it just observes. While a pinch is in progress the
  // ListView's scroll physics are switched to NeverScrollable so a second
  // finger landing mid-scroll can't also drag the list around.
  final Map<int, Offset> _timelinePinchPointers = {};
  double? _pinchStartDistance;
  double? _pinchStartHourHeight;
  double? _pinchStartScrollOffset;
  double? _pinchStartFocalDy;
  ScrollPhysics _timelineScrollPhysics = const AlwaysScrollableScrollPhysics();

  static const int _timelineDays = 365 * 20;
  static const int _initialDayIndex = _timelineDays ~/ 2;
  static const double _dayHeaderHeight = 34.0;
  double get _timelineDayExtent => _dayHeaderHeight + (_hourHeight * 24);
  static const double _leftPillarWidth = 70.0;

  final TextEditingController _subEventTitleCtrl = TextEditingController();
  final TextEditingController _subEventDescCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timelineBaseDate = DateTime(
      widget.currentDate.year,
      widget.currentDate.month,
      widget.currentDate.day,
    );
    _visibleDate = _timelineBaseDate;
    _scrollController = ScrollController(
      initialScrollOffset: _initialDayIndex * _timelineDayExtent,
    );
    _scrollController.addListener(_handleScroll);
    _horizontalPageController = PageController(initialPage: 0);

    if (widget.openEventEditorOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openEventEditor(targetDay: _visibleDate);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalPageController.dispose();
    _subEventTitleCtrl.dispose();
    _subEventDescCtrl.dispose();
    super.dispose();
  }

  void _showEventContextMenu(BuildContext context, Event event) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
                child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99)),
            )),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: event.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(event.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis)),
                  if (event.repeatConfig.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.repeat,
                            size: 11, color: Colors.blue.shade700),
                        const SizedBox(width: 3),
                        Text(event.repeatConfig.label,
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.repeat, color: Colors.blue),
              title: Text(event.repeatConfig.isActive
                  ? 'Edit repeat (${event.repeatConfig.label})'
                  : 'Set repeat'),
              onTap: () => Navigator.pop(ctx, 'repeat'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.orange),
              title: const Text('Edit event'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: const Text('Delete event'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'repeat') {
      final newConfig =
          await showRepeatConfigSheet(context, event.repeatConfig);
      if (newConfig != null) {
        final list = List<Event>.from(widget.eventsNotifier.value);
        final idx = list.indexWhere((e) => e == event);
        if (idx != -1) {
          list[idx].repeatConfig = newConfig;
          widget.eventsNotifier.value = list;
        }
      }
    } else if (result == 'edit') {
      _openEventEditor(existingEvent: event);
    } else if (result == 'delete') {
      _removeEventDirectly(event);
    }
  }

  void _openEventEditor({
    Event? existingEvent,
    DateTime? targetDay,
    double? clickedOffsetDy,
  }) {
    String eventTitle = existingEvent?.title ?? '';
    String eventDesc = existingEvent?.description ?? '';

    DateTime selectedStart;
    DateTime selectedEnd;

    if (existingEvent != null) {
      selectedStart = existingEvent.startTime;
      selectedEnd = existingEvent.endTime;
    } else {
      final day = targetDay ?? _visibleDate;
      if (clickedOffsetDy != null) {
        double totalClickedHours = clickedOffsetDy / _hourHeight;
        int calculatedHour = totalClickedHours.floor().clamp(0, 23);
        int calculatedMinute =
            ((totalClickedHours - calculatedHour) * 60).round().clamp(0, 59);
        selectedStart = DateTime(
          day.year,
          day.month,
          day.day,
          calculatedHour,
          calculatedMinute,
        );
      } else {
        // No grid tap to derive a time from (e.g. opened via the "Add Event"
        // button) — default to the next full hour as a sensible starting point.
        final now = DateTime.now();
        selectedStart = DateTime(day.year, day.month, day.day, now.hour + 1);
      }
      selectedEnd = selectedStart.add(Duration(minutes: 60));
    }

    final presetColors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.pink,
      Colors.teal,
    ];
    Color selectedColor = existingEvent?.color ??
        presetColors[widget.eventsNotifier.value.length % presetColors.length];
    List<SubEvent> localSubEvents =
        existingEvent != null ? List.from(existingEvent.subEvents) : [];
    List<String> localGroupIds =
        existingEvent != null ? List.from(existingEvent.groupIds) : [];
    RepeatConfig localRepeatConfig =
        existingEvent?.repeatConfig.clone() ?? RepeatConfig();
    int? localNotifyMinutesBefore = existingEvent?.notifyMinutesBefore;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                existingEvent == null ? 'New Event' : 'Edit Event',
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        initialValue: eventTitle,
                        decoration: InputDecoration(
                          labelText: 'Event title',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => eventTitle = val,
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        initialValue: eventDesc,
                        decoration: InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        onChanged: (val) => eventDesc = val,
                      ),
                      SizedBox(height: 14),
                      buildGroupAssignmentSection(
                        context: context,
                        itemGroupIds: localGroupIds,
                        groupsNotifier: widget.groupsNotifier,
                        setDialogState: setDialogState,
                        onModified: () {},
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Time',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      Divider(),
                      Builder(builder: (_) {
                        Widget timeTile(String label, DateTime value,
                            ValueChanged<DateTime> onPicked) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(label),
                            trailing: ElevatedButton.icon(
                              icon: Icon(Icons.access_time, size: 14),
                              label: Text(DateFormat('h:mm a').format(value)),
                              onPressed: () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(value),
                                );
                                if (time != null) {
                                  setDialogState(() => onPicked(DateTime(
                                        value.year,
                                        value.month,
                                        value.day,
                                        time.hour,
                                        time.minute,
                                      )));
                                }
                              },
                            ),
                          );
                        }

                        return Column(children: [
                          timeTile('Start:', selectedStart,
                              (v) => selectedStart = v),
                          timeTile('End:', selectedEnd, (v) => selectedEnd = v),
                        ]);
                      }),
                      SizedBox(height: 16),
                      Text(
                        'Add sub-events',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Divider(),
                      TextField(
                        controller: _subEventTitleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Sub-event title',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 6),
                      TextField(
                        controller: _subEventDescCtrl,
                        decoration: InputDecoration(
                          labelText: 'Sub-event notes',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 6),
                      ElevatedButton.icon(
                        icon: Icon(Icons.add_alarm, size: 16),
                        label: Text('Set time & add'),
                        onPressed: () async {
                          if (_subEventTitleCtrl.text.trim().isEmpty) return;
                          final sTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(selectedStart),
                          );
                          if (sTime == null) return;
                          final eTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(selectedEnd),
                          );
                          if (eTime == null) return;

                          final subStart = DateTime(
                            selectedStart.year,
                            selectedStart.month,
                            selectedStart.day,
                            sTime.hour,
                            sTime.minute,
                          );
                          final subEnd = DateTime(
                            selectedStart.year,
                            selectedStart.month,
                            selectedStart.day,
                            eTime.hour,
                            eTime.minute,
                          );

                          setDialogState(() {
                            localSubEvents.add(
                              SubEvent(
                                title: _subEventTitleCtrl.text.trim(),
                                description: _subEventDescCtrl.text.trim(),
                                startTime: subStart,
                                endTime: subEnd,
                              ),
                            );
                            _subEventTitleCtrl.clear();
                            _subEventDescCtrl.clear();
                          });
                        },
                      ),
                      if (localSubEvents.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Container(
                          constraints: BoxConstraints(maxHeight: 110),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: localSubEvents.length,
                            itemBuilder: (c, i) => ListTile(
                              title: Text(
                                localSubEvents[i].title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${DateFormat('h:mm').format(localSubEvents[i].startTime)} - ${DateFormat('h:mm a').format(localSubEvents[i].endTime)}\n${localSubEvents[i].description}',
                                style: TextStyle(fontSize: 11),
                              ),
                              dense: true,
                              isThreeLine:
                                  localSubEvents[i].description.isNotEmpty,
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  color: Colors.red.shade300,
                                  size: 16,
                                ),
                                onPressed: () => setDialogState(
                                  () => localSubEvents.removeAt(i),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 14),
                      // ── Repeat button ────────────────────────────────
                      GestureDetector(
                        onTap: () async {
                          final result = await showRepeatConfigSheet(
                              context, localRepeatConfig);
                          if (result != null)
                            setDialogState(() => localRepeatConfig = result);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: localRepeatConfig.isActive
                                ? Colors.blue.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: localRepeatConfig.isActive
                                  ? Colors.blue.shade300
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.repeat,
                                  size: 18,
                                  color: localRepeatConfig.isActive
                                      ? Colors.blue
                                      : Colors.grey.shade500),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                localRepeatConfig.isActive
                                    ? localRepeatConfig.label
                                    : 'No repeat',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: localRepeatConfig.isActive
                                      ? Colors.blue.shade800
                                      : Colors.grey.shade600,
                                  fontWeight: localRepeatConfig.isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              )),
                              Icon(Icons.chevron_right,
                                  size: 18, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 14),
                      // ── Notify-before picker ─────────────────────────
                      Text('Remind me',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const <MapEntry<String, int?>>[
                          MapEntry('Off', null),
                          MapEntry('5 min', 5),
                          MapEntry('15 min', 15),
                          MapEntry('30 min', 30),
                          MapEntry('1 hour', 60),
                          MapEntry('1 day', 1440),
                        ].map((entry) {
                          final selected =
                              localNotifyMinutesBefore == entry.value;
                          return GestureDetector(
                            onTap: () => setDialogState(
                              () => localNotifyMinutesBefore = entry.value,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.blue.shade50
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: selected
                                      ? Colors.blue.shade800
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Event color: ${hexKey(selectedColor)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.palette, color: Colors.blueGrey),
                            onPressed: () async {
                              final picked = await showRainbowColorPicker(
                                context,
                                selectedColor,
                              );
                              if (picked != null) {
                                setDialogState(() => selectedColor = picked);
                              }
                            },
                          ),
                        ],
                      ),
                      buildColorSwatchRow(
                        colors: presetColors,
                        selectedColor: selectedColor,
                        size: 26,
                        spacing: 6,
                        onSelected: (color) =>
                            setDialogState(() => selectedColor = color),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final currentList = List<Event>.from(
                      widget.eventsNotifier.value,
                    );

                    final newEvent = Event(
                      title:
                          eventTitle.isNotEmpty ? eventTitle : 'Untitled Event',
                      description: eventDesc,
                      startTime: selectedStart,
                      endTime: selectedEnd,
                      color: selectedColor,
                      subEvents: localSubEvents,
                      groupIds: localGroupIds,
                      repeatConfig: localRepeatConfig,
                      notifyMinutesBefore: localNotifyMinutesBefore,
                    );

                    if (existingEvent == null) {
                      currentList.addAll(expandEventWithRepeat(newEvent));
                    } else {
                      final targetIdx = currentList.indexWhere(
                        (e) => e == existingEvent,
                      );
                      if (targetIdx != -1) {
                        currentList.removeAt(targetIdx);
                        final updatedInstances = expandEventWithRepeat(
                          Event(
                            id: existingEvent.id,
                            title: eventTitle.isNotEmpty
                                ? eventTitle
                                : 'Untitled Event',
                            description: eventDesc,
                            startTime: selectedStart,
                            endTime: selectedEnd,
                            color: selectedColor,
                            columnBias: existingEvent.columnBias,
                            subEvents: localSubEvents,
                            groupIds: localGroupIds,
                            repeatConfig: localRepeatConfig,
                            notifyMinutesBefore: localNotifyMinutesBefore,
                          ),
                        );
                        currentList.insertAll(targetIdx, updatedInstances);
                      }
                    }

                    widget.eventsNotifier.value = currentList;
                    Navigator.pop(ctx);
                  },
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEventDetailsDialog(Event event) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.blue),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openEventEditor(existingEvent: event);
                    },
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildGroupAssignmentSection(
                      context: context,
                      itemGroupIds: event.groupIds,
                      groupsNotifier: widget.groupsNotifier,
                      setDialogState: setDialogState,
                      onModified: () => widget.eventsNotifier.value =
                          List.from(widget.eventsNotifier.value),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '${DateFormat('h:mm a').format(event.startTime)} – ${DateFormat('h:mm a').format(event.endTime)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Notes',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Divider(height: 8),
                    Text(
                      event.description.isEmpty
                          ? 'No notes added.'
                          : event.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: event.description.isEmpty
                            ? Colors.grey
                            : Colors.black87,
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Sub-events',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Divider(height: 8),
                    if (event.subEvents.isEmpty)
                      Text(
                        'No sub-events added.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      ...event.subEvents
                          .map(
                            (sub) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 14,
                                    color: event.color,
                                  ),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${sub.title} (${DateFormat('h:mm').format(sub.startTime)} – ${DateFormat('h:mm a').format(sub.endTime)})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (sub.description.isNotEmpty)
                                          Text(
                                            sub.description,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSubEventDetailsDialog(SubEvent sub, Event parent) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          sub.title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Part of: ${parent.title}',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              '${DateFormat('h:mm a').format(sub.startTime)} – ${DateFormat('h:mm a').format(sub.endTime)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            Divider(height: 16),
            Text(
              'Notes',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              sub.description.isEmpty ? 'No notes added.' : sub.description,
              style: TextStyle(fontSize: 13),
            ),
            Divider(height: 24),
            Text(
              'To edit or delete this sub-event, open the parent event.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openEventEditor(existingEvent: parent);
            },
            child: Text('Edit Parent Event'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _removeEventDirectly(Event event) {
    final currentList = List<Event>.from(widget.eventsNotifier.value);
    currentList.removeWhere((e) => e == event);
    widget.eventsNotifier.value = currentList;
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final currentIndex =
        (_scrollController.offset / _timelineDayExtent).round();
    final visibleDayMoment =
        _timelineBaseDate.add(Duration(days: currentIndex - _initialDayIndex));

    if (visibleDayMoment != _visibleDate) {
      setState(() {
        _visibleDate = visibleDayMoment;
      });
    }
  }

  // --- Long-press-then-drag zoom on the timeline --------------------------
  // Pinch-to-zoom doesn't reliably work on a scrolling ListView (the list's
  // own scroll gesture wins the gesture arena before a pinch is recognized).
  // Long-press is a clean, unambiguous gesture instead: hold for ~0.5s (a
  // haptic confirms zoom mode is active), then drag in any direction to
  // resize the timeline — drag right/up to zoom in, left/down to zoom out.
  // Keeps whatever time was under the finger steady on screen.

  void _onTimelineLongPressStart(LongPressStartDetails details) {
    HapticFeedback.mediumImpact();
    _scaleGestureStartHourHeight = _hourHeight;
    _scaleGestureStartScrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    _scaleGestureFocalDy = details.localPosition.dy;
  }

  void _onTimelineLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_scaleGestureStartHourHeight == null) return;

    final startHourHeight = _scaleGestureStartHourHeight!;
    final startOffset = _scaleGestureStartScrollOffset!;
    final focalDy = _scaleGestureFocalDy!;

    // Use whichever axis moved further, so either a horizontal or a
    // vertical drag works — about 150px of drag spans the full zoom range.
    final delta = details.offsetFromOrigin;
    final dominant = delta.dx.abs() > delta.dy.abs() ? delta.dx : -delta.dy;
    final zoomFactor = 1 + (dominant / 150);

    _applyTimelineZoom(
      rawHourHeight: startHourHeight * zoomFactor,
      startHourHeight: startHourHeight,
      startOffset: startOffset,
      focalDy: focalDy,
    );
  }

  void _onTimelineLongPressEnd(LongPressEndDetails details) {
    _scaleGestureStartHourHeight = null;
    _scaleGestureStartScrollOffset = null;
    _scaleGestureFocalDy = null;
    HapticFeedback.selectionClick();
  }

  // Shared zoom math used by both the long-press-drag gesture above and the
  // real two-finger pinch below. Keeps whatever time was under the focal
  // point steady on screen while `_hourHeight` changes.
  void _applyTimelineZoom({
    required double rawHourHeight,
    required double startHourHeight,
    required double startOffset,
    required double focalDy,
  }) {
    if (_navigatingToWeek) return;

    // Already fully zoomed out and still going further out (past what the
    // clamp would otherwise show) — the user wants more context than a
    // single day offers, so escalate to Week view.
    if (rawHourHeight < _minHourHeight - 40) {
      _zoomToWeek();
      return;
    }

    final newHourHeight = rawHourHeight.clamp(_minHourHeight, _maxHourHeight);
    if (newHourHeight == _hourHeight) return;

    final scaleRatio = newHourHeight / startHourHeight;

    // The scroll offset is made of two parts:
    //   1. dayIndex * dayExtent — which day we're on (days don't zoom)
    //   2. withinDay — how far into that day (this scales with hourHeight)
    //
    // startOffset uses the OLD dayExtent; we must recompute using the new
    // dayExtent so the day-index portion doesn't drift when hours resize.
    final startDayExtent = _dayHeaderHeight + startHourHeight * 24;
    final newDayExtent = _dayHeaderHeight + newHourHeight * 24;

    // Which day are we on, in the OLD coordinate space?
    final dayIndex = (startOffset / startDayExtent).floorToDouble();

    // Adjust for the focal point: a pixel at focalDy on screen represents
    // a time; we want that time to stay under the finger(s) after zooming.
    // The focal point is focalDy into the viewport. Before the zoom the
    // content at focalDy was at (startOffset + focalDy) in scroll space;
    // we want that same time at the same screen position after the zoom.
    final focalScrollPosBefore = startOffset + focalDy;
    final focalDayBefore =
        (focalScrollPosBefore / startDayExtent).floorToDouble();
    final focalWithinDayOld =
        focalScrollPosBefore - focalDayBefore * startDayExtent;
    final focalWithinHourOld =
        (focalWithinDayOld - _dayHeaderHeight).clamp(0.0, startHourHeight * 24);
    final focalScrollPosAfter = focalDayBefore * newDayExtent +
        _dayHeaderHeight +
        focalWithinHourOld * scaleRatio;

    final newOffset = (focalScrollPosAfter - focalDy)
        .clamp(0.0, dayIndex * newDayExtent + newDayExtent - 1);

    setState(() {
      _hourHeight = newHourHeight;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        newOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  double _pinchPointerDistance() {
    final pts = _timelinePinchPointers.values.toList();
    return (pts[0] - pts[1]).distance.clamp(1.0, double.infinity);
  }

  void _onTimelinePinchPointerDown(PointerDownEvent event) {
    _timelinePinchPointers[event.pointer] = event.localPosition;
    if (_timelinePinchPointers.length == 2) {
      _pinchStartDistance = _pinchPointerDistance();
      _pinchStartHourHeight = _hourHeight;
      _pinchStartScrollOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      final pts = _timelinePinchPointers.values.toList();
      _pinchStartFocalDy = (pts[0].dy + pts[1].dy) / 2;
      HapticFeedback.selectionClick();
      setState(() => _timelineScrollPhysics = const NeverScrollableScrollPhysics());
    }
  }

  void _onTimelinePinchPointerMove(PointerMoveEvent event) {
    if (!_timelinePinchPointers.containsKey(event.pointer)) return;
    _timelinePinchPointers[event.pointer] = event.localPosition;
    if (_timelinePinchPointers.length != 2 ||
        _pinchStartDistance == null ||
        _pinchStartHourHeight == null) {
      return;
    }
    final scaleRatio = _pinchPointerDistance() / _pinchStartDistance!;
    _applyTimelineZoom(
      rawHourHeight: _pinchStartHourHeight! * scaleRatio,
      startHourHeight: _pinchStartHourHeight!,
      startOffset: _pinchStartScrollOffset!,
      focalDy: _pinchStartFocalDy!,
    );
  }

  void _onTimelinePinchPointerEnd(PointerEvent event) {
    _timelinePinchPointers.remove(event.pointer);
    if (_timelinePinchPointers.length < 2) {
      _pinchStartDistance = null;
      _pinchStartHourHeight = null;
      _pinchStartScrollOffset = null;
      _pinchStartFocalDy = null;
      if (_timelineScrollPhysics is! AlwaysScrollableScrollPhysics) {
        setState(
            () => _timelineScrollPhysics = const AlwaysScrollableScrollPhysics());
      }
      HapticFeedback.selectionClick();
    }
  }

  void _zoomToWeek() {
    if (_navigatingToWeek) return;
    _navigatingToWeek = true;
    _scaleGestureStartHourHeight = null;
    _scaleGestureStartScrollOffset = null;
    _scaleGestureFocalDy = null;
    _timelinePinchPointers.clear();
    _pinchStartDistance = null;
    _pinchStartHourHeight = null;
    _pinchStartScrollOffset = null;
    _pinchStartFocalDy = null;
    HapticFeedback.mediumImpact();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WeekView(
          initialDate: _visibleDate,
          eventsNotifier: widget.eventsNotifier,
          tasksNotifier: widget.tasksNotifier,
          groupsNotifier: widget.groupsNotifier,
        ),
      ),
    );
  }

  // ── Per-day header band ───────────────────────────────────────────────
  Widget _buildDayHeader(DateTime day) => Container(
        height: _dayHeaderHeight,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          border: Border(
            top: BorderSide(color: Colors.blue.shade200, width: 2),
            bottom: BorderSide(color: Colors.blue.shade100),
          ),
        ),
        child: Text(
          DateFormat('EEEE, MMM d').format(day),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800),
        ),
      );

  // ── One hour row in the time grid ────────────────────────────────────
  Widget _buildHourRow(int hour) {
    final isZoomedOut = _hourHeight < 60;
    if (isZoomedOut && hour % 3 != 0) {
      return Container(
        height: _hourHeight,
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      );
    }
    final label = hour == 0
        ? '12:00 AM'
        : DateFormat('h:00 a').format(DateTime(2026, 1, 1, hour));
    final showHalf = _hourHeight >= 110;
    final showQuarter = _hourHeight >= 160;
    return Container(
      height: _hourHeight,
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Stack(children: [
        Row(children: [
          Container(
            width: _leftPillarWidth,
            padding: const EdgeInsets.only(left: 8, top: 4),
            alignment: Alignment.topLeft,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: CustomPaint(
              painter: HourGridPainter(hourHeight: _hourHeight),
              child: const SizedBox.expand(),
            ),
          ),
        ]),
        if (showHalf)
          Positioned(
            top: _hourHeight * 0.5 - 6,
            left: 8,
            width: _leftPillarWidth - 8,
            child: Text(':30',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
          ),
        if (showQuarter) ...[
          Positioned(
            top: _hourHeight * 0.25 - 5,
            left: 8,
            width: _leftPillarWidth - 8,
            child: Text(':15',
                style: TextStyle(fontSize: 8, color: Colors.grey.shade400)),
          ),
          Positioned(
            top: _hourHeight * 0.75 - 5,
            left: 8,
            width: _leftPillarWidth - 8,
            child: Text(':45',
                style: TextStyle(fontSize: 8, color: Colors.grey.shade400)),
          ),
        ],
      ]),
    );
  }

  // ── One event tile positioned on the day timeline ─────────────────────
  Widget _buildEventTile(
    Event event,
    Map<Event, int> eventColumns,
    Map<Event, int> eventMaxColumns,
    DateTime startOfDay,
    DateTime endOfDay,
    double totalScreenWidth,
  ) {
    final displayStart =
        event.startTime.isBefore(startOfDay) ? startOfDay : event.startTime;
    final displayEnd =
        event.endTime.isAfter(endOfDay) ? endOfDay : event.endTime;

    final startFrac = displayStart.hour + displayStart.minute / 60.0;
    final endFrac = displayEnd.hour + displayEnd.minute / 60.0;
    final topPosition = _dayHeaderHeight + startFrac * _hourHeight;
    final rawHeight = (endFrac - startFrac) * _hourHeight;
    final renderHeight = rawHeight < 34.0 ? 34.0 : rawHeight;

    final colIndex = eventColumns[event] ?? 0;
    final totalCols = eventMaxColumns[event] ?? 1;
    final available = totalScreenWidth - _leftPillarWidth - 12.0;
    final widthPerColumn = available / totalCols;
    final leftPosition = _leftPillarWidth + colIndex * widthPerColumn + 2;

    final totalParentMinutes = event.endTime
        .difference(event.startTime)
        .inMinutes
        .toDouble()
        .clamp(1.0, 1440.0);
    final localSubList = List<SubEvent>.from(event.subEvents)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final (subColumns, subMaxColumns) = _assignOverlapColumns<SubEvent>(
      localSubList,
      (s) => s.startTime,
      (s) => s.endTime,
    );

    final textColor = textOnColor(event.color);
    final labelStyle =
        TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.bold);
    final subLabelStyle =
        TextStyle(fontSize: 9, color: textColor.withAlpha(180));

    return Positioned(
      top: topPosition,
      left: leftPosition,
      width: widthPerColumn - 3,
      height: renderHeight,
      child: GestureDetector(
        onTap: () => _showEventDetailsDialog(event),
        onLongPress: () => _showEventContextMenu(context, event),
        onPanUpdate: (details) {
          final minuteDelta = (details.delta.dy / _hourHeight) * 60;
          final shift = Duration(minutes: minuteDelta.round());
          final proposedStart = event.startTime.add(shift);
          final proposedEnd = event.endTime.add(shift);
          if (proposedStart.isAfter(startOfDay) &&
              proposedEnd.isBefore(endOfDay)) {
            event.startTime = proposedStart;
            event.endTime = proposedEnd;
            for (final sub in event.subEvents) {
              sub.startTime = sub.startTime.add(shift);
              sub.endTime = sub.endTime.add(shift);
            }
          }
          _horizontalDragRemainder += details.delta.dx;
          if (_horizontalDragRemainder.abs() >= widthPerColumn) {
            final step = _horizontalDragRemainder > 0 ? 1 : -1;
            event.columnBias += step;
            _horizontalDragRemainder -= step * widthPerColumn;
          }
          setState(() {});
        },
        onPanEnd: (_) {
          widget.eventsNotifier.value = List.from(widget.eventsNotifier.value);
          HapticFeedback.lightImpact();
        },
        child: Container(
          decoration: BoxDecoration(
            color: event.color,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(40),
                  blurRadius: 3,
                  offset: const Offset(0, 1))
            ],
          ),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title.isEmpty ? 'Untitled' : event.title,
                        style: labelStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (renderHeight > 50 && event.description.isNotEmpty)
                      Text(event.description,
                          style: subLabelStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                  ]),
            ),
            // Sub-events
            if (localSubList.isNotEmpty)
              Positioned(
                top: 36,
                bottom: 20,
                left: 4,
                right: 4,
                child: Stack(
                  children: localSubList.map((sub) {
                    final relStart = sub.startTime
                        .difference(event.startTime)
                        .inMinutes
                        .toDouble();
                    final relDur = sub.endTime
                        .difference(sub.startTime)
                        .inMinutes
                        .toDouble();
                    double subTop =
                        (relStart / totalParentMinutes) * (renderHeight - 36);
                    double subH =
                        ((relDur / totalParentMinutes) * (renderHeight - 36))
                            .clamp(18.0, renderHeight);
                    final sCol = subColumns[sub] ?? 0;
                    final sTotal = subMaxColumns[sub] ?? 1;
                    final subW = (widthPerColumn - 38) / sTotal;
                    final toneShifted = event.color.computeLuminance() > 0.5
                        ? Color.alphaBlend(
                            Colors.black.withAlpha(40), event.color)
                        : Color.alphaBlend(
                            Colors.white.withAlpha(55), event.color);
                    return Positioned(
                      top: subTop,
                      left: sCol * subW,
                      width: subW - 1.5,
                      height: subH,
                      child: GestureDetector(
                        onTap: () => _showSubEventDetailsDialog(sub, event),
                        onVerticalDragUpdate: (d) {
                          final shift = Duration(
                              minutes:
                                  ((d.delta.dy / _hourHeight) * 60).round());
                          if (sub.startTime
                                  .add(shift)
                                  .isAfter(event.startTime) &&
                              sub.endTime.add(shift).isBefore(event.endTime)) {
                            setState(() {
                              sub.startTime = sub.startTime.add(shift);
                              sub.endTime = sub.endTime.add(shift);
                            });
                          }
                        },
                        onVerticalDragEnd: (_) {
                          widget.eventsNotifier.value =
                              List.from(widget.eventsNotifier.value);
                          HapticFeedback.lightImpact();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: toneShifted,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: textOnColor(event.color).withAlpha(70),
                                width: 0.8),
                          ),
                          child: Stack(children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
                              child: Text(sub.title,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: textOnColor(toneShifted)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            // Sub-event top resize handle
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 6,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (d) {
                                  final proposed = sub.startTime.add(Duration(
                                      minutes: ((d.delta.dy / _hourHeight) * 60)
                                          .round()));
                                  if (proposed.isBefore(sub.endTime.subtract(
                                          const Duration(minutes: 5))) &&
                                      proposed.isAfter(event.startTime)) {
                                    setState(() => sub.startTime = proposed);
                                  }
                                },
                                onVerticalDragEnd: (_) {
                                  widget.eventsNotifier.value =
                                      List.from(widget.eventsNotifier.value);
                                  HapticFeedback.lightImpact();
                                },
                                child: Container(color: Colors.transparent),
                              ),
                            ),
                            // Sub-event bottom resize handle
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: 6,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (d) {
                                  final proposed = sub.endTime.add(Duration(
                                      minutes: ((d.delta.dy / _hourHeight) * 60)
                                          .round()));
                                  if (proposed.isAfter(sub.startTime
                                          .add(const Duration(minutes: 5))) &&
                                      proposed.isBefore(event.endTime)) {
                                    setState(() => sub.endTime = proposed);
                                  }
                                },
                                onVerticalDragEnd: (_) {
                                  widget.eventsNotifier.value =
                                      List.from(widget.eventsNotifier.value);
                                  HapticFeedback.lightImpact();
                                },
                                child: Container(color: Colors.transparent),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            // Event top resize handle
            Positioned(
              top: 0,
              left: 0,
              right: 34,
              height: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  final proposed = event.startTime.add(Duration(
                      minutes: ((d.delta.dy / _hourHeight) * 60).round()));
                  if (proposed.isBefore(event.endTime
                          .subtract(const Duration(minutes: 10))) &&
                      proposed.isAfter(startOfDay)) {
                    setState(() => event.startTime = proposed);
                  }
                },
                onVerticalDragEnd: (_) {
                  widget.eventsNotifier.value =
                      List.from(widget.eventsNotifier.value);
                  HapticFeedback.lightImpact();
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            // Event bottom resize handle
            Positioned(
              bottom: 0,
              left: 0,
              right: 34,
              height: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  final proposed = event.endTime.add(Duration(
                      minutes: ((d.delta.dy / _hourHeight) * 60).round()));
                  if (proposed.isAfter(
                          event.startTime.add(const Duration(minutes: 10))) &&
                      proposed.isBefore(endOfDay)) {
                    setState(() => event.endTime = proposed);
                  }
                },
                onVerticalDragEnd: (_) {
                  widget.eventsNotifier.value =
                      List.from(widget.eventsNotifier.value);
                  HapticFeedback.lightImpact();
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            // Delete button
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _removeEventDirectly(event),
                child: Icon(Icons.close,
                    size: 12, color: textColor.withAlpha(180)),
              ),
            ),
            // Edit button
            Positioned(
              bottom: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _openEventEditor(existingEvent: event),
                child:
                    Icon(Icons.edit, size: 12, color: textColor.withAlpha(180)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTopSegmentTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: Icon(Icons.view_timeline, size: 16),
            label: Text('Schedule'),
            style: ElevatedButton.styleFrom(
              elevation: _activeHorizontalTab == 0 ? 2 : 0,
              backgroundColor: _activeHorizontalTab == 0
                  ? Colors.blue
                  : Colors.grey.shade200,
              foregroundColor:
                  _activeHorizontalTab == 0 ? Colors.white : Colors.black87,
            ),
            onPressed: () {
              _horizontalPageController.animateToPage(
                0,
                duration: Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
            },
          ),
          SizedBox(width: 16),
          ElevatedButton.icon(
            icon: Icon(Icons.checklist, size: 16),
            label: Text('Tasks'),
            style: ElevatedButton.styleFrom(
              elevation: _activeHorizontalTab == 1 ? 2 : 0,
              backgroundColor: _activeHorizontalTab == 1
                  ? Colors.blue
                  : Colors.grey.shade200,
              foregroundColor:
                  _activeHorizontalTab == 1 ? Colors.white : Colors.black87,
            ),
            onPressed: () {
              _horizontalPageController.animateToPage(
                1,
                duration: Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
            },
          ),
        ],
      ),
    );
  }

  void _openDailyQuickTaskCreator() {
    final TextEditingController _quickNameCtrl = TextEditingController();
    final TextEditingController _quickDescCtrl = TextEditingController();
    final TextEditingController _quickSubInputCtrl = TextEditingController();

    final List<Color> _presetColors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
    ];

    Color localSelectedColor = _presetColors[0];
    List<SubTask> localSubtasks = [];
    List<String> localGroupIds = [];

    bool isDailyTask = true;
    DateTime? localStartDate = _visibleDate;
    DateTime? localEndDate = _visibleDate;
    RepeatConfig localQuickRepeatConfig = RepeatConfig();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'New Task',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            DateFormat('MMM d').format(_visibleDate),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    CheckboxListTile(
                      title: Text(
                        'Lock to this day',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      subtitle: Text(
                        'Automatically sets start and due date to today',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: isDailyTask,
                      activeColor: Colors.blue,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setSheetState(() {
                          isDailyTask = val ?? false;
                          if (isDailyTask) {
                            localStartDate = _visibleDate;
                            localEndDate = _visibleDate;
                          }
                        });
                      },
                    ),
                    Divider(height: 16),
                    TextField(
                      controller: _quickNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Task name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _quickDescCtrl,
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    SizedBox(height: 14),
                    buildGroupAssignmentSection(
                      context: context,
                      itemGroupIds: localGroupIds,
                      groupsNotifier: widget.groupsNotifier,
                      setDialogState: setSheetState,
                      onModified: () {},
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Due dates (optional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    Divider(height: 10),
                    IgnorePointer(
                      ignoring: isDailyTask,
                      child: Opacity(
                        opacity: isDailyTask ? 0.55 : 1.0,
                        child: Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Start',
                                  style: TextStyle(fontSize: 12),
                                ),
                                subtitle: Text(
                                  localStartDate == null
                                      ? 'Not set'
                                      : DateFormat('yyyy-MM-dd').format(
                                          localStartDate!,
                                        ),
                                ),
                                trailing: Icon(
                                  Icons.calendar_month,
                                  size: 20,
                                  color: Colors.blue,
                                ),
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        localStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2040),
                                  );
                                  if (d != null) {
                                    setSheetState(() => localStartDate = d);
                                  }
                                },
                              ),
                            ),
                            if (localStartDate != null && !isDailyTask)
                              IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    setSheetState(() => localStartDate = null),
                              ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.grey.shade300,
                              margin: EdgeInsets.symmetric(horizontal: 8),
                            ),
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Due',
                                  style: TextStyle(fontSize: 12),
                                ),
                                subtitle: Text(
                                  localEndDate == null
                                      ? 'Not set'
                                      : DateFormat('yyyy-MM-dd').format(
                                          localEndDate!,
                                        ),
                                ),
                                trailing: Icon(
                                  Icons.calendar_month,
                                  size: 20,
                                  color: Colors.redAccent,
                                ),
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: localEndDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2040),
                                  );
                                  if (d != null) {
                                    setSheetState(() => localEndDate = d);
                                  }
                                },
                              ),
                            ),
                            if (localEndDate != null && !isDailyTask)
                              IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    setSheetState(() => localEndDate = null),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Checklist items',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quickSubInputCtrl,
                            decoration: InputDecoration(
                              labelText: 'Add a checklist item...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.add_circle,
                            color: Colors.blue,
                            size: 28,
                          ),
                          onPressed: () {
                            if (_quickSubInputCtrl.text.trim().isEmpty) return;
                            setSheetState(() {
                              localSubtasks.add(
                                SubTask(
                                  name: _quickSubInputCtrl.text.trim(),
                                ),
                              );
                              _quickSubInputCtrl.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    if (localSubtasks.isNotEmpty) ...[
                      SizedBox(height: 8),
                      Container(
                        constraints: BoxConstraints(maxHeight: 110),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: localSubtasks.length,
                          itemBuilder: (c, i) => ListTile(
                            title: Text(
                              localSubtasks[i].name,
                              style: TextStyle(fontSize: 13),
                            ),
                            dense: true,
                            trailing: IconButton(
                              icon: Icon(
                                Icons.cancel,
                                color: Colors.red.shade300,
                                size: 18,
                              ),
                              onPressed: () => setSheetState(
                                  () => localSubtasks.removeAt(i)),
                            ),
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 14),
                    // ── Repeat button ──────────────────────────────────
                    GestureDetector(
                      onTap: () async {
                        final result = await showRepeatConfigSheet(
                            context, localQuickRepeatConfig);
                        if (result != null)
                          setSheetState(() => localQuickRepeatConfig = result);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: localQuickRepeatConfig.isActive
                              ? Colors.blue.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: localQuickRepeatConfig.isActive
                                ? Colors.blue.shade300
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.repeat,
                                size: 18,
                                color: localQuickRepeatConfig.isActive
                                    ? Colors.blue
                                    : Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(
                              localQuickRepeatConfig.isActive
                                  ? localQuickRepeatConfig.label
                                  : 'No repeat',
                              style: TextStyle(
                                fontSize: 13,
                                color: localQuickRepeatConfig.isActive
                                    ? Colors.blue.shade800
                                    : Colors.grey.shade600,
                                fontWeight: localQuickRepeatConfig.isActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            )),
                            Icon(Icons.chevron_right,
                                size: 18, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Task color',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.palette, color: Colors.blueGrey),
                          onPressed: () async {
                            final picked = await showRainbowColorPicker(
                              context,
                              localSelectedColor,
                            );
                            if (picked != null) {
                              setSheetState(() => localSelectedColor = picked);
                            }
                          },
                        ),
                      ],
                    ),
                    buildColorSwatchRow(
                      colors: _presetColors,
                      selectedColor: localSelectedColor,
                      size: 32,
                      spacing: 10,
                      showCheckOnSelected: true,
                      onSelected: (color) =>
                          setSheetState(() => localSelectedColor = color),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (_quickNameCtrl.text.trim().isEmpty) return;
                        var updatedList = List<Task>.from(
                          widget.tasksNotifier.value,
                        );

                        final newQuickTask = Task(
                          name: _quickNameCtrl.text.trim(),
                          description: _quickDescCtrl.text.trim(),
                          color: localSelectedColor,
                          subtasks: localSubtasks,
                          startDate: localStartDate,
                          endDate: localEndDate,
                          groupIds: localGroupIds,
                          repeatConfig: localQuickRepeatConfig,
                        );
                        updatedList.addAll(expandTaskWithRepeat(newQuickTask));

                        widget.tasksNotifier.value =
                            getSortedTasks(updatedList);
                        Navigator.pop(sheetContext);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Add Task'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDayTaskboardWorkspace() {
    return ValueListenableBuilder<List<Task>>(
      valueListenable: widget.tasksNotifier,
      builder: (context, globalTasks, _) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);

        final visibleTasks = globalTasks
            .where(
              (t) => isItemVisible(t.groupIds, widget.groupsNotifier.value),
            )
            .toList();

        final List<Task> activeDayTasks = visibleTasks.where((task) {
          if (task.isCompleted) return false;
          final targetDate = task.endDate ?? task.startDate;
          if (targetDate == null) return false;
          return targetDate.year == _visibleDate.year &&
              targetDate.month == _visibleDate.month &&
              targetDate.day == _visibleDate.day;
        }).toList();

        final List<Task> normalUnassignedTasks = visibleTasks.where((task) {
          return !task.isCompleted &&
              task.startDate == null &&
              task.endDate == null;
        }).toList();

        final List<Task> finishedTodayTasks = visibleTasks.where((task) {
          if (!task.isCompleted) return false;
          final targetMatch =
              task.completedDate ?? task.endDate ?? task.startDate;
          if (targetMatch == null) return false;
          return targetMatch.year == _visibleDate.year &&
              targetMatch.month == _visibleDate.month &&
              targetMatch.day == _visibleDate.day;
        }).toList();

        Widget buildBoardSection(
          String trackTitle,
          List<Task> segment,
          Color headerAccent,
          IconData headerIcon,
        ) {
          if (segment.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14.0, 16.0, 14.0, 8.0),
                child: Row(
                  children: [
                    Icon(headerIcon, color: headerAccent, size: 18),
                    SizedBox(width: 6),
                    Text(
                      '$trackTitle (${segment.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              ...segment.map((task) {
                final bool isOverdue = task.endDate != null &&
                    task.endDate!.isBefore(todayStart) &&
                    !task.isCompleted;

                Widget entryCard = Card(
                  margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isOverdue ? Colors.red : task.color.withAlpha(80),
                      width: isOverdue ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(left: 8, right: 14),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade400,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                          onPressed: () {
                            final masterList = List<Task>.from(
                              widget.tasksNotifier.value,
                            );
                            masterList.remove(task);
                            widget.tasksNotifier.value =
                                getSortedTasks(masterList);
                          },
                        ),
                        SizedBox(width: 6),
                        Checkbox(
                          value: task.isCompleted,
                          activeColor: task.color,
                          onChanged: (val) {
                            final masterList = List<Task>.from(
                              widget.tasksNotifier.value,
                            );
                            final targetIdx = masterList.indexOf(task);
                            if (targetIdx != -1) {
                              final bool nextState =
                                  !masterList[targetIdx].isCompleted;
                              masterList[targetIdx].isCompleted = nextState;
                              masterList[targetIdx].completedDate =
                                  nextState ? DateTime.now() : null;
                              widget.tasksNotifier.value =
                                  getSortedTasks(masterList);
                            }
                          },
                        ),
                      ],
                    ),
                    title: Text(
                      task.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isCompleted ? Colors.grey : Colors.black87,
                      ),
                    ),
                    subtitle: task.description.isNotEmpty
                        ? Text(
                            task.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11),
                          )
                        : null,
                    trailing: Icon(
                      Icons.drag_handle,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ),
                );

                return isOverdue
                    ? PulsatingTaskCard(child: entryCard)
                    : entryCard;
              }).toList(),
            ],
          );
        }

        return Container(
          color: Colors.grey.shade50,
          child: ListView(
            padding: EdgeInsets.symmetric(vertical: 12),
            children: [
              buildBoardSection(
                'Due today',
                activeDayTasks,
                Colors.blue,
                Icons.hourglass_top_rounded,
              ),
              buildBoardSection(
                'No due date',
                normalUnassignedTasks,
                Colors.orange,
                Icons.assignment_outlined,
              ),
              buildBoardSection(
                'Completed today',
                finishedTodayTasks,
                Colors.green,
                Icons.task_alt_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_visibleDate);
    final daysList =
        List.generate(_timelineDays, (index) => index - _initialDayIndex);
    final double totalScreenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text(dateStr),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_view_week),
            tooltip: 'Week view',
            onPressed: _zoomToWeek,
          ),
          IconButton(
            icon: Icon(Icons.add),
            tooltip: 'Add event',
            onPressed: () => _openEventEditor(targetDay: _visibleDate),
          ),
          IconButton(
            icon: Icon(Icons.filter_list_rounded),
            tooltip: 'Filter categories',
            onPressed: () => showGroupFilterSheet(
              context,
              widget.groupsNotifier,
              () => setState(() {}),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTopSegmentTabs(),
          Expanded(
            child: PageView(
              controller: _horizontalPageController,
              onPageChanged: (pageIndex) {
                setState(() {
                  _activeHorizontalTab = pageIndex;
                });
              },
              children: [
                // PAGE 0: Timeline
                ValueListenableBuilder<List<Event>>(
                  valueListenable: widget.eventsNotifier,
                  builder: (context, globalEvents, _) {
                    final visibleEvents = globalEvents
                        .where(
                          (e) => isItemVisible(
                            e.groupIds,
                            widget.groupsNotifier.value,
                          ),
                        )
                        .toList();

                    return Listener(
                      // Real two-finger pinch-to-zoom. Kept alongside the
                      // long-press-drag gesture below (Listener never enters
                      // the gesture arena, so it can't interfere with it).
                      onPointerDown: _onTimelinePinchPointerDown,
                      onPointerMove: _onTimelinePinchPointerMove,
                      onPointerUp: _onTimelinePinchPointerEnd,
                      onPointerCancel: _onTimelinePinchPointerEnd,
                      child: GestureDetector(
                      onLongPressStart: _onTimelineLongPressStart,
                      onLongPressMoveUpdate: _onTimelineLongPressMoveUpdate,
                      onLongPressEnd: _onTimelineLongPressEnd,
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: _timelineScrollPhysics,
                        itemExtent: _timelineDayExtent,
                        itemCount: daysList.length,
                        itemBuilder: (context, dayIndexOffset) {
                          final currentDayOffset = daysList[dayIndexOffset];
                          final dayDateTime = _timelineBaseDate.add(
                            Duration(days: currentDayOffset),
                          );

                          final startOfDay = DateTime(
                            dayDateTime.year,
                            dayDateTime.month,
                            dayDateTime.day,
                          );
                          final endOfDay = startOfDay.add(Duration(days: 1));

                          final dayEvents = visibleEvents.where((e) {
                            return e.startTime.isBefore(endOfDay) &&
                                e.endTime.isAfter(startOfDay);
                          }).toList();

                          dayEvents.sort((a, b) {
                            int biasCmp = a.columnBias.compareTo(b.columnBias);
                            if (biasCmp != 0) return biasCmp;
                            return a.hashCode.compareTo(b.hashCode);
                          });

                          final (eventColumns, eventMaxColumns) =
                              _assignOverlapColumns<Event>(
                            dayEvents,
                            (e) => e.startTime,
                            (e) => e.endTime,
                          );

                          return Container(
                            height: _timelineDayExtent,
                            color: Colors.white,
                            child: Stack(children: [
                              Column(children: [
                                _buildDayHeader(dayDateTime),
                                ...List.generate(24, _buildHourRow),
                              ]),
                              Positioned.fill(
                                left: _leftPillarWidth,
                                top: _dayHeaderHeight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) => _openEventEditor(
                                    targetDay: dayDateTime,
                                    clickedOffsetDy: details.localPosition.dy,
                                  ),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                              ...dayEvents.map((event) => _buildEventTile(
                                    event,
                                    eventColumns,
                                    eventMaxColumns,
                                    startOfDay,
                                    endOfDay,
                                    totalScreenWidth,
                                  )),
                            ]),
                          );
                        },
                      ),
                      ),
                    );
                  },
                ),
                // PAGE 1: Task workspace
                _buildDayTaskboardWorkspace(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _activeHorizontalTab == 1
          ? FloatingActionButton(
              onPressed: _openDailyQuickTaskCreator,
              tooltip: 'New task',
              child: Icon(Icons.add_task),
            )
          : null,
    );
  }
}