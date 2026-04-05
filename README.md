# Noor AI – Quran Companion

An offline-first AI voice assistant that helps users interact with the Quran using speech, AI explanations, and habit-building features.

## Architecture

```
Voice Input → ASR (Whisper) → Intent Detection → API Fetch → LLM (Qwen3.5) → TTS → UI Update
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Android arm64) |
| State | Riverpod |
| Navigation | GoRouter |
| On-device AI | MNN runtime (C++ via FFI) |
| ASR | whisper-base-mnn |
| TTS | supertonic-tts-mnn |
| LLM | Qwen3.5-0.8B-MNN |
| Embeddings | bge-small-en-v1.5-mnn |
| Quran Content API | Quran Foundation via Node backend |
| Quran User API | Quran Foundation OAuth via backend token exchange + User APIs |
| Local DB | SQLite (sqflite) |
| Vector Store | In-memory cosine similarity |

### Project Structure

```
lib/
├── main.dart                       # Entry point
├── app.dart                        # MaterialApp.router
├── core/
│   ├── theme/app_theme.dart        # Dark + Gold Material3 theme
│   ├── models/                     # Data models (Verse, Surah, ChatMessage, etc.)
│   ├── services/
│   │   ├── database_service.dart   # SQLite CRUD
│   │   ├── quran_api_service.dart  # alquran.cloud REST client
│   │   ├── native_bridge.dart      # FFI bindings to libedgemind_core.so
│   │   ├── model_manager.dart      # HuggingFace model download
│   │   ├── voice_service.dart      # Record → ASR → TTS → Playback
│   │   ├── llm_service.dart        # Qwen3.5 generation
│   │   ├── embedding_service.dart  # bge-small text embeddings
│   │   └── vector_store_service.dart # In-memory vector search
│   ├── utils/
│   │   ├── intent_parser.dart      # Rule-based + LLM intent detection
│   │   └── prompt_templates.dart   # LLM prompt templates
│   └── router/app_router.dart      # GoRouter config
├── features/
│   ├── home/
│   │   ├── pages/home_page.dart    # Voice-first home with AnimatedVoiceButton
│   │   ├── widgets/animated_voice_button.dart # Gold animated orb
│   │   └── providers/home_provider.dart # Voice pipeline state machine
│   ├── chat/
│   │   ├── pages/chat_history_page.dart
│   │   └── providers/chat_provider.dart
│   ├── daily_ayah/
│   │   ├── pages/daily_ayah_page.dart
│   │   └── providers/daily_ayah_provider.dart
│   ├── bookmarks/
│   │   ├── pages/bookmarks_page.dart
│   │   └── providers/bookmarks_provider.dart
│   ├── settings/
│   │   └── pages/settings_page.dart
│   └── shell/shell_page.dart       # Bottom nav shell
backend/
├── package.json                    # Node proxy for Quran Foundation content APIs
└── src/index.js                    # Token exchange + content route proxy
native/
└── cpp/                            # Edgemind native C++ core (forked)
    ├── CMakeLists.txt
    ├── src/                        # C++ source (ASR, TTS, LLM, vector DB)
    └── include/                    # C++ headers (FFI interface)
```

## Setup

### Prerequisites

- Flutter SDK (stable, 3.11+)
- Android SDK with NDK
- Android device or emulator (arm64-v8a)

### Build & Run

```bash
# Clone
git clone <repo-url> noor-ai && cd noor-ai

# Start the Quran Foundation backend
cd backend
cp .env.example .env
npm install
npm run dev

# In another terminal, return to the Flutter app root
cd ..

# Get dependencies
flutter pub get

# Run on device (debug)
flutter run --dart-define=QURAN_API_PROVIDER=quranfoundation --dart-define=QF_BACKEND_BASE_URL=http://YOUR_MACHINE_IP:8787 --dart-define=QF_USE_PRELIVE=false

# Build release APK
flutter build apk --release --target-platform android-arm64
```

### Deploy Backend To Render

This repo includes a Render blueprint at `render.yaml` for the Quran Foundation backend.

1. Create a new Web Service from the repository using the Render blueprint.
2. Set `QF_CLIENT_ID` and `QF_CLIENT_SECRET` in the Render dashboard.
3. Keep `QF_USE_PRELIVE=false` for production, or set it to `true` only when you have matching pre-production OAuth credentials.
4. After deploy, use the Render service URL as `QF_BACKEND_BASE_URL` in Flutter.

Example Flutter run command against Render:

```bash
flutter run \
    --dart-define=QURAN_API_PROVIDER=quranfoundation \
    --dart-define=QF_BACKEND_BASE_URL=https://your-render-service.onrender.com \
    --dart-define=QF_USE_PRELIVE=false
