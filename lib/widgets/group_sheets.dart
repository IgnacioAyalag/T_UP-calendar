import 'package:flutter/material.dart';
import '../models/group.dart';

void showGroupFilterSheet(
  BuildContext context,
  ValueNotifier<List<Group>> groupsNotifier,
  VoidCallback onUpdate,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return ValueListenableBuilder<List<Group>>(
        valueListenable: groupsNotifier,
        builder: (context, groups, _) {
          List<Group> buildOrderedHierarchy() {
            List<Group> ordered = [];
            void appendChildren(String? parentId) {
              final children =
                  groups.where((g) => g.parentGroupId == parentId).toList();
              for (var child in children) {
                ordered.add(child);
                appendChildren(child.id);
              }
            }

            final topLevel =
                groups.where((g) => g.parentGroupId == null).toList();
            for (var top in topLevel) {
              ordered.add(top);
              appendChildren(top.id);
            }
            for (var g in groups) {
              if (!ordered.contains(g)) ordered.add(g);
            }
            return ordered;
          }

          final orderedList = buildOrderedHierarchy();

          return Padding(
            padding: const EdgeInsets.all(16.0),
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
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Show / Hide Categories',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade900,
                  ),
                ),
                Text(
                  'Toggle which categories appear in your calendar and tasks',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: orderedList.length,
                    itemBuilder: (c, i) {
                      final group = orderedList[i];

                      int depth = 0;
                      String? currentParentId = group.parentGroupId;
                      while (currentParentId != null) {
                        depth++;
                        final parent = groups.firstWhere(
                          (g) => g.id == currentParentId,
                          orElse: () => Group(
                              id: '', name: '', color: Colors.transparent),
                        );
                        currentParentId =
                            parent.id.isNotEmpty ? parent.parentGroupId : null;
                      }

                      return Padding(
                        padding: EdgeInsets.only(left: depth * 20.0),
                        child: CheckboxListTile(
                          activeColor: group.color,
                          title: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: group.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                group.name,
                                style: TextStyle(
                                  fontWeight: depth == 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          value: group.isVisible,
                          onChanged: (val) {
                            // FIX: replace the group object in the list immutably
                            final updatedGroups = groupsNotifier.value.map((g) {
                              if (g.id == group.id) {
                                return g.copyWith(isVisible: val ?? true);
                              }
                              return g;
                            }).toList();
                            groupsNotifier.value = updatedGroups;
                            onUpdate();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void showInlineGroupCreator(
  BuildContext context,
  ValueNotifier<List<Group>> groupsNotifier,
  Function(Group) onCreated,
) {
  final nameController = TextEditingController();
  // Snapshot groups ONCE at dialog-open time so the dropdown items never
  // change mid-rebuild when the parent ValueListenableBuilder fires.
  final List<Group> snapshotGroups = List.unmodifiable(groupsNotifier.value);
  String? selectedParentId;
  Color selectedColor = Colors.blue;
  final presetColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.purple,
    Colors.teal,
    Colors.pink,
  ];

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setSubState) {
          // Validate against the fixed snapshot — never touches groupsNotifier.value
          final String? safeParentId =
              snapshotGroups.any((g) => g.id == selectedParentId)
                  ? selectedParentId
                  : null;

          return AlertDialog(
            title: Text(
              'Create New Category',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Category Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 14),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Subcategory of (optional)',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButton<String>(
                      value: safeParentId,
                      isExpanded: true,
                      underline: SizedBox.shrink(),
                      isDense: true,
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text('None (top level)'),
                        ),
                        ...snapshotGroups.map(
                          (g) => DropdownMenuItem(
                            value: g.id,
                            child: Text(g.name),
                          ),
                        ),
                      ],
                      onChanged: (val) =>
                          setSubState(() => selectedParentId = val),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Pick a color',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presetColors.map((color) {
                      final isSelected =
                          selectedColor.toARGB32() == color.toARGB32();
                      return GestureDetector(
                        onTap: () => setSubState(() => selectedColor = color),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.black87
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) return;
                  final newGroup = Group(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    color: selectedColor,
                    parentGroupId: selectedParentId,
                  );
                  groupsNotifier.value = [
                    ...groupsNotifier.value,
                    newGroup,
                  ];
                  onCreated(newGroup);
                  Navigator.pop(ctx);
                },
                child: Text('Create'),
              ),
            ],
          );
        },
      );
    },
  );
}
