import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/core/agent/agent_models.dart';
import 'package:gradient/core/agent/agent_session_store.dart';

void main() {
  test('conversation snapshots survive JSON round-trip', () {
    final now = DateTime.utc(2026, 10, 5);
    final conversation = AgentConversation(
      id: 'chat-1',
      repoFullName: 'owner/repo',
      title: 'Fix workflow',
      messages: const [
        AgentMessage(role: 'user', content: 'Fix it'),
        AgentMessage(role: 'assistant', content: 'Working on it'),
      ],
      changes: const [
        PendingFileChange(
          path: 'lib/main.dart',
          oldContent: 'old',
          newContent: 'new',
          currentSha: 'abc',
          message: 'Update main',
          branch: 'main',
        ),
      ],
      pullRequests: const [
        PendingPullRequest(
          title: 'Fix',
          body: 'Body',
          head: 'gradient/task-1',
          base: 'main',
        ),
      ],
      checkpoints: [
        AgentCheckpoint(
          id: 'cp-1',
          label: 'Before edit',
          messages: const [
            AgentMessage(role: 'user', content: 'Fix it'),
          ],
          changes: const [],
          pullRequests: const [],
          taskBranch: null,
          createdAt: now,
        ),
      ],
      taskBranch: 'gradient/task-1',
      createdAt: now,
      updatedAt: now,
    );

    final restored = AgentConversation.fromJson(conversation.toJson());

    expect(restored.id, conversation.id);
    expect(restored.repoFullName, 'owner/repo');
    expect(restored.messages.length, 2);
    expect(restored.changes.single.path, 'lib/main.dart');
    expect(restored.pullRequests.single.head, 'gradient/task-1');
    expect(restored.checkpoints.single.label, 'Before edit');
    expect(restored.taskBranch, 'gradient/task-1');
  });
}
