#!/bin/bash
#
# AssKit: local libass XCFramework builder for Apple platforms.
#
# Usage:
#   ./build.sh                         Build all platforms
#   ./build.sh platform=ios,macos      Build selected platforms
#   ./build.sh package                 Repackage already-built thin libraries
#   ./build.sh clean                   Remove build artifacts
#
set -eo pipefail

LIBUNIBREAK_VERSION="libunibreak_6_1"
FREETYPE_VERSION="VER-2-14-3"
FRIBIDI_VERSION="v1.0.16"
HARFBUZZ_VERSION="14.2.0"
LIBASS_VERSION="0.17.4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/Vendor"
SRC_DIR="${BUILD_DIR}/src"
THIN_DIR="${BUILD_DIR}/thin"
WORK_DIR="${BUILD_DIR}/work"
FRAMEWORK_DIR="${BUILD_DIR}/frameworks"

ALL_KEYS=(
    ios-arm64
    isimulator-arm64
    isimulator-x86_64
    tvos-arm64
    tvsimulator-arm64
    tvsimulator-x86_64
    macos-arm64
    macos-x86_64
)

selected_platforms=()

for arg in "$@"; do
    case "$arg" in
        platform=*)
            IFS=',' read -r -a selected_platforms <<< "${arg#platform=}"
            ;;
    esac
done

need_platform() {
    local platform="$1"
    if (( ${#selected_platforms[@]} == 0 )); then
        return 0
    fi
    for item in "${selected_platforms[@]}"; do
        [[ "$item" == "$platform" ]] && return 0
    done
    return 1
}

keys_to_build() {
    local keys=()
    need_platform ios && keys+=(ios-arm64)
    need_platform isimulator && keys+=(isimulator-arm64 isimulator-x86_64)
    need_platform tvos && keys+=(tvos-arm64)
    need_platform tvsimulator && keys+=(tvsimulator-arm64 tvsimulator-x86_64)
    need_platform macos && keys+=(macos-arm64 macos-x86_64)
    printf '%s\n' "${keys[@]}"
}

sdk_for_key() {
    case "$1" in
        ios-*) printf '%s\n' "iphoneos" ;;
        isimulator-*) printf '%s\n' "iphonesimulator" ;;
        tvos-*) printf '%s\n' "appletvos" ;;
        tvsimulator-*) printf '%s\n' "appletvsimulator" ;;
        macos-*) printf '%s\n' "macosx" ;;
    esac
}

arch_for_key() {
    printf '%s\n' "${1##*-}"
}

target_for_key() {
    case "$1" in
        ios-arm64) printf '%s\n' "arm64-apple-ios14.0" ;;
        isimulator-arm64) printf '%s\n' "arm64-apple-ios14.0-simulator" ;;
        isimulator-x86_64) printf '%s\n' "x86_64-apple-ios14.0-simulator" ;;
        tvos-arm64) printf '%s\n' "arm64-apple-tvos14.0" ;;
        tvsimulator-arm64) printf '%s\n' "arm64-apple-tvos14.0-simulator" ;;
        tvsimulator-x86_64) printf '%s\n' "x86_64-apple-tvos14.0-simulator" ;;
        macos-arm64) printf '%s\n' "arm64-apple-macos11.0" ;;
        macos-x86_64) printf '%s\n' "x86_64-apple-macos11.0" ;;
    esac
}

host_for_key() {
    case "$(arch_for_key "$1")" in
        arm64) printf '%s\n' "aarch64-apple-darwin" ;;
        x86_64) printf '%s\n' "x86_64-apple-darwin" ;;
    esac
}

cpu_family_for_arch() {
    case "$1" in
        arm64) printf '%s\n' "aarch64" ;;
        x86_64) printf '%s\n' "x86_64" ;;
    esac
}

fetch_repo() {
    local name="$1"
    local repo="$2"
    local version="$3"
    local dest="${SRC_DIR}/${name}"

    if [[ -d "${dest}/.git" ]]; then
        echo "→ Updating ${name} source to ${version}"
        git -C "${dest}" fetch --depth 1 origin "refs/tags/${version}:refs/tags/${version}" || true
        git -C "${dest}" fetch --depth 1 origin "${version}"
        git -C "${dest}" checkout --detach "${version}"
        return
    fi

    echo "→ Cloning ${name} ${version}"
    git clone --depth 1 --branch "${version}" "${repo}" "${dest}"
}

