# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Local Phonon English worker. Downloads and microphone capture belong to the app."""
import contextlib
import fcntl
import gc
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import time

# Isolated Python excludes the script directory; add only our bundled modules.
sys.path.insert(0, str(Path(__file__).resolve().parent))
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
protocol = sys.stdout


def emit(identifier, text=None, error=None):
    protocol.write("VORSSAINT_DICTATION " + json.dumps({"id": identifier, "text": text, "error": error}) + "\n")
    protocol.flush()


def main():
    root = Path(sys.argv[1]).resolve()
    owner = os.getppid()

    def watch_parent():
        while True:
            time.sleep(1)
            if owner == 1 or os.getppid() != owner:
                os._exit(0)

    threading.Thread(target=watch_parent, daemon=True).start()
    lock_path = Path.home() / "Library/Application Support/VorssaintDictationEngine.lock"
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    # Hold the same lock as the Swift worker throughout initialization/inference.
    with contextlib.redirect_stdout(sys.stderr):
        import mlx.core as mx
        from fermion._speech import fetch, backends
        cache = root / "prepared"
        if not fetch.is_model_dir(cache):
            fetch.unpack_any(root / "phonon-2.5-en.bps.tar.zst", cache)
        model = backends.load("mlx", cache, profile="five-value-25-en",
                              backend="phonon2-five-value", quiet=True)
        gc.collect()
        mx.clear_cache()
    emit("ready", text="")
    for line in sys.stdin:
        identifier = "invalid"
        try:
            request = json.loads(line)
            identifier = request["id"]
            with contextlib.redirect_stdout(sys.stderr):
                text, _, _ = model.transcribe(request["path"])
                mx.clear_cache()
            emit(identifier, text=text)
        except Exception as error:
            emit(identifier, error=str(error))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        emit("ready", error=str(error))
