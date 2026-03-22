#!/usr/bin/env python3
"""Ingest Hadith corpus from assets/db/hadith.db into the existing zvec collection.

Appends hadith documents to a collection previously built by build_vector_db.py.
Run this after the base Quran collection has been built.

Usage:
    python tools/ingest_hadith.py \\
        --embedding-dir /path/to/bge-small-en-v1.5 \\
        [--assets-db-dir assets/db] \\
        [--output-dir build/vector_db/zvec_db] \\
        [--collection-ids 1 2 30 38 10 3]  # omit to ingest all collections
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any

import zvec

# Ensure tools/ is on the import path so we can reuse build_vector_db helpers.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_vector_db import (
    MAX_SEQ_LEN,
    MnnEmbeddingModel,
    SeedDocument,
    WordPieceTokenizer,
    chunk_id_for_hash,
    normalize_text,
    status_code,
    status_message,
)

# ---------------------------------------------------------------------------
# Collection-id → human title map (mirrors the DB collection table).
# Used for metadata only; the join is done at query time.
# ---------------------------------------------------------------------------
COLLECTION_TITLES: dict[str, str] = {
    "1": "Sahih al-Bukhari",
    "2": "Sahih Muslim",
    "3": "Sunan an-Nasa'i",
    "10": "Sunan Abi Dawud",
    "30": "Jami` at-Tirmidhi",
    "38": "Sunan Ibn Majah",
    "40": "Muwatta Malik",
    "50": "Musnad Ahmad",
    "101": "An-Nawawi's 40 Hadith",
    "102": "Collections of Forty",
    "110": "Riyad as-Salihin",
    "113": "Mishkat al-Masabih",
    "115": "Al-Adab Al-Mufrad",
    "130": "Ash-Shama'il Al-Muhammadiyah",
    "200": "Bulugh al-Maram",
    "300": "Hisn al-Muslim",
}


# ---------------------------------------------------------------------------
# Chunking helpers
# ---------------------------------------------------------------------------

def _token_count(text: str, tokenizer: WordPieceTokenizer) -> int:
    """Return the number of tokens for *text* (includes CLS + SEP)."""
    return len(tokenizer.tokenize(text, MAX_SEQ_LEN * 4))  # no hard cap here


def _split_sentences(text: str) -> list[str]:
    """Split *text* into sentences on sentence-ending punctuation."""
    parts = re.split(r'(?<=[.!?])\s+', text)
    return [p for p in parts if p.strip()]


def build_hadith_chunks(
    narrator: str,
    body: str,
    grade: str,
    tokenizer: WordPieceTokenizer,
) -> list[str]:
    """Return content strings for one hadith, chunked to fit MAX_SEQ_LEN tokens.

    Each chunk is formatted as::

        {narrator}

        {sentence(s)}

        Grade: {grade}

    The narrator prefix is repeated in every chunk for retrieval context.
    """
    narrator = (narrator or "").strip()
    body = (body or "").strip()
    grade = (grade or "").strip()

    narrator_block = f"{narrator}\n\n" if narrator else ""
    grade_block = f"\n\nGrade: {grade}" if grade else ""

    full_content = narrator_block + body + grade_block
    if _token_count(full_content, tokenizer) <= MAX_SEQ_LEN:
        return [full_content]

    # Need to chunk — split body into sentences and greedily fill each chunk.
    sentences = _split_sentences(body)
    if not sentences:
        # Fallback: hard truncate (rare edge case).
        return [full_content]

    # Token budget available for body sentences per chunk.
    overhead = _token_count(narrator_block + grade_block, tokenizer)
    body_budget = MAX_SEQ_LEN - overhead - 2  # 2 tokens safety margin

    chunks: list[str] = []
    current: list[str] = []
    current_tokens = 0

    for sentence in sentences:
        # +2 for the space separator we'd add, then -2 for overhead already accounted
        sentence_tokens = len(tokenizer.tokenize(sentence, MAX_SEQ_LEN)) - 2

        if current_tokens + sentence_tokens > body_budget and current:
            chunk_body = " ".join(current)
            chunks.append(narrator_block + chunk_body + grade_block)
            current = [sentence]
            current_tokens = sentence_tokens
        else:
            current.append(sentence)
            current_tokens += sentence_tokens

    if current:
        chunk_body = " ".join(current)
        chunks.append(narrator_block + chunk_body + grade_block)

    return chunks if chunks else [full_content]


# ---------------------------------------------------------------------------
# DB loading
# ---------------------------------------------------------------------------

def load_hadith_seed_documents(
    hadith_db_path: Path,
    tokenizer: WordPieceTokenizer,
    collection_ids: list[str] | None = None,
) -> list[SeedDocument]:
    """Query hadith_en and return chunked SeedDocuments ready for embedding.

    Parameters
    ----------
    hadith_db_path:
        Path to the SQLite3 ``hadith.db``.
    tokenizer:
        WordPieceTokenizer used for token-counting during chunking.
    collection_ids:
        If given, only ingest hadiths from these collection IDs (e.g. ``["1", "2"]``).
        Pass ``None`` to ingest all collections.
    """
    allowed: set[str] | None = set(collection_ids) if collection_ids else None

    with sqlite3.connect(hadith_db_path) as con:
        # Fetch collection titles for richer metadata.
        coll_rows = con.execute(
            "SELECT id, title_en FROM collection"
        ).fetchall()
        coll_title_map: dict[str, str] = {
            str(row[0]): (row[1] or "").strip() for row in coll_rows
        }

        # FTS5 tables can be iterated with SELECT rowid, * FROM <table>.
        rows = con.execute(
            "SELECT arabic_urn, urn, collection_id, narrator_prefix, content,"
            "       narrator_postfix, grades, reference"
            "  FROM hadith_en"
        ).fetchall()

    documents: list[SeedDocument] = []
    for arabic_urn, urn, collection_id, narrator_prefix, content, narrator_postfix, grades, reference in rows:
        collection_id_str = str(collection_id or "").strip()
        if allowed and collection_id_str not in allowed:
            continue

        body = normalize_text(content) or ""
        if not body:
            continue

        narrator = normalize_text(narrator_prefix) or ""
        grade = normalize_text(grades) or ""

        # First line of reference is the canonical citation, e.g. "Sahih al-Bukhari, 1"
        ref_first_line = (reference or "").strip().splitlines()[0].strip()

        urn_str = str(urn or arabic_urn or "").strip()
        if not urn_str:
            continue

        coll_title = (
            coll_title_map.get(collection_id_str)
            or COLLECTION_TITLES.get(collection_id_str, f"Collection {collection_id_str}")
        )

        logical_hash = f"hadith_{urn_str}"

        chunks = build_hadith_chunks(narrator, body, grade, tokenizer)

        for idx, chunk_content in enumerate(chunks):
            documents.append(
                SeedDocument(
                    storage_id=chunk_id_for_hash(logical_hash, idx),
                    logical_hash=logical_hash,
                    content=chunk_content,
                    metadata={
                        "kind": "hadith_corpus",
                        "urn": urn_str,
                        "arabic_urn": str(arabic_urn or "").strip(),
                        "collection_id": collection_id_str,
                        "collection": coll_title,
                        "grade": grade,
                        "reference": ref_first_line,
                        "source": "Sunnah.com",
                        "hash": logical_hash,
                    },
                )
            )

    return documents


# ---------------------------------------------------------------------------
# Sidecar append
# ---------------------------------------------------------------------------

def append_source_index(output_dir: Path, documents: list[SeedDocument]) -> None:
    """Append new logical hashes to the existing _sources.tsv sidecar file."""
    sidecar = output_dir.parent / f"{output_dir.name}_sources.tsv"
    deleted = output_dir.parent / f"{output_dir.name}_deleted.txt"

    # Read existing hashes to avoid duplicates.
    existing: set[str] = set()
    if sidecar.exists():
        for line in sidecar.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t", 1)
            if parts:
                existing.add(parts[0])

    new_lines: list[str] = []
    seen: set[str] = set()
    for doc in documents:
        if doc.logical_hash in existing or doc.logical_hash in seen:
            continue
        seen.add(doc.logical_hash)
        new_lines.append(
            f"{doc.logical_hash}\t"
            f"{json.dumps(doc.metadata, ensure_ascii=True, separators=(',', ':'))}"
        )

    if new_lines:
        with sidecar.open("a", encoding="utf-8") as f:
            f.write("\n".join(new_lines) + "\n")

    if not deleted.exists():
        deleted.write_text("", encoding="utf-8")

    print(f"Appended {len(new_lines)} new entries to {sidecar}")


# ---------------------------------------------------------------------------
# Main ingestion
# ---------------------------------------------------------------------------

def ingest(
    *,
    hadith_db_path: Path,
    embedding_dir: Path,
    output_dir: Path,
    collection_ids: list[str] | None,
) -> None:
    if not output_dir.exists():
        raise SystemExit(
            f"Collection not found at {output_dir}.\n"
            "Run build_vector_db.py first to build the base Quran collection."
        )

    print("Loading embedding model…")
    embedder = MnnEmbeddingModel(embedding_dir)
    print(f"  model: {embedder.model_path}  dim={embedder.embedding_dim}")

    print("Loading hadith documents from DB…")
    documents = load_hadith_seed_documents(hadith_db_path, embedder.tokenizer, collection_ids)
    print(f"  {len(documents)} chunks from {len({d.logical_hash for d in documents})} hadiths")

    print(f"Opening existing collection at {output_dir}…")
    collection = zvec.open(str(output_dir))

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
                        "metadata": json.dumps(
                            document.metadata, ensure_ascii=True, separators=(",", ":")
                        ),
                        "hash": document.logical_hash,
                    },
                )
            )

        statuses = collection.insert(zvec_docs)
        for status in statuses:
            code = status_code(status)
            if code in (None, 0):
                continue
            msg = status_message(status)
            # code=2 → duplicate doc_id (already inserted in a previous run); skip.
            if code == 2 or "already exists" in msg.lower():
                continue
            raise RuntimeError(
                f"zvec insert failed: code={code} message={msg}"
            )

        inserted += len(batch)
        if inserted % 1000 == 0 or inserted == len(documents):
            print(f"  Inserted {inserted}/{len(documents)}")

    collection.flush()
    try:
        collection.optimize()
    except Exception as exc:
        print(f"  Optimize skipped: {exc}")

    append_source_index(output_dir, documents)
    print("Done.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    p = argparse.ArgumentParser(
        description="Append Hadith corpus to an existing zvec collection."
    )
    p.add_argument(
        "--embedding-dir",
        type=Path,
        required=True,
        help="Directory containing embedding.mnn (or model.mnn) and tokenizer.json",
    )
    p.add_argument(
        "--assets-db-dir",
        type=Path,
        default=repo_root / "assets" / "db",
        help="Directory containing hadith.db (default: assets/db)",
    )
    p.add_argument(
        "--output-dir",
        type=Path,
        default=repo_root / "build" / "vector_db" / "zvec_db",
        help="Existing zvec collection directory to append into",
    )
    p.add_argument(
        "--collection-ids",
        nargs="*",
        metavar="ID",
        default=None,
        help=(
            "Space-separated collection IDs to ingest. "
            "Omit to ingest all 15 collections. "
            "E.g. --collection-ids 1 2 30 38 10 3  (Kutub as-Sittah)"
        ),
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    assets_db_dir: Path = args.assets_db_dir.resolve()
    hadith_db_path = assets_db_dir / "hadith.db"

    if not hadith_db_path.exists():
        raise SystemExit(f"hadith.db not found at {hadith_db_path}")
    if not args.embedding_dir.resolve().exists():
        raise SystemExit(f"Embedding directory not found: {args.embedding_dir}")

    ingest(
        hadith_db_path=hadith_db_path,
        embedding_dir=args.embedding_dir.resolve(),
        output_dir=args.output_dir.resolve(),
        collection_ids=args.collection_ids,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
