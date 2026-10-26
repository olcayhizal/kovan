# KOVAN Mac geliştirme ortamı: `source kovan-dev/env.sh`
# Derlemeler "KOVAN Code Signing" ile imzalanır; macOS izinleri derlemeler
# arasında korunur (imza şartı sertifikaya bağlı, derlemeye değil).
export VCPKG_ROOT="$HOME/kovan-araclar/vcpkg"
export PATH="$HOME/kovan-araclar/flutter/bin:$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=10.14
export LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib
export FLUTTER_XCODE_ARCHS=arm64
export FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES
export FLUTTER_XCODE_CODE_SIGN_IDENTITY="KOVAN Code Signing"
export FLUTTER_XCODE_CODE_SIGN_STYLE=Manual
export FLUTTER_XCODE_DEVELOPMENT_TEAM=""
