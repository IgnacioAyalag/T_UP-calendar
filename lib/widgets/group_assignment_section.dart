import 'package:flutter/material.dart';
import '../models/group.dart';
import 'group_sheets.dart';

// Shared component for category assignment with draggable pills (no separate drag handle button)
Widget buildGroupAssignmentSection({
  required BuildContext context,
  required List<String> itemGroupIds,
  required ValueNotifier<List<Group>> groupsNotifier,
  required StateSetter setDialogState,
  required VoidCallback onModified,
}) {
  final currentGroups = groupsNotifier.value;
  final assignedGroups = itemGroupIds
      .map(
        (id) => currentGroups.firstWhere(
          (g) => g.id == id,
          orElse: () => Group(id: '', name: 'Unknown', color: Colors.grey),
        ),
      )
      .where((g) => g.id.isNotEmpty)
      .toList();

  final unassignedGroups =
      currentGroups.where((g) => !itemGroupIds.contains(g.id)).toList();

  final bool hasAnyGroups = groupsNotifier.value.isNotEmpty;

  // When there are no groups yet, show a simple prompt to create the first
  // one instead of hiding the whole section (it used to disappear entirely).
  if (!hasAnyGroups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categories',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 6),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blue,
            side: BorderSide(color: Colors.blue),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(Icons.add_circle_outline, size: 18),
          label: Text('Create your first category'),
          onPressed: () {
            showInlineGroupCreator(context, groupsNotifier, (newGroup) {
              setDialogState(() {
                itemGroupIds.add(newGroup.id);
              });
              onModified();
            });
          },
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Categories',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Colors.grey.shade700,
        ),
      ),
      if (assignedGroups.length > 1) ...[
        SizedBox(height: 2),
        Text(
          'Drag pills to reorder priority',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      ],
      SizedBox(height: 6),
      if (itemGroupIds.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            'No categories assigned yet.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        )
      else if (assignedGroups.length == 1)
        // Nothing to reorder with just one pill — show it plainly, no drag.
        _GroupPill(
          group: assignedGroups.first,
          onRemove: () {
            setDialogState(() => itemGroupIds.remove(assignedGroups.first.id));
            onModified();
          },
        )
      else
        SizedBox(
          height: 42,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            // FIX: use buildDefaultDragHandles: true so the whole item is draggable,
            // wrapping each item in a ReorderableDragStartListener so the entire pill drags
            buildDefaultDragHandles: false,
            itemCount: assignedGroups.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              setDialogState(() {
                final id = itemGroupIds.removeAt(oldIndex);
                itemGroupIds.insert(newIndex, id);
              });
              onModified();
            },
            itemBuilder: (context, idx) {
              final group = assignedGroups[idx];
              return ReorderableDragStartListener(
                key: ValueKey(group.id),
                index: idx,
                child: _GroupPill(
                  group: group,
                  margin: const EdgeInsets.only(right: 8),
                  onRemove: () {
                    setDialogState(() => itemGroupIds.remove(group.id));
                    onModified();
                  },
                ),
              );
            },
          ),
        ),
      SizedBox(height: 6),
      InputDecorator(
        decoration: InputDecoration(
          labelText: 'Add to a category',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButton<String>(
          value: null,
          isExpanded: true,
          underline: SizedBox.shrink(),
          isDense: true,
          hint: Text('Select a category...',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          items: [
            ...unassignedGroups.map(
              (g) => DropdownMenuItem<String>(
                value: g.id,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: g.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(g.name, style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            DropdownMenuItem<String>(
              value: '_CREATE_NEW_GROUP_',
              child: Row(
                children: [
                  Icon(Icons.add, color: Colors.blue, size: 16),
                  SizedBox(width: 8),
                  Text(
                    '+ New category',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
          onChanged: (val) {
            if (val == '_CREATE_NEW_GROUP_') {
              showInlineGroupCreator(context, groupsNotifier, (newGroup) {
                setDialogState(() {
                  itemGroupIds.add(newGroup.id);
                });
                onModified();
              });
            } else if (val != null) {
              setDialogState(() {
                itemGroupIds.add(val);
              });
              onModified();
            }
          },
        ),
      ),
    ],
  );
}

class _GroupPill extends StatelessWidget {
  final Group group;
  final VoidCallback onRemove;
  final EdgeInsets margin;

  const _GroupPill({
    required this.group,
    required this.onRemove,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            group.name,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          SizedBox(width: 6),
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: group.color, shape: BoxShape.circle),
          ),
          SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.cancel, size: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
