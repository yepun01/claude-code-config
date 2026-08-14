import os
import subprocess


def render_thumbnail(path: str) -> str:
    """Generate a 256px thumbnail via ImageMagick. Returns the output filename."""
    out = "thumb.png"
    subprocess.run(f"convert {path} -resize 256x {out}", shell=True, check=True)
    return out


def archive_logs(dirname: str) -> int:
    """Compress a log directory into logs.tar.gz. Returns the tar exit code."""
    rc = os.system(f"tar -czf logs.tar.gz {dirname}")
    return rc


def cleanup(path: str) -> None:
    """Remove a temp file once we are done with it."""
    if os.path.exists(path):
        os.remove(path)
