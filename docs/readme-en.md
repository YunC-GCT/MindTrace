# MindTrace

[简体中文](../README.md) | [English](./readme-en.md)

> A HarmonyOS-native smart note-taking and traceable review app for mathematics learning.

## 1. Project Overview

MindTrace turns math screenshots, formulas, and scattered text into structured notes, saves them after user confirmation, and supports review through personal-note retrieval, knowledge association, and source citations.

The project organizes material understanding, note generation, and review Q&A with an ArkTS-native agent workflow. Note retrieval uses five-way hybrid recall (full-sentence FTS, math signature, token OR, short-term match, and vector semantics), fused with RRF and followed by conditional query rewriting and cross-encoder reranking. Before writing, notes are deduplicated and arbitrated three ways, so duplicate notes are avoided without discarding supplementary content. A 3D Knowledge Galaxy presents knowledge connections, forming an "input — organize — associate — review — trace" learning loop.

Current stage (November 2026): the v1 on-device A2A path is working — Xiaoyi can ingest notes in place and return receipts. The main line has shifted to retrieval quality and note governance. The project is in testing mode and not moving toward release.

## 2. Feature Implementation Status

The following reflects code implementation and on-device probe verification status (2026-11-07).

| Feature | Status | Notes |
|---|---|---|
| Image & text input | Implemented | Camera, album, text, and OCR; Xiaoyi A2A messages can be organized and ingested in place |
| Structured note generation | Implemented | Lightweight, standard, and sectioned generation routes |
| Draft confirmation & incremental editing | Implemented | Preview, modify, cancel, confirm-save, and section-scoped editing |
| AI conversation | Implemented | Streaming output, conversation history, and generation progress |
| Personal note retrieval | Implemented | Five-way hybrid recall (full-sentence FTS / math signature / token OR / short-term LIKE / vector semantics) + RRF fusion; retrieval scores travel with citations |
| Semantic vector retrieval | Implemented (service required) | Local BGE service (`tools/embedding_service`, default bge-m3) or an OpenAI-compatible cloud embedding endpoint; falls back to lexical-only when unconfigured |
| Evidence judgement & study modes | Partially implemented | An LLM judges whether candidates are on-topic before answering, filtering out-of-corpus citations; strict / balanced / expansive policies live in the orchestration layer (default balanced) but are not exposed in the UI yet |
| Note dedupe & arbitration | Implemented | L1 deterministic rules + vector fallback + LLM three-way arbitration (same / supplement / different); supplement content is still written and never discarded |
| Note suggestions | Partially implemented | create / append / merge suggestions are emitted as events and logs; not rendered in the UI yet |
| Traceable review answers | Implemented | Concept explanation, comparison, prerequisite lookup, note locating, and question generation; citations carry fusion scores and summaries, with note-version lookup |
| 3D Knowledge Galaxy | Implemented | Displays knowledge connections with compatible rendering; currently includes preview samples |
| HarmonyOS integrations | Partially implemented | Card shows the learning overview; Xiaoyi A2A now supports draft preview and confirm-to-save (reply "confirm" to save / "cancel" to discard), receipts, and an image fallback plan; intent registration and Agent Framework Kit launch depend on release, deferred in testing mode |
| Interactive mathematical visualizations, tap-to-connect group learning | Planned | Full workflows are not yet implemented |

Evaluations now use the public **MathNet-Retrieve** benchmark (CC-BY-4.0, math-aware retrieval, 334 Chinese queries); the repository's 100-note fixture is kept only for smoke tests and is no longer used for reported metrics. The offline evaluation script lives in [`scripts/rag-lab/`](../scripts/rag-lab/); raw records are in [`docs/research/agent-framework-layering-review-2026-11-02.md`](./research/agent-framework-layering-review-2026-11-02.md) §37–§54.

## 3. Core Usage Flows

**Organize notes**

Input an image or text → Describe organizing requirements → Review the draft → Edit and confirm → Save the note.

**Review & trace sources**

Ask a note-based question → Retrieve related material → Generate a source-backed answer → Click citations to view the note and its version.

For example:

```text
Explain limits based on my notes.
Compare limits and continuity in my notes.
What prerequisite knowledge is needed before learning derivatives?
Generate 3 review questions based on my integral notes.
```

No note is saved before draft confirmation; when sources are insufficient, the user is prompted to add material.

