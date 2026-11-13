#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
tools="${DEEMO_TOOLROOT:?Set DEEMO_TOOLROOT to the ShadeBar iOS cross-toolchain directory}"
sdk="$tools/sdks/iPhoneOS16.5.sdk"
llvm="$tools/llvm23/usr"
export LD_LIBRARY_PATH="$llvm/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p build
c++ -std=c++17 -include initializer_list -Wall -Werror tests/tempo.cpp -o build/test-tempo
build/test-tempo
c++ -std=c++17 -Wall -Werror tests/transport.cpp -o build/test-transport
build/test-transport
flags=(-target arm64-apple-ios15.0 -isysroot "$sdk" -std=c++17 -Os -fobjc-arc -fblocks -Wall -Wextra -Werror=unguarded-availability-new -Wno-unused-parameter -Wno-deprecated-declarations)
linkflags=(-arch arm64 -syslibroot "$sdk" -platform_version ios 15.0 16.5 -lc++ -lSystem -lobjc -framework UIKit -framework Foundation -adhoc_codesign)
"$llvm/lib/llvm-23/bin/clang" "${flags[@]}" -c src/Adapter.mm -o build/Adapter.o
"$llvm/lib/llvm-23/bin/clang" "${flags[@]}" -c src/TrainerApp.mm -o build/TrainerApp.o
"$tools/native/bin/aarch64-apple-darwin-ld" "${linkflags[@]}" -dylib -install_name @rpath/DeemoTempo.dylib -o build/DeemoTempo.dylib build/Adapter.o -framework QuartzCore -framework CoreGraphics
"$tools/native/bin/aarch64-apple-darwin-ld" "${linkflags[@]}" -o build/DeemoTrainer build/TrainerApp.o
"$tools/linux/iphone/bin/ldid" -S -Cadhoc build/DeemoTempo.dylib
"$tools/linux/iphone/bin/ldid" -Sresources/App.entitlements -Cadhoc build/DeemoTrainer
