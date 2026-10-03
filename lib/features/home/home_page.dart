import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/agent/task_router.dart';
import '../workspace/github_workspace_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _router = const TaskRouter();
  String _modelLabel = 'Auto';
  bool _webEnabled = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final route = _router.route(text);
    setState(() => _modelLabel = route.model.label);
    _controller.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Routed to ${route.model.label} • ${route.skills.map((e) => e.name).join(', ')}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const _GradientDrawer(),
      extendBodyBehindAppBar: true,
      appBar: const _FloatingTopBar(),
      body: SafeArea(
        child: Stack(
          children: [
            const _EmptyState(),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Composer(
                controller: _controller,
                webEnabled: _webEnabled,
                modelLabel: _modelLabel,
                onToggleWeb: () => setState(() => _webEnabled = !_webEnabled),
                onSend: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _FloatingTopBar();

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: cs.surfaceContainer.withValues(alpha: .80),
              child: SizedBox(
                height: 50,
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Menu',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gradient',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Remote coding',
                            style: TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'GitHub workspace',
                      onPressed: null,
                      icon: Icon(Icons.call_split_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 150),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.gradient_rounded, size: 28),
            ),
            const SizedBox(height: 20),
            const Text(
              'What are we building?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Open a repo, inspect a workflow, or ask Gradient to fix something remotely.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _PromptChip('Fix workflow'),
                _PromptChip('Review PR'),
                _PromptChip('Explain repo'),
                _PromptChip('Search docs'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.webEnabled,
    required this.modelLabel,
    required this.onToggleWeb,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool webEnabled;
  final String modelLabel;
  final VoidCallback onToggleWeb;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            elevation: 2,
            color: cs.surfaceContainerHigh.withValues(alpha: .91),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Ask Gradient…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Attach',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {},
                        icon: const Icon(Icons.add_rounded),
                      ),
                      FilterChip(
                        label: const Text('Web'),
                        selected: webEnabled,
                        onSelected: (_) => onToggleWeb(),
                        avatar: const Icon(Icons.public_rounded, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                      Chip(
                        label: Text(modelLabel),
                        avatar: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                        ),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: onSend,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientDrawer extends StatelessWidget {
  const _GradientDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width * .78,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.gradient_rounded),
              title: const Text(
                'Gradient',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () {},
                icon: const Icon(Icons.add_rounded),
                label: const Text('New task'),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('GitHub workspace'),
              subtitle: const Text('Browse repositories remotely'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GitHubWorkspacePage(),
                  ),
                );
              },
            ),
            const Divider(),
            const Expanded(
              child: Center(
                child: Text(
                  'Task history will live here',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
