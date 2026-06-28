import 'package:T_UP/widgets/group_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/group.dart';
import '../helpers/general_helpers.dart';
import '../helpers/repeat_helpers.dart';
import '../models/repeat_config.dart';
import '../widgets/repeat_config_sheet.dart';
import '../widgets/group_assignment_section.dart';
import '../widgets/color_picker.dart';
import '../widgets/pulsating_effects.dart';

// --- TASK MANAGEMENT ---
class TasksPage extends StatefulWidget {
  final ValueNotifier<List<Task>> tasksNotifier;
  final ValueNotifier<List<Group>> groupsNotifier;
  final bool openEditorOnLaunch;

  const TasksPage({
    required this.tasksNotifier,
    required this.groupsNotifier,
    this.openEditorOnLaunch = false,
  });

  @override
  _TasksPageState createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _subTaskInputController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    if (widget.openEditorOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTaskEditor();
      });
    }
  }

  void _showTaskContextMenu(BuildContext context, Task task) async {
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
                          color: task.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(task.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis)),
                  if (task.repeatConfig.isActive)
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
                        Text(task.repeatConfig.label,
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
              title: Text(task.repeatConfig.isActive
                  ? 'Edit repeat (${task.repeatConfig.label})'
                  : 'Set repeat'),
              onTap: () => Navigator.pop(ctx, 'repeat'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.orange),
              title: const Text('Edit task'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: const Text('Delete task'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'repeat') {
      final newConfig = await showRepeatConfigSheet(context, task.repeatConfig);
      if (newConfig != null) {
        final list = List<Task>.from(widget.tasksNotifier.value);
        final idx = list.indexOf(task);
        if (idx != -1) {
          list[idx].repeatConfig = newConfig;
          widget.tasksNotifier.value = list;
        }
      }
    } else if (result == 'edit') {
      _openTaskEditor(existingTask: task);
    } else if (result == 'delete') {
      _deleteTask(task);
    }
  }

  void _openTaskEditor({Task? existingTask}) {
    _nameController.text = existingTask?.name ?? '';
    _descController.text = existingTask?.description ?? '';
    _subTaskInputController.clear();

    Color localSelectedColor = existingTask?.color ?? _presetColors[0];
    List<SubTask> localSubtasks = existingTask != null
        ? existingTask.subtasks
            .map((s) => SubTask(name: s.name, isCompleted: s.isCompleted))
            .toList()
        : [];
    List<String> localGroupIds =
        existingTask != null ? List.from(existingTask.groupIds) : [];
    RepeatConfig localTaskRepeatConfig =
        existingTask?.repeatConfig.clone() ?? RepeatConfig();

    DateTime? localStartDate = existingTask?.startDate;
    DateTime? localEndDate = existingTask?.endDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existingTask == null ? 'New Task' : 'Edit Task',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 14),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Task name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _descController,
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
                    Row(
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
                            trailing: IconButton(
                              icon: Icon(
                                Icons.calendar_month,
                                size: 20,
                                color: Colors.blue,
                              ),
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: localStartDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2040),
                                );
                                if (d != null) {
                                  setSheetState(() => localStartDate = d);
                                }
                              },
                            ),
                          ),
                        ),
                        if (localStartDate != null)
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
                            trailing: IconButton(
                              icon: Icon(
                                Icons.calendar_month,
                                size: 20,
                                color: Colors.redAccent,
                              ),
                              onPressed: () async {
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
                        ),
                        if (localEndDate != null)
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
                            controller: _subTaskInputController,
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
                            if (_subTaskInputController.text.trim().isEmpty) {
                              return;
                            }
                            setSheetState(() {
                              localSubtasks.add(
                                SubTask(
                                  name: _subTaskInputController.text.trim(),
                                ),
                              );
                              _subTaskInputController.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    if (localSubtasks.isNotEmpty) ...[
                      SizedBox(height: 8),
                      Container(
                        constraints: BoxConstraints(maxHeight: 120),
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
                            context, localTaskRepeatConfig);
                        if (result != null)
                          setSheetState(() => localTaskRepeatConfig = result);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: localTaskRepeatConfig.isActive
                              ? Colors.blue.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: localTaskRepeatConfig.isActive
                                ? Colors.blue.shade300
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.repeat,
                                size: 18,
                                color: localTaskRepeatConfig.isActive
                                    ? Colors.blue
                                    : Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(
                              localTaskRepeatConfig.isActive
                                  ? localTaskRepeatConfig.label
                                  : 'No repeat',
                              style: TextStyle(
                                fontSize: 13,
                                color: localTaskRepeatConfig.isActive
                                    ? Colors.blue.shade800
                                    : Colors.grey.shade600,
                                fontWeight: localTaskRepeatConfig.isActive
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
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: _presetColors.map((color) {
                        final isSelected =
                            localSelectedColor.toARGB32() == color.toARGB32();
                        return GestureDetector(
                          onTap: () =>
                              setSheetState(() => localSelectedColor = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.black87
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: isSelected
                                ? Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (_nameController.text.trim().isEmpty) return;
                        var updatedList = List<Task>.from(
                          widget.tasksNotifier.value,
                        );

                        final newTask = Task(
                          name: _nameController.text.trim(),
                          description: _descController.text.trim(),
                          color: localSelectedColor,
                          subtasks: localSubtasks,
                          startDate: localStartDate,
                          endDate: localEndDate,
                          groupIds: localGroupIds,
                          repeatConfig: localTaskRepeatConfig,
                        );

                        if (existingTask == null) {
                          updatedList.addAll(expandTaskWithRepeat(newTask));
                        } else {
                          final idx = updatedList.indexOf(existingTask);
                          if (idx != -1) {
                            updatedList.removeAt(idx);
                            updatedList.insertAll(
                                idx,
                                expandTaskWithRepeat(Task(
                                  name: _nameController.text.trim(),
                                  description: _descController.text.trim(),
                                  isCompleted: existingTask.isCompleted,
                                  color: localSelectedColor,
                                  subtasks: localSubtasks,
                                  startDate: localStartDate,
                                  endDate: localEndDate,
                                  completedDate: existingTask.completedDate,
                                  groupIds: localGroupIds,
                                  repeatConfig: localTaskRepeatConfig,
                                )));
                          }
                        }

                        widget.tasksNotifier.value =
                            getSortedTasks(updatedList);
                        _nameController.clear();
                        _descController.clear();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        existingTask == null ? 'Add Task' : 'Save Changes',
                      ),
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

  void _showTaskDetailsDialog(Task task) {
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
                      task.name,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.blue),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openTaskEditor(existingTask: task);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildGroupAssignmentSection(
                        context: context,
                        itemGroupIds: task.groupIds,
                        groupsNotifier: widget.groupsNotifier,
                        setDialogState: setDialogState,
                        onModified: () => widget.tasksNotifier.value =
                            List.from(widget.tasksNotifier.value),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: task.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Color: ${hexKey(task.color)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      if (task.startDate != null || task.endDate != null) ...[
                        SizedBox(height: 10),
                        Text(
                          'Period: ${task.startDate == null ? 'Open' : DateFormat('yyyy-MM-dd').format(task.startDate!)} → ${task.endDate == null ? 'Open' : DateFormat('yyyy-MM-dd').format(task.endDate!)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                      if (task.isCompleted && task.completedDate != null) ...[
                        SizedBox(height: 6),
                        Text(
                          'Completed: ${DateFormat('yyyy-MM-dd HH:mm').format(task.completedDate!)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                      SizedBox(height: 16),
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
                        task.description.isEmpty
                            ? 'No notes added.'
                            : task.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: task.description.isEmpty
                              ? Colors.grey
                              : Colors.black87,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Checklist',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Divider(height: 8),
                      if (task.subtasks.isEmpty)
                        Text(
                          'No checklist items.',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        )
                      else
                        ...task.subtasks.asMap().entries.map((entry) {
                          int subIdx = entry.key;
                          var sub = entry.value;
                          return CheckboxListTile(
                            title: Text(
                              sub.name,
                              style: TextStyle(
                                fontSize: 13,
                                decoration: sub.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            value: sub.isCompleted,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            activeColor: task.color,
                            onChanged: (val) {
                              setDialogState(() {
                                sub.isCompleted = val ?? false;
                              });
                              final updatedList = List<Task>.from(
                                widget.tasksNotifier.value,
                              );
                              final masterIdx = updatedList.indexOf(task);
                              if (masterIdx != -1) {
                                updatedList[masterIdx]
                                    .subtasks[subIdx]
                                    .isCompleted = sub.isCompleted;
                                widget.tasksNotifier.value = updatedList;
                              }
                            },
                          );
                        }).toList(),
                    ],
                  ),
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

  void _toggleTaskStatus(Task task) {
    var updatedList = List<Task>.from(widget.tasksNotifier.value);
    final idx = updatedList.indexOf(task);
    if (idx != -1) {
      final bool nextState = !updatedList[idx].isCompleted;
      updatedList[idx].isCompleted = nextState;
      updatedList[idx].completedDate = nextState ? DateTime.now() : null;
      widget.tasksNotifier.value = getSortedTasks(updatedList);
      if (nextState) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
  }

  void _deleteTask(Task task) {
    final updatedList = List<Task>.from(widget.tasksNotifier.value);
    updatedList.remove(task);
    widget.tasksNotifier.value = updatedList;
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Tasks'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list_rounded),
            tooltip: 'Filter categories',
            onPressed: () => showGroupFilterSheet(
              context,
              widget.groupsNotifier,
              () => setState(() {}),
            ),
          ),
          IconButton(
            icon: Icon(Icons.sort_rounded),
            tooltip: 'Sort tasks',
            onPressed: () {
              widget.tasksNotifier.value =
                  getSortedTasks(widget.tasksNotifier.value);
            },
          ),
          SizedBox(width: 8),
        ],
      ),
      body: ValueListenableBuilder<List<Task>>(
        valueListenable: widget.tasksNotifier,
        builder: (context, currentTasks, _) {
          final visibleTasks = currentTasks
              .where(
                (t) => isItemVisible(t.groupIds, widget.groupsNotifier.value),
              )
              .toList();

          if (visibleTasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Nothing here yet!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add a task using the + button below.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            );
          }

          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);

          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: visibleTasks.length,
            padding: EdgeInsets.all(16),
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final mutableList = List<Task>.from(visibleTasks);
                final item = mutableList.removeAt(oldIndex);
                mutableList.insert(newIndex, item);

                final masterTasks = List<Task>.from(
                  widget.tasksNotifier.value,
                );
                for (var task in masterTasks) {
                  if (visibleTasks.contains(task)) {
                    masterTasks.remove(task);
                  }
                }
                widget.tasksNotifier.value = [
                  ...mutableList,
                  ...masterTasks,
                ];
              });
            },
            itemBuilder: (context, index) {
              final task = visibleTasks[index];
              final doneSub = task.subtasks.where((s) => s.isCompleted).length;
              final totalSub = task.subtasks.length;

              final bool isOverdue = task.endDate != null &&
                  task.endDate!.isBefore(todayStart) &&
                  !task.isCompleted;
              final bool isNotStarted = task.startDate != null &&
                  task.startDate!.isAfter(now) &&
                  !task.isCompleted;

              Widget cardBody = Card(
                key: ObjectKey(task),
                elevation: isOverdue ? 0 : 1,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isOverdue
                        ? Colors.red.shade700
                        : isNotStarted
                            ? Colors.grey.shade300
                            : task.color.withAlpha(120),
                    width: isOverdue ? 2.0 : 1.5,
                  ),
                ),
                child: ReorderableDragStartListener(
                  index: index,
                  child: ListTile(
                    onTap: () => _showTaskDetailsDialog(task),
                    onLongPress: () => _showTaskContextMenu(context, task),
                    leading: Checkbox(
                      value: task.isCompleted,
                      activeColor: task.color,
                      onChanged: (_) => _toggleTaskStatus(task),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: task.isCompleted || isNotStarted
                                  ? Colors.grey
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        if (isOverdue)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'OVERDUE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else if (isNotStarted)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'UPCOMING',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (task.description.isNotEmpty)
                          Text(
                            task.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        if (task.startDate != null || task.endDate != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              '${task.startDate == null ? '...' : DateFormat('MM-dd').format(task.startDate!)} → ${task.endDate == null ? '...' : DateFormat('MM-dd').format(task.endDate!)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isOverdue
                                    ? Colors.red.shade800
                                    : Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (totalSub > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.checklist,
                                  size: 14,
                                  color: Colors.blueGrey,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '$doneSub of $totalSub done',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (task.repeatConfig.isActive)
                          Padding(
                            padding: const EdgeInsets.only(top: 3.0),
                            child: Row(
                              children: [
                                Icon(Icons.repeat,
                                    size: 12, color: Colors.blue.shade400),
                                SizedBox(width: 4),
                                Text(
                                  task.repeatConfig.label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade400,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Colors.red.shade400),
                      onPressed: () => _deleteTask(task),
                    ),
                  ),
                ),
              );

              if (isNotStarted) {
                cardBody = Opacity(opacity: 0.48, child: cardBody);
              }

              return Padding(
                key: ObjectKey(task),
                padding: const EdgeInsets.only(bottom: 12.0),
                child:
                    isOverdue ? PulsatingTaskCard(child: cardBody) : cardBody,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTaskEditor(),
        child: Icon(Icons.add),
        tooltip: 'New task',
      ),
    );
  }
}
