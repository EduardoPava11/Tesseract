#!/bin/sh
# JH4 parity gate: compile the app's actual JepaHHead.swift +
# JepaHWeights.swift against the float64 fixtures. No simulator.
set -e
cd "$(dirname "$0")"
swiftc -O -o /tmp/jepah_parity \
  ../../Tesseract/Tesseract/JepaHHead.swift \
  ../../Tesseract/Tesseract/JepaHWeights.swift \
  main.swift
/tmp/jepah_parity
