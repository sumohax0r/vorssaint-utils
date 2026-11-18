#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")"
RUNTIME="$HOME/Library/Application Support/VorssaintBarkRuntime/python311-v1"
DIGEST="$(shasum -a 256 requirements.txt | awk '{print $1}')"
if [[ ! -x "$RUNTIME/bin/python3" || ! -f "$RUNTIME/.requirements" || "$(cat "$RUNTIME/.requirements")" != "$DIGEST" ]]; then
    PYTHON="${VORSSAINT_BARK_PYTHON:-/opt/homebrew/bin/python3.11}"
    if [[ ! -x "$PYTHON" ]]; then
        echo "Bark Clean requires Python 3.11. Install it or set VORSSAINT_BARK_PYTHON." >&2
        exit 1
    fi
    "$PYTHON" -m venv "$RUNTIME"
    "$RUNTIME/bin/python3" -m pip install --disable-pip-version-check -r requirements.txt
    "$RUNTIME/bin/python3" -m pip freeze > "$RUNTIME/installed-packages.txt"
    printf '%s' "$DIGEST" > "$RUNTIME/.requirements"
fi
# The Apple Silicon adapter uses the existing pinned MLX stack, not Torch.
if [[ "$("$RUNTIME/bin/python3" -c 'import importlib.metadata as m; print(m.version("fermion-research"))' 2>/dev/null || true)" != "0.2.13" ]]; then
    "$RUNTIME/bin/python3" -m pip install --disable-pip-version-check --no-deps fermion-research==0.2.13
fi
mkdir -p ../../build
printf '%s' "$RUNTIME/bin/python3" > ../../build/BarkPythonPath.txt
