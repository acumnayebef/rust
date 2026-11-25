#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_CORE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${RUST_CORE_DIR}/.." && pwd)"
OUT_DIR="${REPO_ROOT}/ios-app/Frameworks"
XCFRAMEWORK_PATH="${OUT_DIR}/MCRustCore.xcframework"

echo "Building mc_rust_core for iOS device (aarch64-apple-ios)..."
cargo build --manifest-path "${RUST_CORE_DIR}/Cargo.toml" --release --target aarch64-apple-ios

echo "Building mc_rust_core for iOS simulator (aarch64-apple-ios-sim)..."
cargo build --manifest-path "${RUST_CORE_DIR}/Cargo.toml" --release --target aarch64-apple-ios-sim

mkdir -p "${OUT_DIR}"
rm -rf "${XCFRAMEWORK_PATH}"

xcodebuild -create-xcframework \
  -library "${RUST_CORE_DIR}/target/aarch64-apple-ios/release/libmc_rust_core.a" \
  -headers "${RUST_CORE_DIR}/include" \
  -library "${RUST_CORE_DIR}/target/aarch64-apple-ios-sim/release/libmc_rust_core.a" \
  -headers "${RUST_CORE_DIR}/include" \
  -output "${XCFRAMEWORK_PATH}"

echo "Created XCFramework at ${XCFRAMEWORK_PATH}"
