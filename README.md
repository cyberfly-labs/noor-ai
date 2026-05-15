# Noor AI – Quran Companion

An offline-first AI voice assistant that helps users interact with the Quran using speech, AI explanations, and habit-building features. Built for the Quran MCP Hackathon.

## Architecture

```
Voice Input → ASR (Whisper) → Intent Detection → Hybrid Retrieval (MCP Search + Direct API) → LLM (Qwen 3.5) → TTS → UI Update
```

## Quran MCP Integration

Noor AI leverages the **Quran Model Context Protocol (MCP)** server (`mcp.quran.ai`) to power its high-precision semantic search and RAG (Retrieval-Augmented Generation) pipeline.

### Why MCP?
While traditional keyword search often fails with conceptual or emotional queries (e.g., "how to find peace during hardship"), the Quran MCP provides:
- **Semantic Understanding**: Finds verses based on meaning and context, not just matching words.
- **Scholar-Grounded Search**: Retrieves verses that are contextually relevant to the user's intent.
- **RAG Grounding**: Before the on-device LLM (Qwen 3.5) answers a question, it queries the MCP server to retrieve grounded "evidence." This ensures the AI's explanation is anchored in the actual text of the Quran, significantly reducing hallucinations.

### Hybrid Retrieval Strategy
To ensure a premium user experience, the app employs a hybrid approach:
- **MCP for Search**: The `search_quran` tool is used for all semantic and topic-based queries.
- **Direct Content API**: Once the MCP identifies the relevant verse keys, the app pulls the detailed translation and tafsir directly from the high-performance **Quran.com v4 API**.
- **Local Caching**: All retrieved data is cached in a local SQLite database, providing near-instant load times for subsequent interactions.


### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Android arm64) |
| State | Riverpod |
| Navigation | GoRouter |
| On-device AI | MNN runtime (C++ via FFI) |
| ASR | whisper-tiny-en-mnn |
| TTS | supertonic-tts-mnn |
| LLM | Qwen3.5-0.8B-MNN |
| Quran Content API | Direct integration with Quran.com v4 API |
| Quran RAG Search | Quran MCP (mcp.quran.ai) |
| Quran User API | Quran Foundation OAuth + User APIs (Bookmarks, Streaks, Reflections) |
| Local DB | SQLite (sqflite) with Cache-First logic |

### Project Structure

```
lib/
├── main.dart                       # Entry point & service warm-up
├── app.dart                        # MaterialApp.router & Theme
├── core/
│   ├── theme/app_theme.dart        # Premium Dark + Gold Material3 theme
│   ├── models/                     # Data models (Verse, Surah, ChatMessage, etc.)
│   ├── services/
│   │   ├── database_service.dart   # SQLite persistence & caching
│   │   ├── quran_api_service.dart  # Direct Quran.com v4 REST client
│   │   ├── quran_mcp_service.dart  # Semantic search via Quran MCP
│   │   ├── quran_rag_service.dart  # Grounded evidence retrieval (Hybrid)
│   │   ├── quran_user_sync_service.dart # Remote sync for User APIs
│   │   ├── native_bridge.dart      # FFI bindings to libedgemind_core.so
│   │   ├── model_manager.dart      # HuggingFace model download & management
│   │   ├── voice_service.dart      # Record → ASR → TTS pipeline
│   │   └── llm_service.dart        # On-device Qwen3.5 inference
│   └── router/app_router.dart      # GoRouter configuration
├── features/
│   ├── home/                       # Voice-first dashboard with habit tracking
│   ├── verse/                      # High-performance verse & tafsir reader
│   ├── search/                     # Semantic search interface
│   ├── chat/                       # AI conversation history
│   ├── daily_ayah/                 # Featured daily content
│   ├── bookmarks/                  # Quran Foundation synced bookmarks
│   └── tools/                      # Collections, Reflections, and Goals
```

## Setup

### Prerequisites

- Flutter SDK (stable, 3.11+)
- Android SDK with NDK
- Android device (arm64-v8a)

### Build & Run

```bash
# Clone
git clone <repo-url> noor-ai && cd noor-ai

# Get dependencies
flutter pub get

# Run on device (debug)
# Note: Ensure you have your Quran Foundation OAuth credentials configured
flutter run
```

### AI Models

On first launch, go to **Settings → Download Models** to fetch the on-device AI models (~600MB total):

| Model | Size | Purpose |
|-------|------|---------|
| whisper-tiny-en | ~40 MB | Speech recognition |
| supertonic-tts | ~30 MB | Text-to-speech |
| Qwen3.5-0.8B | ~500 MB | Question answering |

### Native Core

The native C++ core (in `native/cpp/`) is powered by **MNN** and **Edgemind**, providing high-performance inference on mobile CPUs. The prebuilt `.so` files are included in `android/app/src/main/jniLibs/arm64-v8a/`.

## Features

- **Voice-first interaction**: Tap the golden orb, speak naturally to ask about any verse or topic.
- **Semantic RAG Search**: Powered by **Quran MCP** (`mcp.quran.ai`), providing contextually relevant verses even for vague or emotional queries.
- **Offline-First Intelligence**: All AI inference (Speech-to-Text, LLM Reasoning, Text-to-Speech) runs entirely on-device via MNN.
- **Quran Foundation Integration**:
    - **Bookmarks**: Full sync with your Quran.com account.
    - **Streaks & Goals**: Keep your daily reading habit alive.
    - **Reflections**: Share and read reflections via the Post API.
- **Emotional Guidance**: AI-grounded verses for feelings like anxiety, gratitude, or seeking hope.
- **Cache-First Content**: Blazing fast verse and tafsir loading via local SQLite caching and parallelized API calls.

## Credits

- [Quran Foundation](https://quran.foundation) – Quran APIs and MCP
- [Edgemind](https://github.com/phatneglo/edgemind) – Native AI core
- [MNN](https://github.com/alibaba/MNN) – Mobile Neural Network runtime
- [Quran.com](https://quran.com) – The inspiration for excellence in Quranic tech
