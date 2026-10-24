#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc Sources/SonyProtocol.swift Sources/Compatibility.swift Tests/ProtocolTests.swift -o build/ProtocolTests
build/ProtocolTests
swiftc Sources/SonyProtocol.swift Sources/Compatibility.swift Tests/CompatibilityTests.swift -o build/CompatibilityTests
build/CompatibilityTests
swiftc Sources/SonyProtocol.swift Sources/NothingProtocol.swift Tests/NothingTests.swift -o build/NothingTests
build/NothingTests
