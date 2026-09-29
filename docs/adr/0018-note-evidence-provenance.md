# 0018 — Separate note assertions, source provenance, and verification

The note-generation path previously stored a model claim, source citation, and verifier result in one mutable evidence object. The verifier then had to echo runtime evidence IDs, and a failed classification could send the same model output through an evidence-repair loop. This made provenance depend on generated JSON and allowed verification to rewrite the material it was supposed to inspect.

## Status

`accepted` (2026-09-29)

## Decision

Evidence has three owners with non-overlapping responsibilities:

1. The drafting model may emit only an untrusted `NoteGenerationEvidenceCandidate`: assertion type/text, target section, and a proposed source ID/excerpt.
2. The pipeline resolves an exact excerpt against the captured `SourceBundle` and creates the persistent `NoteGenerationEvidenceItem`, internal evidence/reference IDs, text fingerprint, and `[start, end)` span. `Dispatcher` recomputes every source fingerprint from source text at its boundary; caller-provided record IDs are not content fingerprints.
3. The independent verifier is read-only. It checks the complete outline, draft, sources, requirements, and evidence, then returns one status per evidence array position. The program maps positions back to internal IDs and constructs `decisions` and `checkedEvidenceIds`; runtime IDs are never part of the model output contract.

Source fidelity and factual correctness are separate judgments. If the captured source literally says an implausible statement such as `2+2=5`, the exact quote remains located evidence. The verifier may report the statement or resulting note as factually contradicted, but it must not delete, replace, or silently “correct” the source quote.

An empty evidence array does not skip verification. The verifier must still check the outline, draft, source coverage, and user requirements, and must return an empty positional status array.

Standard and deep generation perform one generation pass and one read-only verification pass. A verification finding stops the run with preserved artifacts; it does not trigger automatic content or evidence regeneration.

## Considered Options

1. **Model echoes dynamic evidence IDs** — rejected because runtime identity is not a semantic task and omissions or invented IDs turn otherwise valid judgments into contract failures.
2. **Verifier rewrites failed evidence** — rejected because the judge must not mutate its own evidence and because source quotations are audit records, not repair suggestions.
3. **Skip the verifier when evidence is empty** — rejected because evidence grounding is only one part of note verification.
4. **Position-aligned, schema-constrained read-only output** *(chosen)* — keeps the model task small while the program owns identity, exact spans, and completeness checks.

## Consequences

- `EvidenceSourceRef` is a stable citation handle: internal ID, source ID, source-text fingerprint, exact excerpt, and offsets.
- `resolveEvidenceSourceRef` reports `located`, `stale`, or `missing` without rewriting the citation.
- Local artifact validation and semantic LLM verification remain separate and their issues are combined.
- JSON Schema constrains output shape and array cardinality; ArkTS parsing and domain validation remain authoritative even for providers that only support JSON-object mode.
- A verifier transport or contract failure is reported as `VERIFIER_UNAVAILABLE`; it is not converted into a content finding or a regeneration request.

## Related

- [ADR-0008 — Agent workflows](./0008-capturegraph-self-built-runtime.md)
- [Spec 018 — Agent workflow architecture](../specs/018-agent-workflow-architecture.md)
