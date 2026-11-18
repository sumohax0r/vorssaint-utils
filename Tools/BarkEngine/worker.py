# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Local Bark Clean worker. Downloads and microphone capture belong to the app."""
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
        import bark_mlx
        import mlx.core as mx
        import numpy as np
        import soundfile as sf
        from mlx_audio.stt import load
        bark_mlx.HERE = str(root)
        cache = root / "bark_mlx_4bit"
        if not (cache / ".ready").is_file():
            shutil.rmtree(cache, ignore_errors=True)
            # Remove only interrupted conversions inside this model directory.
            for previous in root.glob(".bark-prepare-*"):
                if previous.is_dir():
                    shutil.rmtree(previous)
            staging = Path(tempfile.mkdtemp(prefix=".bark-prepare-", dir=root))
            try:
                bark_mlx.prepare(str(root / "model.bark"), str(staging), bits=4)
                (staging / ".ready").write_text("4bit-v1")
                staging.rename(cache)
            finally:
                shutil.rmtree(staging, ignore_errors=True)
            # Conversion builds full-precision intermediates. Replace this
            # process before inference so their CPU/Metal allocations cannot
            # remain resident. Python's lock descriptor closes across exec;
            # the replacement reacquires the shared model lock before loading.
            os.execv(sys.executable, [sys.executable, "-I", "-u", str(Path(__file__).resolve()), str(root)])
        model = load(str(cache), strict=True, model_type="parakeet")
        mx.eval(model.parameters())
        gc.collect()
        mx.clear_cache()
        # Only remove the superseded generated cache after the new model loads.
        # The original pinned download remains available for reconstruction.
        shutil.rmtree(root / "bark_mlx_fp16", ignore_errors=True)
    emit("ready", text="")
    for line in sys.stdin:
        identifier = "invalid"
        try:
            request = json.loads(line)
            identifier = request["id"]
            parts = []
            with contextlib.redirect_stdout(sys.stderr), sf.SoundFile(request["path"]) as audio:
                if audio.samplerate != 16000 or audio.channels != 1:
                    raise ValueError("Expected mono 16 kHz dictation audio")
                while audio.tell() < len(audio):
                    position = audio.tell()
                    wave = audio.read(30 * 16000, dtype="float32")
                    # Prefer a quiet boundary near the end of each bounded chunk.
                    if audio.tell() < len(audio) and len(wave) >= 30 * 16000:
                        tail = wave[25 * 16000:].reshape(-1, 1600)
                        boundary = 25 * 16000 + (int(np.argmin(np.mean(tail * tail, axis=1))) + 1) * 1600
                        wave = wave[:boundary]
                        audio.seek(position + boundary)
                    text = bark_mlx.transcribe(model, wave, sample_rate=16000, pad_s=0.0)
                    if text:
                        parts.append(text)
                    mx.clear_cache()
            emit(identifier, text=" ".join(parts))
        except Exception as error:
            emit(identifier, error=str(error))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        emit("ready", error=str(error))
