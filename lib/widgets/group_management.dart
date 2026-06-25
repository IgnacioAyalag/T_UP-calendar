import 'package:flutter/material.dart';
import '../models/group.dart';
import '../helpers/general_helpers.dart';

// Curated palette of modern calendar colors
const List<Color> _groupPalette = [
  Colors.blue,
  Colors.red,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.amber
];

// --- 1. THE GLOBAL GROUP MANAGER SHEET ---
// Opens from the app bar or forms to create and delete global categories
void showGroupManagerSheet(
    BuildContext context, ValueNotifier<List<Group>> groupsNotifier) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      final nameController = TextEditingController();
      Color selectedColor = _groupPalette.first;

      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return ValueListenableBuilder<List<Group>>(
            valueListenable: groupsNotifier,
            builder: (_, groups, __) {
              return Padding(
                padding: EdgeInsets.only(
                  top: 20,
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Manage Groups',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (groups.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                            'No groups created yet. Add your first category below!',
                            style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: groups.length,
                          itemBuilder: (context, i) {
                            final group = groups[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                  backgroundColor: group.color, radius: 12),
                              title: Text(group.name),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () {
                                  groupsNotifier.value = List.from(groups)
                                    ..removeAt(i);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    const Divider(height: 32),
                    const Text('Create New Group',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: 'Group Name (e.g., Work, Personal, Fitness)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _groupPalette.length,
                        itemBuilder: (context, i) {
                          final color = _groupPalette[i];
                          final isSelected = selectedColor == color;
                          return GestureDetector(
                            onTap: () =>
                                setModalState(() => selectedColor = color),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.black87, width: 3)
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          if (nameController.text.trim().isEmpty) return;
                          final newGroup = Group(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            name: nameController.text.trim(),
                            color: selectedColor,
                          );
                          groupsNotifier.value = [...groups, newGroup];
                          nameController.clear();
                          setModalState(
                              () => selectedColor = _groupPalette.first);
                        },
                        child: const Text('Add Group'),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

// --- 2. THE GLOBAL GROUP FILTER SHEET ---
void showGroupFilterSheet(BuildContext context,
    ValueNotifier<List<Group>> groupsNotifier, VoidCallback onUpdate) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      return ValueListenableBuilder<List<Group>>(
        valueListenable: groupsNotifier,
        builder: (context, groups, _) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter Calendar Categories',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No groups available to filter.',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: groups.length,
                      itemBuilder: (context, i) {
                        final group = groups[i];
                        return CheckboxListTile(
                          title: Text(group.name),
                          secondary: CircleAvatar(
                              backgroundColor: group.color, radius: 10),
                          value: group.isVisible,
                          activeColor: group.color,
                          onChanged: (bool? val) {
                            if (val != null) {
                              final updatedList =
                                  List<Group>.from(groupsNotifier.value);
                              updatedList[i] = group.copyWith(isVisible: val);
                              groupsNotifier.value = updatedList;
                              onUpdate();
                            }
                          },
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

// --- 3. THE SELECTION CHIPS (FOR FORM CREATION/MODIFICATION MENUS) ---
class GroupSelector extends StatelessWidget {
  final List<String> selectedGroupIds;
  final ValueNotifier<List<Group>> groupsNotifier;
  final Function(List<String>) onChanged;

  const GroupSelector({
    super.key,
    required this.selectedGroupIds,
    required this.groupsNotifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Group>>(
      valueListenable: groupsNotifier,
      builder: (context, groups, _) {
        if (groups.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assign to Groups',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add Your First Category'),
                onPressed: () => showGroupManagerSheet(context, groupsNotifier),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Assign to Groups',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      size: 20, color: Colors.blue),
                  tooltip: 'Create new category',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      showGroupManagerSheet(context, groupsNotifier),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: groups.map((group) {
                final isSelected = selectedGroupIds.contains(group.id);
                return FilterChip(
                  label: Text(
                    group.name,
                    style: TextStyle(
                      color: isSelected
                          ? textOnColor(group.color)
                          : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: group.color,
                  backgroundColor: group.color.withValues(alpha: 0.12),
                  checkmarkColor: textOnColor(group.color),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                        color: isSelected
                            ? Colors.transparent
                            : group.color.withValues(alpha: 0.45)),
                  ),
                  onSelected: (bool selected) {
                    final updatedIds = List<String>.from(selectedGroupIds);
                    if (selected) {
                      updatedIds.add(group.id);
                    } else {
                      updatedIds.remove(group.id);
                    }
                    onChanged(updatedIds);
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

// --- 4. CONDITIONAL ACTIVE CATEGORY BADGES DISPLAY WIDGET ---
class ActiveGroupsDisplay extends StatelessWidget {
  final List<String> itemGroupIds;
  final ValueNotifier<List<Group>> groupsNotifier;

  const ActiveGroupsDisplay({
    super.key,
    required this.itemGroupIds,
    required this.groupsNotifier,
  });

  @override
  Widget build(BuildContext context) {
    // If the list of selected groups is empty, hide structural frames, spacing, and texts entirely
    if (itemGroupIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<List<Group>>(
      valueListenable: groupsNotifier,
      builder: (context, globalGroups, _) {
        final matchedGroups =
            globalGroups.where((g) => itemGroupIds.contains(g.id)).toList();

        // If none of the assigned category IDs exist globally anymore, remain completely hidden
        if (matchedGroups.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Text('Active Categories:',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: matchedGroups.map((group) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: group.color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    group.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: textOnColor(group.color),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