fetch_sources() {
    mkdir -p "${SRC_DIR}"
    fetch_repo libunibreak https://github.com/adah1972/libunibreak.git "${LIBUNIBREAK_VERSION}"
    fetch_repo freetype https://github.com/freetype/freetype.git "${FREETYPE_VERSION}"
    fetch_repo fribidi https://github.com/fribidi/fribidi.git "${FRIBIDI_VERSION}"
    fetch_repo harfbuzz https://github.com/harfbuzz/harfbuzz.git "${HARFBUZZ_VERSION}"
    fetch_repo libass https://github.com/libass/libass.git "${LIBASS_VERSION}"
}

common_env_for_key() {
    local key="$1"
    local sdk="$(sdk_for_key "$key")"
    local arch="$(arch_for_key "$key")"
    local target="$(target_for_key "$key")"
    local sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"

    export CC="/usr/bin/clang"
    export AR="/usr/bin/ar"
    export RANLIB="/usr/bin/ranlib"
    export STRIP="/usr/bin/strip"
    export CFLAGS="-arch ${arch} -isysroot ${sdk_path} -target ${target} -fPIC"
    export CXXFLAGS="${CFLAGS} -stdlib=libc++"
    export LDFLAGS="-arch ${arch} -isysroot ${sdk_path} -target ${target}"
}

write_meson_cross_file() {
    local key="$1"
    local cross_file="$2"
    local sdk="$(sdk_for_key "$key")"
    local arch="$(arch_for_key "$key")"
    local target="$(target_for_key "$key")"
    local sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
    local cpu_family="$(cpu_family_for_arch "$arch")"

    cat > "${cross_file}" << EOF
[binaries]
c = '/usr/bin/clang'
cpp = '/usr/bin/clang++'
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-arch', '${arch}', '-isysroot', '${sdk_path}', '-target', '${target}', '-fPIC']
cpp_args = ['-arch', '${arch}', '-isysroot', '${sdk_path}', '-target', '${target}', '-fPIC', '-stdlib=libc++', '-U_LIBCPP_ENABLE_ASSERTIONS', '-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST']
c_link_args = ['-arch', '${arch}', '-isysroot', '${sdk_path}', '-target', '${target}']
cpp_link_args = ['-arch', '${arch}', '-isysroot', '${sdk_path}', '-target', '${target}', '-stdlib=libc++']

[host_machine]
system = 'darwin'
cpu_family = '${cpu_family}'
cpu = '${cpu_family}'
endian = 'little'
EOF
}

dep_pkg_config_path() {
    local key="$1"
    printf '%s\n' "${THIN_DIR}/libunibreak/${key}/lib/pkgconfig:${THIN_DIR}/freetype/${key}/lib/pkgconfig:${THIN_DIR}/fribidi/${key}/lib/pkgconfig:${THIN_DIR}/harfbuzz/${key}/lib/pkgconfig"
}

run_make() {
    make -j"$(sysctl -n hw.ncpu)"
}

build_unibreak() {
    local key="$1"
    echo ""
    echo "━━━ Building libunibreak: ${key} ━━━"

    local install_dir="${THIN_DIR}/libunibreak/${key}"
    local work="${WORK_DIR}/libunibreak/${key}"
    rm -rf "${work}" "${install_dir}"
    mkdir -p "${work}" "${install_dir}"
    cp -R "${SRC_DIR}/libunibreak/." "${work}/"

    common_env_for_key "$key"
    cd "${work}"
    [[ -x ./bootstrap ]] && ./bootstrap
    ./configure \
        --prefix="${install_dir}" \
        --host="$(host_for_key "$key")" \
        --enable-static \
        --disable-shared \
        --disable-fast-install \
        --disable-dependency-tracking
    run_make
    make install
}

build_meson_library() {
    local name="$1"
    local key="$2"
    local source="$3"
    local args=("${@:4}")

    echo ""
    echo "━━━ Building ${name}: ${key} ━━━"

    local install_dir="${THIN_DIR}/${name}/${key}"
    local work="${WORK_DIR}/${name}/${key}"
    local cross="${work}/cross.txt"
    rm -rf "${work}" "${install_dir}"
    mkdir -p "${work}" "${install_dir}"
    write_meson_cross_file "$key" "$cross"

    export PKG_CONFIG_PATH="$(dep_pkg_config_path "$key")"
    export PKG_CONFIG_LIBDIR="${PKG_CONFIG_PATH}"

    meson setup "${work}/build" "${source}" \
        --cross-file "${cross}" \
        --prefix="${install_dir}" \
        --default-library=static \
        --buildtype=release \
        "${args[@]}"
    ninja -C "${work}/build" -j"$(sysctl -n hw.ncpu)"
    ninja -C "${work}/build" install
}

