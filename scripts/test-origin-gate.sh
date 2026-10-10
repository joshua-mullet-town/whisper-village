#!/bin/bash
# Compiles BrowserOriginGate.swift alone with its regression check and runs it.
# Exit non-zero if any case fails. Run before every ship of :8179 changes.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)/origin-gate-check"
swiftc -O "$ROOT/WhisperVillage/Services/BrowserOriginGate.swift" "$ROOT/tests/origin-gate/main.swift" -o "$OUT" || exit 2
"$OUT"
