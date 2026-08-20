#!/bin/zsh
# 构建 DSH Controller.app 到 /Applications
set -e

SRC_DIR="/Users/zhangyang/ZCodeProject/dsh-controller"
APP_PATH="/Applications/DSH Controller.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"

echo "编译二进制..."
swiftc -O \
    -target arm64-apple-macosx11.0 \
    -framework Cocoa \
    -o "$SRC_DIR/dsh-controller" \
    "$SRC_DIR/main.swift"

echo "组装 .app 包..."
rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR"
cp "$SRC_DIR/dsh-controller" "$MACOS_DIR/dsh-controller"
cp "$SRC_DIR/Info.plist" "$CONTENTS/Info.plist"

echo "清除 quarantine..."
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "构建完成: $APP_PATH"
