#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/../dagu-kernel}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$ROOT_DIR/../proton-clang}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out/dagu}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/dagu}"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -f "$KERNEL_DIR/Makefile" ]]; then
    echo "kernel source not found: $KERNEL_DIR" >&2
    exit 1
fi

if [[ ! -x "$TOOLCHAIN_DIR/bin/clang" ]]; then
    echo "clang toolchain not found: $TOOLCHAIN_DIR/bin/clang" >&2
    exit 1
fi

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="github-actions"
export KBUILD_BUILD_HOST="dagu-builder"

compat_toolchain_prefix="${CROSS_COMPILE_COMPAT:-/usr/bin/arm-linux-gnueabi-}"
cc_compat="${CC_COMPAT:-${compat_toolchain_prefix}gcc}"
ld_compat="${LD_COMPAT:-${compat_toolchain_prefix}ld}"
kernel_toolchain_prefix="${CROSS_COMPILE:-/usr/bin/aarch64-linux-gnu-}"

if ! command -v "${kernel_toolchain_prefix}as" >/dev/null; then
    echo "AArch64 GNU toolchain not found: $kernel_toolchain_prefix" >&2
    exit 1
fi

if ! command -v "$cc_compat" >/dev/null || ! command -v "$ld_compat" >/dev/null; then
    echo "32-bit ARM compat toolchain not found: $compat_toolchain_prefix" >&2
    exit 1
fi

for kernel_patch in "$ROOT_DIR"/patches/dagu/*.patch; do
    git -C "$KERNEL_DIR" apply --unidiff-zero "$kernel_patch"
done

mkdir -p "$OUT_DIR" "$DIST_DIR"

make_args=(
    -C "$KERNEL_DIR"
    O="$OUT_DIR"
    ARCH=arm64
    LLVM=1
    LLVM_IAS=0
    CC=clang
    HOSTCC=clang
    HOSTCXX=clang++
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE="$kernel_toolchain_prefix"
    CROSS_COMPILE_COMPAT="$compat_toolchain_prefix"
    CC_COMPAT="$cc_compat"
    LD_COMPAT="$ld_compat"
)

if [[ -n "${KERNEL_CONFIG_GZ_BASE64:-}" ]]; then
    if [[ -z "${KERNEL_LOCALVERSION:-}" ]]; then
        echo "KERNEL_LOCALVERSION is required with a supplied kernel config" >&2
        exit 1
    fi

    printf '%s' "$KERNEL_CONFIG_GZ_BASE64" | base64 --decode | gzip --decompress > "$OUT_DIR/.config"
    "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
        --disable LOCALVERSION_AUTO \
        --set-str LOCALVERSION "$KERNEL_LOCALVERSION"
    make_args+=(LOCALVERSION=)
else
    make "${make_args[@]}" dagu_user_defconfig

    "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
        --enable MODULES \
        --enable MODVERSIONS \
        --enable KALLSYMS \
        --enable KALLSYMS_ALL \
        --enable KPROBES
fi

make "${make_args[@]}" olddefconfig
make -j"$JOBS" "${make_args[@]}" Image Image.gz dtbs modules
make -j"$JOBS" "${make_args[@]}" M="$ROOT_DIR/lsdriver" modules

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/dtbs"

for artifact in \
    "$OUT_DIR/arch/arm64/boot/Image" \
    "$OUT_DIR/arch/arm64/boot/Image.gz" \
    "$OUT_DIR/System.map" \
    "$OUT_DIR/Module.symvers" \
    "$OUT_DIR/.config" \
    "$ROOT_DIR/lsdriver/lsdriver.ko"; do
    if [[ -f "$artifact" ]]; then
        cp "$artifact" "$DIST_DIR/"
    fi
done

dt_root="$OUT_DIR/arch/arm64/boot/dts"
if [[ -d "$dt_root" ]]; then
    while IFS= read -r -d '' artifact; do
        relative="${artifact#"$dt_root/"}"
        mkdir -p "$DIST_DIR/dtbs/$(dirname -- "$relative")"
        cp "$artifact" "$DIST_DIR/dtbs/$relative"
    done < <(find "$dt_root" -type f \( -name '*.dtb' -o -name '*.dtbo' \) -print0)
fi

{
    echo "kernel_commit=$(git -C "$KERNEL_DIR" rev-parse HEAD)"
    echo "kernel_release=$(make -s "${make_args[@]}" kernelrelease)"
    echo "clang=$($TOOLCHAIN_DIR/bin/clang --version | head -n 1)"
    echo "driver_commit=$(git -C "$ROOT_DIR" rev-parse HEAD)"
} > "$DIST_DIR/build-info.txt"

echo "Build artifacts: $DIST_DIR"
find "$DIST_DIR" -maxdepth 3 -type f -printf '%P\n' | sort
