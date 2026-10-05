import 'package:flutter/material.dart';

import '../../core/ai/provider_model_catalog.dart';
import '../../core/gh/gh_auth_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/update/update_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _store = AppSettingsStore();

  final _baseUrl = TextEditingController();
  final _defaultModel = TextEditingController();
  final _fastModel = TextEditingController();
  final _codingModel = TextEditingController();
  final _reasoningModel = TextEditingController();
  final _searchModel = TextEditingController();
  final _visionModel = TextEditingController();
  final _reviewerModel = TextEditingController();
  final _apiKey = TextEditingController();
  final _githubToken = TextEditingController();

  List<ProviderModel> _models = const [];
  String _reasoningEffort = '';
  bool _loading = true;
  bool _saving = false;
  bool _fetchingModels = false;
  bool _connecting = false;
  bool _githubConnected = false;
  String? _deviceCode;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  double? _downloadProgress;
  GradientUpdateStatus? _updateStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _store.load();
    final apiKey = await _store.apiKey();
    final githubToken = await _store.githubToken();
    final cachedModels = await _store.cachedModels();

    if (!mounted) return;
    _baseUrl.text = settings.baseUrl;
    _defaultModel.text = settings.defaultModel;
    _fastModel.text = settings.fastModel;
    _codingModel.text = settings.codingModel;
    _reasoningModel.text = settings.reasoningModel;
    _searchModel.text = settings.searchModel;
    _visionModel.text = settings.visionModel;
    _reviewerModel.text = settings.reviewerModel;
    _apiKey.text = apiKey;

    setState(() {
      _models = cachedModels
          .map((id) => ProviderModel(id: id, displayName: id))
          .toList(growable: false);
      _reasoningEffort = settings.reasoningEffort;
      _githubConnected = githubToken.isNotEmpty;
      _loading = false;
    });
  }

  AiSettings _settingsFromForm() {
    return AiSettings(
      baseUrl: _baseUrl.text,
      defaultModel: _defaultModel.text,
      fastModel: _fastModel.text,
      codingModel: _codingModel.text,
      reasoningModel: _reasoningModel.text,
      searchModel: _searchModel.text,
      visionModel: _visionModel.text,
      reviewerModel: _reviewerModel.text,
      reasoningEffort: _reasoningEffort,
      githubClientId: '',
    );
  }

  Future<void> _fetchModels() async {
    if (_fetchingModels) return;

    setState(() => _fetchingModels = true);
    final catalog = ProviderModelCatalog(
      baseUrl: _baseUrl.text,
      apiKey: _apiKey.text,
    );

    try {
      final models = await catalog.fetchModels();
      await _store.saveCachedModels(models.map((e) => e.id));

      if (!mounted) return;
      setState(() => _models = models);

      if (models.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Provider returned no models. Check the endpoint or API key.',
            ),
          ),
        );
        return;
      }

      await _pickModel(
        controller: _defaultModel,
        title: 'Choose default model',
        allowClear: false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      catalog.dispose();
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Future<void> _pickModel({
    required TextEditingController controller,
    required String title,
    required bool allowClear,
  }) async {
    if (_models.isEmpty) {
      await _fetchModels();
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ModelPickerSheet(
        title: title,
        models: _models,
        current: controller.text.trim(),
        allowClear: allowClear,
      ),
    );

    if (selected == null || !mounted) return;
    setState(() => controller.text = selected);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _store.save(_settingsFromForm());
      await _store.setApiKey(_apiKey.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePersonalToken() async {
    final token = _githubToken.text.trim();
    if (token.isEmpty) return;
    await _store.setGithubToken(token);
    _githubToken.clear();
    if (!mounted) return;
    setState(() => _githubConnected = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GitHub token stored securely')),
    );
  }

  Future<void> _connectWithGitHub() async {
    await _store.save(_settingsFromForm());
    setState(() {
      _connecting = true;
      _deviceCode = null;
    });

    final auth = GhAuthService();
    try {
      final token = await auth.login(
        onPrompt: (prompt) {
          if (!mounted || prompt.code.isEmpty) return;
          setState(() => _deviceCode = prompt.code);
        },
      );
      await _store.setGithubToken(token);

      if (!mounted) return;
      setState(() {
        _githubConnected = true;
        _deviceCode = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GitHub connected through gh CLI')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      auth.cancel();
      if (mounted) {
        setState(() {
          _connecting = false;
          _deviceCode = null;
        });
      }
    }
  }

  Future<void> _disconnectGitHub() async {
    await _store.clearGithubToken();
    if (!mounted) return;
    setState(() => _githubConnected = false);
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;

    setState(() => _checkingUpdate = true);
    final service = GradientUpdateService();

    try {
      final status = await service.check();
      if (!mounted) return;
      setState(() => _updateStatus = status);

      if (!status.updateAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gradient is up to date • '
              '${status.currentVersionName}+${status.currentVersionCode}',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      service.dispose();
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _downloadUpdate() async {
    final info = _updateStatus?.latest;
    if (info == null || info.apkUrl.isEmpty || _downloadingUpdate) return;

    setState(() {
      _downloadingUpdate = true;
      _downloadProgress = 0;
    });
    final service = GradientUpdateService();

    try {
      final result = await service.downloadAndInstall(
        info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = total == null || total <= 0
                ? null
                : (received / total).clamp(0.0, 1.0);
          });
        },
      );

      if (!mounted) return;
      if (result == 'permission_requested') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow Gradient to install updates once. The Android installer will open when you return.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      service.dispose();
      if (mounted) {
        setState(() {
          _downloadingUpdate = false;
          _downloadProgress = null;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _baseUrl,
      _defaultModel,
      _fastModel,
      _codingModel,
      _reasoningModel,
      _searchModel,
      _visionModel,
      _reviewerModel,
      _apiKey,
      _githubToken,
    ]) {
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

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
        children: [
          _sectionCard(
            icon: Icons.auto_awesome_rounded,
            title: 'AI provider',
            subtitle: 'Models, endpoint, and reasoning',
            children: [
              TextField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'OpenAI-compatible base URL',
                  hintText: 'https://openrouter.ai/api/v1',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  helperText: 'Optional for anonymous/custom providers.',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _fetchingModels ? null : _fetchModels,
                  icon: _fetchingModels
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_rounded),
                  label: Text(
                    _fetchingModels
                        ? 'Fetching models…'
                        : _models.isEmpty
                            ? 'Fetch models'
                            : 'Refresh models (${_models.length})',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _modelField(
                _defaultModel,
                'Default model',
                allowClear: false,
              ),
              DropdownButtonFormField<String>(
                initialValue: _reasoningEffort,
                decoration: const InputDecoration(
                  labelText: 'Reasoning effort',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.psychology_alt_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Provider default'),
                  ),
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (value) {
                  setState(() => _reasoningEffort = value ?? '');
                },
              ),
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4),
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Role-specific models'),
                subtitle: const Text(
                  'Optional overrides for faster or specialized tasks.',
                ),
                children: [
                  _modelField(_fastModel, 'Fast / title model'),
                  _modelField(_codingModel, 'Coding model'),
                  _modelField(_reasoningModel, 'Reasoning model'),
                  _modelField(_searchModel, 'Search model'),
                  _modelField(_visionModel, 'Vision model'),
                  _modelField(_reviewerModel, 'Reviewer model'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _sectionCard(
            icon: Icons.code_rounded,
            title: 'GitHub',
            subtitle: _githubConnected
                ? 'Connected through the bundled gh CLI'
                : 'Connect Gradient to your GitHub account',
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _githubConnected
                      ? cs.primaryContainer.withValues(alpha: .45)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: Icon(
                    _githubConnected
                        ? Icons.verified_rounded
                        : Icons.link_off_rounded,
                  ),
                  title: Text(
                    _githubConnected ? 'Connected' : 'Not connected',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _githubConnected
                        ? 'GitHub operations run through gh. Your token stays in Android secure storage.'
                        : 'Connect once to use repositories, Actions, issues, PRs, and the agent.',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (!_githubConnected)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _connecting ? null : _connectWithGitHub,
                    icon: _connecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(
                      _connecting
                          ? 'Waiting for GitHub…'
                          : 'Connect with GitHub',
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _connecting ? null : _connectWithGitHub,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Reconnect'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _disconnectGitHub,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Disconnect'),
                    ),
                  ],
                ),
              if (_deviceCode != null) ...[
                const SizedBox(height: 8),
                Card.filled(
                  child: ListTile(
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('Enter this code on GitHub'),
                    subtitle: SelectableText(
                      _deviceCode!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.password_rounded),
                title: const Text('Personal access token fallback'),
                subtitle: const Text(
                  'Only needed if browser login is unavailable.',
                ),
                children: [
                  TextField(
                    controller: _githubToken,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'GitHub token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: _savePersonalToken,
                      child: const Text('Store token'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _sectionCard(
            icon: Icons.system_update_alt_rounded,
            title: 'Updates',
            subtitle: 'Signed Gradient update channel',
            children: [
              Text(
                _updateStatus == null
                    ? 'Check for a newer signed build. Gradient downloads it privately and opens Android’s updater directly.'
                    : _updateStatus!.updateAvailable
                        ? 'Gradient ${_updateStatus!.latest.versionName} '
                            '(${_updateStatus!.latest.versionCode}) is ready.'
                        : 'Gradient ${_updateStatus!.currentVersionName} '
                            '(${_updateStatus!.currentVersionCode}) is up to date.',
              ),
              if (_downloadingUpdate) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _downloadProgress),
                const SizedBox(height: 6),
                Text(
                  _downloadProgress == null
                      ? 'Downloading update…'
                      : 'Downloading… ${(_downloadProgress! * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _updateStatus?.updateAvailable == true
                    ? FilledButton.icon(
                        onPressed:
                            _downloadingUpdate ? null : _downloadUpdate,
                        icon: _downloadingUpdate
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.install_mobile_rounded),
                        label: Text(
                          _downloadingUpdate
                              ? 'Preparing update…'
                              : 'Download & install',
                        ),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: _checkingUpdate
                            ? null
                            : _checkForUpdates,
                        icon: _checkingUpdate
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(
                          _checkingUpdate
                              ? 'Checking…'
                              : 'Check for updates',
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                'Android still requires the final system “Update” confirmation. '
                'On the first in-app update, Android may also ask you to allow '
                'Gradient as an install source.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _modelField(
    TextEditingController controller,
    String label, {
    bool allowClear = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: _models.isEmpty
              ? 'Fetch models or type a model ID'
              : 'Choose from ${_models.length} fetched models',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Choose fetched model',
            onPressed: () => _pickModel(
              controller: controller,
              title: 'Choose $label',
              allowClear: allowClear,
            ),
            icon: const Icon(Icons.expand_more_rounded),
          ),
        ),
      ),
    );
  }
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.title,
    required this.models,
    required this.current,
    required this.allowClear,
  });

  final String title;
  final List<ProviderModel> models;
  final String current;
  final bool allowClear;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _search
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.models
        : widget.models
            .where(
              (model) =>
                  model.id.toLowerCase().contains(q) ||
                  model.displayName.toLowerCase().contains(q),
            )
            .toList(growable: false);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('${widget.models.length} models'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SearchBar(
                controller: _search,
                hintText: 'Search model IDs',
                leading: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (widget.allowClear)
                    ListTile(
                      leading: const Icon(Icons.restart_alt_rounded),
                      title: const Text('Use default model'),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  for (final model in visible)
                    ListTile(
                      leading: Icon(
                        model.id == widget.current
                            ? Icons.check_circle_rounded
                            : Icons.memory_rounded,
                      ),
                      title: Text(model.displayName),
                      subtitle: model.displayName == model.id
                          ? null
                          : Text(
                              model.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.pop(context, model.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
