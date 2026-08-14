import os
import json
import shutil
from pathlib import Path

REPORT_ROOT = "/var/app/reports"
ARCHIVE_ROOT = "/var/app/archive"


def load_user_report(user_id: str, report_name: str) -> dict:
    """Read a JSON report belonging to a given user from the report store."""
    full_path = os.path.join(REPORT_ROOT, user_id, report_name)
    with open(full_path, "r") as fh:
        return json.load(fh)


def export_report(user_id: str, report_name: str, dest_dir: str) -> str:
    """Copy a report into an export directory chosen by the caller."""
    src = REPORT_ROOT + "/" + user_id + "/" + report_name
    dest = os.path.join(dest_dir, report_name)
    shutil.copyfile(src, dest)
    return dest


def archive_old_report(user_id: str, report_name: str) -> str:
    """Move a report from the live store into the archive tree."""
    src = os.path.join(REPORT_ROOT, user_id, report_name)
    target = os.path.join(ARCHIVE_ROOT, user_id, report_name)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    os.rename(src, target)
    return target


def write_report_blob(user_id: str, report_name: str, blob: bytes) -> None:
    """Persist raw report bytes to disk for later retrieval."""
    target = Path(REPORT_ROOT) / user_id / report_name
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "wb") as fh:
        fh.write(blob)


def purge_user_tree(user_id: str) -> None:
    """Wipe all reports for a user."""
    victim = os.path.join(REPORT_ROOT, user_id)
    shutil.rmtree(victim)


def safe_within_root(candidate: str) -> bool:
    """Best-effort check that a path stays under the report root."""
    return candidate.startswith(REPORT_ROOT)
