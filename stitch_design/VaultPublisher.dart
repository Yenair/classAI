import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A production-ready Flutter implementation of the ClassAI Vault Publisher.
/// This widget follows the modern corporate design system optimized for
/// the Nigerian educational landscape.
class VaultPublisherPage extends StatefulWidget {
  const VaultPublisherPage({super.key});

  @override
  State<VaultPublisherPage> createState() => _VaultPublisherPageState();
}

class _VaultPublisherPageState extends State<VaultPublisherPage> {
  final _formKey = GlobalKey<FormState>();
  int _currentIndex = 3; // Vault is active

  @override
  Widget build(BuildContext context) {
    // Custom Theme Colors mapping from ClassAI design system
    final theme = Theme.of(context);
    const primaryColor = Color(0xFF115B9B);
    const secondaryColor = Color(0xFF4B53BA);
    const backgroundColor = Color(0xFFF8F9FF);
    const surfaceColorLow = Color(0xFFF2F3F9);
    const outlineColor = Color(0xFF727781);
    const errorColor = Color(0xFFBA1A1A);

    return Scaffold(
      backgroundColor: backgroundColor,
      // Desktop-style sidebar or Mobile Drawer can be handled via LayoutBuilder
      // For this widget, we implement a standard responsive structure
      appBar: MediaQuery.of(context).size.width < 900
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    child:
                        const Icon(Icons.person, size: 20, color: outlineColor),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'ClassAI',
                    style: GoogleFonts.openSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '₦500',
                        style: GoogleFonts.openSans(
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      body: Row(
        children: [
          // Navigation Drawer for Tablet/Desktop
          if (MediaQuery.of(context).size.width >= 900)
            const _NavigationDrawer(),

          // Main Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(primaryColor),
                      const SizedBox(height: 32),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth > 700) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    flex: 2,
                                    child: _buildMainForm(
                                        surfaceColorLow, primaryColor)),
                                const SizedBox(width: 24),
                                Expanded(
                                    flex: 1,
                                    child: _buildRecentSubmissions(
                                        surfaceColorLow, primaryColor)),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              _buildMainForm(surfaceColorLow, primaryColor),
                              const SizedBox(height: 24),
                              _buildRecentSubmissions(
                                  surfaceColorLow, primaryColor),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 48),
                      _buildFooter(outlineColor),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 900
          ? _CustomBottomNavBar(currentIndex: _currentIndex)
          : null,
    );
  }

  Widget _buildHeader(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vault Publisher',
          style: GoogleFonts.openSans(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Publish academic resources to the national curriculum repository.',
          style: GoogleFonts.albertSans(
            fontSize: 18,
            color: const Color(0xFF414750),
          ),
        ),
      ],
    );
  }

  Widget _buildMainForm(Color bg, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('Resource Title'),
            _buildTextField('e.g., SS2 Biology Term 1 Notes'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('Subject'),
                      _buildDropdown('Select subject...'),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('Class Level'),
                      _buildDropdown('Select class...'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildFieldLabel('Description'),
            _buildTextField('Provide a brief overview...', minLines: 3),
            const SizedBox(height: 20),
            _buildFieldLabel('Resource Content'),
            _buildUploadArea(primaryColor),
            const SizedBox(height: 20),
            _buildFieldLabel('Cover Image (Optional)'),
            _buildImagePicker(primaryColor),
            const SizedBox(height: 32),
            _buildActions(primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        label,
        style: GoogleFonts.openSans(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black.withOpacity(0.8),
        ),
      ),
    );
  }

  Widget _buildTextField(String hint, {int minLines = 1}) {
    return TextFormField(
      maxLines: minLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildDropdown(String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(hint, style: TextStyle(color: Colors.grey[400])),
          const Icon(Icons.expand_more, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildUploadArea(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: Colors.grey[300]!,
            style:
                BorderStyle.none), // Should be dashed in production via painter
      ),
      // For demonstration, using simple container with border
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: Colors.grey[300]!,
              style:
                  BorderStyle.solid), // Dash effect ignored for standard widget
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.upload_file, size: 32, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'Tap to upload PDF or Document',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Supports .pdf, .docx, .ppt (Max 10MB)',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.image, color: Colors.grey[300], size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor, width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Choose Image'),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.error_outline, size: 14, color: Colors.red),
                    SizedBox(width: 4),
                    Text(
                      'Strict limit: 50KB for remote school access.',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.send),
          label: const Text('Publish to Vault'),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: const StadiumBorder(),
            elevation: 8,
            shadowColor: primaryColor.withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSubmissions(Color bg, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                'Recent Submissions',
                style: GoogleFonts.openSans(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _StatusCard(
            title: 'SS1 Chemistry Practicals',
            status: 'Pending',
            date: 'Today, 09:45 AM',
          ),
          const SizedBox(height: 12),
          const _StatusCard(
            title: 'JSS3 Math Revision Guide',
            status: 'Approved',
            date: 'Yesterday',
          ),
          const SizedBox(height: 12),
          const _StatusCard(
            title: 'English Essay Topics',
            status: 'Rejected',
            date: 'Oct 12',
            error: 'Image size exceeds 50KB limit.',
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(Color outlineColor) {
    return Center(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'EmergencyFlushService: Background Sync Active',
                style: TextStyle(
                    color: outlineColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Support classes follow in actual implementation...
class _StatusCard extends StatelessWidget {
  final String title;
  final String status;
  final String date;
  final String? error;

  const _StatusCard(
      {required this.title,
      required this.status,
      required this.date,
      this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        overflow: TextOverflow.ellipsis)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                        radius: 3,
                        backgroundColor: status == 'Approved'
                            ? Colors.green
                            : (status == 'Rejected'
                                ? Colors.red
                                : Colors.grey)),
                    const SizedBox(width: 6),
                    Text(status,
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          if (error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(error!,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.red,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: const Color(0xFFF2F3F9),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ClassAI',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF115B9B))),
                Text('Nigerian Academic Partner',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const _DrawerItem(icon: Icons.home_outlined, label: 'Home'),
          const _DrawerItem(icon: Icons.book_outlined, label: 'Lessons'),
          const _DrawerItem(icon: Icons.quiz_outlined, label: 'Exams'),
          const _DrawerItem(
              icon: Icons.inventory_2, label: 'Vault', active: true),
          const _DrawerItem(
              icon: Icons.admin_panel_settings_outlined, label: 'Admin'),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _DrawerItem(
      {required this.icon, required this.label, this.active = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE0E0FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        children: [
          Icon(icon,
              color: active ? const Color(0xFF00026C) : Colors.grey[700],
              weight: active ? 700 : 400),
          const SizedBox(width: 16),
          Text(label,
              style: TextStyle(
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? const Color(0xFF00026C) : Colors.grey[700])),
        ],
      ),
    );
  }
}

class _CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  const _CustomBottomNavBar({required this.currentIndex});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavBarItem(icon: Icons.home_outlined, label: 'Home'),
          _NavBarItem(icon: Icons.book_outlined, label: 'Lessons'),
          _NavBarItem(icon: Icons.quiz_outlined, label: 'Exams'),
          _NavBarItem(icon: Icons.inventory_2, label: 'Vault', active: true),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _NavBarItem(
      {required this.icon, required this.label, this.active = false});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding:
              EdgeInsets.symmetric(horizontal: active ? 20 : 0, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8C94FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: active ? Colors.white : Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}
