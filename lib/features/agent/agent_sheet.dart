import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/agent/agent_models.dart';
import '../../core/agent/agent_task_coordinator.dart';
import '../../core/agent/agent_session_store.dart';
import '../../core/ai/openai_compatible_provider.dart';
import '../../core/diff/simple_diff.dart';
import '../../core/gh/gh_backend.dart';
import '../../core/models/model_router.dart';
import '../../core/settings/app_settings.dart';
import '../../core/workspace/workspace_store.dart';
import '../../shared/gradient_markdown.dart';
import 'kelivo_chat_widgets.dart';

class AgentSheet extends StatefulWidget {
  const AgentSheet({
    super.key,
    required this.workspace,
    this.contextText = '',
  });

  final WorkspaceSelection workspace;
  final String contextText;

  @override
  State<AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<AgentSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _settings = AppSettingsStore();
  final _sessionStore = AgentSessionStore();
  final _taskCoordinator = AgentTaskCoordinator.instance;
  final _imagePicker = ImagePicker();

  final _messages = <AgentMessage>[];
  final _changes = <PendingFileChange>[];
  final _pullRequests = <PendingPullRequest>[];
  final _progress = <AgentProgressEvent>[];
  final _pendingImages = <_PendingImage>[];

  AgentConversation? _conversation;
  String? _taskBranch;
  final _streamingNotifier = ValueNotifier<String>('');
  ValueListenable<AgentTaskSnapshot>? _taskListenable;
  VoidCallback? _taskListener;
  bool _scrollTickPending = false;
  bool _titleGenerationInFlight = false;
  bool _busy = false;
  bool _applying = false;
  bool _webEnabled = true;
  ModelRole? _roleOverride;
  bool _loadingSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    var conversation =
        await _sessionStore.loadActive(widget.workspace.fullName);
    conversation ??=
        await _sessionStore.create(widget.workspace.fullName);

