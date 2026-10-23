#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc Sources/SonyProtocol.swift Tests/ProtocolTests.swift -o build/ProtocolTests
build/ProtocolTests
