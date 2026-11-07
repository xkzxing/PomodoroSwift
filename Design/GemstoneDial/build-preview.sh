#!/bin/bash
set -euo pipefail

design_root="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$design_root/../.." && pwd)"
cd "$project_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
local_signing="$project_root/Config/Signing.local.sh"
if [[ -z "${GEMSTONE_PREVIEW_CERTIFICATE:-}" && -f "$local_signing" ]]; then
    source "$local_signing"
fi
certificate="${GEMSTONE_PREVIEW_CERTIFICATE:-}"
if [[ ! "$certificate" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo '请在本机配置中设置预览工具的开发者证书指纹。' >&2
    exit 1
fi
identities="$(security find-identity -v -p codesigning)"
if [[ "$identities" != *"$certificate"* ]]; then
    echo '指定的开发者证书不可用，已停止构建。' >&2
    exit 1
fi
(cd "$design_root/Photos" && shasum -a 256 -c SHA256SUMS)

preview_root="${GEMSTONE_PREVIEW_OUTPUT:-$project_root/build/GemstonePhotoPreview.app}"
mkdir -p "$preview_root/Contents/MacOS" "$preview_root/Contents/Resources/Photos"
cat > "$preview_root/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GemstonePhotoPreview</string>
<key>CFBundleIdentifier</key><string>local.GemstonePhotoPreview</string>
<key>CFBundleName</key><string>鎏金彩晶实景预览</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -n "${GEMSTONE_PREVIEW_IDENTIFIER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $GEMSTONE_PREVIEW_IDENTIFIER" "$preview_root/Contents/Info.plist"
fi
cp "$design_root/Photos/"* "$preview_root/Contents/Resources/Photos/"
reference="${1:-$project_root/build/GemstoneReferencePhoto.png}"
if [[ -f "$reference" ]]; then cp "$reference" "$preview_root/Contents/Resources/PreviewBackdrop.png"; fi

sources=(
    PomodoroSwift/Models/GemstoneMesh.swift
    PomodoroSwift/Models/GemstoneReferenceGeometry.swift
    PomodoroSwift/Models/GemstoneBackdropMapping.swift
    PomodoroSwift/Models/SwissClockProgress.swift
    PomodoroSwift/Views/GemstoneRaySurface.swift
    Design/GemstoneDial/PreviewBackdrops.swift
)
xcrun -sdk macosx metal -fmodules-cache-path=build/GemstoneMetalModuleCache \
    -c PomodoroSwift/Shaders/GemstoneRayTracing.metal -o build/GemstoneRayTracing.air
xcrun -sdk macosx metallib build/GemstoneRayTracing.air -o build/GemstoneRayTracing.metallib
cp build/GemstoneRayTracing.metallib "$preview_root/Contents/Resources/default.metallib"
xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
    -module-cache-path build/GemstonePreviewCache "${sources[@]}" \
    Design/GemstoneDial/GemstonePreview.swift -o "$preview_root/Contents/MacOS/GemstonePhotoPreview"
xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
    -module-cache-path build/GemstonePreviewCache "${sources[@]}" \
    Design/GemstoneDial/RenderBackdropComparison.swift -o build/GemstonePhotoComparison
xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
    -module-cache-path build/GemstonePreviewCache "${sources[@]}" \
    Design/GemstoneDial/RenderLocalLightStudy.swift -o build/GemstoneLocalLightStudy
xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
    -module-cache-path build/GemstonePreviewCache "${sources[@]}" \
    Design/GemstoneDial/ValidatePhotoScenes.swift -o build/GemstonePhotoValidation
if [[ "${GEMSTONE_BUILD_MEMORY_PROBE:-0}" == "1" ]]; then
    xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
        -module-cache-path build/GemstonePreviewCache "${sources[@]}" \
        Design/GemstoneDial/MeasureResourceMemory.swift -o build/GemstoneMemoryMeasurement
fi
codesign --force --sign "$certificate" "$preview_root"
codesign --verify --deep --strict "$preview_root"
codesign -dv --verbose=4 "$preview_root"
codesign -d -r- "$preview_root"
echo "$preview_root"
