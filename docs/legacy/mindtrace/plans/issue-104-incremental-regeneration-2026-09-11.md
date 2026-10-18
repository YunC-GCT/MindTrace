---
name: issue-104-incremental-regeneration
status: completed
issue: 104
parent: 96
---

# Issue 104 Incremental Regeneration

1. Add red seam tests for Dispatcher, ConversationWorkflow/AgentChatService, NoteGenerationRepository, and KnowledgeUnitWriteService plus deterministic parser/planner/merge behavior. Completed.
2. Add typed regeneration contracts and stable section parser/hash, manual-edit locking, change planner, patch-only merge gate, consistency validation, and diff model in common. Completed.
3. Extend persisted run/revision/source lookup so regeneration loads the current KnowledgeUnit, latest generated manifest, source snapshots, and base version. Completed.
4. Add KnowledgeModel patch-only LLM call and Dispatcher regeneration branch; save checkpoint/manifest and preserve current note metadata. Completed.
5. Extend prepared confirmation and PersistNode/NoteDaoAdapter/KnowledgeUnitWriteService for expectedVersion updates, atomic revision+commit, embedding invalidation, and explicit VERSION_CONFLICT. Completed.
6. Add explicit conversation regeneration entry and diff preview; on conflict reload/replan and emit a fresh preview. Completed.
7. Run ArkTS checks frequently, focused source/Hypium-relevant tests, full source tests, lint, naming, diff checks, and complete debug product build. Completed. Device acceptance and #105 cleanup intentionally not performed.