## 4. Technical Architecture

| Layer | Primary responsibilities |
|---|---|
| Interaction layer | ArkUI pages, AI overlay, Knowledge Galaxy, home-screen card, and Xiaoyi entry |
| Orchestration layer | ArkTS-native `StateGraph`, reused across capture, conversation, tool-calling, and skill-intent workflows |
| Business layer | Material understanding, note generation, hybrid retrieval (RRF fusion), evidence judgement, dedupe and arbitration, and source resolution |
| Shared capabilities | `LlmClient` for unified model requests, OCR for image processing, content protocol for unified Markdown and formulas, and an embedding port that works with lexical or cloud vectors |
| Data layer | HarmonyOS RDB (schema v22) stores notes, versions, relationships, generation records, full-text indexes, and vector chunks; local snapshots store session state |

Workflows run on-device on HarmonyOS; chat and generation models are provided by the configured model service. Semantic retrieval requires a separate embedding endpoint: run the BGE service locally with `tools/embedding_service`, or connect an OpenAI-compatible cloud embedding endpoint. When unconfigured or offline, retrieval automatically falls back to lexical-only.

## 5. Quick Start

1. **Get the code**

   ```bash
   git clone --branch develop https://github.com/YunC-GCT/MindTrace.git
   cd MindTrace
   ```

2. **Open the project**

   Open the repository root with DevEco Studio and complete dependency sync. The current SDK configuration is **HarmonyOS 6.1.1 (API 24)**; see `build-profile.json5` for the authoritative value.

3. **Configure and run**

   Configure local debug signing, connect a device or emulator that meets the version requirement, and run `entry`.

4. **Configure the model**

   In the app's "AI Settings", select a provider, fill in the API key, service address, and model, save, then test the connection.

5. **Configure external OCR as needed**

   Quick mode prioritizes on-device text recognition. Formula recognition or server-side fallback requires starting the companion OCR service:

   ```powershell
   .\start-ocr-server.bat
   ```

   The service script targets Windows and requires Python 3.10+. Fill the address shown after startup into the app's OCR settings, for example:

   ```text
   http://192.168.1.50:8000/api/v1/ocr/recognize
   ```

   Replace the IP with the service machine's actual address and ensure the device can reach it. See the [OCR service guide](../tools/ocr_service/README.md) for dependency details.

6. **Optional: enable semantic retrieval**

   Lexical retrieval works out of the box. For semantic recall, start the local embedding service (Windows, Python 3.10+; the first run downloads the model, about 1.3 GB):

   ```powershell
   .\tools\embedding_service\start.bat
   ```

   Then fill in the service address and model name in the app's embedding settings, for example:

   ```text
   Endpoint: http://<PC-IP>:8001/v1
   Model: BAAI/bge-m3
   ```

   Replace the IP with the service machine's actual address; the API key can be left empty. The settings page shows "Online · 1024 dims"; when the service is not running, retrieval falls back to lexical-only.

On first use, it is recommended to complete "generate a note from text → confirm and save → ask based on the note → view sources" before trying image input.

## 6. Repository Structure

```text
MindTrace/
├── entry/                  # Main app, pages, business services, and data access
├── agents/                 # Dispatch, classification, note generation, and capture workflows
├── common/                 # StateGraph, model calls, tools, and shared capabilities
├── skill/                  # Xiaoyi intent entry
├── cardservice/            # Home-screen card
├── AppScope/               # App-level configuration and resources
├── tools/
│   ├── ocr_service/        # Standalone OCR service
│   └── embedding_service/  # Local BGE semantic retrieval service
├── scripts/                # Test and engineering check scripts
├── docs/                   # Architecture, specs, plans, and historical archive
├── build-profile.json5     # SDK, module, and signing configuration
├── oh-package.json5        # Project dependencies
├── CONTEXT.md              # Project terminology
└── AGENTS.md               # Repository collaboration conventions
```

## 7. Upcoming Additions

- Product screenshots & demo: to be added.
- Testing & verification: retrieval evaluations and on-device probe records live in `docs/research/`; a systematic regression report is pending.
- Known issues & roadmap: see `docs/agents/phase-tracker.md` and the evaluation summary above.
- Documentation navigation: see `docs/index.md`.
- License & acknowledgments: to be added.
