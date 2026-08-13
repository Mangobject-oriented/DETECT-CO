import 'package:flutter/material.dart';

class EvacuateTab extends StatelessWidget {
  const EvacuateTab({super.key});

  // =====================================================
  // FLOATING BURGER MENU
  // =====================================================

  void _showMenu(BuildContext menuContext) {
    final RenderBox button =
        menuContext.findRenderObject() as RenderBox;

    final RenderBox overlay =
        Overlay.of(menuContext)
            .context
            .findRenderObject() as RenderBox;

    final Offset position = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    showMenu<String>(
      context: menuContext,

      // =================================================
      // POSITION MENU UNDERNEATH BURGER BUTTON
      // =================================================

      position: RelativeRect.fromLTRB(
        position.dx - 155,
        position.dy + 48,
        overlay.size.width -
            position.dx -
            button.size.width,
        0,
      ),

      color: Colors.white,
      elevation: 8,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),

      // =================================================
      // MENU ITEMS
      // =================================================

      items: [
        // ===============================================
        // HOW TO USE
        // ===============================================

        PopupMenuItem<String>(
          value: 'how_to_use',
          height: 52,
          child: Row(
            children: const [
              Icon(
                Icons.help,
                color: Color(0xFF1D2B4A),
                size: 22,
              ),

              SizedBox(width: 12),

              Text(
                'How to Use',
                style: TextStyle(
                  color: Color(0xFF1D2B4A),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        // ===============================================
        // TERMS OF SERVICE
        // ===============================================

        PopupMenuItem<String>(
          value: 'terms',
          height: 52,
          child: Row(
            children: const [
              Icon(
                Icons.description,
                color: Color(0xFF1D2B4A),
                size: 22,
              ),

              SizedBox(width: 12),

              Text(
                'Terms of Service',
                style: TextStyle(
                  color: Color(0xFF1D2B4A),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        // ===============================================
        // ABOUT APP
        // ===============================================

        PopupMenuItem<String>(
          value: 'about',
          height: 52,
          child: Row(
            children: const [
              Icon(
                Icons.info,
                color: Color(0xFF1D2B4A),
                size: 22,
              ),

              SizedBox(width: 12),

              Text(
                'About app',
                style: TextStyle(
                  color: Color(0xFF1D2B4A),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'how_to_use') {
        // TODO:
        // Navigator.push(
        //   context,
        //   MaterialPageRoute(
        //     builder: (_) => const HowToUsePage(),
        //   ),
        // );
      }

      if (value == 'terms') {
        // TODO:
        // Navigator.push(
        //   context,
        //   MaterialPageRoute(
        //     builder: (_) => const TermsPage(),
        //   ),
        // );
      }

      if (value == 'about') {
        // TODO:
        // Navigator.push(
        //   context,
        //   MaterialPageRoute(
        //     builder: (_) => const AboutPage(),
        //   ),
        // );
      }
    });
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: Column(
        children: [
          // =================================================
          // HEADER
          // =================================================

          Container(
            width: double.infinity,

            color: const Color.fromARGB(
              255,
              72,
              119,
              247,
            ),

            child: SafeArea(
              bottom: false,

              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),

                child: Row(
                  children: [
                    // =======================================
                    // LOGO
                    // =======================================

                    GestureDetector(
                      child: SizedBox(
                        width: 50,
                        height: 50,

                        child: Image.asset(
                          "assets/icon/detect-co_logo.png",
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // =======================================
                    // APP NAME
                    // =======================================

                    const Text(
                      'DETECT-CO',

                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const Spacer(),

                    // =======================================
                    // NOTIFICATION
                    // =======================================

                    IconButton(
                      icon: const Icon(
                        Icons.notifications_none,
                        color: Colors.white,
                        size: 28,
                      ),

                      onPressed: () {},
                    ),

                    // =======================================
                    // BURGER MENU
                    // =======================================

                    Builder(
                      builder: (menuContext) {
                        return IconButton(
                          icon: const Icon(
                            Icons.menu,
                            color: Colors.white,
                            size: 30,
                          ),

                          onPressed: () {
                            _showMenu(menuContext);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}
