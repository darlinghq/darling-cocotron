#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
: "${OUT:?}" "${SWIFT_TOOLCHAIN:?}" "${SWIFT_CORE_MODULES:?}" "${SWIFT_SHIMS:?}" "${SWIFT_APINOTES:?}" "${IOS_SDK:?}"
mkdir -p "$OUT/resource"
ln -sfn "$SWIFT_TOOLCHAIN/lib/swift/clang" "$OUT/resource/clang"
ln -sfn "$SWIFT_SHIMS" "$OUT/resource/shims"
ln -sfn "$SWIFT_APINOTES" "$OUT/resource/apinotes"
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$here/NSManagedObjectContext.swift" -whole-module-optimization \
    -target arm64-apple-ios16.0 -sdk "$IOS_SDK" -resource-dir "$OUT/resource" \
    -module-cache-path "$OUT/module-cache" -I "$SWIFT_CORE_MODULES" -I "$here/Bridge" \
    -module-name CoreData -import-underlying-module -swift-version 5 -enable-library-evolution -parse-as-library -O -warnings-as-errors \
    -runtime-compatibility-version none -disable-autolinking-runtime-compatibility \
    -disable-implicit-concurrency-module-import -disable-implicit-string-processing-module-import \
    -o "$OUT/CoreDataSupplement.o"
"$SWIFT_TOOLCHAIN/bin/clang" -c -O2 -fblocks -Wall -Wextra -Werror -target arm64-apple-ios16.0 -isysroot "$IOS_SDK" "$here/Bridge/CoreDataBridge.m" -o "$OUT/CoreDataBridge.o"
"${LD64_LLD:-ld64.lld}" -dylib -arch arm64 -platform_version ios 16.0 16.5 -syslibroot "$IOS_SDK" \
    -ignore_auto_link -install_name /usr/lib/swift/libDarlingCoreDataSupplement.dylib \
    -o "$OUT/libDarlingCoreDataSupplement.dylib" "$OUT/CoreDataSupplement.o" "$OUT/CoreDataBridge.o" \
    -L "$IOS_SDK/usr/lib/swift" -lswiftCore -lswiftObjectiveC -lswiftDarwin -lswiftCoreFoundation -lswiftDispatch \
    -framework CoreData -framework Foundation -lobjc -lSystem
