/// Memory prompt language for model-facing contracts (not UI l10n / ARB).
enum MemoryPromptLang { zh, en }

/// Built-in default prompt templates and pure time helpers for the memory system.
///
/// These strings are model contracts and must NOT go through ARB (§16.2).
abstract final class MemoryPrompts {
  MemoryPrompts._();

  // ── §11.2 / §11.3 memory rules ───────────────────────────────────────────

  static final String rulesZh = rulesEn;

  static final String rulesEn =
      '''
## Long-term memory

The conversation may contain memory information provided by the system. It is not what the user said in the current turn:

- <user_profile> holds stable facts about the user, such as how they want to be addressed, language preference and timezone.
- <user_memory type="..."> holds long-term memory in four categories. Each line looks like `- [2026-08-07] content`, where the bracket is the date this entry was last updated. Entries prefixed with `(assistant) ` belong only to the current assistant; the rest are visible to all assistants.
- A block marked mode="summary" means the category has the number of entries given by the total attribute, and only the most recent ones indicated by the shown attribute are listed. Use memory_search_profile when you need more.
- An empty tag such as <user_memory type="voice"/> means the category currently has no entries.
- A <user_memory_update> appearing mid-conversation is the latest complete snapshot. Replace the memory you saw earlier with it.

When addressing the user, use preferred_name from <user_profile> if present. Otherwise do not guess, and never use the name of another person that appears in memory.

When the user reveals something that will still be true in a different conversation, write one entry with memory_update. The test is: if you started a fresh conversation, would not knowing this make your answer worse?

Do not write: temporary context from this conversation, conclusions you inferred but the user did not confirm, topics the user merely mentioned in passing, or facts that can be looked up directly in the chat history.

Write complete third-person statements about the user. Do not use words like "this" or "just now" that point back to the current conversation. The system deduplicates and merges automatically, so you do not need to read first and rewrite the whole entry.

When the user says an entry is wrong, use memory_edit to fix it or memory_delete to archive it.
'''
          .trim();

  static final String legacyRulesZh = legacyRulesEn;

  /// English counterpart of [legacyRulesZh].
  static final String legacyRulesEn =
      '''
## Memory Tool
You are a stateless model and cannot retain memories on your own; to remember something, use the **memory tools**.
Use the `create_memory`, `edit_memory`, and `delete_memory` tools to create, update, or delete memories.
- If nothing relevant is stored yet, use create_memory to add a new entry.
- If a related entry already exists, use edit_memory to update it.
- If an entry is outdated or useless, use delete_memory to remove it.
These memories are automatically included in future conversation context, inside the <memories> tag.
Never store sensitive information, which includes the user's ethnicity, religious beliefs, sexual orientation, political views and party affiliation, sex life, and criminal record.
While chatting with the user, act like a personal secretary and **proactively** record information about them, including but not limited to:
- Nickname / name
- Age / gender / interests
- Plans and scheduled items
- Preferred chat style
- Work-related details
- Time of the first conversation
- ...
Call the tools on your own initiative rather than waiting for the user to ask.
When an entry involves dates, include them in an absolute time format; the current time is {{currentTime}}.
There is no need to tell the user you changed an entry, and do not show memory contents in the conversation unless the user asks.
Similar or related memories should be merged into one entry instead of duplicated, and outdated entries should be deleted.
You may hint during casual chat that you are able to remember things.
'''
          .trim();

  static const String legacyCurrentTimePlaceholder = '{{currentTime}}';

  /// Appended to [rulesZh] when `allowPastConversationRecall` is on.
  static const String rulesPastConversationRecallZh = rulesPastConversationRecallEn;

  /// Appended to [rulesEn] when `allowPastConversationRecall` is on.
  static const String rulesPastConversationRecallEn =
      'When you need to recall something discussed before, use chat_search to search past conversations by keyword. Do not answer from impression.';

  // ── §12.4 Gatekeeper ─────────────────────────────────────────────────────

  static final String gateZh = gateEn;

  static final String gateEn =
      '''
Analyse the conversation below and decide whether it contains user information worth remembering long term.

Worth remembering: the user revealed personal information, a way of working, a characteristic of how they express themselves, or an explicit requirement for the assistant.
Not worth remembering: pure technical Q&A, project details, one-off operational instructions.

Output format (follow this XML exactly, no extra text):
<gate>
  <user_memory>true or false</user_memory>
</gate>

## Conversation
{{conversation}}
'''
          .trim();

  // ── §12.5 Extract ────────────────────────────────────────────────────────

  static final String extractZh = extractEn;