build_key() {
    local key="$1"
    build_unibreak "$key"
    build_meson_library freetype "$key" "${SRC_DIR}/freetype" \
        -Dzlib=enabled -Dharfbuzz=disabled -Dbzip2=disabled -Dmmap=disabled -Dpng=disabled -Dbrotli=disabled
    build_meson_library fribidi "$key" "${SRC_DIR}/fribidi" \
        -Ddeprecated=false -Ddocs=false -Dbin=false -Dtests=false
    build_meson_library harfbuzz "$key" "${SRC_DIR}/harfbuzz" \
        -Dglib=disabled \
        -Dfreetype=disabled \
        -Ddocs=disabled \
        -Dtests=disabled \
        -Dutilities=disabled \
        -Dgpu=disabled \
        -Dgpu_demo=disabled \
        -Dsubset=disabled \
        -Dpng=disabled \
        -Dicu=disabled
    build_meson_library libass "$key" "${SRC_DIR}/libass" \
        -Dlibunibreak=enabled -Dcoretext=enabled -Dfontconfig=disabled -Ddirectwrite=disabled \
        -Dasm=disabled -Dcheckasm=disabled -Dtest=disabled -Dprofile=disabled -Dcompare=disabled -Dfuzz=disabled
}

framework_min_os() {
    case "$1" in
        ios|isimulator) printf '%s\n' "14.0" ;;
        tvos|tvsimulator) printf '%s\n' "14.0" ;;
        macos) printf '%s\n' "11.0" ;;
    esac
}

create_versioned_bundle() {
    local framework="$1"
    local platform="$2"
    local framework_dir="$3"

    [[ "$platform" == "macos" ]] || return 0

    local info_plist_path="${framework_dir}/Info.plist"
    local versions_path="${framework_dir}/Versions"

    if [[ -d "${framework_dir}" && -f "${info_plist_path}" && ! -d "${versions_path}" ]]; then
        echo "Converting ${framework}.framework to versioned bundle structure..."

        local version_a_resources_path="${framework_dir}/Versions/A/Resources"
        mkdir -p "${version_a_resources_path}"

        local new_info_plist_path="${version_a_resources_path}/Info.plist"
        mv "${info_plist_path}" "${new_info_plist_path}"

        local binary_path="${framework_dir}/${framework}"
        local new_binary_path="${framework_dir}/Versions/A/${framework}"
        if [[ -e "${binary_path}" ]]; then
            mv "${binary_path}" "${new_binary_path}"
        fi

        local license_path="${framework_dir}/LICENSE"
        if [[ -e "${license_path}" ]]; then
            mv "${license_path}" "${framework_dir}/Versions/A/LICENSE"
        fi

        local current_link_path="${framework_dir}/Versions/Current"
        rm -f "${current_link_path}"
        ln -s A "${current_link_path}"

        local binary_link_path="${framework_dir}/${framework}"
        rm -f "${binary_link_path}"
        ln -s "Versions/Current/${framework}" "${binary_link_path}"

        local resources_link_path="${framework_dir}/Resources"
        rm -rf "${resources_link_path}"
        ln -s "Versions/Current/Resources" "${resources_link_path}"

        echo "${framework}.framework converted to versioned bundle structure."
    fi
}

copy_framework_license() {
    local framework="$1"
    local framework_dir="$2"
    local license_source=""

    case "$framework" in
        Libunibreak)
            license_source="${SRC_DIR}/libunibreak/LICENCE"
            ;;
        Libfreetype)
            license_source="${SRC_DIR}/freetype/LICENSE.TXT"
            ;;
        Libfribidi)
            license_source="${SRC_DIR}/fribidi/COPYING"
            ;;
        Libharfbuzz)
            license_source="${SRC_DIR}/harfbuzz/COPYING"
            ;;
        Libass)
            license_source="${SRC_DIR}/libass/COPYING"
            ;;
    esac

    if [[ -n "${license_source}" ]]; then
        [[ -f "${license_source}" ]] || {
            echo "Missing license source for ${framework}: ${license_source}" >&2
            exit 1
        }
        cp "${license_source}" "${framework_dir}/LICENSE"
    fi
}

