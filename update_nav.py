import re

with open('lib/screens/male_dashboard_screen.dart', 'r') as f:
    content = f.read()

nav_replacement = """      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (index) {
            setState(() {
              _currentTab = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: brandPrimary,
          unselectedItemColor: Colors.grey.shade500,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined, size: 26),
              activeIcon: Icon(Icons.home_rounded, size: 26),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.access_time_rounded, size: 26),
              activeIcon: Icon(Icons.access_time_filled_rounded, size: 26),
              label: 'Recents',
            ),
            BottomNavigationBarItem(
              icon: _buildIconWithBadge(Icons.chat_bubble_outline_rounded, _unreadCount > 0 ? (_unreadCount > 99 ? '99+' : _unreadCount.toString()) : ''),
              activeIcon: _buildIconWithBadge(Icons.chat_bubble_rounded, _unreadCount > 0 ? (_unreadCount > 99 ? '99+' : _unreadCount.toString()) : '', isActive: true),
              label: 'Chat',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded, size: 26),
              activeIcon: Icon(Icons.person_rounded, size: 26),
              label: 'Profile',
            ),
          ],
        ),
      ),"""

# Regex to find bottomNavigationBar: SafeArea(...)
pattern = re.compile(r'bottomNavigationBar:\s*SafeArea\([\s\S]*?Closes SafeArea\n', re.MULTILINE)

content = pattern.sub(nav_replacement + '\n', content)

# Now inject _buildIconWithBadge method just before widget build(BuildContext context)
badge_method = """  Widget _buildIconWithBadge(IconData icon, String count, {bool isActive = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 26),
        if (count.isNotEmpty)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                count,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override"""

content = content.replace('  @override\n  Widget build(BuildContext context)', badge_method + '\n  Widget build(BuildContext context)')

with open('lib/screens/male_dashboard_screen.dart', 'w') as f:
    f.write(content)
