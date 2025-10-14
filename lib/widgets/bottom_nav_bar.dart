import 'package:flutter/material.dart';

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabSelected;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          // Left tab: Records
          IconButton(
            icon: Icon(
              Icons.list,
              color: selectedIndex == 0 ? const Color.fromARGB(255, 255, 81, 81) : Colors.grey,
            ),
            onPressed: () => onTabSelected(0),
          ),
          
          const SizedBox(width: 40), // Space for center button

          // Right tab: Settings
          IconButton(
            icon: Icon(
              Icons.settings,
              color: selectedIndex == 2 ? const Color.fromARGB(255, 255, 81, 81) : Colors.grey,
            ),
            onPressed: () => onTabSelected(2),
          ),
        ],
      ),
    );
  }
}
