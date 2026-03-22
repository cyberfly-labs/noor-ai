#!/usr/bin/env python3

"""Run a focused macOS smoke test against a built zvec collection.

The goal is not exhaustive quality evaluation. This verifies that the offline
vector database can be reopened, queried with the MNN embedding model, and that
results contain the expected metadata shape. It also flags clearly degenerate
retrieval, such as identical top hits for unrelated queries or all-zero scores.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

import zvec

from build_vector_db import MnnEmbeddingModel


@dataclass(frozen=True)
class SmokeCase:
    label: str
    query: str
    expected_hashes: tuple[str, ...] = ()
    required_within_rank: int | None = None
    require_quran_tafsir_hit: bool = False
    min_tafsir_words: int = 0


DEFAULT_CASES: tuple[SmokeCase, ...] = (
    SmokeCase("anxiety", "I feel anxious and overwhelmed"),
    SmokeCase(
        "mercy",
        "Do not despair of the mercy of Allah",
        expected_hashes=("emotion_39:53", "quran_39:53"),
        required_within_rank=5,
    ),
    SmokeCase(
        "dua",
        "Call upon Me and I will respond",
        expected_hashes=("emotion_40:60", "quran_40:60"),
        required_within_rank=3,
    ),
    SmokeCase(
        "hardship",
        "with hardship will be ease",
        expected_hashes=(
            "emotion_94:5",
            "emotion_94:6",
            "quran_94:5",
            "quran_94:6",
        ),
        required_within_rank=4,
    ),
)


TAFSIR_CASES: tuple[SmokeCase, ...] = (
    SmokeCase(
        "tawakkul",
        "What does the Quran teach about trusting Allah in hardship?",
        require_quran_tafsir_hit=True,
        min_tafsir_words=20,
    ),
    SmokeCase(
        "sabr",
        "Explain the meaning of patience and prayer in times of difficulty",
        require_quran_tafsir_hit=True,
        min_tafsir_words=20,
    ),
    SmokeCase(
        "tawbah",
        "What is the tafsir of sincere repentance and returning to Allah?",
        require_quran_tafsir_hit=True,
        min_tafsir_words=20,
    ),
    SmokeCase(
        "rahmah",
        "How does tafsir explain Allahs mercy toward sinners who return?",
        require_quran_tafsir_hit=True,
        min_tafsir_words=20,
    ),
    SmokeCase(
        "dua_nearness",
        "What is the explanation of Allah being near and answering dua?",
        require_quran_tafsir_hit=True,
        min_tafsir_words=20,
    ),
    SmokeCase(
        "straight_path",
        "What does tafsir say about guide us to the straight path?",
        require_quran_tafsir_hit=True,
        min_tafsir_words=20,
    ),
)


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Smoke test a built zvec vector database")
    parser.add_argument(
        "--embedding-dir",
        type=Path,
        default=repo_root / "build" / "embedding_model",
        help="Directory containing model.mnn and tokenizer.json",
    )
    parser.add_argument(
        "--collection-dir",
        type=Path,
        default=repo_root / "build" / "vector_db" / "zvec_db",
        help="Path to the built zvec collection directory",
    )
    parser.add_argument(
        "--topk",
        type=int,
        default=5,
        help="Number of results to request per query",
    )
    parser.add_argument(
        "--allow-identical-top-hit",
        action="store_true",
        help="Do not fail when all smoke queries return the same top result",
    )
    parser.add_argument(
        "--allow-zero-scores",
        action="store_true",
        help="Do not fail when all returned scores are zero",
    )
    return parser.parse_args()


def require_path(path: Path, description: str) -> Path:
    resolved = path.resolve()
    if not resolved.exists():
        raise SystemExit(f"{description} not found: {resolved}")
    return resolved


def parse_metadata(doc) -> dict[str, str]:
    raw = doc.fields.get("metadata")
    if not isinstance(raw, str) or not raw:
        raise RuntimeError(f"Document {doc.id} is missing metadata")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise RuntimeError(f"Document {doc.id} metadata is not a JSON object")
    return {str(key): str(value) for key, value in payload.items()}


def parse_entry_content(content: str) -> tuple[str, str]:
    translation = ""
    tafsir_lines: list[str] = []
    in_tafsir = False
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if line.startswith("Translation: "):
            translation = line[len("Translation: ") :].strip()
            continue
        if line.startswith("Tafsir: "):
            tafsir_lines.append(line[len("Tafsir: ") :].strip())
            in_tafsir = True
            continue
        if in_tafsir and line:
            tafsir_lines.append(line)
    return translation, " ".join(part for part in tafsir_lines if part).strip()


def run_case(collection, embedder: MnnEmbeddingModel, case: SmokeCase, topk: int) -> list[dict[str, object]]:
    vector = embedder.embed(case.query, is_query=True)
    docs = collection.query(
        zvec.VectorQuery("vector", vector=vector),
        topk=topk,
        output_fields=["content", "metadata", "hash"],
    )

    if not docs:
        raise RuntimeError(f"Query returned no results for case '{case.label}'")

    parsed: list[dict[str, object]] = []
    for doc in docs:
        metadata = parse_metadata(doc)
        stored_hash = doc.fields.get("hash")
        metadata_hash = metadata.get("hash")
        if stored_hash and metadata_hash and str(stored_hash) != str(metadata_hash):
            raise RuntimeError(
                f"Hash mismatch for {doc.id}: field={stored_hash} metadata={metadata_hash}"
            )
        if "verse_key" not in metadata:
            raise RuntimeError(f"Document {doc.id} is missing verse_key metadata")
        parsed.append(
            {
                "id": doc.id,
                "score": float(doc.score),
                "kind": metadata.get("kind", ""),
                "verse_key": metadata.get("verse_key", ""),
                "hash": str(stored_hash or metadata_hash or ""),
                "translation": parse_entry_content(doc.fields.get("content") or "")[0],
                "tafsir": parse_entry_content(doc.fields.get("content") or "")[1],
            }
        )
    return parsed


def print_case(case: SmokeCase, results: list[dict[str, object]]) -> None:
    print(f"\n[{case.label}] {case.query}")
    for index, result in enumerate(results, start=1):
        print(
            f"  {index}. {result['id']} score={result['score']:.6f} "
            f"kind={result['kind']} verse={result['verse_key']} hash={result['hash']}"
        )


def assert_case_expectations(case: SmokeCase, results: list[dict[str, object]]) -> None:
    if case.expected_hashes:
        rank_limit = case.required_within_rank or len(results)
        top_results = results[:rank_limit]
        observed_hashes = {str(result["hash"]) for result in top_results}
        if not any(expected_hash in observed_hashes for expected_hash in case.expected_hashes):
            expected = ", ".join(case.expected_hashes)
            observed = ", ".join(str(result["hash"]) for result in top_results)
            raise SystemExit(
                f"Expectation failed for '{case.label}': none of [{expected}] appeared within top {rank_limit}. "
                f"Observed: [{observed}]"
            )

    if case.require_quran_tafsir_hit:
        min_words = case.min_tafsir_words
        substantial_quran_hit_found = False
        for result in results:
            if result["kind"] != "quran_corpus":
                continue
            tafsir_text = str(result["tafsir"])
            tafsir_word_count = len(re.findall(r"\S+", tafsir_text))
            if tafsir_word_count >= min_words:
                substantial_quran_hit_found = True
                break
        if not substantial_quran_hit_found:
            raise SystemExit(
                f"Expectation failed for '{case.label}': no quran_corpus result contained at least {min_words} tafsir words"
            )


def main() -> int:
    args = parse_args()
    embedding_dir = require_path(args.embedding_dir, "Embedding directory")
    collection_dir = require_path(args.collection_dir, "Collection directory")

    if not (embedding_dir / "tokenizer.json").exists():
        raise SystemExit(f"tokenizer.json not found in {embedding_dir}")

    collection = zvec.open(str(collection_dir))
    embedder = MnnEmbeddingModel(embedding_dir)

    case_results: list[tuple[SmokeCase, list[dict[str, object]]]] = []
    for case in (*DEFAULT_CASES, *TAFSIR_CASES):
        results = run_case(collection, embedder, case, args.topk)
        print_case(case, results)
        assert_case_expectations(case, results)
        case_results.append((case, results))

    top_hashes = [results[0]["hash"] for _, results in case_results]
    all_scores = [result["score"] for _, results in case_results for result in results]

    if not args.allow_identical_top_hit and len(set(top_hashes)) == 1:
        raise SystemExit(
            "Degenerate retrieval detected: all smoke queries returned the same top result "
            f"({top_hashes[0]})"
        )

    if not args.allow_zero_scores and all(score == 0.0 for score in all_scores):
        raise SystemExit("Degenerate retrieval detected: all returned scores were zero")

    print("\nSmoke test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())