import 'package:flutter/material.dart';

import '../../core/ai/provider_model_catalog.dart';
import '../../core/github/github_auth_service.dart';
import '../../core/settings/app_settings.dart';

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
  final _githubClientId = TextEditingController();
  final _githubToken = TextEditingController();

  List<ProviderModel> _models = const [];
  String _reasoningEffort = '';
  bool _loading = true;
  bool _saving = false;
  bool _fetchingModels = false;
  bool _connecting = false;
  bool _githubConnected = false;
  String? _deviceCode;

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
    _githubClientId.text = settings.githubClientId;
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
      githubClientId: _githubClientId.text,
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
    final clientId = _githubClientId.text.trim();
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add your GitHub OAuth App client ID first.'),
        ),
      );
      return;
    }

    await _store.save(_settingsFromForm());
    setState(() {
      _connecting = true;
      _deviceCode = null;
    });

    final auth = GitHubAuthService();
    try {
      final code = await auth.requestDeviceCode(clientId);
      if (!mounted) return;
      setState(() => _deviceCode = code.userCode);
      await auth.openVerification(code);
      final token = await auth.pollForToken(
        clientId: clientId,
        code: code,
      );
      await _store.setGithubToken(token);

      if (!mounted) return;
      setState(() {
        _githubConnected = true;
        _deviceCode = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GitHub connected')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      auth.dispose();
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
      _githubClientId,
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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(
            'AI provider',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: 'OpenAI-compatible base URL',
              hintText: 'https://openrouter.ai/api/v1',
              border: OutlineInputBorder(),
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
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
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
                      : 'Fetch models again (${_models.length})',
            ),
          ),
          const SizedBox(height: 10),
          _modelField(
            _defaultModel,
            'Default model',
            allowClear: false,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _reasoningEffort,
            decoration: const InputDecoration(
              labelText: 'Reasoning effort',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Provider default')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'high', child: Text('High')),
            ],
            onChanged: (value) {
              setState(() => _reasoningEffort = value ?? '');
            },
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Role-specific models'),
            subtitle: const Text(
              'Optional. Empty roles fall back to the default model.',
            ),
            children: [
              _modelField(_fastModel, 'Fast model'),
              _modelField(_codingModel, 'Coding model'),
              _modelField(_reasoningModel, 'Reasoning model'),
              _modelField(_searchModel, 'Search model'),
              _modelField(_visionModel, 'Vision model'),
              _modelField(_reviewerModel, 'Reviewer model'),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'GitHub',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _githubConnected
                  ? Icons.verified_rounded
                  : Icons.link_off_rounded,
            ),
            title: Text(
              _githubConnected ? 'Connected' : 'Not connected',
            ),
            subtitle: const Text(
              'Tokens are stored with Android secure storage.',
            ),
          ),
          TextField(
            controller: _githubClientId,
            decoration: const InputDecoration(
              labelText: 'GitHub OAuth App client ID',
              helperText:
                  'Device flow must be enabled on the OAuth App. No client secret is stored.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _connecting ? null : _connectWithGitHub,
            icon: _connecting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(
              _connecting ? 'Waiting for GitHub…' : 'Connect with GitHub',
            ),
          ),
          if (_deviceCode != null) ...[
            const SizedBox(height: 8),
            Card(
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
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Personal access token fallback'),
            subtitle: const Text(
              'Useful for testing before creating an OAuth App.',
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
          if (_githubConnected)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _disconnectGitHub,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Disconnect GitHub'),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save settings'),
          ),
        ],
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