  static final String extractEn =
      '''
Extract new information about the user from the conversation. Each item must be independent, concise and complete.

Four categories:
- identity: name, gender, pronoun preference, occupation, company, people around them, background
- workflow: how they work, tool preferences, debugging habits
- voice: writing style, sentence rhythm, word choice
- instruction: explicit requirements the user has for the assistant — reply style, prohibitions, interaction preferences

Rules:
- Extract only from what the user said
- Do not extract the assistant's persona
- Do not extract facts that can be looked up directly in the chat history or in code
- One sentence per item, self-contained, third person about the user
- Do not use words like "this" or "just now" that point back to the current conversation
- Do not re-extract anything already present in "Existing memory"

## Existing memory
{{existingMemory}}

Output format:
<extracted>
<item type="identity|workflow|voice|instruction">one sentence</item>
</extracted>

If there is nothing worth extracting:
<extracted/>

## Conversation
{{conversation}}
'''
          .trim();

  /// Appended under Extract rules when write scope is `toolDefault*`.
  static const String extractToolDefaultScopeRuleZh = extractToolDefaultScopeRuleEn;

  static const String extractToolDefaultScopeRuleEn =
      '- For information that only applies to the current assistant, add scope="assistant" on the item; for information that applies everywhere, add scope="global" or omit it';

  // ── §12.6 Smart Add (per-item) ───────────────────────────────────────────

  static final String smartAddZh = smartAddEn;

  static final String smartAddEn =
      '''
You are a memory deduplication judge. Decide how the new information relates to existing memory.

## New information
Type: {{type}}
Content: {{newInfo}}

## Similar existing memories (up to 5)
{{entriesText}}

Decide:
- NEW: nothing related exists; create a new entry
- MERGE: merge into an existing entry; output the full merged content
- CONFLICT: contradicts an existing entry (the user changed a preference); archive the old one and write the new one
- SKIP: existing memory already contains this information; do nothing

Also decide: which of the listed existing memories are semantically related to the new information (even if not duplicate and not conflicting)?

Output JSON only, no explanation:
{ "action": "NEW" | "MERGE" | "CONFLICT" | "SKIP", "targetId": "...", "mergedContent": "...", "relatedIds": ["mem_xxxxxxxx"] }
'''
          .trim();

  // ── §12.6 Smart Add (batched) ────────────────────────────────────────────

  static final String smartAddBatchZh = smartAddBatchEn;

  static final String smartAddBatchEn =
      '''
You are a memory deduplication judge. Decide how each piece of new information relates to existing memory.

## New information
{{itemsText}}

## Similar existing memories
{{entriesText}}

For each piece of new information, decide:
- NEW: nothing related exists; create a new entry
- MERGE: merge into an existing entry; output the full merged content
- CONFLICT: contradicts an existing entry (the user changed a preference); archive the old one and write the new one
- SKIP: existing memory already contains this information; do nothing

Also, for each piece of new information, decide which of the listed existing memories are semantically related to it (even if not duplicate and not conflicting).

Output JSON only, no explanation:
{"results":[{"index":1,"action":"NEW","targetId":null,"mergedContent":null,"relatedIds":[]}]}
'''
          .trim();

  // ── §12.7 Profile Distiller ──────────────────────────────────────────────

  static final String profileDistillZh = profileDistillEn;

  static final String profileDistillEn =
      '''
Distill stable profile fields from the user's identity memories.

## Current profile
{{profileBlock}}

## Identity memories
{{identityEntries}}

Available fields: preferred_name (how the user wants to be addressed), gender, pronouns, preferred_language, timezone, occupation, location

Rules:
- Do not output a field without clear evidence in the memories
- Do not output a field that already has a value in the current profile unless the memories overturn it
- Only output preferred_name when the user has explicitly said how they want to be addressed; never use the name of another person that appears in memory
- If uncertain, do not output

Output JSON only, no explanation:
{"fields":[{"key":"preferred_name","value":"..."}]}
'''
          .trim();

  // ── Legacy memory migration ──────────────────────────────────────────────

  static final String migrateZh = migrateEn;

  static final String migrateEn =
      '''
You are migrating legacy long-term memories into a typed memory system.

For every input item, return exactly one output item with the same integer id. Preserve every fact, preference, negation, qualification, and uncertainty. Keep the original language. Rewrite only enough to make the memory concise, self-contained, and understandable without conversation context. When appropriate, phrase it as a third-person statement about the user.

Choose exactly one type:
- identity: stable facts, preferences, background, relationships, interests, or personal context
- workflow: recurring ways the user works, decides, plans, or uses tools
- voice: preferred tone, wording, language, formatting, or communication style
- instruction: durable rules for how an assistant should behave or respond

Do not invent, translate, merge, split, omit, deduplicate, explain, or add advice.

Return only a JSON array in this exact shape:
[{"id":1,"type":"identity","content":"..."}]

Input:
{{items}}
'''
          .trim();

