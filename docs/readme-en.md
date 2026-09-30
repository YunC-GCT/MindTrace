# MindTrace

[简体中文](../README.md) | [English](./readme-en.md)

> A HarmonyOS-native smart note-taking and traceable review app for mathematics learning.

## 1. Project Overview

MindTrace turns math screenshots, formulas, and scattered text into structured notes, saves them after user confirmation, and supports review through personal-note retrieval, knowledge association, and source citations.

The project organizes material understanding, note generation, and review Q&A with an ArkTS-native agent workflow, and presents knowledge connections through a 3D Knowledge Galaxy, forming an "input — organize — associate — review — trace" learning loop.

## 2. Feature Implementation Status

The following reflects code implementation status; testing and on-device validation results will be added later.

| Feature | Status | Notes |
|---|---|---|
| Image & text input | Implemented | Supports camera, album, text, and OCR |
| Structured note generation | Implemented | Supports lightweight, standard, and sectioned generation routes |
| Draft confirmation & incremental editing | Implemented | Preview, modify, cancel, confirm-save, and section-scoped editing |
| AI conversation | Implemented | Supports streaming output, conversation history, and generation progress |
| Personal note RAG | Implemented | Keyword retrieval and expansion through confirmed knowledge relationships |
| Traceable review answers | Implemented | Concept explanation, knowledge comparison, prerequisite lookup, note locating, and question generation, with access to the cited note version |
| 3D Knowledge Galaxy | Implemented | Displays knowledge connections with compatible rendering; currently includes preview samples |
| HarmonyOS integrations | Partially implemented | Card shows the learning overview; Xiaoyi is connected to `SearchNote` |
| Interactive mathematical visualizations, tap-to-connect group learning, vector retrieval | Planned | Full workflows are not yet implemented |

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
| Business layer | Material understanding, note generation, independent verification, retrieval, relationship expansion, and source resolution |
| Shared capabilities | `LlmClient` for unified model requests, OCR for image processing, content protocol for unified Markdown and formulas |
| Data layer | HarmonyOS RDB stores notes, versions, relationships, and generation records; local snapshots store session state |

Workflows run on-device on HarmonyOS; model inference is provided by the configured model service. Current retrieval uses keyword matching and confirmed-relationship expansion; full vector retrieval is not yet integrated.

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
   .\start_ocr_server.bat
   ```

   The service script targets Windows and requires Python 3.10+. Fill the address shown after startup into the app's OCR settings, for example:

   ```text
   http://192.168.1.50:8000/api/v1/ocr/recognize
   ```

   Replace the IP with the service machine's actual address and ensure the device can reach it. See the [OCR service guide](../tools/ocr_service/README.md) for dependency details.

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
├── tools/ocr_service/      # Standalone OCR service
├── scripts/                # Test and engineering check scripts
├── docs/                   # Architecture, specs, plans, and historical archive
├── build-profile.json5     # SDK, module, and signing configuration
├── oh-package.json5        # Project dependencies
├── CONTEXT.md              # Project terminology
└── AGENTS.md               # Repository collaboration conventions
```

## 7. Upcoming Additions

- Product screenshots & demo: to be added.
- Testing & verification: to be added.
- Known issues & roadmap: to be added.
- Documentation navigation & contribution guide: to be added.
- License & acknowledgments: to be added.
