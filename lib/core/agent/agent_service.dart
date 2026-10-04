import 'dart:convert';

import '../ai/openai_compatible_provider.dart';
import '../github/github_service.dart';
import '../search/web_research_service.dart';
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
  }) async {
    final route = const TaskRouter().route(prompt);
    final model = settings.modelFor(route.model);
    if (model.isEmpty) {
      throw StateError('No model configured for ${route.model.label}.');
    }

    final ai = OpenAiCompatibleProvider(
      baseUrl: settings.baseUrl,
      apiKey: apiKey,
    );

    // Public repositories can be inspected anonymously. A token is only
    // mandatory when GitHub itself requires authentication.
    final github =
        workspace == null ? null : GitHubService(token: githubToken);
    final web = webEnabled ? WebResearchService() : null;

    var activeBranch = workspace?.branch;
    final changes = <PendingFileChange>[];
    final pullRequests = <PendingPullRequest>[];

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _systemPrompt(
          skills: route.skills.map((e) => e.name).join(', '),
          activeBranch: activeBranch,
        ),
      },
      ...history.takeLast(16).map(
            (e) => {'role': e.role, 'content': e.content},
          ),
      {'role': 'user', 'content': prompt},
    ];

    final tools = _tools(
      hasGithub: github != null,
      hasWeb: web != null,
      canMutateGithub: githubToken.trim().isNotEmpty,
    );

    String finalText = '';
    try {
      for (var round = 0; round < 8; round++) {
        final turn = await ai.complete(
          model: model,
          messages: messages,
          tools: tools,
          reasoningEffort: settings.reasoningEffort,
        );

        messages.add({
          'role': 'assistant',
          'content': turn.content,
          if (turn.assistantMessage['tool_calls'] != null)
            'tool_calls': turn.assistantMessage['tool_calls'],
        });

        if (turn.toolCalls.isEmpty) {
          finalText = turn.content.trim();
          break;
        }

        for (final call in turn.toolCalls) {
          final result = await _runTool(
            call,
            github: github,
            web: web,
            activeBranch: activeBranch,
            changes: changes,
            pullRequests: pullRequests,
          );

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

      if (finalText.isEmpty) {
        finalText = changes.isNotEmpty || pullRequests.isNotEmpty
            ? 'I prepared the requested changes for your review.'
            : 'The agent reached its tool-call limit before producing a final response.';
      }

      return AgentResult(
        text: finalText,
        fileChanges: changes,
        pullRequests: pullRequests,
        branchUsed: activeBranch,
        model: model,
      );
    } finally {
      ai.dispose();
      github?.dispose();
      web?.dispose();
    }
  }

  String _systemPrompt({
    required String skills,
    required String? activeBranch,
  }) {
    final repo = workspace;
    return '''
You are Gradient, an AI coding overlay running on top of the GitHub website on Android.

Active skills: $skills.
${repo == null ? 'No repository API context is available for this page.' : 'Repository: ${repo.fullName}\nDefault branch: ${repo.defaultBranch}\nActive branch: ${activeBranch ?? repo.branch}'}

Current GitHub browser context:
${pageContext.trim().isEmpty ? 'No safe page excerpt is available.' : pageContext}

Rules:
- Treat the GitHub website page as the user's primary workspace.
- Use the current page context before asking the user to repeat what they are looking at.
- Inspect relevant repository files with GitHub tools before proposing edits when those tools are available.
- Never expose credentials, tokens, .env contents, keystores, signing secrets, private keys, or sensitive configuration.
- Never modify the default branch directly.
- File edits must go through propose_file_change with the COMPLETE replacement file content. Gradient shows a diff and requires explicit user approval before committing.
- Pull requests must go through propose_pull_request and require explicit user approval.
- Use workflow tools to inspect actual failed runs/jobs/logs before diagnosing CI failures.
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
    required GitHubService? github,
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
        final file = await github!.readFile(
          repo!.fullName,
          args['path'] as String? ?? '',
          ref: activeBranch,
        );
        return _ToolResult(file.content);

      case 'github_list_files':
        final entries = await github!.listContents(
          repo!.fullName,
          path: args['path'] as String? ?? '',
          ref: activeBranch,
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

      case 'propose_file_change':
        final path = args['path'] as String? ?? '';
        final newContent = args['content'] as String? ?? '';
        final message = args['message'] as String? ?? 'Update $path';

        String oldContent = '';
        String? sha;
        try {
          final current = await github!.readFile(
            repo!.fullName,
            path,
            ref: activeBranch,
          );
          oldContent = current.content;
          sha = current.sha;
        } on GitHubException catch (error) {
          if (error.statusCode != 404) rethrow;
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

      default:
        throw UnsupportedError('Unknown agent tool: ${call.name}');
    }
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