  static final String migratePreserveZh = migratePreserveEn;

  static final String migratePreserveEn =
      '''
You are classifying legacy long-term memories into a typed memory system. The system will keep each memory's original wording. You only assign a type.

For every input item, return exactly one output item with the same integer id. Choose exactly one type:
- identity: stable facts, preferences, background, relationships, interests, or personal context
- workflow: recurring ways the user works, decides, plans, or uses tools
- voice: preferred tone, wording, language, formatting, or communication style
- instruction: durable rules for how an assistant should behave or respond

Do not rewrite, translate, invent, merge, split, or omit items. Do not output content.

Return only a JSON array in this exact shape:
[{"id":1,"type":"identity"}]

Input:
{{items}}
'''
          .trim();

  // ── §7.5 injection intros ────────────────────────────────────────────────

  static const String introFullZh = introFullEn;
  static const String introFullEn =
      'The following context is provided by the system. It is not what the user said in this turn.';
  // No longer written: injection always emits a full snapshot. Kept so
  // prompts frozen by earlier versions can still be parsed and stripped.
  static const String introUpdateZh = introUpdateEn;
  static const String introUpdateEn =
      'The following memory changes happened after this conversation started, provided by the system.';

  // ── §7.2 moreHint ────────────────────────────────────────────────────────

  static const String moreHintZh = moreHintEn;
  static const String moreHintEn =
      '[More entries exist. Use memory_search_profile to look them up.]';

  // ── §9.1 / §9.3 time helpers ─────────────────────────────────────────────

  static const List<String> _weekdayAbbrev = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Wraps [timestamp] as `<current_time>EEE yyyy-MM-dd HH:mm:ss</current_time>`
  /// in the local timezone, without a UTC offset (§9.1) by default.
  /// With [useIso8601], emits ISO 8601 to seconds with a UTC offset.
  ///
  /// Four-digit year avoids `yy-MM-dd` / `dd-MM-yy` ambiguity (e.g. 22–26).
  static String formatCurrentTimeTag(
    DateTime timestamp, {
    bool useIso8601 = false,
  }) {
    final local = timestamp.isUtc ? timestamp.toLocal() : timestamp;
    final eee = _weekdayAbbrev[local.weekday - 1];
    final yyyy = local.year.toString();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    if (useIso8601) {
      final offset = local.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final minutes = offset.inMinutes.abs();
      final offsetHours = (minutes ~/ 60).toString().padLeft(2, '0');
      final offsetMinutes = (minutes % 60).toString().padLeft(2, '0');
      return '<current_time>${yyyy.padLeft(4, '0')}-$mm-${dd}T$hh:$min:$ss'
          '$sign$offsetHours:$offsetMinutes</current_time>';
    }
    return '<current_time>$eee $yyyy-$mm-$dd $hh:$min:$ss</current_time>';
  }

  /// Returns which of `{cur_date}`, `{cur_time}`, `{cur_datetime}` occur in
  /// [systemPrompt], in that fixed order. `{timezone}` etc. are ignored (§9.3).
  static List<String> detectTimeVariablesInSystemPrompt(String systemPrompt) {
    const candidates = ['{cur_date}', '{cur_time}', '{cur_datetime}'];
    return [
      for (final token in candidates)
        if (systemPrompt.contains(token)) token,
    ];
  }

  static String rulesFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? rulesZh : rulesEn;

  static String rulesPastConversationRecallFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh
      ? rulesPastConversationRecallZh
      : rulesPastConversationRecallEn;

  static String gateFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? gateZh : gateEn;

  static String extractFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? extractZh : extractEn;

  static String extractToolDefaultScopeRuleFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh
      ? extractToolDefaultScopeRuleZh
      : extractToolDefaultScopeRuleEn;

  static String smartAddFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? smartAddZh : smartAddEn;

  static String smartAddBatchFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? smartAddBatchZh : smartAddBatchEn;

  static String profileDistillFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? profileDistillZh : profileDistillEn;

  static String migrateFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? migrateZh : migrateEn;

  static String migratePreserveFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? migratePreserveZh : migratePreserveEn;

  static String introFullFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? introFullZh : introFullEn;

  static String moreHintFor(MemoryPromptLang lang) =>
      lang == MemoryPromptLang.zh ? moreHintZh : moreHintEn;
}
