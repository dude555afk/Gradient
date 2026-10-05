import 'package:flutter/material.dart';

import '../../core/models/model_router.dart';
import '../../core/settings/app_settings.dart';

class ModelsRoutingPage extends StatefulWidget {
  const ModelsRoutingPage({super.key});

  @override
  State<ModelsRoutingPage> createState() => _ModelsRoutingPageState();
}

class _ModelsRoutingPageState extends State<ModelsRoutingPage> {
  final _store = AppSettingsStore();
  final Map<ModelRole, TextEditingController> _primary = {};
  final Map<ModelRole, TextEditingController> _fallback = {};
  final Map<ModelRole, String> _effort = {};
  final Map<ModelRole, bool> _web = {};

  List<String> _models = const [];
  AiSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _preferFree = true;
  double _historyLimit = 20;

  @override
  void initState() {
    super.initState();
    for (final role in ModelRole.values) {
      _primary[role] = TextEditingController();
      _fallback[role] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    final settings = await _store.load();
    final models = await _store.cachedModels();
    if (!mounted) return;

    for (final role in ModelRole.values) {
      _primary[role]!.text = settings.primaryModelFor(role);
      _fallback[role]!.text =
          (settings.fallbackModels[role.key] ?? const <String>[]).join(', ');
      _effort[role] =
          settings.roleReasoningEffort[role.key]?.trim() ?? '';
      _web[role] = settings.webEnabledFor(role);
    }

    setState(() {
      _settings = settings;
      _models = models;
      _preferFree = settings.preferFreeModels;
      _historyLimit = settings.maxHistoryMessages.toDouble();
      _loading = false;
    });
  }

  Future<void> _save() async {
    final current = _settings;
    if (current == null || _saving) return;
    setState(() => _saving = true);

    final fallbacks = <String, List<String>>{};
    final efforts = <String, String>{};
    final roleWeb = <String, bool>{};

    for (final role in ModelRole.values) {
      final values = _fallback[role]!
          .text
          .split(RegExp(r'[,\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (values.isNotEmpty) fallbacks[role.key] = values;

      final effort = (_effort[role] ?? '').trim();
      if (effort.isNotEmpty) efforts[role.key] = effort;
      roleWeb[role.key] = _web[role] ?? true;
    }

    final next = current.copyWith(
      defaultModel: _primary[ModelRole.general]!.text,
      fastModel: _primary[ModelRole.fast]!.text,
      codingModel: _primary[ModelRole.coding]!.text,
      debuggingModel: _primary[ModelRole.debugging]!.text,
      reasoningModel: _primary[ModelRole.reasoning]!.text,
      searchModel: _primary[ModelRole.research]!.text,
      visionModel: _primary[ModelRole.vision]!.text,
      ocrModel: _primary[ModelRole.ocr]!.text,
      reviewerModel: _primary[ModelRole.reviewer]!.text,
      explainerModel: _primary[ModelRole.explainer]!.text,
      fallbackModels: fallbacks,
      roleReasoningEffort: efforts,
      roleWebEnabled: roleWeb,
      maxHistoryMessages: _historyLimit.round(),
      preferFreeModels: _preferFree,
    );

    await _store.save(next);
    if (!mounted) return;
    setState(() {
      _settings = next;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model routing saved')),
    );
  }

  Future<void> _pickModel(
    ModelRole role, {
    required bool primary,
  }) async {
    if (_models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fetch models from AI Provider settings first.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RoutingModelPicker(
        models: _models,
        title: primary
            ? 'Primary ${role.label} model'
            : 'Add ${role.label} fallback',
      ),
    );
    if (selected == null || !mounted) return;

    if (primary) {
      setState(() => _primary[role]!.text = selected);
      return;
    }

    final current = _fallback[role]!
        .text
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (!current.contains(selected)) current.add(selected);
    setState(() => _fallback[role]!.text = current.join(', '));
  }

  String _description(ModelRole role) => switch (role) {
        ModelRole.general => 'Normal chat and uncategorized requests',
        ModelRole.fast => 'Titles, tiny requests, and cheap quick work',
        ModelRole.coding => 'Implementation, refactors, and code changes',
        ModelRole.debugging => 'Crashes, CI failures, logs, and root causes',
        ModelRole.reasoning => 'Architecture, planning, and hard analysis',
        ModelRole.research => 'Web research, docs, and fresh information',
        ModelRole.vision => 'Screenshots and visual understanding',
        ModelRole.ocr => 'Reading and extracting text from images',
        ModelRole.reviewer => 'Code review, security, and regression checks',
        ModelRole.explainer => 'Teaching, summaries, and repo explanations',
      };

  IconData _icon(ModelRole role) => switch (role) {
        ModelRole.general => Icons.chat_bubble_outline_rounded,
        ModelRole.fast => Icons.bolt_rounded,
        ModelRole.coding => Icons.code_rounded,
        ModelRole.debugging => Icons.bug_report_outlined,
        ModelRole.reasoning => Icons.psychology_alt_rounded,
        ModelRole.research => Icons.travel_explore_rounded,
        ModelRole.vision => Icons.visibility_outlined,
        ModelRole.ocr => Icons.document_scanner_outlined,
        ModelRole.reviewer => Icons.fact_check_outlined,
        ModelRole.explainer => Icons.school_outlined,
      };

  @override
  void dispose() {
    for (final controller in [..._primary.values, ..._fallback.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Models & routing'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 36),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _preferFree,
                  onChanged: (value) => setState(() => _preferFree = value),
                  secondary: const Icon(Icons.savings_outlined),
                  title: const Text('Prefer free fallbacks'),
                  subtitle: const Text(
                    'Keeps your selected primary first, then prefers free models in the fallback chain.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Context history'),
                  subtitle: Text('${_historyLimit.round()} recent messages'),
                ),
                Slider(
                  value: _historyLimit,
                  min: 4,
                  max: 80,
                  divisions: 19,
                  label: _historyLimit.round().toString(),
                  onChanged: (value) =>
                      setState(() => _historyLimit = value),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final role in ModelRole.values) ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: Icon(_icon(role)),
                title: Text(
                  role.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_description(role)),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  TextField(
                    controller: _primary[role],
                    decoration: InputDecoration(
                      labelText: 'Primary model',
                      suffixIcon: IconButton(
                        tooltip: 'Choose model',
                        icon: const Icon(Icons.expand_more_rounded),
                        onPressed: () => _pickModel(role, primary: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _fallback[role],
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Fallback models',
                      helperText: 'Ordered, comma separated',
                      suffixIcon: IconButton(
                        tooltip: 'Add fallback',
                        icon: const Icon(Icons.add_rounded),
                        onPressed: () => _pickModel(role, primary: false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _effort[role] ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Reasoning effort',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: '',
                        child: Text('Use global default'),
                      ),
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                    ],
                    onChanged: (value) =>
                        setState(() => _effort[role] = value ?? ''),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _web[role] ?? true,
                    onChanged: (value) =>
                        setState(() => _web[role] = value),
                    secondary: const Icon(Icons.public_rounded),
                    title: const Text('Allow web tools'),
                    subtitle: const Text(
                      'This role can use search/open when the chat Web toggle is on.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _RoutingModelPicker extends StatefulWidget {
  const _RoutingModelPicker({
    required this.models,
    required this.title,
  });

  final List<String> models;
  final String title;

  @override
  State<_RoutingModelPicker> createState() => _RoutingModelPickerState();
}

class _RoutingModelPickerState extends State<_RoutingModelPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? widget.models
        : widget.models
            .where((model) => model.toLowerCase().contains(query))
            .toList(growable: false);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SearchBar(
                controller: _search,
                hintText: 'Search models',
                leading: const Icon(Icons.search_rounded),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final model = visible[index];
                  return ListTile(
                    leading: Icon(
                      model.toLowerCase().contains(':free')
                          ? Icons.savings_outlined
                          : Icons.memory_rounded,
                    ),
                    title: Text(model),
                    onTap: () => Navigator.pop(context, model),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
