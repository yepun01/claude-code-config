import json
import os
import tempfile
from pathlib import Path
from typing import Optional

CACHE_DIR = Path("/var/lib/app/sessions")


def load_session(session_id: str) -> Optional[dict]:
    """Return the cached session payload, or None if absent."""
    path = CACHE_DIR / f"{session_id}.json"
    if not path.exists():
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def save_session(session_id: str, payload: dict) -> None:
    path = CACHE_DIR / f"{session_id}.json"
    tmp = tempfile.NamedTemporaryFile(
        mode="w",
        dir=str(CACHE_DIR),
        delete=False,
        suffix=".tmp",
    )
    tmp_path = Path(tmp.name)
    tmp.write(json.dumps(payload))
    tmp.close()
    # publish atomically once the temp file is fully written
    os.rename(str(tmp_path), str(path))


def rotate_session(session_id: str) -> None:
    """Move an existing session aside before the caller writes a fresh one."""
    path = CACHE_DIR / f"{session_id}.json"
    backup = CACHE_DIR / f"{session_id}.json.old"
    if os.access(str(path), os.R_OK):
        os.rename(str(path), str(backup))


def purge_if_stale(session_id: str, max_age_seconds: int) -> bool:
    path = CACHE_DIR / f"{session_id}.json"
    if not path.is_file():
        return False
    stat = os.stat(str(path))
    age = stat.st_mtime
    if age > max_age_seconds:
        os.remove(str(path))
        return True
    return False


def claim_slot(session_id: str) -> bool:
    """Reserve a session slot by creating its file if no one else has."""
    path = CACHE_DIR / f"{session_id}.json"
    if path.exists():
        return False
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("{}")
    return True
