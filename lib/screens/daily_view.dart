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

  static const int _timelineDays = 365 * 20;
  static const int _initialDayIndex = _timelineDays ~/ 2;
  double get _timelineDayExtent => _hourHeight * 24;
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

                    return ListView.builder(
                      controller: _scrollController,
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
                          child: Stack(
                            children: [
                              Column(
                                children: List.generate(24, (hour) {
                                  final timeDisplay =
                                      DateFormat('h:00 a').format(
                                    DateTime(2026, 1, 1, hour),
                                  );
                                  return Container(
                                    height: _hourHeight,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade100,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: _leftPillarWidth,
                                          padding: EdgeInsets.only(
                                            left: 8,
                                            top: 4,
                                          ),
                                          alignment: Alignment.topLeft,
                                          child: Text(
                                            hour == 0
                                                ? '12:00 AM'
                                                : timeDisplay,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: CustomPaint(
                                            painter: HourGridPainter(
                                              hourHeight: _hourHeight,
                                            ),
                                            child: Container(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                              Positioned.fill(
                                left: _leftPillarWidth,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) => _openEventEditor(
                                    targetDay: dayDateTime,
                                    clickedOffsetDy: details.localPosition.dy,
                                  ),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                              ...dayEvents.map((event) {
                                final displayStart =
                                    event.startTime.isBefore(startOfDay)
                                        ? startOfDay
                                        : event.startTime;
                                final displayEnd =
                                    event.endTime.isAfter(endOfDay)
                                        ? endOfDay
                                        : event.endTime;

                                final double startFractionHours =
                                    displayStart.hour +
                                        (displayStart.minute / 60.0);
                                final double endFractionHours =
                                    displayEnd.hour +
                                        (displayEnd.minute / 60.0);

                                final double topPosition =
                                    startFractionHours * _hourHeight;
                                final double parentTotalHeight =
                                    (endFractionHours - startFractionHours) *
                                        _hourHeight;
                                final double renderHeight =
                                    parentTotalHeight < 34.0
                                        ? 34.0
                                        : parentTotalHeight;

                                final int colIndex = eventColumns[event] ?? 0;
                                final int totalCols =
                                    eventMaxColumns[event] ?? 1;

                                final double rightSpacingPadding = 12.0;
                                final double availableWidth = totalScreenWidth -
                                    _leftPillarWidth -
                                    rightSpacingPadding;
                                final double widthPerColumn =
                                    availableWidth / totalCols;
                                final double leftPosition = _leftPillarWidth +
                                    (colIndex * widthPerColumn) +
                                    2;

                                final double totalParentMinutes = event.endTime
                                    .difference(event.startTime)
                                    .inMinutes
                                    .toDouble()
                                    .clamp(1.0, 1440.0);

                                final List<SubEvent> localSubList =
                                    List.from(event.subEvents);
                                localSubList.sort(
                                  (a, b) => a.startTime.compareTo(b.startTime),
                                );

                                final (subColumns, subMaxColumns) =
                                    _assignOverlapColumns<SubEvent>(
                                  localSubList,
                                  (s) => s.startTime,
                                  (s) => s.endTime,
                                );

                                return Positioned(
                                  top: topPosition,
                                  left: leftPosition,
                                  width: widthPerColumn - 3,
                                  height: renderHeight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: event.color.withAlpha(235),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 1.5,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: event.color.withAlpha(255),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          top: 4,
                                          left: 6,
                                          right: 34,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                event.title,
                                                style: TextStyle(
                                                  color: textOnColor(
                                                    event.color,
                                                  ),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${DateFormat('h:mm a').format(event.startTime)} – ${DateFormat('h:mm a').format(event.endTime)}',
                                                style: TextStyle(
                                                  color: textOnColor(
                                                    event.color,
                                                  ).withAlpha(190),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (event.repeatConfig.isActive)
                                                Icon(Icons.repeat,
                                                    size: 9,
                                                    color:
                                                        textOnColor(event.color)
                                                            .withAlpha(180)),
                                            ],
                                          ),
                                        ),
                                        if (event.subEvents.isNotEmpty)
                                          Positioned.fill(
                                            top: 32,
                                            bottom: 4,
                                            left: 4,
                                            right: 34,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Stack(
                                                children:
                                                    event.subEvents.map((sub) {
                                                  double relativeStartMinutes =
                                                      sub.startTime
                                                          .difference(
                                                            event.startTime,
                                                          )
                                                          .inMinutes
                                                          .toDouble();
                                                  double subDurationMinutes =
                                                      sub.endTime
                                                          .difference(
                                                            sub.startTime,
                                                          )
                                                          .inMinutes
                                                          .toDouble();

                                                  double subTop =
                                                      (relativeStartMinutes /
                                                              totalParentMinutes) *
                                                          (renderHeight - 36);
                                                  double subHeight =
                                                      (subDurationMinutes /
                                                              totalParentMinutes) *
                                                          (renderHeight - 36);
                                                  subHeight = subHeight.clamp(
                                                    18.0,
                                                    renderHeight,
                                                  );

                                                  int sCol =
                                                      subColumns[sub] ?? 0;
                                                  int sTotal =
                                                      subMaxColumns[sub] ?? 1;

                                                  double subAvailableWidth =
                                                      widthPerColumn - 38;
                                                  double subWidthPerColumn =
                                                      subAvailableWidth /
                                                          sTotal;
                                                  double subLeft =
                                                      sCol * subWidthPerColumn;

                                                  Color toneShiftedColor = event
                                                              .color
                                                              .computeLuminance() >
                                                          0.5
                                                      ? Color.alphaBlend(
                                                          Colors.black
                                                              .withAlpha(40),
                                                          event.color,
                                                        )
                                                      : Color.alphaBlend(
                                                          Colors.white
                                                              .withAlpha(55),
                                                          event.color,
                                                        );

                                                  return Positioned(
                                                    top: subTop,
                                                    left: subLeft,
                                                    width:
                                                        subWidthPerColumn - 1.5,
                                                    height: subHeight,
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: toneShiftedColor,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                        border: Border.all(
                                                          color: textOnColor(
                                                            event.color,
                                                          ).withAlpha(70),
                                                          width: 0.8,
                                                        ),
                                                      ),
                                                      child: Stack(
                                                        children: [
                                                          Positioned(
                                                            top: 3,
                                                            bottom: 3,
                                                            left: 0,
                                                            right: 0,
                                                            child:
                                                                GestureDetector(
                                                              behavior:
                                                                  HitTestBehavior
                                                                      .opaque,
                                                              onTap: () =>
                                                                  _showSubEventDetailsDialog(
                                                                sub,
                                                                event,
                                                              ),
                                                              onVerticalDragUpdate:
                                                                  (details) {
                                                                double
                                                                    minuteDelta =
                                                                    (details.delta.dy /
                                                                            _hourHeight) *
                                                                        60;
                                                                Duration shift =
                                                                    Duration(
                                                                  minutes:
                                                                      minuteDelta
                                                                          .round(),
                                                                );
                                                                if (sub.startTime
                                                                        .add(
                                                                          shift,
                                                                        )
                                                                        .isAfter(
                                                                          event
                                                                              .startTime,
                                                                        ) &&
                                                                    sub.endTime
                                                                        .add(
                                                                          shift,
                                                                        )
                                                                        .isBefore(
                                                                          event
                                                                              .endTime,
                                                                        )) {
                                                                  setState(() {
                                                                    sub.startTime = sub
                                                                        .startTime
                                                                        .add(
                                                                      shift,
                                                                    );
                                                                    sub.endTime = sub
                                                                        .endTime
                                                                        .add(
                                                                      shift,
                                                                    );
                                                                  });
                                                                }
                                                              },
                                                              onVerticalDragEnd:
                                                                  (_) {
                                                                widget.eventsNotifier
                                                                        .value =
                                                                    List.from(
                                                                  widget
                                                                      .eventsNotifier
                                                                      .value,
                                                                );
                                                                HapticFeedback
                                                                    .lightImpact();
                                                              },
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      3.0,
                                                                ),
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    Expanded(
                                                                      child:
                                                                          Text(
                                                                        sub.title,
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              textOnColor(toneShiftedColor),
                                                                          fontSize:
                                                                              9,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                        ),
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Positioned(
                                                            top: 0,
                                                            left: 0,
                                                            right: 0,
                                                            height: 4,
                                                            child:
                                                                GestureDetector(
                                                              behavior:
                                                                  HitTestBehavior
                                                                      .opaque,
                                                              onVerticalDragUpdate:
                                                                  (details) {
                                                                double
                                                                    minuteDelta =
                                                                    (details.delta.dy /
                                                                            _hourHeight) *
                                                                        60;
                                                                DateTime
                                                                    proposedStart =
                                                                    sub.startTime
                                                                        .add(
                                                                  Duration(
                                                                    minutes:
                                                                        minuteDelta
                                                                            .round(),
                                                                  ),
                                                                );
                                                                if (proposedStart
                                                                        .isBefore(
                                                                      sub.endTime
                                                                          .subtract(
                                                                        Duration(
                                                                          minutes:
                                                                              5,
                                                                        ),
                                                                      ),
                                                                    ) &&
                                                                    proposedStart
                                                                        .isAfter(
                                                                      event
                                                                          .startTime,
                                                                    )) {
                                                                  setState(() {
                                                                    sub.startTime =
                                                                        proposedStart;
                                                                  });
                                                                }
                                                              },
                                                              onVerticalDragEnd:
                                                                  (_) {
                                                                widget.eventsNotifier
                                                                        .value =
                                                                    List.from(
                                                                  widget
                                                                      .eventsNotifier
                                                                      .value,
                                                                );
                                                                HapticFeedback
                                                                    .lightImpact();
                                                              },
                                                              child: Container(
                                                                color: Colors
                                                                    .transparent,
                                                              ),
                                                            ),
                                                          ),
                                                          Positioned(
                                                            bottom: 0,
                                                            left: 0,
                                                            right: 0,
                                                            height: 4,
                                                            child:
                                                                GestureDetector(
                                                              behavior:
                                                                  HitTestBehavior
                                                                      .opaque,
                                                              onVerticalDragUpdate:
                                                                  (details) {
                                                                double
                                                                    minuteDelta =
                                                                    (details.delta.dy /
                                                                            _hourHeight) *
                                                                        60;
                                                                DateTime
                                                                    proposedEnd =
                                                                    sub.endTime
                                                                        .add(
                                                                  Duration(
                                                                    minutes:
                                                                        minuteDelta
                                                                            .round(),
                                                                  ),
                                                                );
                                                                if (proposedEnd
                                                                        .isAfter(
                                                                      sub.startTime
                                                                          .add(
                                                                        Duration(
                                                                          minutes:
                                                                              5,
                                                                        ),
                                                                      ),
                                                                    ) &&
                                                                    proposedEnd
                                                                        .isBefore(
                                                                      event
                                                                          .endTime,
                                                                    )) {
                                                                  setState(() {
                                                                    sub.endTime =
                                                                        proposedEnd;
                                                                  });
                                                                }
                                                              },
                                                              onVerticalDragEnd:
                                                                  (_) {
                                                                widget.eventsNotifier
                                                                        .value =
                                                                    List.from(
                                                                  widget
                                                                      .eventsNotifier
                                                                      .value,
                                                                );
                                                                HapticFeedback
                                                                    .lightImpact();
                                                              },
                                                              child: Container(
                                                                color: Colors
                                                                    .transparent,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          top: 0,
                                          bottom: 0,
                                          left: 0,
                                          right: 34,
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.move,
                                            child: GestureDetector(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onTap: () =>
                                                  _showEventDetailsDialog(
                                                event,
                                              ),
                                              onLongPress: () =>
                                                  _showEventContextMenu(
                                                context,
                                                event,
                                              ),
                                              onPanStart: (_) =>
                                                  _horizontalDragRemainder =
                                                      0.0,
                                              onPanUpdate: (details) {
                                                double minuteDelta =
                                                    (details.delta.dy /
                                                            _hourHeight) *
                                                        60;
                                                Duration trackingShift =
                                                    Duration(
                                                  minutes: minuteDelta.round(),
                                                );
                                                DateTime proposedStart =
                                                    event.startTime.add(
                                                  trackingShift,
                                                );
                                                DateTime proposedEnd =
                                                    event.endTime.add(
                                                  trackingShift,
                                                );

                                                if (proposedStart.isAfter(
                                                      startOfDay,
                                                    ) &&
                                                    proposedEnd.isBefore(
                                                      endOfDay,
                                                    )) {
                                                  event.startTime =
                                                      proposedStart;
                                                  event.endTime = proposedEnd;
                                                  for (var sub
                                                      in event.subEvents) {
                                                    sub.startTime = sub
                                                        .startTime
                                                        .add(trackingShift);
                                                    sub.endTime = sub.endTime
                                                        .add(trackingShift);
                                                  }
                                                }

                                                _horizontalDragRemainder +=
                                                    details.delta.dx;
                                                if (_horizontalDragRemainder
                                                        .abs() >=
                                                    widthPerColumn) {
                                                  int stepDirection =
                                                      _horizontalDragRemainder >
                                                              0
                                                          ? 1
                                                          : -1;
                                                  event.columnBias +=
                                                      stepDirection;
                                                  _horizontalDragRemainder -=
                                                      stepDirection *
                                                          widthPerColumn;
                                                }

                                                // Repaint this widget locally
                                                // while dragging — committing
                                                // to eventsNotifier on every
                                                // frame would trigger a save
                                                // to disk and a full
                                                // notification reschedule
                                                // dozens of times per second.
                                                setState(() {});
                                              },
                                              onPanEnd: (_) {
                                                // Commit once, after the
                                                // gesture finishes.
                                                widget.eventsNotifier.value =
                                                    List.from(
                                                  widget.eventsNotifier.value,
                                                );
                                                HapticFeedback.lightImpact();
                                              },
                                              child: Container(
                                                color: Colors.transparent,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          bottom: 0,
                                          width: 34,
                                          child: Center(
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                Icons.delete_outline,
                                                size: 16,
                                                color: textOnColor(event.color)
                                                    .withAlpha(180),
                                              ),
                                              onPressed: () =>
                                                  _removeEventDirectly(event),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          right: 34,
                                          height: 6,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onVerticalDragUpdate: (details) {
                                              double minuteDelta =
                                                  (details.delta.dy /
                                                          _hourHeight) *
                                                      60;
                                              DateTime proposedStart =
                                                  event.startTime.add(
                                                Duration(
                                                  minutes: minuteDelta.round(),
                                                ),
                                              );
                                              if (proposedStart.isBefore(
                                                    event.endTime.subtract(
                                                      Duration(minutes: 10),
                                                    ),
                                                  ) &&
                                                  proposedStart
                                                      .isAfter(startOfDay)) {
                                                setState(() {
                                                  event.startTime =
                                                      proposedStart;
                                                });
                                              }
                                            },
                                            onVerticalDragEnd: (_) {
                                              widget.eventsNotifier.value =
                                                  List.from(
                                                widget.eventsNotifier.value,
                                              );
                                              HapticFeedback.lightImpact();
                                            },
                                            child: Container(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 34,
                                          height: 6,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onVerticalDragUpdate: (details) {
                                              double minuteDelta =
                                                  (details.delta.dy /
                                                          _hourHeight) *
                                                      60;
                                              DateTime proposedEnd =
                                                  event.endTime.add(
                                                Duration(
                                                  minutes: minuteDelta.round(),
                                                ),
                                              );
                                              if (proposedEnd.isAfter(
                                                    event.startTime.add(
                                                      Duration(minutes: 10),
                                                    ),
                                                  ) &&
                                                  proposedEnd
                                                      .isBefore(endOfDay)) {
                                                setState(() {
                                                  event.endTime = proposedEnd;
                                                });
                                              }
                                            },
                                            onVerticalDragEnd: (_) {
                                              widget.eventsNotifier.value =
                                                  List.from(
                                                widget.eventsNotifier.value,
                                              );
                                              HapticFeedback.lightImpact();
                                            },
                                            child: Container(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        );
                      },
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