```

### AI Models

On first launch, go to **Settings → Download Models** to fetch the on-device AI models from HuggingFace:

| Model | Size | Purpose |
|-------|------|---------|
| whisper-base-mnn | ~40 MB | Speech recognition |
| supertonic-tts-mnn | ~30 MB | Text-to-speech |
| Qwen3.5-0.8B-MNN | ~500 MB | Question answering |
| bge-small-en-v1.5-mnn | ~30 MB | Text embeddings |

### Prebuilt Vector DB

The intended runtime path is to ship a prebuilt zvec bundle in `assets/vector_db/` and let the app copy it into the models directory on startup.

The app should not rebuild the full Quran + tafsir corpus on device. If you need to refresh the vector DB, build it on macOS and restage `assets/vector_db/` before running the app:

```bash
source .venv/bin/activate
python tools/build_vector_db.py \
    --embedding-dir "$HOME/.noor-ai/models/embedding" \
    --assets-db-dir assets/db \
    --output-dir build/vector_db/zvec_db \
    --bundle-dir assets/vector_db \
    --version quran-tafsir-v3
```

Notes:

- `--embedding-dir` must point at the local embedding model directory containing `embedding.mnn` and `tokenizer.json`.
- The script writes the collection to `build/vector_db/zvec_db` and stages a bundle under `assets/vector_db/` with `manifest.json`, `zvec_db_sources.tsv`, and `zvec_db_deleted.txt`.
- After rebuilding the bundle, run `flutter pub get` if assets changed and then launch the app so it copies the refreshed DB into its runtime models directory.

### Native Core Setup

The native C++ core (in `native/cpp/`) is preconfigured with:

- **MNN 3.4.1 prebuilt binaries** (`arm64-v8a`) from [GitHub releases](https://github.com/alibaba/MNN/releases/download/3.4.1/mnn_3.4.1_android_armv7_armv8_cpu_opencl_vulkan.zip)
- **MNN headers** from the bundled source tree
- **Edgemind core** C++ source (ASR, TTS, LLM, vector DB bindings)
- **Sherpa-MNN** for streaming ASR
- **RNNoise** for audio denoising
- **Supertonic TTS** for speech synthesis
- **Zvec** for vector database operations

The prebuilt `.so` files are in `android/app/src/main/jniLibs/arm64-v8a/`:

```
libMNN.so, libMNN_Express.so, libMNN_CL.so, libMNN_Vulkan.so,
libMNNAudio.so, libMNNOpenCV.so, libmnncore.so, libllm.so, libc++_shared.so
```

CMake is wired via `android/app/build.gradle.kts` → `native/cpp/CMakeLists.txt`.

## Features

- **Voice-first interaction**: Tap the golden orb, speak your question
- **7 intents**: Explain ayah, explain surah, play audio, translate, tafsir, emotional guidance, general questions
- **Offline AI**: All inference runs on-device via MNN
- **Daily Ayah**: Fresh verse every day with streak tracking
- **Bookmarks**: Save and annotate verses
- **Emotional guidance**: AI-matched verses for feelings like anxiety, sadness, or gratitude
- **Dark + Gold theme**: Elegant Islamic-inspired design

## API

Content APIs are served through the local Node backend, which exchanges the Quran Foundation client secret server-side and proxies the responses to Flutter.

User login still starts in the app with Quran Foundation OAuth PKCE, but authorization-code exchange and refresh now go through the Node backend because the current OAuth client is confidential.

The backend exposes:

- `POST /api/qf/auth/exchange`
- `POST /api/qf/auth/refresh`
- `GET /api/qf/resources/tafsirs`
- `GET /api/qf/resources/translations`
- `GET /api/qf/resources/recitations`
- `GET /api/qf/chapters`
- `GET /api/qf/chapters/{chapterNumber}/info`
- `GET /api/qf/verses/by_key/{verseKey}`
- `GET /api/qf/verses/by_chapter/{chapterNumber}`
- `GET /api/qf/tafsirs/{resourceId}/by_ayah/{verseKey}`
- `GET /api/qf/tafsirs/{resourceId}/by_chapter/{chapterNumber}`
- `GET /api/qf/recitations/{recitationId}/by_ayah/{verseKey}`
- `GET /api/qf/v1/search`
- `GET /api/qf/verses/random`

The backend service client must still be granted Quran Foundation content scopes. Keeping the client secret on the server fixes the security problem, but it does not grant missing upstream permissions by itself.

## Credits

- [Edgemind](https://github.com/phatneglo/edgemind) – Native AI core
- [MNN](https://github.com/alibaba/MNN) – Mobile Neural Network runtime
- [Al Quran Cloud API](https://alquran.cloud/api) – Quran data
