import 'dart:convert';

import '../ai/model_health_registry.dart';
import '../ai/openai_compatible_provider.dart';
import '../gh/gh_backend.dart';
import '../gh/gh_command_runner.dart';
import '../models/model_router.dart';
import '../search/web_research_service.dart';
import '../security/protected_path.dart';
import '../settings/app_settings.dart';
import '../workspace/workspace_store.dart';
import 'agent_models.dart';
import 'task_router.dart';

class AgentService {
  AgentService({
    required this.settings,
    required this.apiKey,
    required this.githubToken,
    required this.workspace,
    required this.webEnabled,
    this.pageContext = '',
  });

  final AiSettings settings;
  final String apiKey;
  final String githubToken;
  final WorkspaceSelection? workspace;
  final bool webEnabled;
  final String pageContext;

  Future<AgentResult> run({
    required String prompt,
    required List<AgentMessage> history,
    List<String> imageDataUris = const [],
    ModelRole? roleOverride,
    void Function(String delta)? onTextDelta,
    void Function(AgentProgressEvent event)? onProgress,
  }) async {
    final route = const TaskRouter().route(
      prompt,
      hasImages: imageDataUris.isNotEmpty,
    );
    final selectedRole = roleOverride ?? route.model;
    final health = ModelHealthRegistry.instance;
    final configuredCandidates = settings.modelCandidates(selectedRole);
    final candidates = health.healthyFirst(configuredCandidates);
    if (candidates.isEmpty) {
      throw StateError('No model configured for ${selectedRole.label}.');
    }
    var activeModel = candidates.first;

    final ai = OpenAiCompatibleProvider(
      baseUrl: settings.baseUrl,
      apiKey: apiKey,
    );

    final github =
        workspace == null ? null : GhBackend(token: githubToken);
    final web = webEnabled && settings.webEnabledFor(selectedRole)
        ? WebResearchService()
        : null;

    var activeBranch = workspace?.branch;
    final changes = <PendingFileChange>[];
    final pullRequests = <PendingPullRequest>[];

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _systemPrompt(
          skills: route.skills.map((e) => e.name).join(', '),
          activeBranch: activeBranch,
          imageCount: imageDataUris.length,
        ),
      },
      ...history.takeLast(settings.maxHistoryMessages).map(
            (e) => {'role': e.role, 'content': e.content},
          ),
      {
        'role': 'user',
        'content': imageDataUris.isEmpty
            ? prompt
            : [
                {
                  'type': 'text',
                  'text': prompt,
                },
                for (final dataUri in imageDataUris)
                  {
                    'type': 'image_url',
                    'image_url': {'url': dataUri},
                  },
              ],
      },
    ];

    final tools = _tools(
      hasGithub: github != null,
      hasWeb: web != null,
      canMutateGithub: githubToken.trim().isNotEmpty,
    );

    String finalText = '';
    try {
      for (var round = 0; round < 14; round++) {
        onProgress?.call(
          AgentProgressEvent(
            label: round == 0 ? selectedRole.label : 'Continuing',
            detail: activeModel,
            kind: 'model',
          ),
        );

        AiTurn? turn;
        AiProviderException? lastProviderError;

        for (var modelIndex = 0;
            modelIndex < candidates.length && turn == null;
            modelIndex++) {
          final candidate = candidates[modelIndex];
          activeModel = candidate;
          final maxAttempts = candidates.length == 1 ? 3 : 2;

          for (var attempt = 0; attempt < maxAttempts; attempt++) {
            var emittedText = false;
            try {
              turn = await ai.completeStreaming(
                model: candidate,
                messages: messages,
                tools: tools,
                reasoningEffort: settings.reasoningEffortFor(selectedRole),
                onDelta: (delta) {
                  if (delta.isNotEmpty) emittedText = true;
                  onTextDelta?.call(delta);
                },
              );
              health.markSuccess(candidate);
              break;
            } on AiProviderException catch (error) {
              lastProviderError = error;
              if (!error.retryable || emittedText) rethrow;

              health.markFailure(
                candidate,
                statusCode: error.statusCode,
              );

              final hasFallback = modelIndex + 1 < candidates.length;
              final shouldFallbackNow = error.statusCode == 429 && hasFallback;
              final lastAttempt = attempt + 1 >= maxAttempts;

              if (shouldFallbackNow || lastAttempt) {
                if (hasFallback) {
                  final nextModel = candidates[modelIndex + 1];
                  onProgress?.call(
                    AgentProgressEvent(
                      label: 'Provider busy · trying fallback',
                      detail: nextModel,
                      kind: 'fallback',
                    ),
                  );
                }
                break;
              }

              final wait = Duration(milliseconds: 700 * (1 << attempt));
              onProgress?.call(
                AgentProgressEvent(
                  label: 'Provider busy · retrying',
                  detail: candidate,
                  kind: 'retry',
                ),
              );
              await Future<void>.delayed(wait);
            }
          }
        }

        if (turn == null) {
          if (lastProviderError != null) throw lastProviderError;
          throw StateError('No healthy model could complete this request.');
        }

        final completedTurn = turn;

        messages.add({
          'role': 'assistant',
          'content': completedTurn.content,
          if (completedTurn.assistantMessage['tool_calls'] != null)
            'tool_calls': completedTurn.assistantMessage['tool_calls'],
        });

        if (completedTurn.toolCalls.isEmpty) {
          finalText = completedTurn.content.trim();
          break;
        }

        for (final call in completedTurn.toolCalls) {
          onProgress?.call(
            AgentProgressEvent(
              label: _progressLabel(call.name),
              detail: _progressDetail(call),
              kind: 'tool',
            ),
          );

          _ToolResult result;
          try {
            result = await _runTool(
              call,
              github: github,
              web: web,
              activeBranch: activeBranch,
              changes: changes,
              pullRequests: pullRequests,
            );
          } on GhCommandException catch (error) {
            result = _ToolResult(
              _githubToolError(call.name, error),
            );
          }

          if (call.name == 'github_create_branch' &&
              result.updatedBranch != null) {
            activeBranch = result.updatedBranch;
          }

          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'name': call.name,
            'content': result.content,
          });
        }
      }

      if (finalText.isEmpty &&
          changes.isEmpty &&
          pullRequests.isEmpty) {
        finalText =
            'The agent reached its tool-call limit before producing a final response.';
      }

      onProgress?.call(
        const AgentProgressEvent(
          label: 'Done',
          kind: 'done',
        ),
      );

      return AgentResult(
        text: finalText,
        fileChanges: changes,
        pullRequests: pullRequests,
        branchUsed: activeBranch,
        model: activeModel,
      );
    } finally {
      ai.dispose();
      web?.dispose();
    }
  }

  String _systemPrompt({
    required String skills,
    required String? activeBranch,
    required int imageCount,
  }) {
    final repo = workspace;
    return '''
You are Gradient, an AI coding agent inside a native GitHub mobile client on Android. GitHub operations are executed through a controlled GitHub CLI backend.

Active skills: $skills.
${repo == null ? 'No repository API context is available for this page.' : 'Repository: ${repo.fullName}\nDefault branch: ${repo.defaultBranch}\nActive branch: ${activeBranch ?? repo.branch}'}

Current GitHub browser context:
${pageContext.trim().isEmpty ? 'No safe page excerpt is available.' : pageContext}

${imageCount == 0 ? 'No image is attached to the current request.' : 'The current request includes $imageCount image attachment(s). Inspect them directly when relevant.'}

Rules:
- Treat the currently selected native GitHub repository and screen as the user's primary workspace.
- Use the current native screen/repository context before asking the user to repeat what they are looking at.
- Inspect relevant repository files with GitHub tools before proposing edits when those tools are available.
- A GitHub tool may report a missing path or other recoverable error. Try another relevant path or continue with the information you do have instead of aborting the whole task.
- Never expose credentials, tokens, .env contents, keystores, signing secrets, private keys, or sensitive configuration.
- Never modify the default branch directly.
- File edits must go through propose_file_change with the COMPLETE replacement file content. Gradient shows a diff and requires explicit user approval before committing.
- Pull requests must go through propose_pull_request and require explicit user approval.
- Use github_repo_map and github_search_code before blindly guessing file locations in unfamiliar repositories.
- Use workflow tools to inspect actual failed runs/jobs/logs before diagnosing CI failures.
- You may rerun or cancel workflows only when the user's request clearly asks for that action.
- Search official documentation for version-sensitive facts when web tools are available.
- Prefer minimal, targeted changes.
''';
  }

  List<Map<String, dynamic>> _tools({
    required bool hasGithub,
    required bool hasWeb,
    required bool canMutateGithub,
  }) {
    final tools = <Map<String, dynamic>>[];

    if (hasWeb) {
      tools.addAll([
        _tool(
          'web_search',
          'Search the web with DuckDuckGo.',
          {
            'query': {'type': 'string'},
          },
          const ['query'],
        ),
        _tool(
          'web_open',
          'Open and extract readable text from a web page.',
          {
            'url': {'type': 'string'},
          },
          const ['url'],
        ),
      ]);
    }

    if (hasGithub) {
      tools.addAll([
        _tool(
          'github_read_file',
          'Read a UTF-8 file from the current GitHub repository.',
          {
            'path': {'type': 'string'},
          },
          const ['path'],
        ),
        _tool(
          'github_list_files',
          'List files and folders in the current repository.',
          {
            'path': {'type': 'string'},
          },
          const [],
        ),
        _tool(
          'github_workflow_runs',
          'List recent GitHub Actions workflow runs.',
          {},
          const [],
        ),
        _tool(
          'github_workflow_jobs',
          'List jobs for a workflow run.',
          {
            'run_id': {'type': 'integer'},
          },
          const ['run_id'],
        ),
        _tool(
          'github_workflow_job_log',
          'Read logs for one GitHub Actions job.',
          {
            'job_id': {'type': 'integer'},
          },
          const ['job_id'],
        ),
        _tool(
          'github_repo_map',
          'Get a recursive repository path map for the active branch. Use this to understand repository structure without opening every directory.',
          {},
          const [],
        ),
        _tool(
          'github_search_code',
          'Search code in the current GitHub repository.',
          {
            'query': {'type': 'string'},
          },
          const ['query'],
        ),
      ]);

      if (canMutateGithub) {
        tools.addAll([
          _tool(
            'github_create_branch',
            'Create and switch to a new branch from the current active branch.',
            {
              'name': {'type': 'string'},
            },
            const ['name'],
          ),
          _tool(
            'propose_file_change',
            'Propose a complete replacement for a repository file. This does not commit.',
            {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
              'message': {'type': 'string'},
            },
            const ['path', 'content', 'message'],
          ),
          _tool(
            'propose_pull_request',
            'Propose a pull request for user approval. This does not create it.',
            {
              'title': {'type': 'string'},
              'body': {'type': 'string'},
              'base': {'type': 'string'},
            },
            const ['title', 'body'],
          ),
          _tool(
            'github_rerun_workflow',
            'Rerun a GitHub Actions workflow run. Use only when the user asked to rerun it.',
            {
              'run_id': {'type': 'integer'},
              'failed_only': {'type': 'boolean'},
            },
            const ['run_id'],
          ),
          _tool(
            'github_cancel_workflow',
            'Cancel a running GitHub Actions workflow. Use only when the user asked to cancel it.',
            {
              'run_id': {'type': 'integer'},
            },
            const ['run_id'],
          ),
        ]);
      }
    }

    return tools;
  }

  Map<String, dynamic> _tool(
    String name,
    String description,
    Map<String, dynamic> properties,
    List<String> required,
  ) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': required,
          'additionalProperties': false,
        },
      },
    };
  }

  Future<_ToolResult> _runTool(
    AiToolCall call, {
    required GhBackend? github,
    required WebResearchService? web,
    required String? activeBranch,
    required List<PendingFileChange> changes,
    required List<PendingPullRequest> pullRequests,
  }) async {
    final repo = workspace;
    final args = call.arguments;

    switch (call.name) {
      case 'web_search':
        final result = await web!.search(args['query'] as String? ?? '');
        return _ToolResult(
          jsonEncode(
            result.items
                .map(
                  (e) => {
                    'title': e.title,
                    'url': e.url,
                    'snippet': e.text,
                  },
                )
                .toList(),
          ),
        );

      case 'web_open':
        return _ToolResult(
          await web!.openPage(args['url'] as String? ?? ''),
        );

      case 'github_read_file':
        final path = args['path'] as String? ?? '';
        if (isProtectedRepositoryPath(path)) {
          return const _ToolResult(
            'Blocked: Gradient will not send protected credential or secret files to the model.',
          );
        }
        final file = await github!.readFile(
          repo!.fullName,
          path,
          ref: activeBranch ?? repo.branch,
        );
        return _ToolResult(file.content);

      case 'github_list_files':
        final entries = await github!.listContents(
          repo!.fullName,
          path: args['path'] as String? ?? '',
          ref: activeBranch ?? repo.branch,
        );
        return _ToolResult(
          jsonEncode(entries.map((e) => e.toJson()).toList()),
        );

      case 'github_create_branch':
        final name = args['name'] as String? ?? '';
        if (name.isEmpty) throw const FormatException('Branch name is empty.');
        final created = await github!.createBranch(
          fullName: repo!.fullName,
          branch: name,
          from: activeBranch ?? repo.branch,
        );
        return _ToolResult(
          'Created branch $created and switched the agent context to it.',
          updatedBranch: created,
        );

      case 'github_workflow_runs':
        final runs = await github!.listWorkflowRuns(repo!.fullName);
        return _ToolResult(
          jsonEncode(runs.map((e) => e.toJson()).toList()),
        );

      case 'github_workflow_jobs':
        final runId = _intArg(args['run_id']);
        final jobs = await github!.listWorkflowJobs(repo!.fullName, runId);
        return _ToolResult(
          jsonEncode(jobs.map((e) => e.toJson()).toList()),
        );

      case 'github_workflow_job_log':
        final jobId = _intArg(args['job_id']);
        final log = await github!.workflowJobLog(repo!.fullName, jobId);
        return _ToolResult(
          log.length > 18000 ? log.substring(log.length - 18000) : log,
        );


      case 'github_repo_map':
        final paths = await github!.repositoryMap(
          repo!.fullName,
          ref: activeBranch ?? repo.branch,
        );
        return _ToolResult(
          jsonEncode({
            'branch': activeBranch ?? repo.branch,
            'count': paths.length,
            'paths': paths,
          }),
        );

      case 'github_search_code':
        final query = args['query'] as String? ?? '';
        final results = await github!.searchCode(repo!.fullName, query);
        return _ToolResult(jsonEncode(results));

      case 'propose_file_change':
        final path = args['path'] as String? ?? '';
        if (isProtectedRepositoryPath(path)) {
          return const _ToolResult(
            'Blocked: Gradient will not edit protected credential or secret files.',
          );
        }
        final newContent = args['content'] as String? ?? '';
        final message = args['message'] as String? ?? 'Update $path';

        String oldContent = '';
        String? sha;
        try {
          final current = await github!.readFile(
            repo!.fullName,
            path,
            ref: activeBranch ?? repo.branch,
          );
          oldContent = current.content;
          sha = current.sha;
        } on GhCommandException catch (error) {
          if (!error.message.contains('404') &&
              !error.message.toLowerCase().contains('not found')) {
            rethrow;
          }
        }

        changes.add(
          PendingFileChange(
            path: path,
            oldContent: oldContent,
            newContent: newContent,
            currentSha: sha,
            message: message,
            branch: activeBranch ?? repo!.branch,
          ),
        );
        return _ToolResult(
          'Change proposal recorded for $path. The user will review the diff before commit.',
        );

      case 'propose_pull_request':
        final base = (args['base'] as String?)?.trim();
        pullRequests.add(
          PendingPullRequest(
            title: args['title'] as String? ?? 'Gradient change',
            body: args['body'] as String? ?? '',
            head: activeBranch ?? repo!.branch,
            base: base == null || base.isEmpty ? repo!.defaultBranch : base,
          ),
        );
        return const _ToolResult(
          'Pull request proposal recorded for user approval.',
        );


      case 'github_rerun_workflow':
        final runId = _intArg(args['run_id']);
        final failedOnly = args['failed_only'] as bool? ?? false;
        await github!.rerunWorkflow(
          repo!.fullName,
          runId,
          failedOnly: failedOnly,
        );
        return _ToolResult(
          failedOnly
              ? 'Rerunning failed jobs for workflow run $runId.'
              : 'Rerunning workflow run $runId.',
        );

      case 'github_cancel_workflow':
        final runId = _intArg(args['run_id']);
        await github!.cancelWorkflow(repo!.fullName, runId);
        return _ToolResult('Cancelled workflow run $runId.');

      default:
        throw UnsupportedError('Unknown agent tool: ${call.name}');
    }
  }

  String _progressLabel(String toolName) {
    return switch (toolName) {
      'web_search' => 'Searching the web',
      'web_open' => 'Reading a web page',
      'github_read_file' => 'Reading a file',
      'github_list_files' => 'Listing repository files',
      'github_repo_map' => 'Mapping the repository',
      'github_search_code' => 'Searching repository code',
      'github_workflow_runs' => 'Checking workflow runs',
      'github_workflow_jobs' => 'Inspecting workflow jobs',
      'github_workflow_job_log' => 'Reading workflow logs',
      'github_create_branch' => 'Creating a task branch',
      'propose_file_change' => 'Preparing a file change',
      'propose_pull_request' => 'Preparing a pull request',
      'github_rerun_workflow' => 'Rerunning a workflow',
      'github_cancel_workflow' => 'Cancelling a workflow',
      _ => 'Using $toolName',
    };
  }

  String _progressDetail(AiToolCall call) {
    final args = call.arguments;
    for (final key in const ['path', 'query', 'run_id', 'job_id', 'name']) {
      final value = args[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        final text = value.toString().trim();
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
      }
    }
    return '';
  }

  String _githubToolError(String toolName, GhCommandException error) {
    final message = error.message.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = message.toLowerCase();

    if (error.exitCode == 1 &&
        (lower.contains('404') || lower.contains('not found'))) {
      return jsonEncode({
        'ok': false,
        'tool': toolName,
        'error': 'not_found',
        'message':
            'GitHub could not find that path/resource. Try another likely path, ref, run, or job and continue instead of aborting.',
      });
    }

    return jsonEncode({
      'ok': false,
      'tool': toolName,
      'error': 'github_cli_error',
      'exit_code': error.exitCode,
      'message': message.length > 600 ? '${message.substring(0, 600)}…' : message,
    });
  }

  int _intArg(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
}

class _ToolResult {
  const _ToolResult(this.content, {this.updatedBranch});

  final String content;
  final String? updatedBranch;
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList(growable: false);
    final start = list.length > count ? list.length - count : 0;
    return list.skip(start);
  }
}
