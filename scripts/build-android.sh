#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# NDK and its prebuilt host dir follow the host OS: macOS keeps the old default, Linux (and
# WSL) reads the NDK from $ANDROID_HOME. ANDROID_NDK overrides both.
case "$(uname -s)" in
	Darwin)
		NDK_DEFAULT="$HOME/Library/Android/sdk/ndk/28.0.13004108"
		HOST_TAG="darwin-x86_64"
		;;
	Linux)
		NDK_DEFAULT="${ANDROID_HOME:-$HOME/Android/Sdk}/ndk/28.0.13004108"
		HOST_TAG="linux-x86_64"
		;;
	*)
		echo "build-android.sh: unsupported host $(uname -s)" >&2
		exit 1
		;;
esac

NDK="${ANDROID_NDK:-$NDK_DEFAULT}"
ENTRY="${ENTRY:-src/examples/androidCubeEntry.ms}"
CC="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/aarch64-linux-android26-clang"
DEST="android/app/src/main/jniLibs/arm64-v8a"
[ -x "$CC" ] || { echo "build-android.sh: no NDK clang at $CC (set ANDROID_NDK or ANDROID_HOME)" >&2; exit 1; }
mkdir -p "$DEST"

msc build "$ENTRY" --os=android --app=lib --cc="$CC" --output="$DEST/libVoidAndroid.so"
"$CC" -shared -fPIC android/app/src/main/jni/voidJni.c -L"$DEST" -lVoidAndroid -landroid -llog -o "$DEST/libVoidJni.so"
# libVoidAndroid.so links libc++_shared.so, which is not on the device — ship the NDK's copy.
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
"$TOOLCHAIN/bin/llvm-strip" --strip-unneeded -o "$DEST/libc++_shared.so" "$TOOLCHAIN/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"

echo "OK: $DEST"
