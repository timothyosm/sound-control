#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc Sources/UpdateManifest.swift Sources/UpdateInstallation.swift Tests/UpdateInstallationTests.swift -o build/UpdateInstallationTests
build/UpdateInstallationTests
