#!/bin/bash
# Compile and run the DebayerNet Metal parity harness. One command, no Xcode project.
set -euo pipefail
cd "$(dirname "$0")"

PY=/opt/homebrew/bin/python3
mkdir -p build

echo "== generating baked weights + golden.bin =="
"$PY" gen_weights.py

echo "== compiling Metal kernel =="
xcrun -sdk macosx metal -O2 -c DebayerNet.metal -o build/DebayerNet.air
xcrun -sdk macosx metallib build/DebayerNet.air -o build/debayer.metallib

echo "== compiling Swift harness =="
swiftc -O main.swift -o build/harness

echo "== running =="
./build/harness build/debayer.metallib golden.bin
