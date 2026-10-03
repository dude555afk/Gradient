import 'package:flutter/material.dart';

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

  String _reasoningEffort = '';
  bool _loading = true;
  bool _saving = false;
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
          TextField(
            controller: _defaultModel,
            decoration: const InputDecoration(
              labelText: 'Default model',
              hintText: 'provider/model-name',
              border: OutlineInputBorder(),
            ),
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

  Widget _modelField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