    if (!mounted) return;
    _loadConversation(conversation);
  }

  void _loadConversation(AgentConversation conversation) {
    setState(() {
      _conversation = conversation;
      _messages
        ..clear()
        ..addAll(conversation.messages);
      _changes
        ..clear()
        ..addAll(conversation.changes);
      _pullRequests
        ..clear()
        ..addAll(conversation.pullRequests);
      _taskBranch = conversation.taskBranch;
      _progress.clear();
      _pendingImages.clear();
      _streamingNotifier.value = '';
      _loadingSession = false;
    });
    _sessionStore.setActive(
      widget.workspace.fullName,
      conversation.id,
    );
    _attachTask(conversation.id);
    _scrollToLatest();
  }

  void _attachTask(String conversationId) {
    final previous = _taskListenable;
    final previousListener = _taskListener;
    if (previous != null && previousListener != null) {
      previous.removeListener(previousListener);
    }

    final listenable = _taskCoordinator.listenable(conversationId);
    _taskListenable = listenable;

    if (listenable == null) {
      _taskListener = null;
      if (mounted && _busy) {
        setState(() {
          _busy = false;
          _progress.clear();
              _streamingNotifier.value = '';
        });
      }
      return;
    }

    void sync() {
      if (!mounted) return;
      final snapshot = listenable.value;
      setState(() {
        _busy = snapshot.running;
        _streamingNotifier.value = snapshot.streamingText;
        _progress
          ..clear()
          ..addAll(snapshot.progress);
        _conversation = snapshot.conversation;
        _messages
          ..clear()
          ..addAll(snapshot.conversation.messages);
        _changes
          ..clear()
          ..addAll(snapshot.conversation.changes);
        _pullRequests
          ..clear()
          ..addAll(snapshot.conversation.pullRequests);
        _taskBranch = snapshot.conversation.taskBranch;
      });
      _scrollToLatest();
    }

    _taskListener = sync;
    listenable.addListener(sync);
    sync();
  }

  Future<void> _persistSession() async {
    final current = _conversation;
    if (current == null) return;

    final keptMessages = _messages.length > 80
        ? _messages.sublist(_messages.length - 80)
        : List<AgentMessage>.from(_messages);

    final next = current.copyWith(
      title: _deriveTitle(current.title),
      messages: keptMessages,
      changes: List<PendingFileChange>.from(_changes),
      pullRequests: List<PendingPullRequest>.from(_pullRequests),
      taskBranch: _taskBranch,
      clearTaskBranch: _taskBranch == null,
      updatedAt: DateTime.now(),
    );
    _conversation = next;
    await _sessionStore.save(next);
  }

  String _deriveTitle(String existing) {
    final clean = existing.trim();
    return clean.isEmpty ? 'New chat' : clean;
  }

  Future<void> _generateSmartTitleIfNeeded(
    AiSettings settings,
    String apiKey,
  ) async {
    final current = _conversation;
    if (current == null ||
        current.title != 'New chat' ||
        _titleGenerationInFlight ||
        _messages.isEmpty) {
      return;
    }

    _titleGenerationInFlight = true;
    final provider = OpenAiCompatibleProvider(
      baseUrl: settings.baseUrl,
      apiKey: apiKey,
    );

    try {
      final source = _messages
          .take(8)
          .map((message) {
            final role = message.role == 'user' ? 'User' : 'Assistant';
            final content =
                message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
            return '$role: $content';
          })
          .join('\n');

      final clipped = source.length > 3000
          ? source.substring(source.length - 3000)
          : source;
      final model = settings.fastModel.trim().isNotEmpty
          ? settings.fastModel.trim()
          : settings.defaultModel.trim();

      final turn = await provider.complete(
        model: model,
        tools: const [],
        messages: [
          {
            'role': 'system',
            'content':
                'Create a concise chat title from the conversation. '
                'Use the same primary language as the user. '
                'Use 2 to 6 useful words, no quotes, no markdown, no ending punctuation. '
                'Describe the actual topic, not generic phrases like New chat or Question. '
                'Return only the title.',
          },
          {
            'role': 'user',
            'content': clipped,
          },
        ],
      );

      final generated = _cleanGeneratedTitle(turn.content);
      final latest = _conversation;
      if (!mounted ||
          generated.isEmpty ||
          latest == null ||
          latest.id != current.id ||
          latest.title != 'New chat') {
        return;
      }

      final renamed = latest.copyWith(title: generated);
      setState(() => _conversation = renamed);
      await _sessionStore.save(renamed);
    } catch (_) {
      // Title generation is cosmetic and must never break chat.
    } finally {
      provider.dispose();
      _titleGenerationInFlight = false;
    }
  }

  String _cleanGeneratedTitle(String raw) {
    var title = raw
        .split('\n')
        .first
        .replaceAll(RegExp(r'^[#>*_\-\s]+|[#>*_\-\s]+$'), '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[.!?:;]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.length > 64) {
      title = title.substring(0, 64).trimRight();
    }
    return title;
  }

  Future<void> _newConversation() async {
    if (_busy || _applying) return;

    if (_conversation != null &&
        _messages.isEmpty &&
        _changes.isEmpty &&
        _pullRequests.isEmpty) {
      _controller.clear();
      _pendingImages.clear();
      return;
    }

    await _persistSession();
    final conversation =
        await _sessionStore.create(widget.workspace.fullName);
    if (!mounted) return;
    _loadConversation(conversation);
  }

  Future<void> _showHistory() async {
    if (_busy || _applying) return;
    await _persistSession();
    final conversations =
        await _sessionStore.list(widget.workspace.fullName);
    if (!mounted) return;

    final items = List<AgentConversation>.from(conversations);
    final selected = await showModalBottomSheet<AgentConversation>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .68,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text(
                    'Gradient chats',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${items.length} saved chat${items.length == 1 ? '' : 's'}',
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('No saved chats yet.'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final active = item.id == _conversation?.id;
                            return ListTile(
                              leading: Icon(
                                active
                                    ? Icons.chat_bubble_rounded
                                    : Icons.chat_bubble_outline_rounded,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${item.messages.length} messages • '
                                '${item.updatedAt.toLocal().toString().substring(0, 16)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (active)
                                    const Icon(Icons.check_rounded, size: 18),
                                  IconButton(
                                    tooltip: 'Rename chat',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final renamed =
                                          await _renameStoredConversation(item);
                                      if (renamed == null ||
                                          !sheetContext.mounted) {
                                        return;
                                      }
                                      setSheetState(() {
                                        items[index] = renamed;
                                      });
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Delete chat',
                                    icon: const Icon(Icons.delete_outline_rounded),
                                    onPressed: () async {
                                      final confirmed =
                                          await _confirmDeleteConversation(item);
                                      if (!confirmed ||
                                          !sheetContext.mounted) {
                                        return;
                                      }

                                      await _sessionStore.delete(
                                        widget.workspace.fullName,
                                        item.id,
                                      );
                                      final wasActive =
                                          item.id == _conversation?.id;
                                      items.removeAt(index);

                                      if (wasActive) {
                                        final replacement = items.isNotEmpty
                                            ? items.first
                                            : await _sessionStore.create(
                                                widget.workspace.fullName,
                                              );
                                        if (sheetContext.mounted) {
                                          Navigator.pop(
                                            sheetContext,
                                            replacement,
                                          );
                                        }
                                        return;
                                      }

                                      setSheetState(() {});
                                    },
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.pop(context, item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      _loadConversation(selected);
    }
  }

  Future<AgentConversation?> _renameStoredConversation(
    AgentConversation conversation,
  ) async {
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Chat name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text.trim(),
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (title == null || title.trim().isEmpty) return null;
    final renamed = conversation.copyWith(
      title: title.trim(),
      updatedAt: DateTime.now(),
    );
    await _sessionStore.save(renamed);

    if (mounted && _conversation?.id == renamed.id) {
      setState(() => _conversation = renamed);
    }
    return renamed;
  }

  Future<bool> _confirmDeleteConversation(
    AgentConversation conversation,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete chat?'),
            content: Text(
              'Delete “${conversation.title}” and its saved task state? '
              'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _renameConversation() async {
    final current = _conversation;
    if (current == null || _busy) return;

    final controller = TextEditingController(text: current.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Chat name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text.trim(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (title == null || title.isEmpty || !mounted) return;
    setState(() {
      _conversation = current.copyWith(title: title);
    });
    await _persistSession();
  }

  Future<void> _createCheckpoint({
    String label = 'Checkpoint',
    bool silent = false,
  }) async {
    final current = _conversation;
    if (current == null) return;

    final now = DateTime.now();
    final checkpoint = AgentCheckpoint(
      id: now.microsecondsSinceEpoch.toString(),
      label: label,
      messages: List<AgentMessage>.from(_messages),
      changes: List<PendingFileChange>.from(_changes),
      pullRequests: List<PendingPullRequest>.from(_pullRequests),
      taskBranch: _taskBranch,
      createdAt: now,
    );

    final checkpoints = <AgentCheckpoint>[
      checkpoint,
      ...current.checkpoints,
    ].take(12).toList(growable: false);

    setState(() {
      _conversation = current.copyWith(checkpoints: checkpoints);
    });
    await _persistSession();

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checkpoint saved')),
      );
    }
  }

  Future<void> _showCheckpoints() async {
    final current = _conversation;
    if (current == null || _busy || _applying) return;

    if (current.checkpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No checkpoints in this chat yet.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<AgentCheckpoint>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.bookmarks_rounded),
                title: Text(
                  'Checkpoints',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: current.checkpoints.length,
                  itemBuilder: (context, index) {
                    final checkpoint = current.checkpoints[index];
                    return ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: Text(checkpoint.label),
                      subtitle: Text(
                        '${checkpoint.messages.length} messages • '
                        '${checkpoint.createdAt.toLocal().toString().substring(0, 16)}',
                      ),
                      onTap: () =>
                          Navigator.pop(context, checkpoint),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null || !mounted) return;

    setState(() {
      _messages
        ..clear()
        ..addAll(selected.messages);
      _changes
        ..clear()
        ..addAll(selected.changes);
      _pullRequests
        ..clear()
        ..addAll(selected.pullRequests);
      _taskBranch = selected.taskBranch;
      _conversation = current.copyWith(
        messages: List<AgentMessage>.from(selected.messages),
        changes: List<PendingFileChange>.from(selected.changes),
        pullRequests:
            List<PendingPullRequest>.from(selected.pullRequests),
        taskBranch: selected.taskBranch,
        clearTaskBranch: selected.taskBranch == null,
      );
    });
    await _persistSession();
    _scrollToLatest();
  }

  Future<void> _messageAction(int index, String action) async {
    if (_busy || index < 0 || index >= _messages.length) return;
    final message = _messages[index];

    if (action == 'edit' && message.role == 'user') {
      await _createCheckpoint(label: 'Before message edit', silent: true);
      setState(() {
        _controller.text = message.content;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
        _messages.removeRange(index, _messages.length);
        _changes.clear();
        _pullRequests.clear();
        _taskBranch = null;
      });
      await _persistSession();
      return;
    }

    if (action == 'retry' && message.role != 'user') {
      var userIndex = index - 1;
      while (userIndex >= 0 && _messages[userIndex].role != 'user') {
        userIndex--;
      }
      if (userIndex < 0) return;

      final prompt = _messages[userIndex]
          .content
          .replaceFirst(RegExp(r'\n\n📎 \d+ images? attached$'), '')
          .trim();

      await _createCheckpoint(label: 'Before response retry', silent: true);
      setState(() {
        _messages.removeRange(userIndex, _messages.length);
        _changes.clear();
        _pullRequests.clear();
      });
      await _persistSession();
      if (mounted) await _send(prompt);
      return;
    }

    if (action == 'delete') {
      await _createCheckpoint(label: 'Before message delete', silent: true);
      setState(() => _messages.removeAt(index));
      await _persistSession();
      return;
    }

    if (action == 'branch') {
      final source = _conversation;
      if (source == null) return;
      final branched = await _sessionStore.branchFrom(source, index + 1);
      if (!mounted) return;
      _loadConversation(branched);
    }
  }

  void _scrollToLatest() {
    if (_scrollTickPending) return;
    _scrollTickPending = true;
    Future<void>.delayed(const Duration(milliseconds: 55), () {
      _scrollTickPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final target = _scrollController.position.maxScrollExtent;
        if ((target - _scrollController.offset).abs() < 24) {
          _scrollController.jumpTo(target);
          return;
        }
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
        );
      });
    });
  }

  Future<void> _pickImages() async {
    if (_busy || _applying) return;

    try {
      final picked = await _imagePicker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 2048,
      );
      if (picked.isEmpty || !mounted) return;

      final next = <_PendingImage>[];
      var totalBytes = 0;

      for (final file in picked.take(4)) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        totalBytes += bytes.length;
        if (totalBytes > 12 * 1024 * 1024) break;

        final lower = file.name.toLowerCase();
        final mime = lower.endsWith('.png')
            ? 'image/png'
            : lower.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';

        next.add(
          _PendingImage(
            name: file.name,
            bytes: bytes,
            dataUri: 'data:$mime;base64,${base64Encode(bytes)}',
          ),
        );
      }

      if (!mounted) return;
      setState(() => _pendingImages.addAll(next));

      if (picked.length > 4 || totalBytes > 12 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gradient keeps image prompts to 4 images / about 12 MB.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach image: $error')),
      );
    }
  }

  Future<void> _send([String? forced]) async {
    if (_busy || _applying) return;
    final typedPrompt = (forced ?? _controller.text).trim();
    if (typedPrompt.isEmpty && _pendingImages.isEmpty) return;
    final prompt = typedPrompt.isEmpty
        ? 'Inspect the attached image(s) in the context of this repository.'
        : typedPrompt;

    final settings = await _settings.load();
    if (!settings.providerReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure an AI provider and model first.'),
        ),
      );
      return;
    }

    final apiKey = await _settings.apiKey();
    final githubToken = await _settings.githubToken();
    final history = List<AgentMessage>.from(_messages);
    final imageDataUris =
        _pendingImages.map((e) => e.dataUri).toList(growable: false);
    final imageCount = imageDataUris.length;

    final userMessage = AgentMessage.create(
      role: 'user',
      content: imageCount == 0
          ? prompt
          : '$prompt\n\n📎 $imageCount image${imageCount == 1 ? '' : 's'} attached',
    );
    final assistantMessageId =
        (DateTime.now().microsecondsSinceEpoch + 1).toString();
    final assistantSlot = AgentMessage(
      id: assistantMessageId,
      role: 'assistant',
      content: '',
    );

    setState(() {
      _busy = true;
      _streamingNotifier.value = '';
      _progress.clear();
      _messages
        ..add(userMessage)
        ..add(assistantSlot);
      _pendingImages.clear();
      if (forced == null) _controller.clear();
    });
    await _persistSession();
    _scrollToLatest();

    final current = _conversation;
    if (current == null) {
      if (mounted) {
        setState(() => _busy = false);
      }
      return;
    }

    final task = _taskCoordinator.launch(
      conversation: current,
      assistantMessageId: assistantMessageId,
      history: history,
      prompt: prompt,
      imageDataUris: imageDataUris,
      settings: settings,
      apiKey: apiKey,
      githubToken: githubToken,
      workspace: widget.workspace,
      webEnabled: _webEnabled,
      pageContext: widget.contextText,
      roleOverride: _roleOverride,
    );

    _taskListenable = task;
    _attachTask(current.id);
    unawaited(_generateSmartTitleIfNeeded(settings, apiKey));
  }

  Future<String> _ensureTaskBranch(GhBackend gh) async {
    final existing = _taskBranch?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    if (widget.workspace.branch != widget.workspace.defaultBranch) {
      _taskBranch = widget.workspace.branch;
      await _persistSession();
      return widget.workspace.branch;
    }

    final suffix = _conversation?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final compact = suffix.length > 10
        ? suffix.substring(suffix.length - 10)
        : suffix;
    final branch = 'gradient/task-$compact';

    await gh.createBranch(
      fullName: widget.workspace.fullName,
      branch: branch,
      from: widget.workspace.defaultBranch,
    );
    _taskBranch = branch;
    await _persistSession();
    return branch;
  }

  Future<void> _apply(PendingFileChange change) async {
    if (_busy || _applying) return;
    final token = await _settings.githubToken();
    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect GitHub before applying changes.'),
        ),
      );
      return;
    }

    setState(() => _applying = true);
    final gh = GhBackend(token: token);

    try {
      final branch = await _ensureTaskBranch(gh);
      final sha = await gh.writeFilesBatch(
        fullName: widget.workspace.fullName,
        branch: branch,
        files: {change.path: change.newContent},
        message: change.message,
      );

      if (!mounted) return;
      setState(() {
        _changes.remove(change);
        _messages.add(
          AgentMessage.create(
            role: 'assistant',
            content: 'Committed **${change.path}** to `$branch` '
                '(${sha.length > 8 ? sha.substring(0, 8) : sha}).',
          ),
        );
      });
      await _persistSession();
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _applyAll() async {
    if (_changes.isEmpty || _busy || _applying) return;

    final token = await _settings.githubToken();
    if (token.isEmpty) return;

    setState(() => _applying = true);
    final gh = GhBackend(token: token);

    try {
      final branch = await _ensureTaskBranch(gh);
      final files = <String, String>{};
      for (final change in _changes) {
        files[change.path] = change.newContent;
      }

      final sha = await gh.writeFilesBatch(
        fullName: widget.workspace.fullName,
        branch: branch,
        files: files,
        message: _changes.length == 1
            ? _changes.first.message
            : 'Gradient: update ${files.length} files',
      );

      if (!mounted) return;
      final count = files.length;
      setState(() {
        _changes.clear();
        _messages.add(
          AgentMessage.create(
            role: 'assistant',
            content: 'Committed **$count files** atomically to `$branch` '
                '(${sha.length > 8 ? sha.substring(0, 8) : sha}).',
          ),
        );
      });
      await _persistSession();
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _createPr(PendingPullRequest proposal) async {
    if (_busy || _applying) return;
    final token = await _settings.githubToken();
    if (token.isEmpty) return;
    final gh = GhBackend(token: token);

    try {
      final head = _taskBranch?.trim().isNotEmpty == true
          ? _taskBranch!.trim()
          : proposal.head;

      final url = await gh.createPullRequest(
        fullName: widget.workspace.fullName,
        title: proposal.title,
        body: proposal.body,
        head: head,
        base: proposal.base,
      );
      if (!mounted) return;
      setState(() {
        _pullRequests.remove(proposal);
        _messages.add(
          AgentMessage.create(
            role: 'assistant',
            content: 'Pull request created: $url',
          ),
        );
      });
      await _persistSession();
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  void dispose() {
    final listenable = _taskListenable;
    final listener = _taskListener;
    if (listenable != null && listener != null) {
      listenable.removeListener(listener);
    }
    _controller.dispose();
    _scrollController.dispose();
    _streamingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final usableHeight = media.size.height - keyboard;
    final sheetHeight = usableHeight * (keyboard > 0 ? .98 : .9);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: _loadingSession
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _renameConversation,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _conversation?.title ?? 'New chat',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      _taskBranch?.isNotEmpty == true
                                          ? '${widget.workspace.fullName} · $_taskBranch'
                                          : widget.workspace.fullName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Chat history',
                            onPressed: _busy ? null : _showHistory,
                            icon: const Icon(Icons.history_rounded),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Chat menu',
                            icon: const Icon(Icons.more_horiz_rounded),
                            enabled: !_busy && !_applying,
                            onSelected: (value) {
                              if (value == 'new') {
                                _newConversation();
                              } else if (value == 'save') {
                                _createCheckpoint();
                              } else if (value == 'restore') {
                                _showCheckpoints();
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'new',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.add_comment_outlined),
                                  title: Text('New chat'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'save',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.bookmark_add_outlined),
                                  title: Text('Create checkpoint'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'restore',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.restore_rounded),
                                  title: Text('Restore checkpoint'),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (_messages.isEmpty && !_busy)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          ActionChip(
                            label: const Text('Explain repo'),
                            onPressed: _busy
                                ? null
                                : () => _send(
                                      'Inspect this repository and explain its architecture, risks, and most useful next steps.',
                                    ),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            label: const Text('Fix workflow'),
                            onPressed: _busy
                                ? null
                                : () => _send(
                                      'Inspect the latest failed GitHub Actions workflow, read the failed job logs, diagnose the root cause, and propose the smallest safe fix.',
                                    ),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            label: const Text('Review'),
                            onPressed: _busy
                                ? null
                                : () => _send(
                                      'Map this repository first, then review it for bugs, regressions, security risks, and cleanup opportunities.',
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          if (_messages.isEmpty &&
                              _changes.isEmpty &&
                              _pullRequests.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 44, 22, 28),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 28,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'What are we building?',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Ask about the repo, fix code, inspect workflows, or make a change.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (var i = 0; i < _messages.length; i++)
                            KelivoChatMessage(
                              message: _messages[i],
                              onAction: (action) =>
                                  _messageAction(i, action),
                            ),
                          if (_busy && _progress.isNotEmpty)
                            KelivoProgressTimeline(events: _progress),
                          if (_busy)
                            ValueListenableBuilder<String>(
                              valueListenable: _streamingNotifier,
                              builder: (context, text, _) =>
                                  KelivoStreamingMessage(text: text),
                            ),
                          if (_changes.length > 1)
                            Card(
                              child: ListTile(
                                leading:
                                    const Icon(Icons.commit_rounded),
                                title: Text(
                                  '${_changes.length} files ready',
                                ),
                                subtitle: const Text(
                                  'Apply them as one atomic Git commit.',
                                ),
                                trailing: FilledButton(
                                  onPressed:
                                      _applying ? null : _applyAll,
                                  child: Text(
                                    _applying ? 'Applying…' : 'Apply all',
                                  ),
                                ),
                              ),
                            ),
                          for (final change in _changes)
                            Card(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: ExpansionTile(
                                leading:
                                    const Icon(Icons.difference_rounded),
                                title: Text(change.path),
                                subtitle: Text(change.message),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                children: [
                                  Container(
                                    width: double.infinity,
                                    constraints:
                                        const BoxConstraints(maxHeight: 320),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          cs.surfaceContainerHighest,
                                      borderRadius:
                                          BorderRadius.circular(14),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        buildSimpleDiff(
                                          path: change.path,
                                          oldText: change.oldContent,
                                          newText: change.newContent,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: _applying
                                          ? null
                                          : () => _apply(change),
                                      icon:
                                          const Icon(Icons.check_rounded),
                                      label:
                                          const Text('Apply to task branch'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final proposal in _pullRequests)
                            Card(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Pull request proposal',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(proposal.title),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_taskBranch ?? proposal.head} → ${proposal.base}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                    if (proposal.body.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      GradientMarkdown(proposal.body),
                                    ],
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.icon(
                                        onPressed: _applying
                                            ? null
                                            : () => _createPr(proposal),
                                        icon:
                                            const Icon(Icons.merge_rounded),
                                        label:
                                            const Text('Create PR'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    KelivoChatComposer(
                      controller: _controller,
                      enabled: !_busy && !_applying,
                      busy: _busy,
                      webEnabled: _webEnabled,
                      onWebChanged: (value) =>
                          setState(() => _webEnabled = value),
                      selectedRole: _roleOverride,
                      onRoleChanged: (role) =>
                          setState(() => _roleOverride = role),
                      onAttach: _pickImages,
                      onSend: () => _send(),
                      maxLines: keyboard > 0 ? 3 : 5,
                      attachmentPreview: _pendingImages.isEmpty
                          ? null
                          : SizedBox(
                              height: 76,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _pendingImages.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final image = _pendingImages[index];
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        child: Image.memory(
                                          image.bytes,
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        right: -6,
                                        top: -6,
                                        child: IconButton.filledTonal(
                                          visualDensity:
                                              VisualDensity.compact,
                                          iconSize: 16,
                                          tooltip: 'Remove image',
                                          onPressed: () {
                                            setState(
                                              () => _pendingImages
                                                  .removeAt(index),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.close_rounded,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PendingImage {
  const _PendingImage({
    required this.name,
    required this.bytes,
    required this.dataUri,
  });

  final String name;
  final Uint8List bytes;
  final String dataUri;
}