make_framework() {
    local name="$1"
    local framework="$2"
    local static_lib="$3"
    local header_root="$4"
    local platform="$5"
    shift 5
    local keys=("$@")

    local fw_dir="${FRAMEWORK_DIR}/${platform}/${framework}.framework"
    rm -rf "${fw_dir}"
    mkdir -p "${fw_dir}/Headers" "${fw_dir}/Modules"

    local first_key="${keys[0]}"
    cp -R "${THIN_DIR}/${name}/${first_key}/${header_root}/." "${fw_dir}/Headers/"

    local inputs=()
    for key in "${keys[@]}"; do
        inputs+=("${THIN_DIR}/${name}/${key}/lib/${static_lib}")
    done
    lipo -create "${inputs[@]}" -output "${fw_dir}/${framework}"

    cat > "${fw_dir}/Modules/module.modulemap" << EOF
framework module ${framework} [system] {
    umbrella "."
    export *
}
EOF

    local min_os="$(framework_min_os "$platform")"
    cat > "${fw_dir}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>${framework}</string>
<key>CFBundleIdentifier</key><string>dev.asskit.${framework}</string>
<key>CFBundleName</key><string>${framework}</string>
<key>CFBundleVersion</key><string>${LIBASS_VERSION}</string>
<key>CFBundleShortVersionString</key><string>${LIBASS_VERSION}</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>MinimumOSVersion</key><string>${min_os}</string>
</dict></plist>
EOF

    copy_framework_license "$framework" "$fw_dir"
    create_versioned_bundle "$framework" "$platform" "$fw_dir"
}

create_xcframework() {
    local name="$1"
    local framework="$2"
    local static_lib="$3"
    local header_root="$4"

    local frameworks=()

    if [[ -d "${THIN_DIR}/${name}/ios-arm64" ]]; then
        make_framework "$name" "$framework" "$static_lib" "$header_root" ios ios-arm64
        frameworks+=(-framework "${FRAMEWORK_DIR}/ios/${framework}.framework")
    fi
    if [[ -d "${THIN_DIR}/${name}/isimulator-arm64" && -d "${THIN_DIR}/${name}/isimulator-x86_64" ]]; then
        make_framework "$name" "$framework" "$static_lib" "$header_root" isimulator isimulator-arm64 isimulator-x86_64
        frameworks+=(-framework "${FRAMEWORK_DIR}/isimulator/${framework}.framework")
    fi
    if [[ -d "${THIN_DIR}/${name}/tvos-arm64" ]]; then
        make_framework "$name" "$framework" "$static_lib" "$header_root" tvos tvos-arm64
        frameworks+=(-framework "${FRAMEWORK_DIR}/tvos/${framework}.framework")
    fi
    if [[ -d "${THIN_DIR}/${name}/tvsimulator-arm64" && -d "${THIN_DIR}/${name}/tvsimulator-x86_64" ]]; then
        make_framework "$name" "$framework" "$static_lib" "$header_root" tvsimulator tvsimulator-arm64 tvsimulator-x86_64
        frameworks+=(-framework "${FRAMEWORK_DIR}/tvsimulator/${framework}.framework")
    fi
    if [[ -d "${THIN_DIR}/${name}/macos-arm64" && -d "${THIN_DIR}/${name}/macos-x86_64" ]]; then
        make_framework "$name" "$framework" "$static_lib" "$header_root" macos macos-arm64 macos-x86_64
        frameworks+=(-framework "${FRAMEWORK_DIR}/macos/${framework}.framework")
    fi

    if (( ${#frameworks[@]} == 0 )); then
        echo "No slices found for ${framework}; skipping"
        return
    fi

    local output="${OUTPUT_DIR}/${framework}.xcframework"
    rm -rf "${output}"
    echo "→ Creating ${framework}.xcframework"
    xcodebuild -create-xcframework "${frameworks[@]}" -output "${output}"
}

make_xcframeworks() {
    mkdir -p "${OUTPUT_DIR}"
    rm -rf "${FRAMEWORK_DIR}"
    create_xcframework libunibreak Libunibreak libunibreak.a include
    create_xcframework freetype Libfreetype libfreetype.a include/freetype2
    create_xcframework fribidi Libfribidi libfribidi.a include/fribidi
    create_xcframework harfbuzz Libharfbuzz libharfbuzz.a include/harfbuzz
    create_xcframework libass Libass libass.a include/ass
}

if [[ "$1" == "clean" ]]; then
    echo "Cleaning AssKit build artifacts"
    rm -rf "${BUILD_DIR}"
    exit 0
fi

if [[ "$1" == "package" ]]; then
    fetch_sources
    make_xcframeworks
    exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║  AssKit: libass local XCFrameworks  ║"
echo "╚══════════════════════════════════════╝"

fetch_sources

build_keys=($(keys_to_build))
for key in "${build_keys[@]}"; do
    build_key "$key"
done

make_xcframeworks

echo ""
echo "✓ Build complete"
for xcf in "${OUTPUT_DIR}"/*.xcframework; do
    [[ -d "$xcf" ]] && echo "  $(du -sh "$xcf" | cut -f1)  $(basename "$xcf")"
done