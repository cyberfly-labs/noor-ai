#!/usr/bin/env python3

"""Build a precomputed zvec collection on macOS using Python zvec + MNN.

This script mirrors the app's current native ingestion behavior closely enough
to prebuild a reusable vector DB outside the phone:

- Corpus documents come from the local SQLite assets and use English
    translation plus the full tafsir text.
- Emotional guidance verses mirror the fixed seed set in the Flutter app.
- Passage embeddings are generated without the BGE query prefix.
- Stored zvec doc IDs are sanitized chunk IDs, while the original logical hash
  is preserved in the scalar `hash` field and metadata JSON.

The resulting collection directory can be copied into the app's runtime models
directory or staged into assets/vector_db for bundling.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import MNN
import numpy as np
import zvec


MAX_SEQ_LEN = 512
DEFAULT_EMBED_DIM = 384
BGE_QUERY_PREFIX = "Represent this sentence for searching relevant passages: "


@dataclass(frozen=True)
class SeedDocument:
    storage_id: str
    logical_hash: str
    content: str
    metadata: dict[str, str]


EMOTIONAL_VERSES: tuple[dict[str, str], ...] = (
    {
        "verse_key": "2:286",
        "category": "comfort_relief",
        "emotion": "hardship relief anxiety worry stress overwhelmed burden resilience",
        "translation_text": "Allah does not burden a soul beyond that it can bear.",
    },
    {
        "verse_key": "94:5",
        "category": "comfort_relief",
        "emotion": "hardship relief sadness difficulty hope ease struggle",
        "translation_text": "For indeed, with hardship will be ease.",
    },
    {
        "verse_key": "94:6",
        "category": "comfort_relief",
        "emotion": "hardship relief sadness difficulty hope ease struggle",
        "translation_text": "Indeed, with hardship will be ease.",
    },
    {
        "verse_key": "9:51",
        "category": "comfort_relief",
        "emotion": "hardship decree trust acceptance trial relief surrender",
        "translation_text": "Nothing will happen to us except what Allah has decreed for us.",
    },
    {
        "verse_key": "94:7-8",
        "category": "comfort_relief",
        "emotion": "hardship worship renewal longing devotion recovery",
        "translation_text": "So when you have finished your duties, then stand up for worship. And to your Lord direct your longing.",
    },
    {
        "verse_key": "13:28",
        "category": "calm_peace",
        "emotion": "anxiety calm peace heart rest remembrance worry stress",
        "translation_text": "Verily, in the remembrance of Allah do hearts find rest.",
    },
    {
        "verse_key": "89:27-30",
        "category": "calm_peace",
        "emotion": "peace calm tranquil soul contentment return serenity",
        "translation_text": "O tranquil soul, return to your Lord, well-pleased and pleasing.",
    },
    {
        "verse_key": "2:152",
        "category": "calm_peace",
        "emotion": "peace remembrance closeness calm heart gratitude",
        "translation_text": "So remember Me; I will remember you.",
    },
    {
        "verse_key": "39:53",
        "category": "hope_trust",
        "emotion": "hope trust mercy despair guilt regret sin forgiveness",
        "translation_text": "O My servants who have transgressed against themselves, do not despair of the mercy of Allah. Indeed, Allah forgives all sins.",
    },
    {
        "verse_key": "65:3",
        "category": "hope_trust",
        "emotion": "hope trust reliance uncertainty tawakkul relief provision",
        "translation_text": "And whoever relies upon Allah, then He is sufficient for him.",
    },
    {
        "verse_key": "12:87",
        "category": "hope_trust",
        "emotion": "hope despair relief hopelessness trust",
        "translation_text": "Indeed, no one despairs of relief from Allah except the disbelieving people.",
    },
    {
        "verse_key": "7:156",
        "category": "mercy_forgiveness",
        "emotion": "mercy forgiveness compassion hope healing",
        "translation_text": "My mercy encompasses all things.",
    },
    {
        "verse_key": "4:110",
        "category": "mercy_forgiveness",
        "emotion": "guilt regret forgiveness repentance mercy sin",
        "translation_text": "Whoever does a wrong or wrongs himself but then seeks forgiveness of Allah will find Allah Forgiving and Merciful.",
    },
    {
        "verse_key": "6:54",
        "category": "mercy_forgiveness",
        "emotion": "mercy compassion hope repentance",
        "translation_text": "Your Lord has decreed upon Himself mercy.",
    },
    {
        "verse_key": "14:7",
        "category": "gratitude_blessings",
        "emotion": "gratitude thankful blessings increase favor abundance",
        "translation_text": "If you are grateful, I will surely increase you.",
    },
    {
        "verse_key": "16:18",
        "category": "gratitude_blessings",
        "emotion": "gratitude blessings favors abundance reflection",
        "translation_text": "If you tried to count Allah’s favors, you could never enumerate them.",
    },
    {
        "verse_key": "2:172",
        "category": "gratitude_blessings",
        "emotion": "gratitude provision blessing thankfulness",
        "translation_text": "Eat from the good things We have provided for you and be grateful to Allah.",
    },
    {
        "verse_key": "2:153",
        "category": "patience_strength",
        "emotion": "patience strength endurance struggle prayer resilience",
        "translation_text": "Indeed, Allah is with the patient.",
    },
    {
        "verse_key": "3:139",
        "category": "patience_strength",
        "emotion": "patience strength sadness courage hope grief",
        "translation_text": "Do not lose hope nor be sad.",
    },
    {
        "verse_key": "29:69",
        "category": "patience_strength",
        "emotion": "patience striving strength guidance perseverance",
        "translation_text": "Those who strive for Us, We will surely guide them to Our ways.",
    },
    {
        "verse_key": "93:3",
        "category": "hope_trust",
        "emotion": "abandoned forsaken alone lonely reassurance",
        "translation_text": "Your Lord has not taken leave of you, nor has He detested you.",
    },
    {
        "verse_key": "9:40",
        "category": "calm_peace",
        "emotion": "fear lonely alone calm reassurance",
        "translation_text": "Do not grieve; indeed Allah is with us.",
    },
    {
        "verse_key": "3:173",
        "category": "hope_trust",
        "emotion": "fear trust safety reliance protection",
        "translation_text": "Sufficient for us is Allah, and He is the best Disposer of affairs.",
    },
)


def normalize_text(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = re.sub(r"\s+", " ", value).replace("﴿", "").replace("﴾", "").strip()
    return normalized or None


def combine_translation_parts(text: str | None, footnotes: str | None) -> str | None:
    normalized_text = normalize_text(text)
    normalized_footnotes = normalize_text(footnotes)
    if not normalized_text:
        return normalized_footnotes
    if not normalized_footnotes:
        return normalized_text
    return f"{normalized_text}\nFootnotes: {normalized_footnotes}"


def sanitize_doc_id_component(value: str) -> str:
    output: list[str] = []
    last_was_underscore = False
    for char in value:
        allowed = char.isalnum() or char in {"_", "-"}
        out = char if allowed else "_"
        if out == "_":
            if not last_was_underscore:
                output.append(out)
            last_was_underscore = True
        else:
            output.append(out)
            last_was_underscore = False
    sanitized = "".join(output).strip("_")
    return sanitized or "doc"


def chunk_id_for_hash(logical_hash: str, index: int) -> str:
    return f"chunk_{sanitize_doc_id_component(logical_hash)}_{index}"


class WordPieceTokenizer:
    def __init__(self, tokenizer_path: Path, max_input_chars: int = 100) -> None:
        self.max_input_chars = max_input_chars
        self.continuing_prefix = "##"
        self.vocab: dict[str, int] = {}
        self.unk_id = 100
        self.cls_id = 101
        self.sep_id = 102
        self.pad_id = 0
        self._load(tokenizer_path)

    def _load(self, tokenizer_path: Path) -> None:
        payload = json.loads(tokenizer_path.read_text(encoding="utf-8"))
        model = payload.get("model") or {}
        vocab = model.get("vocab")
        if isinstance(vocab, dict):
            self.vocab = {str(key): int(value) for key, value in vocab.items()}
        elif isinstance(vocab, list):
            built: dict[str, int] = {}
            for index, entry in enumerate(vocab):
                if isinstance(entry, list) and entry and isinstance(entry[0], str):
                    built[entry[0]] = index
                elif isinstance(entry, str):
                    built[entry] = index
            self.vocab = built

        for entry in payload.get("added_tokens") or []:
            if isinstance(entry, dict) and isinstance(entry.get("content"), str):
                self.vocab[entry["content"]] = int(entry.get("id", self.vocab.get(entry["content"], 0)))

        if isinstance(model.get("continuing_subword_prefix"), str):
            self.continuing_prefix = model["continuing_subword_prefix"]

        self.cls_id = self._find_id(("[CLS]", "<s>"), 101)
        self.sep_id = self._find_id(("[SEP]", "</s>"), 102)
        self.pad_id = self._find_id(("[PAD]", "<pad>"), 0)
        self.unk_id = self._find_id(("[UNK]", "<unk>"), self.unk_id)

        if not self.vocab:
            raise RuntimeError(f"Tokenizer vocab is empty: {tokenizer_path}")

    def _find_id(self, candidates: tuple[str, ...], fallback: int) -> int:
        for token in candidates:
            if token in self.vocab:
                return self.vocab[token]
        return fallback

    def _basic_tokenize(self, text: str) -> list[str]:
        lower = "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in text)
        tokens: list[str] = []
        current: list[str] = []
        for ch in lower:
            if ch.isspace():
                if current:
                    tokens.append("".join(current))
                    current.clear()
                continue
            if re.match(r"[!-/:-@\[-`{-~]", ch):
                if current:
                    tokens.append("".join(current))
                    current.clear()
                tokens.append(ch)
                continue
            current.append(ch)
        if current:
            tokens.append("".join(current))
        return tokens

    def _wordpiece_tokenize(self, word: str) -> list[int]:
        if len(word) > self.max_input_chars:
            return [self.unk_id]
        ids: list[int] = []
        start = 0
        while start < len(word):
            end = len(word)
            found: int | None = None
            while start < end:
                piece = word[start:end]
                if start > 0:
                    piece = self.continuing_prefix + piece
                if piece in self.vocab:
                    found = self.vocab[piece]
                    ids.append(found)
                    break
                end -= 1
            if found is None:
                ids.append(self.unk_id)
                break
            start = end
        return ids

    def tokenize(self, text: str, max_len: int = MAX_SEQ_LEN) -> list[int]:
        ids = [self.cls_id]
        for word in self._basic_tokenize(text):
            for piece_id in self._wordpiece_tokenize(word):
                if len(ids) >= max_len - 1:
                    break
                ids.append(piece_id)
            if len(ids) >= max_len - 1:
                break
        ids.append(self.sep_id)
        return ids


class MnnEmbeddingModel:
    def __init__(self, model_dir: Path, threads: int = 4) -> None:
        self.model_dir = model_dir
        self.threads = threads
        self.tokenizer = WordPieceTokenizer(model_dir / "tokenizer.json")
        self.model_path = self._resolve_model_path(model_dir)
        self.interpreter = MNN.Interpreter(str(self.model_path))
        self.session = self._create_session()
        self.input_ids_tensor = self.interpreter.getSessionInput(self.session, "input_ids")
        if self.input_ids_tensor is None:
            raise RuntimeError("MNN model is missing required input 'input_ids'")
        self.attention_mask_tensor = self.interpreter.getSessionInput(self.session, "attention_mask")
        self.token_type_tensor = self.interpreter.getSessionInput(self.session, "token_type_ids")
        self.output_names = ("last_hidden_state", "embeddings", "sentence_embedding", "output")
        self.embedding_dim = DEFAULT_EMBED_DIM
        self.host_input_ids_tensor = None
        self.host_attention_mask_tensor = None
        self.host_token_type_tensor = None
        self.host_output_tensor = None
        self._ensure_input_shapes()
        self._detect_output_dim()

    @staticmethod
    def _resolve_model_path(model_dir: Path) -> Path:
        for candidate in ("embedding.mnn", "model.mnn", "llm.mnn"):
            path = model_dir / candidate
            if path.exists():
                return path
        raise FileNotFoundError(f"No embedding model file found in {model_dir}")

    def _create_session(self):
        configs = (
            {"backend": "CPU", "precision": "low", "numThread": self.threads},
            {"backend": "CPU", "numThread": self.threads},
            None,
        )
        last_error: Exception | None = None
        for config in configs:
            try:
                if config is None:
                    return self.interpreter.createSession()
                return self.interpreter.createSession(config)
            except TypeError as exc:
                last_error = exc
                continue
        if last_error is not None:
            raise last_error
        raise RuntimeError("Unable to create MNN session")

    def _ensure_input_shapes(self) -> None:
        shape = (1, MAX_SEQ_LEN)
        self.interpreter.resizeTensor(self.input_ids_tensor, shape)
        if self.attention_mask_tensor is not None:
            self.interpreter.resizeTensor(self.attention_mask_tensor, shape)
        if self.token_type_tensor is not None:
            self.interpreter.resizeTensor(self.token_type_tensor, shape)
        self.interpreter.resizeSession(self.session)
        self.host_input_ids_tensor = MNN.Tensor(
            self.input_ids_tensor,
            MNN.Tensor_DimensionType_Caffe,
        )
        self.host_attention_mask_tensor = (
            MNN.Tensor(
                self.attention_mask_tensor,
                MNN.Tensor_DimensionType_Caffe,
            )
            if self.attention_mask_tensor is not None
            else None
        )
        self.host_token_type_tensor = (
            MNN.Tensor(
                self.token_type_tensor,
                MNN.Tensor_DimensionType_Caffe,
            )
            if self.token_type_tensor is not None
            else None
        )
        self.host_output_tensor = None

    def _resolve_output_tensor(self):
        for name in self.output_names:
            tensor = self.interpreter.getSessionOutput(self.session, name)
            if tensor is not None:
                return tensor
        return self.interpreter.getSessionOutput(self.session)

    def _detect_output_dim(self) -> None:
        output_tensor = self._resolve_output_tensor()
        if output_tensor is None:
            return
        shape = output_tensor.getShape()
        if shape:
            last_dim = int(shape[-1])
            if 0 < last_dim < 10000:
                self.embedding_dim = last_dim

    @staticmethod
    def _copy_tensor(device_tensor, host_tensor, array: np.ndarray) -> None:
        if host_tensor is None:
            raise RuntimeError("Host tensor is not initialized")
        view = host_tensor.getNumpyData()
        if view is None:
            raise RuntimeError("Unable to access host tensor numpy buffer")
        view[...] = array
        host_tensor.copyFrom(np.asarray(view, dtype=array.dtype))
        device_tensor.copyFromHostTensor(host_tensor)

    def _read_tensor(self, device_tensor) -> np.ndarray:
        if self.host_output_tensor is None or tuple(self.host_output_tensor.getShape()) != tuple(device_tensor.getShape()):
            self.host_output_tensor = MNN.Tensor(
                device_tensor,
                MNN.Tensor_DimensionType_Caffe,
            )
        device_tensor.copyToHostTensor(self.host_output_tensor)
        array = self.host_output_tensor.getNumpyData()
        if array is None:
            raise RuntimeError("Unable to access output host tensor numpy buffer")
        return np.asarray(array)

    def embed(self, text: str, *, is_query: bool = False) -> np.ndarray:
        model_text = f"{BGE_QUERY_PREFIX}{text}" if is_query else text
        token_ids = self.tokenizer.tokenize(model_text, MAX_SEQ_LEN)
        seq_len = min(len(token_ids), MAX_SEQ_LEN)

        input_ids = np.zeros((1, MAX_SEQ_LEN), dtype=np.int32)
        input_ids[0, :seq_len] = np.asarray(token_ids[:seq_len], dtype=np.int32)
        attention_mask = np.zeros((1, MAX_SEQ_LEN), dtype=np.int32)
        attention_mask[0, :seq_len] = 1
        token_type_ids = np.zeros((1, MAX_SEQ_LEN), dtype=np.int32)

        self._copy_tensor(self.input_ids_tensor, self.host_input_ids_tensor, input_ids)
        if self.attention_mask_tensor is not None:
            self._copy_tensor(
                self.attention_mask_tensor,
                self.host_attention_mask_tensor,
                attention_mask,
            )
        if self.token_type_tensor is not None:
            self._copy_tensor(
                self.token_type_tensor,
                self.host_token_type_tensor,
                token_type_ids,
            )

        self.interpreter.runSession(self.session)
        output_tensor = self._resolve_output_tensor()
        if output_tensor is None:
            raise RuntimeError("No output tensor found after MNN inference")

        output = self._read_tensor(output_tensor)
        if output.ndim == 3:
            embedding = output[0, 0, : self.embedding_dim]
        elif output.ndim == 2:
            embedding = output[0, : self.embedding_dim]
        elif output.ndim == 1:
            embedding = output[: self.embedding_dim]
        else:
            raise RuntimeError(f"Unsupported output shape: {output.shape}")

        embedding = np.asarray(embedding, dtype=np.float32)
        norm = float(np.linalg.norm(embedding))
        if norm > 1e-6:
            embedding = embedding / norm
        return embedding


def load_quran_seed_documents(assets_db_dir: Path) -> list[SeedDocument]:
    arabic_db_path = assets_db_dir / "quran.db"
    translation_db_path = assets_db_dir / "english_saheeh.db"
    tafsir_db_path = assets_db_dir / "quran-tafsir-english.db"

    with sqlite3.connect(arabic_db_path) as arabic_db, sqlite3.connect(translation_db_path) as translation_db, sqlite3.connect(tafsir_db_path) as tafsir_db:
        arabic_rows = arabic_db.execute(
            "SELECT sora, aya_no FROM quran ORDER BY id ASC"
        ).fetchall()
        translation_rows = translation_db.execute(
            "SELECT sura, aya, text, footnotes FROM english_saheeh"
        ).fetchall()
        tafsir_rows = tafsir_db.execute(
            "SELECT ayah_key, text FROM tafsir"
        ).fetchall()

    translation_map = {
        f"{row[0]}:{row[1]}": combine_translation_parts(row[2], row[3]) or ""
        for row in translation_rows
    }
    tafsir_map = {
        str(row[0] or ""): normalize_text(row[1]) or ""
        for row in tafsir_rows
    }

    documents: list[SeedDocument] = []
    for surah_number, ayah_number in arabic_rows:
        verse_key = f"{surah_number}:{ayah_number}"
        translation = translation_map.get(verse_key, "")
        tafsir = tafsir_map.get(verse_key, "")
        sections: list[str] = []
        if translation:
            sections.append(f"Translation: {translation}")
        if tafsir:
            sections.append(f"Tafsir: {tafsir}")
        if not sections:
            continue

        logical_hash = f"quran_{verse_key}"
        documents.append(
            SeedDocument(
                storage_id=chunk_id_for_hash(logical_hash, 0),
                logical_hash=logical_hash,
                content="\n".join(sections),
                metadata={
                    "kind": "quran_corpus",
                    "verse_key": verse_key,
                    "surah": str(surah_number),
                    "ayah": str(ayah_number),
                    "source": "Local English Tafsir",
                    "hash": logical_hash,
                },
            )
        )
    return documents


def load_emotional_seed_documents() -> list[SeedDocument]:
    documents: list[SeedDocument] = []
    for item in EMOTIONAL_VERSES:
        verse_key = item["verse_key"]
        logical_hash = f"emotion_{verse_key}"
        documents.append(
            SeedDocument(
                storage_id=chunk_id_for_hash(logical_hash, 0),
                logical_hash=logical_hash,
                content=item["translation_text"],
                metadata={
                    "kind": "emotional",
                    "verse_key": verse_key,
                    "category": item["category"],
                    "emotion": item["emotion"],
                    "hash": logical_hash,
                },
            )
        )
    return documents


def build_schema(dimension: int) -> zvec.CollectionSchema:
    return zvec.CollectionSchema(
        name="edgemind",
        fields=[
            zvec.FieldSchema("content", zvec.DataType.STRING, nullable=True),
            zvec.FieldSchema("metadata", zvec.DataType.STRING, nullable=True),
            zvec.FieldSchema(
                "hash",
                zvec.DataType.STRING,
                nullable=True,
                index_param=zvec.InvertIndexParam(),
            ),
        ],
        vectors=[
            zvec.VectorSchema(
                "vector",
                zvec.DataType.VECTOR_FP16,
                dimension=dimension,
                index_param=zvec.HnswIndexParam(metric_type=zvec.MetricType.IP),
            )
        ],
    )


def create_collection(output_dir: Path, dimension: int) -> zvec.Collection:
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    if output_dir.exists():
        shutil.rmtree(output_dir)
    schema = build_schema(dimension)
    return zvec.create_and_open(str(output_dir), schema)


def status_code(status) -> int | None:
    code = getattr(status, "code", None)
    if callable(code):
        try:
            return int(code())
        except Exception:
            return None
    if code is None:
        return None
    try:
        return int(code)
    except Exception:
        return None


def status_message(status) -> str:
    message = getattr(status, "message", None)
    if callable(message):
        try:
            return str(message())
        except Exception:
            return str(status)
    if message is None:
        return str(status)
    return str(message)


def write_source_index(output_dir: Path, documents: list[SeedDocument]) -> None:
    source_index_path = output_dir.parent / f"{output_dir.name}_sources.tsv"
    deleted_hashes_path = output_dir.parent / f"{output_dir.name}_deleted.txt"
    lines = []
    seen: set[str] = set()
    for document in documents:
        if document.logical_hash in seen:
            continue
        seen.add(document.logical_hash)
        lines.append(f"{document.logical_hash}\t{json.dumps(document.metadata, ensure_ascii=True, separators=(',', ':'))}")
    source_index_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    deleted_hashes_path.write_text("", encoding="utf-8")


def collect_bundle_inputs(output_dir: Path) -> list[tuple[Path, str]]:
    artifacts: list[tuple[Path, str]] = []

    for source_path in sorted(path for path in output_dir.rglob("*") if path.is_file()):
        if source_path.name.upper() == "LOCK":
            continue
        relative_path = Path(output_dir.name) / source_path.relative_to(output_dir)
        artifacts.append((source_path, relative_path.as_posix()))

    sidecar_names = (
        f"{output_dir.name}_sources.tsv",
        f"{output_dir.name}_deleted.txt",
    )
    for sidecar_name in sidecar_names:
        sidecar_path = output_dir.parent / sidecar_name
        if sidecar_path.exists() and sidecar_path.is_file():
            artifacts.append((sidecar_path, sidecar_name))

    return artifacts


def stage_asset_bundle(output_dir: Path, bundle_dir: Path, version: str) -> None:
    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True, exist_ok=True)

    files: list[str] = []
    for source_path, relative_path in collect_bundle_inputs(output_dir):
        target_path = bundle_dir / relative_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, target_path)
        files.append(relative_path)

    manifest = {
        "version": version,
        "files": files,
    }
    (bundle_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )


def build_collection(
    *,
    assets_db_dir: Path,
    embedding_dir: Path,
    output_dir: Path,
    bundle_dir: Path | None,
    version: str,
) -> None:
    corpus_docs = load_quran_seed_documents(assets_db_dir)
    emotional_docs = load_emotional_seed_documents()
    documents = corpus_docs + emotional_docs
    print(f"Loaded {len(corpus_docs)} Quran corpus documents and {len(emotional_docs)} emotional documents")

    embedder = MnnEmbeddingModel(embedding_dir)
    print(f"Embedding model loaded from {embedder.model_path} with dim={embedder.embedding_dim}")

    collection = create_collection(output_dir, embedder.embedding_dim)

    batch_size = 32
    inserted = 0
    for start in range(0, len(documents), batch_size):
        batch = documents[start : start + batch_size]
        zvec_docs: list[zvec.Doc] = []
        for document in batch:
            vector = embedder.embed(document.content, is_query=False)
            zvec_docs.append(
                zvec.Doc(
                    id=document.storage_id,
                    vectors={"vector": vector},
                    fields={
                        "content": document.content,
                        "metadata": json.dumps(document.metadata, ensure_ascii=True, separators=(",", ":")),
                        "hash": document.logical_hash,
                    },
                )
            )

        statuses = collection.insert(zvec_docs)
        for status in statuses:
            code = status_code(status)
            if code not in (None, 0):
                raise RuntimeError(f"zvec insert failed: code={code} message={status_message(status)}")
        inserted += len(batch)
        print(f"Inserted {inserted}/{len(documents)} documents")

    collection.flush()
    try:
        collection.optimize()
    except Exception as exc:
        print(f"Optimize skipped: {exc}")

    write_source_index(output_dir, documents)
    print(f"Wrote collection to {output_dir}")
    print(f"Wrote sidecars next to collection in {output_dir.parent}")

    if bundle_dir is not None:
        stage_asset_bundle(output_dir, bundle_dir, version)
        print(f"Staged asset bundle in {bundle_dir}")


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Build a reusable zvec vector DB with Python MNN embeddings")
    parser.add_argument(
        "--embedding-dir",
        type=Path,
        required=True,
        help="Directory containing model.mnn and tokenizer.json for the embedding model",
    )
    parser.add_argument(
        "--assets-db-dir",
        type=Path,
        default=repo_root / "assets" / "db",
        help="Directory containing quran.db, english_saheeh.db, and quran-tafsir-english.db",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=repo_root / "build" / "vector_db" / "zvec_db",
        help="Output collection directory",
    )
    parser.add_argument(
        "--bundle-dir",
        type=Path,
        default=None,
        help="Optional bundle directory, e.g. assets/vector_db",
    )
    parser.add_argument(
        "--version",
        default="quran-tafsir-v3",
        help="Version string to write into the asset manifest when bundling",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    assets_db_dir: Path = args.assets_db_dir.resolve()
    embedding_dir: Path = args.embedding_dir.resolve()
    output_dir: Path = args.output_dir.resolve()
    bundle_dir = args.bundle_dir.resolve() if args.bundle_dir is not None else None

    if not assets_db_dir.exists():
        raise SystemExit(f"Assets DB directory not found: {assets_db_dir}")
    if not embedding_dir.exists():
        raise SystemExit(f"Embedding directory not found: {embedding_dir}")
    if not (embedding_dir / "tokenizer.json").exists():
        raise SystemExit(f"tokenizer.json not found in {embedding_dir}")

    build_collection(
        assets_db_dir=assets_db_dir,
        embedding_dir=embedding_dir,
        output_dir=output_dir,
        bundle_dir=bundle_dir,
        version=args.version,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())