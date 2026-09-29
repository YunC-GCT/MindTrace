/**
 * ChatHistorySchema.ets - Shared chat snapshot format version owner.
 *
 * Path: entry/src/main/ets/services/ChatHistorySchema.ets
 * Responsibility: Keep the root snapshot version constant shared by decoders and writers.
 * Dependencies: None.
 *
 * Data flow:
 *   Root schema version -> decoder catalog and taskpool/worker writers.
 *
 * Versioning rule:
 *   Additive optional fields stay within the current decoder. Removing a field,
 *   changing its meaning, or introducing a required field needs a new root
 *   schema version and an explicit decoder catalog entry.
 */

export const CHAT_HISTORY_V1_SCHEMA_VERSION: number = 1;
export const CHAT_HISTORY_SCHEMA_VERSION: number = CHAT_HISTORY_V1_SCHEMA_VERSION;
