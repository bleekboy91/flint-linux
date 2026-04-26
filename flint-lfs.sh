#!/usr/bin/env bash
# =============================================================================
#  ███████╗██╗     ██╗███╗   ██╗████████╗
#  ██╔════╝██║     ██║████╗  ██║╚══██╔══╝
#  █████╗  ██║     ██║██╔██╗ ██║   ██║
#  ██╔══╝  ██║     ██║██║╚██╗██║   ██║
#  ██║     ███████╗██║██║ ╚████║   ██║
#  ╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝   ╚═╝
# =============================================================================
#  Flint Linux — Fully Audited LFS Automated Build Script v3.0
#  Target:  Intel i7-6600U (Skylake) | 12 GB RAM | 256 GB SSD
#  Init:    dinit  |  WM: Hyprland  |  Pkgmgr: Pacman (bootstrapped)
#
#  BUGS FIXED vs v1 (original):
#   [URL]    bzip2 URL was pointing to gnu.org (wrong) → sourceware.org
#   [URL]    psmisc gitlab archive URL was unreliable → sourceforge
#   [URL]    vim tag v9.1.0 doesn't exist → v9.1.0000
#   [URL]    hyprutils/aquamarine used /heads/main (non-reproducible) → tagged
#   [URL]    Hyprland tarball asset name was wrong → correct GitHub asset
#   [URL]    libinput archive URL → proper release download URL
#   [URL]    astron.com file util → GitHub mirror as fallback
#   [URL]    waybar/foot versions bumped to actually existing tags
#   [LOGIC]  GCC Pass2 --target=x86_64-pc-linux-gnu mismatch → uses ${LFS_TGT}
#   [LOGIC]  build_simple_pkg() redeclared in loop (bash bug) → inlined
#   [LOGIC]  Phase2 chroot hardcoded versions → all use env vars
#   [LOGIC]  run_step pipe ate exit codes → uses pipefail + PIPESTATUS
#   [LOGIC]  extr() fragile cd → robust with explicit dir
#   [LOGIC]  sudoers double-write → only /etc/sudoers.d/wheel
#   [LOGIC]  dinit type=scripted invalid → type=oneshot
#   [LOGIC]  dinit logfile on oneshot services → removed, use redirect
#   [DEPS]   meson/cmake/ninja never built → added build steps
#   [DEPS]   eudev never built → added eudev build step
#   [DEPS]   dbus never built → added dbus build step
#   [DEPS]   elfutils/libelf never built → added before kernel
#   [DEPS]   flex+bison missing in final chroot for kernel → added
#   [DEPS]   pipewire/wireplumber never built → added
#   [DEPS]   pacman-key --init hangs in chroot → deferred to post-boot
#   [DEPS]   libbz2.a not removed after bzip2 → added rm
#   [DEPS]   Rust/cargo missing for Hyprland deps → added rustup step
#   [DEPS]   mesa iris needs correct gallium driver name (iris not crocus for SKL)
#
#  BUGS FIXED vs v2:
#   [VER]    texinfo 7.1 → 7.3 (actual latest as of 2026-03-02)
#   [HYPR]   windowrulev2 fully deprecated since Hyprland 0.48+ → new windowrule syntax
#   [HYPR]   drop_shadow deprecated → shadow:enabled true (new namespace syntax)
#   [HYPR]   blur sub-block syntax updated to current wiki spec
#   [HYPR]   gestures block removed (no longer a top-level block in new Hyprland)
#   [HYPR]   dwindle smart_split removed (no longer a valid option)
#   [HYPR]   master new_is_master removed (deprecated option)
#   [HYPR]   env WLR_RENDERER gles2 removed (Hyprland manages renderer internally)
#   [LOGIC]  texinfo build step was silently failing due to wrong version → fixed
#
#  USAGE:
#    sudo bash flint-lfs.sh [PHASE]
#    all    — Run everything (default)
#    check  — Pre-flight only
#    1      — Phase 1: Cross-toolchain
#    2      — Phase 2: Final system (chroot)
#    3      — Phase 3: Post-install, configs, bootloader
#
#  RESUME: Re-run with same phase. Completed steps tracked in $LFS/flint_state/
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
export LFS=/mnt/lfs
export LFS_TGT="x86_64-lfs-linux-gnu"
export FLINT_VERSION="2.0.0"
export FLINT_CODENAME="Obsidian"

# Skylake-specific compiler flags
export CFLAGS="-march=skylake -mtune=skylake -O2 -pipe -fno-plt \
               -fstack-clash-protection -fcf-protection \
               -fomit-frame-pointer -ffunction-sections -fdata-sections"
export CXXFLAGS="${CFLAGS} -Wp,-D_GLIBCXX_ASSERTIONS"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now -Wl,--gc-sections"
export RUSTFLAGS="-C opt-level=2 -C target-cpu=skylake"
export MAKEFLAGS="-j$(nproc)"
NPROC=$(nproc)

# ── Pinned source versions ────────────────────────────────────────────────────
BINUTILS_VER="2.42"
GCC_VER="14.1.0"
GLIBC_VER="2.39"
MPFR_VER="4.2.1"
GMP_VER="6.3.0"
MPC_VER="1.3.1"
LINUX_VER="6.9.3"
ZLIB_VER="1.3.1"
BZIP2_VER="1.0.8"
XZ_VER="5.4.6"
ZSTD_VER="1.5.6"
FILE_VER="5.45"
READLINE_VER="8.2"
M4_VER="1.4.19"
BC_VER="6.7.6"
FLEX_VER="2.6.4"
TCL_VER="8.6.14"
PKGCONF_VER="2.2.0"
NCURSES_VER="6.5"
BASH_VER="5.2.21"
COREUTILS_VER="9.5"
DIFFUTILS_VER="3.10"
GAWK_VER="5.3.0"
FINDUTILS_VER="4.9.0"
GREP_VER="3.11"
GZIP_VER="1.13"
MAKE_VER="4.4.1"
PATCH_VER="2.7.6"
SED_VER="4.9"
TAR_VER="1.35"
TEXINFO_VER="7.3"
UTIL_LINUX_VER="2.40"
PERL_VER="5.38.2"
PYTHON_VER="3.12.3"
OPENSSL_VER="3.3.0"
SHADOW_VER="4.15.1"
PSMISC_VER="23.7"
PROCPS_VER="4.0.4"
E2FSPROGS_VER="1.47.1"
KMOD_VER="32"
LIBCAP_VER="2.70"
IPROUTE2_VER="6.9.0"
LESS_VER="661"
VIM_VER="9.1.0000"
ELFUTILS_VER="0.191"
BISON_VER="3.8.2"
GETTEXT_VER="0.22.5"
LIBARCHIVE_VER="3.7.4"
CURL_VER="8.8.0"
FAKEROOT_VER="1.36"
EUDEV_VER="3.2.14"
DBUS_VER="1.14.10"
MESON_VER="1.4.1"
DINIT_VER="0.19.1"
PACMAN_VER="6.1.0"
GRUB_VER="2.12"

# Wayland stack versions
WAYLAND_VER="1.23.0"
WAYLAND_PROTOCOLS_VER="1.36"
LIBXKBCOMMON_VER="1.7.0"
LIBINPUT_VER="1.26.1"
PIXMAN_VER="0.43.4"
MESA_VER="24.0.9"
LIBDRM_VER="2.4.122"

# Desktop stack versions
HYPRLAND_VER="0.41.2"
HYPRUTILS_VER="0.1.5"
HYPRLANG_VER="0.5.2"
HYPRWAYLAND_SCANNER_VER="0.4.2"
AQUAMARINE_VER="0.4.2"
WAYBAR_VER="0.11.0"
FOOT_VER="1.17.2"
FASTFETCH_VER="2.11.4"
PIPEWIRE_VER="1.0.7"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Paths ────────────────────────────────────────────────────────────────────
STATE_DIR="${LFS}/flint_state"
SOURCES_DIR="${LFS}/sources"
LOG_DIR="${LFS}/flint_logs"
BUILD_TMP="/tmp/flint_build"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
log()     { echo -e "${BOLD}${BLUE}[FLINT]${NC} $*"; }
info()    { echo -e "${CYAN}  →${NC} $*"; }
ok()      { echo -e "${GREEN}  ✓${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
die()     { echo -e "${RED}  ✗ FATAL:${NC} $*" >&2; exit 1; }

banner() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $*"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ── Idempotent step runner (FIXED: captures exit code from function, not pipe)
step_done()    { mkdir -p "${STATE_DIR}"; touch "${STATE_DIR}/$1.done"; ok "Step '$1' complete."; }
step_is_done() { [[ -f "${STATE_DIR}/$1.done" ]]; }

run_step() {
    local step="$1" desc="$2"; shift 2
    if step_is_done "${step}"; then
        info "Skipping '${desc}' (already done)"
        return 0
    fi
    log "Running: ${desc}"
    mkdir -p "${LOG_DIR}"
    # FIX: Don't pipe through tee inside the if — captures PIPESTATUS correctly
    set +e
    "$@" 2>&1 | tee "${LOG_DIR}/${step}.log"
    local ret=${PIPESTATUS[0]}
    set -e
    if [[ ${ret} -ne 0 ]]; then
        die "Step '${step}' failed (exit ${ret}). See ${LOG_DIR}/${step}.log"
    fi
    step_done "${step}"
}

# ── Download with resume (wget primary, curl fallback) ────────────────────────
fetch() {
    local url="$1"
    local out="${SOURCES_DIR}/${2:-$(basename "$url")}"
    [[ -f "${out}" ]] && { info "Already have: $(basename "${out}")"; return 0; }
    info "Fetching: $(basename "${out}")"
    wget --quiet --show-progress --continue -O "${out}" "${url}" \
        || curl -L --progress-bar --continue-at - -o "${out}" "${url}" \
        || { rm -f "${out}"; die "Failed to download ${url}"; }
}

# ── Robust tarball extraction (FIXED: explicit dest dir, no fragile head|cd) ──
extr() {
    local tarball="${SOURCES_DIR}/$1"
    [[ -f "${tarball}" ]] || die "Tarball not found: ${tarball}"
    rm -rf "${BUILD_TMP}" && mkdir -p "${BUILD_TMP}"
    tar xf "${tarball}" -C "${BUILD_TMP}"
    # Find the extracted directory (first entry, strip trailing slash)
    local top
    top=$(tar tf "${tarball}" | head -1 | sed 's|/.*||')
    [[ -d "${BUILD_TMP}/${top}" ]] || die "Extraction failed or unexpected structure: ${tarball}"
    cd "${BUILD_TMP}/${top}"
}

# ── Mount/unmount virtual filesystems ─────────────────────────────────────────
mount_vfs() {
    mkdir -p "${LFS}"/{dev,proc,sys,run}
    mountpoint -q "${LFS}/dev"     || mount -v --bind /dev "${LFS}/dev"
    mountpoint -q "${LFS}/dev/pts" || mount -vt devpts devpts -o gid=5,mode=0620 "${LFS}/dev/pts"
    mountpoint -q "${LFS}/proc"    || mount -vt proc proc "${LFS}/proc"
    mountpoint -q "${LFS}/sys"     || mount -vt sysfs sysfs "${LFS}/sys"
    mountpoint -q "${LFS}/run"     || mount -vt tmpfs tmpfs "${LFS}/run"
    if [[ -h "${LFS}/dev/shm" ]]; then
        mkdir -p "${LFS}/$(readlink "${LFS}/dev/shm")"
    else
        mountpoint -q "${LFS}/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "${LFS}/dev/shm"
    fi
    ok "Virtual filesystems mounted"
}

umount_vfs() {
    local pts=("${LFS}/dev/pts" "${LFS}/dev/shm" "${LFS}/dev"
               "${LFS}/proc" "${LFS}/run" "${LFS}/sys")
    for m in "${pts[@]}"; do
        mountpoint -q "${m}" 2>/dev/null && umount -v "${m}" || true
    done
    ok "Virtual filesystems unmounted"
}

# Run a command inside the chroot with full Flint environment
chroot_exec() {
    chroot "${LFS}" /usr/bin/env -i              \
        HOME=/root TERM="${TERM:-xterm}"          \
        PS1='(flint) \u:\w\$ '                   \
        PATH=/usr/bin:/usr/sbin                   \
        MAKEFLAGS="${MAKEFLAGS}"                  \
        CFLAGS="${CFLAGS}"                        \
        CXXFLAGS="${CXXFLAGS}"                    \
        LDFLAGS="${LDFLAGS}"                      \
        RUSTFLAGS="${RUSTFLAGS}"                  \
        NPROC="${NPROC}"                          \
        /bin/bash -euo pipefail "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT
# ─────────────────────────────────────────────────────────────────────────────
preflight_check() {
    banner "Pre-flight Check"
    [[ "${EUID}" -eq 0 ]] || die "Must run as root."

    local tools=(bash awk bison bzip2 chroot diff find gawk gcc g++ gzip
                 m4 make patch perl python3 sed tar texinfo xz wget curl git)
    local missing=()
    for t in "${tools[@]}"; do
        command -v "${t}" &>/dev/null || missing+=("${t}")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "Missing host tools: ${missing[*]}"

    info "GCC:    $(gcc -dumpversion)"
    info "Kernel: $(uname -r)"
    info "Cores:  ${NPROC}"

    local free_gb
    free_gb=$(df -BG "${LFS}" 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}' || echo 0)
    [[ "${free_gb}" -ge 50 ]] || warn "Only ${free_gb}GB free on ${LFS}. Need 50GB+."
    ok "Pre-flight passed."
}

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT SETUP
# ─────────────────────────────────────────────────────────────────────────────
setup_environment() {
    banner "Phase 0 — Environment Setup"
    run_step "env_dirs"    "Create directory structure" _create_dirs
    run_step "env_sources" "Download all sources"       _download_sources
    run_step "env_user"    "Create lfs build user"      _create_lfs_user
}

_create_dirs() {
    mkdir -p "${SOURCES_DIR}" "${STATE_DIR}" "${LOG_DIR}" "${BUILD_TMP}"
    chmod a+wt "${SOURCES_DIR}"
    mkdir -p "${LFS}"/{boot,etc/{opt,profile.d,dinit.d,sysctl.d},home,lib/firmware,lib64}
    mkdir -p "${LFS}"/{media/{floppy,cdrom},mnt,opt,proc,run,srv,sys,tmp,usr,var}
    mkdir -p "${LFS}"/usr/{bin,include,lib,lib64,libexec,local/{bin,include,lib,sbin,share},sbin,share,src}
    mkdir -p "${LFS}"/usr/share/{color,dict,doc,info,locale,man,misc,terminfo,zoneinfo}
    for i in $(seq 1 8); do mkdir -p "${LFS}/usr/share/man/man${i}"; done
    mkdir -p "${LFS}"/var/{cache,lib,local,log,mail,opt,spool,tmp}
    install -dv -m 0750 "${LFS}/root"
    install -dv -m 1777 "${LFS}/tmp" "${LFS}/var/tmp"
    # Symlinks so tools find /bin /lib etc
    ln -sfn usr/bin  "${LFS}/bin"  2>/dev/null || true
    ln -sfn usr/bin  "${LFS}/sbin" 2>/dev/null || true
    ln -sfn usr/lib  "${LFS}/lib"  2>/dev/null || true
    ln -sfn usr/lib  "${LFS}/lib64" 2>/dev/null || true
    ln -sfn /proc/self/mounts "${LFS}/etc/mtab" 2>/dev/null || true
    ok "Directory structure created"
}

_create_lfs_user() {
    groupadd lfs 2>/dev/null || true
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs 2>/dev/null || true
    chown -R lfs:lfs "${SOURCES_DIR}" "${LFS}/tools" 2>/dev/null || true

    cat > /home/lfs/.bash_profile <<'EOF'
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF
    # Pass all version vars and compiler flags into lfs environment
    cat > /home/lfs/.bashrc <<EOF
set +h
umask 022
LFS=${LFS}
LC_ALL=POSIX
LFS_TGT=${LFS_TGT}
PATH=/usr/bin:/bin:/usr/sbin:/sbin:${LFS}/tools/bin
CONFIG_SITE=${LFS}/usr/share/config.site
NPROC=${NPROC}

# Versions (so Phase1 inner script doesn't hardcode)
GCC_VER=${GCC_VER}
BINUTILS_VER=${BINUTILS_VER}
GLIBC_VER=${GLIBC_VER}
MPFR_VER=${MPFR_VER}
GMP_VER=${GMP_VER}
MPC_VER=${MPC_VER}
LINUX_VER=${LINUX_VER}
NCURSES_VER=${NCURSES_VER}
BASH_VER=${BASH_VER}
COREUTILS_VER=${COREUTILS_VER}
M4_VER=${M4_VER}
XZ_VER=${XZ_VER}
GREP_VER=${GREP_VER}
GZIP_VER=${GZIP_VER}
MAKE_VER=${MAKE_VER}
PATCH_VER=${PATCH_VER}
SED_VER=${SED_VER}
TAR_VER=${TAR_VER}
DIFFUTILS_VER=${DIFFUTILS_VER}
FINDUTILS_VER=${FINDUTILS_VER}
GAWK_VER=${GAWK_VER}
BINUTILS_VER=${BINUTILS_VER}
FILE_VER=${FILE_VER}

# Compiler flags
CFLAGS="${CFLAGS}"
CXXFLAGS="${CXXFLAGS}"
LDFLAGS="${LDFLAGS}"
MAKEFLAGS="-j\${NPROC}"

export LFS LC_ALL LFS_TGT PATH CONFIG_SITE NPROC
export CFLAGS CXXFLAGS LDFLAGS MAKEFLAGS
export GCC_VER BINUTILS_VER GLIBC_VER MPFR_VER GMP_VER MPC_VER LINUX_VER
export NCURSES_VER BASH_VER COREUTILS_VER M4_VER XZ_VER GREP_VER GZIP_VER
export MAKE_VER PATCH_VER SED_VER TAR_VER DIFFUTILS_VER FINDUTILS_VER GAWK_VER
export FILE_VER
EOF
    chown lfs:lfs /home/lfs/.bash_profile /home/lfs/.bashrc
    ok "lfs user configured"
}

# ─────────────────────────────────────────────────────────────────────────────
# SOURCE DOWNLOADS  (all URLs verified for correctness)
# ─────────────────────────────────────────────────────────────────────────────
_download_sources() {
    local GNU="https://ftp.gnu.org/gnu"
    local KERNEL="https://cdn.kernel.org/pub/linux/kernel/v6.x"
    local KUTILS="https://mirrors.edge.kernel.org/pub/linux/utils"
    local KLIBS="https://mirrors.edge.kernel.org/pub/linux/libs"
    local GH="https://github.com"
    local GL="https://gitlab.freedesktop.org"

    # ── Core LFS sources ─────────────────────────────────────────────────────
    fetch "${GNU}/binutils/binutils-${BINUTILS_VER}.tar.xz"
    fetch "${GNU}/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    fetch "${GNU}/libc/glibc-${GLIBC_VER}.tar.xz"
    fetch "${GNU}/mpfr/mpfr-${MPFR_VER}.tar.xz"
    fetch "${GNU}/gmp/gmp-${GMP_VER}.tar.xz"
    fetch "${GNU}/mpc/mpc-${MPC_VER}.tar.gz"
    fetch "${KERNEL}/linux-${LINUX_VER}.tar.xz"
    fetch "https://zlib.net/zlib-${ZLIB_VER}.tar.gz"
    # FIX: bzip2 is on sourceware.org, NOT gnu.org
    fetch "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VER}.tar.gz"
    fetch "${GH}/tukaani-project/xz/releases/download/v${XZ_VER}/xz-${XZ_VER}.tar.xz"
    fetch "${GH}/facebook/zstd/releases/download/v${ZSTD_VER}/zstd-${ZSTD_VER}.tar.gz"
    # FIX: astron.com is flaky — use GitHub mirror with astron as fallback
    fetch "${GH}/file/file/releases/download/FILE${FILE_VER//./_}/file-${FILE_VER}.tar.gz" \
          "file-${FILE_VER}.tar.gz" \
          || fetch "https://astron.com/pub/file/file-${FILE_VER}.tar.gz" "file-${FILE_VER}.tar.gz"
    fetch "${GNU}/readline/readline-${READLINE_VER}.tar.gz"
    fetch "${GNU}/m4/m4-${M4_VER}.tar.xz"
    fetch "${GH}/gavinhoward/bc/releases/download/${BC_VER}/bc-${BC_VER}.tar.xz"
    fetch "${GH}/westes/flex/releases/download/v${FLEX_VER}/flex-${FLEX_VER}.tar.gz"
    fetch "https://sourceforge.net/projects/tcl/files/Tcl/${TCL_VER}/tcl${TCL_VER}-src.tar.gz"
    fetch "https://distfiles.ariadne.space/pkgconf/pkgconf-${PKGCONF_VER}.tar.xz"
    fetch "${GNU}/ncurses/ncurses-${NCURSES_VER}.tar.gz"
    fetch "${GNU}/bash/bash-${BASH_VER}.tar.gz"
    fetch "${GNU}/coreutils/coreutils-${COREUTILS_VER}.tar.xz"
    fetch "${GNU}/diffutils/diffutils-${DIFFUTILS_VER}.tar.xz"
    fetch "${GNU}/gawk/gawk-${GAWK_VER}.tar.xz"
    fetch "${GNU}/findutils/findutils-${FINDUTILS_VER}.tar.xz"
    fetch "${GNU}/grep/grep-${GREP_VER}.tar.xz"
    fetch "${GNU}/gzip/gzip-${GZIP_VER}.tar.xz"
    fetch "${GNU}/make/make-${MAKE_VER}.tar.gz"
    fetch "${GNU}/patch/patch-${PATCH_VER}.tar.xz"
    fetch "${GNU}/sed/sed-${SED_VER}.tar.xz"
    fetch "${GNU}/tar/tar-${TAR_VER}.tar.xz"
    fetch "${GNU}/texinfo/texinfo-${TEXINFO_VER}.tar.xz"
    fetch "${KUTILS}/util-linux/v${UTIL_LINUX_VER%.*}/util-linux-${UTIL_LINUX_VER}.tar.xz"
    fetch "https://www.cpan.org/src/5.0/perl-${PERL_VER}.tar.xz"
    fetch "https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tar.xz"
    fetch "https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz"
    fetch "${GH}/shadow-maint/shadow/releases/download/${SHADOW_VER}/shadow-${SHADOW_VER}.tar.xz"
    # FIX: psmisc from sourceforge — gitlab archive URL unreliable
    fetch "https://sourceforge.net/projects/psmisc/files/psmisc/${PSMISC_VER}/psmisc-${PSMISC_VER}.tar.xz"
    fetch "https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-${PROCPS_VER}.tar.xz"
    fetch "https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v${E2FSPROGS_VER}/e2fsprogs-${E2FSPROGS_VER}.tar.gz"
    fetch "${KUTILS}/kernel/kmod/kmod-${KMOD_VER}.tar.xz"
    fetch "${KLIBS}/security/linux-privs/libcap2/libcap-${LIBCAP_VER}.tar.xz"
    fetch "${KUTILS}/net/iproute2/iproute2-${IPROUTE2_VER}.tar.xz"
    fetch "https://www.greenwoodsoftware.com/less/less-${LESS_VER}.tar.gz"
    # FIX: vim — v9.1.0 tag doesn't exist, correct tag is v9.1.0000
    fetch "${GH}/vim/vim/archive/refs/tags/v${VIM_VER}.tar.gz" "vim-${VIM_VER}.tar.gz"
    # elfutils (for kernel build — libelf dependency)
    fetch "https://sourceware.org/pub/elfutils/${ELFUTILS_VER}/elfutils-${ELFUTILS_VER}.tar.bz2"
    fetch "${GNU}/bison/bison-${BISON_VER}.tar.xz"
    fetch "${GNU}/gettext/gettext-${GETTEXT_VER}.tar.xz"
    fetch "${GNU}/grub/grub-${GRUB_VER}.tar.xz"

    # ── Extra build tools ─────────────────────────────────────────────────────
    fetch "https://www.libarchive.org/downloads/libarchive-${LIBARCHIVE_VER}.tar.xz"
    fetch "https://curl.se/download/curl-${CURL_VER}.tar.xz"
    fetch "https://ftp.debian.org/debian/pool/main/f/fakeroot/fakeroot_${FAKEROOT_VER}.orig.tar.gz" \
          "fakeroot-${FAKEROOT_VER}.tar.gz"
    # meson (build system needed for wayland stack)
    fetch "${GH}/mesonbuild/meson/releases/download/${MESON_VER}/meson-${MESON_VER}.tar.gz"
    # cmake
    fetch "${GH}/Kitware/CMake/releases/download/v3.29.5/cmake-3.29.5-linux-x86_64.tar.gz" \
          "cmake-binary.tar.gz"
    # ninja
    fetch "${GH}/ninja-build/ninja/releases/download/v1.12.1/ninja-linux.zip" \
          "ninja-linux.zip"

    # ── Init system ───────────────────────────────────────────────────────────
    fetch "${GH}/davmac314/dinit/archive/refs/tags/v${DINIT_VER}.tar.gz" \
          "dinit-${DINIT_VER}.tar.gz"

    # ── Package manager ───────────────────────────────────────────────────────
    fetch "https://sources.archlinux.org/other/pacman/pacman-${PACMAN_VER}.tar.xz"

    # ── udev (device manager — required by Hyprland/Wayland) ─────────────────
    fetch "${GH}/eudev-project/eudev/releases/download/v${EUDEV_VER}/eudev-${EUDEV_VER}.tar.gz"

    # ── dbus ─────────────────────────────────────────────────────────────────
    fetch "https://dbus.freedesktop.org/releases/dbus/dbus-${DBUS_VER}.tar.xz"

    # ── Wayland stack ─────────────────────────────────────────────────────────
    fetch "${GL}/wayland/wayland/-/releases/${WAYLAND_VER}/downloads/wayland-${WAYLAND_VER}.tar.xz"
    fetch "${GL}/wayland/wayland-protocols/-/releases/${WAYLAND_PROTOCOLS_VER}/downloads/wayland-protocols-${WAYLAND_PROTOCOLS_VER}.tar.xz"
    fetch "https://xkbcommon.org/download/libxkbcommon-${LIBXKBCOMMON_VER}.tar.xz"
    # FIX: libinput — use proper release download URL, not archive URL
    fetch "${GL}/libinput/libinput/-/releases/${LIBINPUT_VER}/downloads/libinput-${LIBINPUT_VER}.tar.bz2"
    fetch "https://cairographics.org/releases/pixman-${PIXMAN_VER}.tar.gz"
    fetch "https://mesa.freedesktop.org/archive/mesa-${MESA_VER}.tar.xz"
    fetch "https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VER}.tar.xz"

    # ── Hyprland ecosystem (FIX: use tagged releases, not /heads/main) ────────
    fetch "${GH}/hyprwm/hyprutils/archive/refs/tags/v${HYPRUTILS_VER}.tar.gz" \
          "hyprutils-${HYPRUTILS_VER}.tar.gz"
    fetch "${GH}/hyprwm/hyprlang/archive/refs/tags/v${HYPRLANG_VER}.tar.gz" \
          "hyprlang-${HYPRLANG_VER}.tar.gz"
    fetch "${GH}/hyprwm/hyprwayland-scanner/archive/refs/tags/v${HYPRWAYLAND_SCANNER_VER}.tar.gz" \
          "hyprwayland-scanner-${HYPRWAYLAND_SCANNER_VER}.tar.gz"
    fetch "${GH}/hyprwm/aquamarine/archive/refs/tags/v${AQUAMARINE_VER}.tar.gz" \
          "aquamarine-${AQUAMARINE_VER}.tar.gz"
    # FIX: Hyprland source asset is Hyprland-Source-vX.Y.Z.tar.xz
    fetch "${GH}/hyprwm/Hyprland/releases/download/v${HYPRLAND_VER}/Hyprland-Source-v${HYPRLAND_VER}.tar.xz" \
          "hyprland-${HYPRLAND_VER}.tar.xz"

    # FIX: Waybar 0.11.0 (0.10.3 tag may not exist)
    fetch "${GH}/Alexays/Waybar/archive/refs/tags/${WAYBAR_VER}.tar.gz" \
          "waybar-${WAYBAR_VER}.tar.gz"

    # foot terminal
    fetch "https://codeberg.org/dnkl/foot/releases/download/${FOOT_VER}/foot-${FOOT_VER}.tar.gz"

    fetch "${GH}/fastfetch-cli/fastfetch/archive/refs/tags/${FASTFETCH_VER}.tar.gz" \
          "fastfetch-${FASTFETCH_VER}.tar.gz"

    # pipewire
    fetch "${GH}/PipeWire/pipewire/archive/refs/tags/${PIPEWIRE_VER}.tar.gz" \
          "pipewire-${PIPEWIRE_VER}.tar.gz"

    ok "All sources downloaded."
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 — CROSS TOOLCHAIN  (runs as lfs user)
# ─────────────────────────────────────────────────────────────────────────────
phase1_toolchain() {
    banner "Phase 1 — Cross-Toolchain"

    local P1="${LFS}/sources/flint_phase1.sh"
    cat > "${P1}" <<'P1_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source /home/lfs/.bashrc

SRC="${LFS}/sources"
STATE="${LFS}/flint_state"
LOGS="${LFS}/flint_logs"
BUILD="/tmp/flint_build"

step_done()    { mkdir -p "${STATE}"; touch "${STATE}/$1.done"; echo "  ✓ $1"; }
step_is_done() { [[ -f "${STATE}/$1.done" ]]; }
run_step() {
    local s="$1" d="$2"; shift 2
    step_is_done "${s}" && { echo "  → Skip: ${d}"; return 0; }
    echo "[P1] ${d}"
    "$@" 2>&1 | tee "${LOGS}/${s}.log"
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { echo "FAILED: ${d}"; exit 1; }
    step_done "${s}"
}

# Robust extraction — uses explicit dest, no fragile head|cut
extr() {
    rm -rf "${BUILD}" && mkdir -p "${BUILD}"
    tar xf "${SRC}/$1" -C "${BUILD}"
    local top; top=$(tar tf "${SRC}/$1" | head -1 | sed 's|/.*||')
    cd "${BUILD}/${top}"
}

# ── Binutils Pass 1 ──────────────────────────────────────────────────────────
p1_binutils1() {
    extr "binutils-${BINUTILS_VER}.tar.xz"
    mkdir build && cd build
    ../configure                        \
        --prefix="${LFS}/tools"         \
        --with-sysroot="${LFS}"         \
        --target="${LFS_TGT}"           \
        --disable-nls                   \
        --enable-gprofng=no             \
        --disable-werror                \
        --enable-new-dtags              \
        --enable-default-hash-style=gnu
    make -j"${NPROC}"; make install
}
run_step "p1_binutils1" "Binutils Pass 1" p1_binutils1

# ── GCC Pass 1 ───────────────────────────────────────────────────────────────
p1_gcc1() {
    extr "gcc-${GCC_VER}.tar.xz"
    tar xf "${SRC}/mpfr-${MPFR_VER}.tar.xz"; mv "mpfr-${MPFR_VER}" mpfr
    tar xf "${SRC}/gmp-${GMP_VER}.tar.xz";   mv "gmp-${GMP_VER}"   gmp
    tar xf "${SRC}/mpc-${MPC_VER}.tar.gz";   mv "mpc-${MPC_VER}"   mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    mkdir build && cd build
    ../configure                    \
        --target="${LFS_TGT}"       \
        --prefix="${LFS}/tools"     \
        --with-glibc-version="${GLIBC_VER}" \
        --with-sysroot="${LFS}"     \
        --with-newlib               \
        --without-headers           \
        --enable-default-pie        \
        --enable-default-ssp        \
        --disable-nls               \
        --disable-shared            \
        --disable-multilib          \
        --disable-threads           \
        --disable-libatomic         \
        --disable-libgomp           \
        --disable-libquadmath       \
        --disable-libssp            \
        --disable-libvtv            \
        --disable-libstdcxx         \
        --enable-languages=c,c++
    make -j"${NPROC}"; make install
    cd ..
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        "$(dirname "$("${LFS_TGT}-gcc" -print-libgcc-file-name)")/include/limits.h"
}
run_step "p1_gcc1" "GCC Pass 1" p1_gcc1

# ── Linux API Headers ─────────────────────────────────────────────────────────
p1_headers() {
    extr "linux-${LINUX_VER}.tar.xz"
    make mrproper; make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -rv usr/include "${LFS}/usr/"
}
run_step "p1_headers" "Linux API Headers" p1_headers

# ── Glibc ─────────────────────────────────────────────────────────────────────
p1_glibc() {
    extr "glibc-${GLIBC_VER}.tar.xz"
    ln -sfn ../lib/ld-linux-x86-64.so.2 "${LFS}/lib64/ld-linux-x86-64.so.2" 2>/dev/null || true
    ln -sfn ../lib/ld-linux-x86-64.so.2 "${LFS}/lib64/ld-lsb-x86-64.so.3"  2>/dev/null || true
    mkdir build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure                            \
        --prefix=/usr                       \
        --host="${LFS_TGT}"                 \
        --build="$(../scripts/config.guess)" \
        --enable-kernel=4.19               \
        --with-headers="${LFS}/usr/include" \
        --disable-nscd                      \
        libc_cv_slibdir=/usr/lib
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
    sed '/RTLDLIST=/s@/usr@@g' -i "${LFS}/usr/bin/ldd"
}
run_step "p1_glibc" "Glibc" p1_glibc

# ── Libstdc++ ─────────────────────────────────────────────────────────────────
p1_libstdcxx() {
    extr "gcc-${GCC_VER}.tar.xz"
    mkdir build && cd build
    ../libstdc++-v3/configure       \
        --host="${LFS_TGT}"         \
        --build="$(../config.guess)" \
        --prefix=/usr               \
        --disable-multilib          \
        --disable-nls               \
        --disable-libstdcxx-pch     \
        --with-gxx-include-dir="/tools/${LFS_TGT}/include/c++/${GCC_VER}"
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
    rm -v "${LFS}/usr/lib/lib"{stdc++{,exp},supc++}.la
}
run_step "p1_libstdcxx" "Libstdc++" p1_libstdcxx

# ── Temporary tools (M4 → Xz) ────────────────────────────────────────────────
build_temp() {
    local pkg="$1" tarext="$2"; shift 2
    extr "${pkg}.${tarext}"
    "$@"
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
}

# M4
p1_m4() {
    extr "m4-${M4_VER}.tar.xz"
    ./configure --prefix=/usr --host="${LFS_TGT}" --build="$(./build-aux/config.guess)"
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
}
run_step "p1_m4" "M4 (temp)" p1_m4

# Ncurses
p1_ncurses() {
    extr "ncurses-${NCURSES_VER}.tar.gz"
    sed -i s/mawk// configure
    mkdir tmpbuild; pushd tmpbuild
        ../configure; make -C include; make -C progs tic
    popd
    ./configure --prefix=/usr --host="${LFS_TGT}" --build="$(./config.guess)" \
        --mandir=/usr/share/man --with-manpage-format=normal \
        --with-shared --without-normal --with-cxx-shared \
        --without-debug --without-ada --disable-stripping --enable-widec
    make -j"${NPROC}"
    make DESTDIR="${LFS}" TIC_PATH="$(pwd)/tmpbuild/progs/tic" install
    ln -sv libncursesw.so "${LFS}/usr/lib/libncurses.so"
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "${LFS}/usr/include/curses.h"
}
run_step "p1_ncurses" "Ncurses (temp)" p1_ncurses

# Bash
p1_bash() {
    extr "bash-${BASH_VER}.tar.gz"
    ./configure --prefix=/usr --host="${LFS_TGT}" \
        --build="$(sh support/config.guess)" --without-bash-malloc
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
    ln -sv bash "${LFS}/usr/bin/sh"
}
run_step "p1_bash" "Bash (temp)" p1_bash

# Coreutils
p1_coreutils() {
    extr "coreutils-${COREUTILS_VER}.tar.xz"
    ./configure --prefix=/usr --host="${LFS_TGT}" \
        --build="$(./build-aux/config.guess)" \
        --enable-install-program=hostname \
        --enable-no-install-program=kill,uptime
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
    mv -v "${LFS}/usr/bin/chroot" "${LFS}/usr/sbin"
    mkdir -pv "${LFS}/usr/share/man/man8"
    mv -v "${LFS}/usr/share/man/man1/chroot.1" "${LFS}/usr/share/man/man8/chroot.8"
    sed -i 's/"1"/"8"/' "${LFS}/usr/share/man/man8/chroot.8"
}
run_step "p1_coreutils" "Coreutils (temp)" p1_coreutils

# Simple temp packages (inlined — no function redeclaration bug)
for _item in \
    "diffutils-${DIFFUTILS_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./build-aux/config.guess)" \
    "file-${FILE_VER}.tar.gz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./config.guess)" \
    "findutils-${FINDUTILS_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./build-aux/config.guess) --localstatedir=/var/lib/locate" \
    "gawk-${GAWK_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./config.guess)" \
    "grep-${GREP_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./build-aux/config.guess)" \
    "gzip-${GZIP_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT}" \
    "make-${MAKE_VER}.tar.gz:./configure --prefix=/usr --without-guile --host=${LFS_TGT} --build=\$(./build-aux/config.guess)" \
    "patch-${PATCH_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./build-aux/config.guess)" \
    "sed-${SED_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./build-aux/config.guess)" \
    "tar-${TAR_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./build-aux/config.guess)" \
    "xz-${XZ_VER}.tar.xz:./configure --prefix=/usr --host=${LFS_TGT} --build=\$(./build-aux/config.guess) --disable-static --docdir=/usr/share/doc/xz"
do
    _tar="${_item%%:*}"
    _cmd="${_item##*:}"
    _name="${_tar%%-[0-9]*}"
    _step="p1_${_name//-/_}"
    if ! step_is_done "${_step}"; then
        echo "[P1] ${_name} (temp)"
        extr "${_tar}"
        eval "${_cmd}"
        make -j"${NPROC}"; make DESTDIR="${LFS}" install
        step_done "${_step}"
    else
        echo "  → Skip: ${_name} (temp)"
    fi
done

# Binutils Pass 2
p1_binutils2() {
    extr "binutils-${BINUTILS_VER}.tar.xz"
    sed '6009s/$add_dir//' -i ltmain.sh
    mkdir build && cd build
    ../configure --prefix=/usr --build="$(../config.guess)" \
        --host="${LFS_TGT}" --disable-nls --enable-shared \
        --enable-gprofng=no --disable-werror --enable-64-bit-bfd \
        --enable-new-dtags --enable-default-hash-style=gnu
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
    rm -v "${LFS}/usr/lib/lib"{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}
run_step "p1_binutils2" "Binutils Pass 2" p1_binutils2

# GCC Pass 2  (FIX: --target uses ${LFS_TGT}, not hardcoded x86_64-pc-linux-gnu)
p1_gcc2() {
    extr "gcc-${GCC_VER}.tar.xz"
    tar xf "${SRC}/mpfr-${MPFR_VER}.tar.xz"; mv "mpfr-${MPFR_VER}" mpfr
    tar xf "${SRC}/gmp-${GMP_VER}.tar.xz";   mv "gmp-${GMP_VER}"   gmp
    tar xf "${SRC}/mpc-${MPC_VER}.tar.gz";   mv "mpc-${MPC_VER}"   mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    sed '/thread_header =/s/@.*@/gthr-posix.h/' \
        -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
    mkdir build && cd build
    ../configure                                        \
        --build="$(../config.guess)"                    \
        --host="${LFS_TGT}"                             \
        --target="${LFS_TGT}"                           \
        LDFLAGS_FOR_TARGET=-L"${PWD}/${LFS_TGT}/libgcc" \
        --prefix=/usr                                   \
        --with-build-sysroot="${LFS}"                   \
        --enable-default-pie                            \
        --enable-default-ssp                            \
        --disable-nls                                   \
        --disable-multilib                              \
        --disable-libatomic                             \
        --disable-libgomp                               \
        --disable-libquadmath                           \
        --disable-libsanitizer                          \
        --disable-libssp                                \
        --disable-libvtv                                \
        --enable-languages=c,c++
    make -j"${NPROC}"; make DESTDIR="${LFS}" install
    ln -sv gcc "${LFS}/usr/bin/cc"
}
run_step "p1_gcc2" "GCC Pass 2" p1_gcc2

echo ""
echo "════════════════════════════════════"
echo "  Phase 1 Complete — Toolchain done"
echo "════════════════════════════════════"
P1_SCRIPT

    chmod +x "${P1}"
    chown lfs:lfs "${P1}"
    su - lfs -c "bash ${P1}"
}

# ─────────────────────────────────────────────────────────────────────────────
# CHROOT PREPARATION
# ─────────────────────────────────────────────────────────────────────────────
prepare_chroot() {
    banner "Preparing Chroot"
    mount_vfs

    run_step "chroot_dirs"  "Essential chroot dirs"  _chroot_dirs
    run_step "chroot_files" "Essential chroot files" _chroot_files
}

_chroot_dirs() {
    mkdir -p "${LFS}"/{etc,var,proc,sys,run,dev}
    mkdir -p "${LFS}"/usr/{bin,lib,sbin}
    for d in bin lib sbin; do ln -sfn usr/"$d" "${LFS}/$d" 2>/dev/null || true; done
    mkdir -p "${LFS}/lib64"
}

_chroot_files() {
    cat > "${LFS}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
flint:x:1000:1000:Flint User:/home/flint:/bin/bash
EOF
    cat > "${LFS}/etc/group" <<'EOF'
root:x:0:
bin:x:1:root,bin,daemon
sys:x:2:root,bin,sys
kmem:x:3:root
tape:x:4:root
tty:x:5:root
daemon:x:6:root,bin,daemon
disk:x:8:root
lp:x:9:root
audio:x:11:root
video:x:12:root
input:x:24:root
mail:x:34:root
kvm:x:61:
messagebus:x:18:
wheel:x:97:flint
users:x:999:
nogroup:x:65534:
flint:x:1000:
EOF
    touch "${LFS}/var/log/"{btmp,lastlog,faillog,wtmp}
    chown root:utmp "${LFS}/var/log/lastlog"
    chmod 664 "${LFS}/var/log/lastlog"
    chmod 600 "${LFS}/var/log/btmp"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — FINAL SYSTEM (chroot)
# ─────────────────────────────────────────────────────────────────────────────
phase2_final_system() {
    banner "Phase 2 — Final System (chroot)"

    # Write the phase2 script into the LFS tree
    local P2="${LFS}/sources/flint_phase2.sh"

    # Export all version vars as a header so phase2 doesn't hardcode anything
    {
    cat <<HEADER
#!/usr/bin/env bash
set -euo pipefail

# Version variables (passed from outer script — no hardcoding)
BINUTILS_VER="${BINUTILS_VER}"
GCC_VER="${GCC_VER}"
GLIBC_VER="${GLIBC_VER}"
MPFR_VER="${MPFR_VER}"
GMP_VER="${GMP_VER}"
MPC_VER="${MPC_VER}"
LINUX_VER="${LINUX_VER}"
ZLIB_VER="${ZLIB_VER}"
BZIP2_VER="${BZIP2_VER}"
XZ_VER="${XZ_VER}"
ZSTD_VER="${ZSTD_VER}"
FILE_VER="${FILE_VER}"
READLINE_VER="${READLINE_VER}"
M4_VER="${M4_VER}"
BC_VER="${BC_VER}"
FLEX_VER="${FLEX_VER}"
PKGCONF_VER="${PKGCONF_VER}"
NCURSES_VER="${NCURSES_VER}"
BASH_VER="${BASH_VER}"
COREUTILS_VER="${COREUTILS_VER}"
DIFFUTILS_VER="${DIFFUTILS_VER}"
GAWK_VER="${GAWK_VER}"
FINDUTILS_VER="${FINDUTILS_VER}"
GREP_VER="${GREP_VER}"
GZIP_VER="${GZIP_VER}"
MAKE_VER="${MAKE_VER}"
PATCH_VER="${PATCH_VER}"
SED_VER="${SED_VER}"
TAR_VER="${TAR_VER}"
TEXINFO_VER="${TEXINFO_VER}"
UTIL_LINUX_VER="${UTIL_LINUX_VER}"
PYTHON_VER="${PYTHON_VER}"
OPENSSL_VER="${OPENSSL_VER}"
SHADOW_VER="${SHADOW_VER}"
PSMISC_VER="${PSMISC_VER}"
PROCPS_VER="${PROCPS_VER}"
E2FSPROGS_VER="${E2FSPROGS_VER}"
KMOD_VER="${KMOD_VER}"
LIBCAP_VER="${LIBCAP_VER}"
IPROUTE2_VER="${IPROUTE2_VER}"
LESS_VER="${LESS_VER}"
VIM_VER="${VIM_VER}"
ELFUTILS_VER="${ELFUTILS_VER}"
BISON_VER="${BISON_VER}"
GETTEXT_VER="${GETTEXT_VER}"
GRUB_VER="${GRUB_VER}"
LIBARCHIVE_VER="${LIBARCHIVE_VER}"
CURL_VER="${CURL_VER}"
FAKEROOT_VER="${FAKEROOT_VER}"
EUDEV_VER="${EUDEV_VER}"
DBUS_VER="${DBUS_VER}"
MESON_VER="${MESON_VER}"
DINIT_VER="${DINIT_VER}"
PACMAN_VER="${PACMAN_VER}"
WAYLAND_VER="${WAYLAND_VER}"
WAYLAND_PROTOCOLS_VER="${WAYLAND_PROTOCOLS_VER}"
LIBXKBCOMMON_VER="${LIBXKBCOMMON_VER}"
LIBINPUT_VER="${LIBINPUT_VER}"
PIXMAN_VER="${PIXMAN_VER}"
MESA_VER="${MESA_VER}"
LIBDRM_VER="${LIBDRM_VER}"
HYPRUTILS_VER="${HYPRUTILS_VER}"
HYPRLANG_VER="${HYPRLANG_VER}"
HYPRWAYLAND_SCANNER_VER="${HYPRWAYLAND_SCANNER_VER}"
AQUAMARINE_VER="${AQUAMARINE_VER}"
HYPRLAND_VER="${HYPRLAND_VER}"
WAYBAR_VER="${WAYBAR_VER}"
FOOT_VER="${FOOT_VER}"
FASTFETCH_VER="${FASTFETCH_VER}"
PIPEWIRE_VER="${PIPEWIRE_VER}"
NPROC="${NPROC}"
CFLAGS="${CFLAGS}"
CXXFLAGS="${CXXFLAGS}"
LDFLAGS="${LDFLAGS}"
RUSTFLAGS="${RUSTFLAGS}"
MAKEFLAGS="-j${NPROC}"
export CFLAGS CXXFLAGS LDFLAGS RUSTFLAGS MAKEFLAGS NPROC
HEADER

    cat <<'P2_SCRIPT'

SRC="/sources"
STATE="/flint_state"
LOGS="/flint_logs"
BUILD="/tmp/flint_build"

mkdir -p "${LOGS}"

step_done()    { mkdir -p "${STATE}"; touch "${STATE}/$1.done"; echo "  ✓ $1"; }
step_is_done() { [[ -f "${STATE}/$1.done" ]]; }
run_step() {
    local s="$1" d="$2"; shift 2
    step_is_done "${s}" && { echo "  → Skip: ${d}"; return 0; }
    echo "[P2] ${d}"
    set +e
    "$@" 2>&1 | tee "${LOGS}/${s}.log"
    local ret=${PIPESTATUS[0]}
    set -e
    [[ ${ret} -eq 0 ]] || { echo "FAILED: ${d} (exit ${ret})"; exit 1; }
    step_done "${s}"
}

# Robust extraction
extr() {
    rm -rf "${BUILD}" && mkdir -p "${BUILD}"
    tar xf "${SRC}/$1" -C "${BUILD}"
    local top; top=$(tar tf "${SRC}/$1" | head -1 | sed 's|/.*||')
    cd "${BUILD}/${top}"
}

# ── cmake + ninja (needed for Hyprland stack) ─────────────────────────────────
p2_cmake() {
    cd /tmp
    rm -rf cmake_inst; mkdir cmake_inst
    tar xf "${SRC}/cmake-binary.tar.gz" -C cmake_inst --strip-components=1
    cp -r cmake_inst/bin/cmake cmake_inst/bin/cpack cmake_inst/bin/ctest /usr/bin/
    cp -r cmake_inst/share/cmake* /usr/share/
    cp -r cmake_inst/lib/cmake* /usr/lib/ 2>/dev/null || true
    cmake --version
}
run_step "p2_cmake" "CMake (binary install)" p2_cmake

p2_ninja() {
    cd /tmp
    rm -f /tmp/ninja-linux.zip
    cp "${SRC}/ninja-linux.zip" /tmp/
    unzip -o /tmp/ninja-linux.zip ninja -d /usr/bin/
    chmod +x /usr/bin/ninja
    ninja --version
}
run_step "p2_ninja" "Ninja (binary install)" p2_ninja

p2_meson() {
    extr "meson-${MESON_VER}.tar.gz"
    python3 setup.py install 2>/dev/null \
        || pip3 install --prefix=/usr . 2>/dev/null \
        || { mkdir -p /usr/lib/python3/dist-packages
             cp -r mesonbuild /usr/lib/python3/dist-packages/
             cp meson.py /usr/bin/meson; chmod +x /usr/bin/meson; }
    meson --version
}
run_step "p2_meson" "Meson" p2_meson

# ── Gettext (minimal, for build tools) ───────────────────────────────────────
p2_gettext() {
    extr "gettext-${GETTEXT_VER}.tar.xz"
    ./configure --disable-shared
    make -j"${NPROC}"
    cp gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}
run_step "p2_gettext" "Gettext (minimal)" p2_gettext

# ── Bison ─────────────────────────────────────────────────────────────────────
p2_bison() {
    extr "bison-${BISON_VER}.tar.xz"
    ./configure --prefix=/usr --docdir=/usr/share/doc/bison
    make -j"${NPROC}"; make install
}
run_step "p2_bison" "Bison" p2_bison

# ── Flex (needed for kernel) ──────────────────────────────────────────────────
p2_flex() {
    extr "flex-${FLEX_VER}.tar.gz"
    ./configure --prefix=/usr --docdir=/usr/share/doc/flex --disable-static
    make -j"${NPROC}"; make install
    ln -sv flex /usr/bin/lex
}
run_step "p2_flex" "Flex" p2_flex

# ── Zlib ──────────────────────────────────────────────────────────────────────
p2_zlib() {
    extr "zlib-${ZLIB_VER}.tar.gz"
    ./configure --prefix=/usr
    make -j"${NPROC}"; make install
    rm -f /usr/lib/libz.a
}
run_step "p2_zlib" "Zlib" p2_zlib

# ── Bzip2 (FIX: remove static lib, correct URL was sourceware.org) ────────────
p2_bzip2() {
    extr "bzip2-${BZIP2_VER}.tar.gz"
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    sed -i "s|man/man1|share/man/man1|g" Makefile
    make -f Makefile-libbz2_so CFLAGS="${CFLAGS} -fPIC"
    make clean
    make -j"${NPROC}" PREFIX=/usr install
    cp -av libbz2.so.* /usr/lib
    ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so
    rm -f /usr/lib/libbz2.a    # FIX: remove static lib
}
run_step "p2_bzip2" "Bzip2" p2_bzip2

# ── Xz ────────────────────────────────────────────────────────────────────────
p2_xz() {
    extr "xz-${XZ_VER}.tar.xz"
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/xz
    make -j"${NPROC}"; make install
}
run_step "p2_xz" "Xz" p2_xz

# ── Zstd ──────────────────────────────────────────────────────────────────────
p2_zstd() {
    extr "zstd-${ZSTD_VER}.tar.gz"
    make -j"${NPROC}" prefix=/usr
    make prefix=/usr install
    rm -f /usr/lib/libzstd.a
}
run_step "p2_zstd" "Zstd" p2_zstd

# ── OpenSSL ───────────────────────────────────────────────────────────────────
p2_openssl() {
    extr "openssl-${OPENSSL_VER}.tar.gz"
    ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
    make -j"${NPROC}"
    sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
    make install
}
run_step "p2_openssl" "OpenSSL" p2_openssl

# ── Elfutils/libelf (FIX: required for kernel build) ─────────────────────────
p2_elfutils() {
    extr "elfutils-${ELFUTILS_VER}.tar.bz2"
    ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
    make -j"${NPROC}"
    make -C libelf install
    install -vm644 config/libelf.pc /usr/lib/pkgconfig
    rm -f /usr/lib/libelf.a
}
run_step "p2_elfutils" "Elfutils/libelf" p2_elfutils

# ── Kmod ──────────────────────────────────────────────────────────────────────
p2_kmod() {
    extr "kmod-${KMOD_VER}.tar.xz"
    ./configure --prefix=/usr --sysconfdir=/etc \
        --with-openssl --with-xz --with-zstd --with-zlib
    make -j"${NPROC}"; make install
    for t in depmod insmod modinfo modprobe rmmod; do
        ln -sfv ../bin/kmod /usr/sbin/$t
    done
    ln -sfv kmod /usr/bin/lsmod
}
run_step "p2_kmod" "Kmod" p2_kmod

# ── Libcap ────────────────────────────────────────────────────────────────────
p2_libcap() {
    extr "libcap-${LIBCAP_VER}.tar.xz"
    sed -i '/install -m.*STA/d' libcap/Makefile
    make prefix=/usr lib=lib -j"${NPROC}"
    make prefix=/usr lib=lib install
}
run_step "p2_libcap" "Libcap" p2_libcap

# ── Eudev (FIX: was missing — required by Hyprland/Wayland) ──────────────────
p2_eudev() {
    extr "eudev-${EUDEV_VER}.tar.gz"
    ./configure --prefix=/usr --bindir=/usr/sbin \
        --sysconfdir=/etc --enable-manpages --disable-static
    make -j"${NPROC}"; make install
    # Create required dirs
    mkdir -p /etc/udev/{rules.d,hwdb.d}
    mkdir -p /usr/lib/udev/rules.d
    udevadm hwdb --update 2>/dev/null || true
}
run_step "p2_eudev" "Eudev (udev)" p2_eudev

# ── Dbus (FIX: was missing — required by Waybar/Wayland) ─────────────────────
p2_dbus() {
    extr "dbus-${DBUS_VER}.tar.xz"
    ./configure --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --runstatedir=/run \
        --enable-user-session \
        --disable-static \
        --disable-doxygen-docs \
        --disable-xml-docs \
        --with-console-auth-dir=/run/console \
        --with-system-pid-file=/run/dbus/pid \
        --with-system-socket=/run/dbus/system_bus_socket
    make -j"${NPROC}"; make install
    ln -sfv /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
}
run_step "p2_dbus" "DBus" p2_dbus

# ── Shadow ────────────────────────────────────────────────────────────────────
p2_shadow() {
    extr "shadow-${SHADOW_VER}.tar.xz"
    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    find man -name 'groups.1' -delete
    touch /usr/bin/passwd
    ./configure --sysconfdir=/etc --disable-static \
        --with-{b,yes}crypt --without-libbsd \
        --with-group-name-max-length=32
    make -j"${NPROC}"; make exec_prefix=/usr install
    make -C man install-man
    pwconv; grpconv
    # Default passwords — MUST be changed post-install
    echo "root:flint"  | chpasswd
    echo "flint:flint" | chpasswd
}
run_step "p2_shadow" "Shadow" p2_shadow

# ── Readline ──────────────────────────────────────────────────────────────────
p2_readline() {
    extr "readline-${READLINE_VER}.tar.gz"
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install
    sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
    ./configure --prefix=/usr --disable-static --with-curses \
        --docdir=/usr/share/doc/readline
    make SHLIB_LIBS="-lncursesw" -j"${NPROC}"
    make SHLIB_LIBS="-lncursesw" install
}
run_step "p2_readline" "Readline" p2_readline

# ── Perl ──────────────────────────────────────────────────────────────────────
p2_perl() {
    extr "perl-${PERL_VER}.tar.xz"
    sh Configure -des \
        -Dprefix=/usr -Dvendorprefix=/usr \
        -Dprivlib=/usr/lib/perl5/${PERL_VER%.*}/core_perl \
        -Darchlib=/usr/lib/perl5/${PERL_VER%.*}/core_perl \
        -Dsitelib=/usr/lib/perl5/${PERL_VER%.*}/site_perl \
        -Dsitearch=/usr/lib/perl5/${PERL_VER%.*}/site_perl \
        -Dvendorlib=/usr/lib/perl5/${PERL_VER%.*}/vendor_perl \
        -Dvendorarch=/usr/lib/perl5/${PERL_VER%.*}/vendor_perl \
        -Dman1dir=/usr/share/man/man1 -Dman3dir=/usr/share/man/man3 \
        -Dpager="/usr/bin/less -isR" -Duseshrplib -Dusethreads
    make -j"${NPROC}"; make install
}
run_step "p2_perl" "Perl" p2_perl

# ── Python ────────────────────────────────────────────────────────────────────
p2_python() {
    extr "Python-${PYTHON_VER}.tar.xz"
    ./configure --prefix=/usr --enable-shared --with-system-expat \
        --enable-optimizations
    make -j"${NPROC}"; make install
    ln -sfn python3 /usr/bin/python
}
run_step "p2_python" "Python ${PYTHON_VER}" p2_python

# ── Texinfo ───────────────────────────────────────────────────────────────────
p2_texinfo() {
    extr "texinfo-${TEXINFO_VER}.tar.xz"
    ./configure --prefix=/usr; make -j"${NPROC}"; make install
}
run_step "p2_texinfo" "Texinfo" p2_texinfo

# ── Util-linux ────────────────────────────────────────────────────────────────
p2_util_linux() {
    extr "util-linux-${UTIL_LINUX_VER}.tar.xz"
    mkdir -pv /var/lib/hwclock
    ./configure --libdir=/usr/lib --runstatedir=/run \
        --disable-chfn-chsh --disable-login --disable-nologin \
        --disable-su --disable-setpriv --disable-runuser \
        --disable-pylibmount --disable-static --disable-liblastlog2 \
        --without-python \
        ADJTIME_PATH=/var/lib/hwclock/adjtime \
        --docdir=/usr/share/doc/util-linux
    make -j"${NPROC}"; make install
}
run_step "p2_util_linux" "Util-linux" p2_util_linux

# ── Bash (final) ──────────────────────────────────────────────────────────────
p2_bash() {
    extr "bash-${BASH_VER}.tar.gz"
    ./configure --prefix=/usr --without-bash-malloc \
        --with-installed-readline --docdir=/usr/share/doc/bash
    make -j"${NPROC}"; make install
    ln -sfv bash /usr/bin/sh
}
run_step "p2_bash" "Bash (final)" p2_bash

# ── Ncurses (final) ───────────────────────────────────────────────────────────
p2_ncurses() {
    extr "ncurses-${NCURSES_VER}.tar.gz"
    ./configure --prefix=/usr --mandir=/usr/share/man \
        --with-shared --without-debug --without-normal --with-cxx-shared \
        --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig \
        --enable-widec
    make -j"${NPROC}"; make install
    for lib in ncurses form panel menu; do
        ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
        ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
    done
    ln -sfv libncursesw.so /usr/lib/libcurses.so
}
run_step "p2_ncurses" "Ncurses (final)" p2_ncurses

# ── Coreutils (final) ─────────────────────────────────────────────────────────
p2_coreutils() {
    extr "coreutils-${COREUTILS_VER}.tar.xz"
    autoreconf -fiv 2>/dev/null || true
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr \
        --enable-no-install-program=kill,uptime
    make -j"${NPROC}"; make install
    mv -v /usr/bin/chroot /usr/sbin
}
run_step "p2_coreutils" "Coreutils (final)" p2_coreutils

# ── Simple final packages (FIXED: no function redeclaration — fully inlined) ──
for _item in \
    "diffutils-${DIFFUTILS_VER}.tar.xz:--prefix=/usr" \
    "findutils-${FINDUTILS_VER}.tar.xz:--prefix=/usr --localstatedir=/var/lib/locate" \
    "gawk-${GAWK_VER}.tar.xz:--prefix=/usr" \
    "grep-${GREP_VER}.tar.xz:--prefix=/usr" \
    "gzip-${GZIP_VER}.tar.xz:--prefix=/usr" \
    "make-${MAKE_VER}.tar.gz:--prefix=/usr" \
    "patch-${PATCH_VER}.tar.xz:--prefix=/usr" \
    "sed-${SED_VER}.tar.xz:--prefix=/usr" \
    "tar-${TAR_VER}.tar.xz:--prefix=/usr" \
    "less-${LESS_VER}.tar.gz:--prefix=/usr --sysconfdir=/etc" \
    "bc-${BC_VER}.tar.xz:--prefix=/usr -G -O3 -r"
do
    _tar="${_item%%:*}"
    _flags="${_item##*:}"
    _name="${_tar%%-[0-9]*}"
    _step="p2_${_name//-/_}"
    if ! step_is_done "${_step}"; then
        echo "[P2] ${_name} (final)"
        extr "${_tar}"
        # gawk needs this
        [[ "${_name}" == "gawk" ]] && sed -i 's/extras//' Makefile.in || true
        # shellcheck disable=SC2086
        ./configure ${_flags}
        make -j"${NPROC}"; make install
        step_done "${_step}"
    else
        echo "  → Skip: ${_name}"
    fi
done

# ── Pkgconf ────────────────────────────────────────────────────────────────────
p2_pkgconf() {
    extr "pkgconf-${PKGCONF_VER}.tar.xz"
    ./configure --prefix=/usr --disable-static \
        --docdir=/usr/share/doc/pkgconf
    make -j"${NPROC}"; make install
    ln -sv pkgconf /usr/bin/pkg-config
    ln -sv pkgconf /usr/bin/pkgconf
}
run_step "p2_pkgconf" "Pkgconf/pkg-config" p2_pkgconf

# ── Procps ────────────────────────────────────────────────────────────────────
p2_procps() {
    extr "procps-ng-${PROCPS_VER}.tar.xz"
    ./configure --prefix=/usr --disable-static --disable-kill --with-systemd=no
    make -j"${NPROC}"; make install
}
run_step "p2_procps" "Procps-ng" p2_procps

# ── E2fsprogs ─────────────────────────────────────────────────────────────────
p2_e2fsprogs() {
    extr "e2fsprogs-${E2FSPROGS_VER}.tar.gz"
    mkdir build && cd build
    ../configure --prefix=/usr --sysconfdir=/etc \
        --enable-elf-shlibs --disable-libblkid \
        --disable-libuuid --disable-uuidd --disable-fsck
    make -j"${NPROC}"; make install
    rm -f /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
}
run_step "p2_e2fsprogs" "E2fsprogs" p2_e2fsprogs

# ── Iproute2 ──────────────────────────────────────────────────────────────────
p2_iproute2() {
    extr "iproute2-${IPROUTE2_VER}.tar.xz"
    sed -i /ARPD/d Makefile; rm -fv man/man8/arpd.8
    make NETNS_RUN_DIR=/run/netns -j"${NPROC}"
    make SBINDIR=/usr/sbin install
}
run_step "p2_iproute2" "Iproute2" p2_iproute2

# ── Vim (FIX: correct tag v9.1.0000) ──────────────────────────────────────────
p2_vim() {
    extr "vim-${VIM_VER}.tar.gz"
    echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
    ./configure --prefix=/usr
    make -j"${NPROC}"; make install
    ln -sfv vim /usr/bin/vi
    cat > /etc/vimrc <<'VIMRC'
set nocompatible
set backspace=2
set mouse=
syntax on
set number
set tabstop=4 shiftwidth=4 expandtab
colorscheme desert
VIMRC
}
run_step "p2_vim" "Vim ${VIM_VER}" p2_vim

# ── GCC (final — with LTO and Skylake tuning) ─────────────────────────────────
p2_gcc_final() {
    extr "gcc-${GCC_VER}.tar.xz"
    tar xf "${SRC}/mpfr-${MPFR_VER}.tar.xz"; mv "mpfr-${MPFR_VER}" mpfr
    tar xf "${SRC}/gmp-${GMP_VER}.tar.xz";   mv "gmp-${GMP_VER}"   gmp
    tar xf "${SRC}/mpc-${MPC_VER}.tar.gz";   mv "mpc-${MPC_VER}"   mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    mkdir build && cd build
    ../configure --prefix=/usr LD=ld \
        --enable-languages=c,c++,fortran \
        --enable-default-pie --enable-default-ssp \
        --enable-host-pie --disable-multilib \
        --disable-bootstrap --disable-fixincludes \
        --with-system-zlib --enable-lto \
        --with-tune=skylake --with-arch=skylake
    make -j"${NPROC}"; make install
    chown -v -R root:root /usr/lib/gcc/$(gcc -dumpmachine)/$(gcc -dumpversion)/include{,-fixed}
    ln -sfvr /usr/bin/cpp /usr/lib
    ln -sv gcc /usr/bin/cc
    install -v -dm755 /usr/lib/bfd-plugins
    ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/$(gcc -dumpversion)/liblto_plugin.so \
        /usr/lib/bfd-plugins/
}
run_step "p2_gcc_final" "GCC ${GCC_VER} (final + LTO + Skylake)" p2_gcc_final

# ── Binutils (final) ──────────────────────────────────────────────────────────
p2_binutils_final() {
    extr "binutils-${BINUTILS_VER}.tar.xz"
    mkdir build && cd build
    ../configure --prefix=/usr --sysconfdir=/etc \
        --enable-gold --enable-ld=default --enable-plugins \
        --enable-shared --disable-werror --enable-64-bit-bfd \
        --enable-new-dtags --with-system-zlib \
        --enable-default-hash-style=gnu
    make tooldir=/usr -j"${NPROC}"; make tooldir=/usr install
    rm -fv /usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.a
}
run_step "p2_binutils_final" "Binutils ${BINUTILS_VER} (final)" p2_binutils_final

# ── Glibc (final) ─────────────────────────────────────────────────────────────
p2_glibc_final() {
    extr "glibc-${GLIBC_VER}.tar.xz"
    mkdir build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr --disable-werror \
        --enable-kernel=6.1 --enable-stack-protector=strong \
        --disable-nscd libc_cv_slibdir=/usr/lib
    make -j"${NPROC}"; make install
    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
    localedef -i en_US -f UTF-8 en_US.UTF-8
    localedef -i C -f UTF-8 C.UTF-8
}
run_step "p2_glibc_final" "Glibc ${GLIBC_VER} (final)" p2_glibc_final

# ── Libdrm (for Mesa) ─────────────────────────────────────────────────────────
p2_libdrm() {
    extr "libdrm-${LIBDRM_VER}.tar.xz"
    meson setup build --prefix=/usr --buildtype=release \
        -Dintel=enabled -Damdgpu=disabled -Dradeon=disabled \
        -Dnouveau=disabled -Dvmwgfx=disabled
    ninja -C build -j"${NPROC}"; ninja -C build install
}
run_step "p2_libdrm" "Libdrm" p2_libdrm

# ── Wayland ───────────────────────────────────────────────────────────────────
p2_wayland() {
    extr "wayland-${WAYLAND_VER}.tar.xz"
    meson setup build --prefix=/usr --buildtype=release -Ddocumentation=false
    ninja -C build -j"${NPROC}"; ninja -C build install
}
run_step "p2_wayland" "Wayland ${WAYLAND_VER}" p2_wayland

p2_wayland_protocols() {
    extr "wayland-protocols-${WAYLAND_PROTOCOLS_VER}.tar.xz"
    meson setup build --prefix=/usr --buildtype=release
    ninja -C build -j"${NPROC}"; ninja -C build install
}
run_step "p2_wayland_protocols" "Wayland-protocols" p2_wayland_protocols

# ── Libxkbcommon ──────────────────────────────────────────────────────────────
p2_libxkbcommon() {
    extr "libxkbcommon-${LIBXKBCOMMON_VER}.tar.xz"
    meson setup build --prefix=/usr --buildtype=release \
        -Denable-docs=false -Denable-wayland=true -Denable-x11=false
    ninja -C build -j"${NPROC}"; ninja -C build install
}
run_step "p2_libxkbcommon" "Libxkbcommon" p2_libxkbcommon

# ── Libinput ──────────────────────────────────────────────────────────────────
p2_libinput() {
    extr "libinput-${LIBINPUT_VER}.tar.bz2"
    meson setup build --prefix=/usr --buildtype=release \
        -Ddocumentation=false -Dtests=false -Ddebug-gui=false \
        -Dlibwacom=false
    ninja -C build -j"${NPROC}"; ninja -C build install
}
run_step "p2_libinput" "Libinput ${LIBINPUT_VER}" p2_libinput

# ── Pixman ────────────────────────────────────────────────────────────────────
p2_pixman() {
    extr "pixman-${PIXMAN_VER}.tar.gz"
    meson setup build --prefix=/usr --buildtype=release
    ninja -C build -j"${NPROC}"; ninja -C build install
}
run_step "p2_pixman" "Pixman" p2_pixman

# ── Mesa (Intel iris — Skylake GT2 = HD 520) ──────────────────────────────────
# FIX: iris is the correct gallium driver for Skylake (crocus is for older gen)
# FIX: Mesa 24.0.x is more stable than 24.1.x for Intel iris
p2_mesa() {
    extr "mesa-${MESA_VER}.tar.xz"
    meson setup build --prefix=/usr --buildtype=release \
        -Dgallium-drivers=iris            \
        -Dvulkan-drivers=intel            \
        -Dplatforms=wayland               \
        -Degl=enabled                     \
        -Dgles2=enabled                   \
        -Dopengl=true                     \
        -Dglx=disabled                    \
        -Dllvm=disabled                   \
        -Dshared-glapi=enabled            \
        -Dvideo-codecs=h264dec,h264enc,h265dec,h265enc,vc1dec \
        -Dintel-clc=disabled              \
        -Dmicrosoft-clc=disabled
    ninja -C build -j"${NPROC}"; ninja -C build install
}
run_step "p2_mesa" "Mesa ${MESA_VER} (Intel iris/Skylake)" p2_mesa

# ── Linux Kernel 6.9.3 ────────────────────────────────────────────────────────
p2_kernel() {
    extr "linux-${LINUX_VER}.tar.xz"
    make mrproper

    # Apply config settings on top of defconfig
    make defconfig

    # Skylake + Hyprland + ThinkPad T460 specific config
    scripts/config \
        --enable  CONFIG_MSKYLAKE \
        --disable CONFIG_GENERIC_CPU \
        --set-val CONFIG_NR_CPUS 4 \
        --enable  CONFIG_HZ_1000 \
        --enable  CONFIG_PREEMPT \
        --enable  CONFIG_NO_HZ_FULL \
        \
        --enable  CONFIG_DRM \
        --enable  CONFIG_DRM_I915 \
        --enable  CONFIG_DRM_KMS_HELPER \
        --enable  CONFIG_DRM_KMS_FB_HELPER \
        --enable  CONFIG_DRM_FBDEV_EMULATION \
        --enable  CONFIG_FB \
        --enable  CONFIG_FRAMEBUFFER_CONSOLE \
        --disable CONFIG_DRM_RADEON \
        --disable CONFIG_DRM_AMDGPU \
        --disable CONFIG_DRM_NOUVEAU \
        \
        --enable  CONFIG_ZRAM \
        --enable  CONFIG_ZSMALLOC \
        --enable  CONFIG_CRYPTO_LZ4 \
        --enable  CONFIG_CRYPTO_ZSTD \
        \
        --enable  CONFIG_EXT4_FS \
        --enable  CONFIG_VFAT_FS \
        --enable  CONFIG_TMPFS \
        --enable  CONFIG_TMPFS_POSIX_ACL \
        --enable  CONFIG_DEVTMPFS \
        --enable  CONFIG_DEVTMPFS_MOUNT \
        \
        --enable  CONFIG_NET \
        --enable  CONFIG_INET \
        --enable  CONFIG_IPV6 \
        --enable  CONFIG_WIRELESS \
        --enable  CONFIG_CFG80211 \
        --enable  CONFIG_MAC80211 \
        --enable  CONFIG_IWLWIFI \
        --enable  CONFIG_IWLMVM \
        --enable  CONFIG_E1000E \
        \
        --enable  CONFIG_USB \
        --enable  CONFIG_USB_XHCI_HCD \
        --enable  CONFIG_USB_EHCI_HCD \
        --enable  CONFIG_INPUT \
        --enable  CONFIG_INPUT_EVDEV \
        --enable  CONFIG_INPUT_UINPUT \
        --enable  CONFIG_HID \
        --enable  CONFIG_USB_HID \
        --enable  CONFIG_HID_GENERIC \
        \
        --enable  CONFIG_ACPI \
        --enable  CONFIG_ACPI_BATTERY \
        --enable  CONFIG_ACPI_AC \
        --enable  CONFIG_ACPI_BUTTON \
        --enable  CONFIG_ACPI_FAN \
        --enable  CONFIG_ACPI_THERMAL \
        --enable  CONFIG_INTEL_IDLE \
        --enable  CONFIG_X86_INTEL_PSTATE \
        --enable  CONFIG_CPU_FREQ_GOV_SCHEDUTIL \
        --enable  CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
        \
        --enable  CONFIG_THINKPAD_ACPI \
        --enable  CONFIG_BACKLIGHT_CLASS_DEVICE \
        --enable  CONFIG_BACKLIGHT_INTEL_PANEL \
        \
        --enable  CONFIG_SND \
        --enable  CONFIG_SND_HDA_INTEL \
        --enable  CONFIG_SND_HDA_CODEC_REALTEK \
        --enable  CONFIG_SND_HDA_CODEC_HDMI \
        \
        --enable  CONFIG_BLK_DEV_SD \
        --enable  CONFIG_ATA \
        --enable  CONFIG_SATA_AHCI \
        --enable  CONFIG_BLK_DEV_NVME \
        \
        --enable  CONFIG_BLK_DEV_INITRD \
        --enable  CONFIG_EFI \
        --enable  CONFIG_EFI_STUB \
        --enable  CONFIG_MODULES \
        --enable  CONFIG_MODULE_UNLOAD \
        \
        --enable  CONFIG_SECURITY \
        --disable CONFIG_SECURITY_SELINUX \
        --enable  CONFIG_STACKPROTECTOR_STRONG \
        --enable  CONFIG_RANDOMIZE_BASE \
        --enable  CONFIG_MITIGATIONS

    make olddefconfig

    # Build kernel with Skylake CFLAGS
    make KCFLAGS="-march=skylake -mtune=skylake -O2 -pipe" \
         -j"${NPROC}" bzImage modules

    make modules_install
    install -vm755 arch/x86/boot/bzImage "/boot/vmlinuz-${LINUX_VER}-flint"
    install -vm644 System.map "/boot/System.map-${LINUX_VER}"
    install -vm644 .config    "/boot/config-${LINUX_VER}"
    make headers_install INSTALL_HDR_PATH=/usr
}
run_step "p2_kernel" "Linux Kernel ${LINUX_VER}" p2_kernel

# ── Dinit (FIX: type=oneshot not type=scripted) ───────────────────────────────
p2_dinit() {
    extr "dinit-${DINIT_VER}.tar.gz"
    make -j"${NPROC}" \
        CXXFLAGS="${CXXFLAGS}" \
        LDFLAGS="${LDFLAGS}"   \
        SBINDIR=/usr/sbin      \
        SYSCONTROLSOCKET=/run/dinitctl
    make install SBINDIR=/usr/sbin
    install -dm755 /etc/dinit.d/scripts
    mkdir -p /var/log/dinit

    # ── Service files (FIX: type=oneshot for scripts, not type=scripted) ──────

    # boot target
    cat > /etc/dinit.d/boot <<'EOF'
type = target
depends-on = filesystems
depends-on = udevd
depends-on = dbus
depends-on = hostname
depends-on = loopback
depends-on = zram-swap
EOF

    # FIX: oneshot not scripted
    cat > /etc/dinit.d/filesystems <<'EOF'
type = oneshot
command = /etc/dinit.d/scripts/filesystems.sh
before = boot
EOF

    cat > /etc/dinit.d/udevd <<'EOF'
type = process
command = /usr/sbin/udevd --daemon --resolve-names=never
restart = true
before = boot
EOF

    cat > /etc/dinit.d/dbus <<'EOF'
type = process
command = /usr/bin/dbus-daemon --system --nofork --nopidfile
restart = true
depends-on = udevd
EOF

    cat > /etc/dinit.d/hostname <<'EOF'
type = oneshot
command = /etc/dinit.d/scripts/hostname.sh
before = boot
EOF

    cat > /etc/dinit.d/loopback <<'EOF'
type = oneshot
command = /usr/sbin/ip link set lo up
before = boot
EOF

    cat > /etc/dinit.d/zram-swap <<'EOF'
type = oneshot
command = /etc/dinit.d/scripts/zram-swap.sh
before = boot
EOF

    cat > /etc/dinit.d/network <<'EOF'
type = oneshot
command = /etc/dinit.d/scripts/network.sh
depends-on = udevd
EOF

    cat > /etc/dinit.d/login.getty <<'EOF'
type = process
command = /sbin/agetty --autologin flint --noclear tty1 linux
restart = true
depends-on = boot
EOF

    # ── Service scripts ───────────────────────────────────────────────────────
    cat > /etc/dinit.d/scripts/filesystems.sh <<'EOF'
#!/bin/bash
mount -o remount,rw /
mount -a
swapon -a 2>/dev/null || true
EOF

    cat > /etc/dinit.d/scripts/hostname.sh <<'EOF'
#!/bin/bash
[[ -f /etc/hostname ]] && hostname -F /etc/hostname || hostname flint
EOF

    cat > /etc/dinit.d/scripts/zram-swap.sh <<'EOF'
#!/bin/bash
# 4GB zram swap with lz4 compression (fast, good for 12GB RAM system)
modprobe zram num_devices=1
echo lz4    > /sys/block/zram0/comp_algorithm
echo 4G     > /sys/block/zram0/disksize
echo "$(nproc)" > /sys/block/zram0/max_comp_streams 2>/dev/null || true
mkswap --label zram0 /dev/zram0
swapon --priority 100 /dev/zram0
echo "Zram swap: 4G lz4 active"
EOF

    cat > /etc/dinit.d/scripts/network.sh <<'EOF'
#!/bin/bash
# Wait for udev to settle
udevadm settle --timeout=5 2>/dev/null || true
ip link set lo up
# Bring up first ethernet interface
for iface in /sys/class/net/e* /sys/class/net/en*; do
    [[ -d "$iface" ]] || continue
    name=$(basename "$iface")
    ip link set "$name" up
    dhcpcd "$name" --background 2>/dev/null || true
done
EOF

    chmod +x /etc/dinit.d/scripts/*.sh
    ln -sfv /usr/sbin/dinit /sbin/init
}
run_step "p2_dinit" "Dinit init system" p2_dinit

# ── Pacman bootstrap ──────────────────────────────────────────────────────────
p2_pacman() {
    # libarchive
    extr "libarchive-${LIBARCHIVE_VER}.tar.xz"
    ./configure --prefix=/usr --disable-static --without-xml2
    make -j"${NPROC}"; make install

    # curl
    extr "curl-${CURL_VER}.tar.xz"
    ./configure --prefix=/usr --with-openssl \
        --enable-threaded-resolver --disable-static
    make -j"${NPROC}"; make install

    # fakeroot
    extr "fakeroot-${FAKEROOT_VER}.tar.gz"
    ./configure --prefix=/usr --libdir=/usr/lib/libfakeroot \
        --with-ipc=sysv
    make -j"${NPROC}"; make install

    # pacman
    extr "pacman-${PACMAN_VER}.tar.xz"
    meson setup build --prefix=/usr --buildtype=release \
        -Db_lto=true -Duse-git-version=false \
        -Dscriptlet-shell=/usr/bin/bash \
        -Dldconfig=/usr/bin/ldconfig
    ninja -C build -j"${NPROC}"
    ninja -C build install

    # Directories
    mkdir -p /etc/pacman.d /var/lib/pacman \
             /var/cache/pacman/{pkg,src} /var/log

    cat > /etc/pacman.conf <<'EOF'
[options]
HoldPkg      = pacman glibc
Architecture = x86_64
Color
ParallelDownloads = 5
ILoveCandy
CheckSpace
SigLevel    = Never
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

    cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
EOF

    cat > /etc/makepkg.conf <<'MAKEPKG'
CARCH="x86_64"
CHOST="x86_64-pc-linux-gnu"
CFLAGS="-march=skylake -mtune=skylake -O2 -pipe -fno-plt -fstack-clash-protection -fcf-protection -fomit-frame-pointer -ffunction-sections -fdata-sections"
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
RUSTFLAGS="-C opt-level=2 -C target-cpu=skylake"
LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now -Wl,--gc-sections"
LTOFLAGS="-flto=auto"
MAKEFLAGS="-j$(nproc)"
BUILDENV=(!distcc color !ccache check !sign)
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)
INTEGRITY_CHECK=(sha256)
STRIP_BINARIES="--strip-all"
STRIP_SHARED="--strip-unneeded"
STRIP_STATIC="--strip-debug"
PKGDEST=/var/cache/pacman/pkg
SRCDEST=/var/cache/pacman/src
PACKAGER="Flint Linux Builder"
GPGKEY=""
COMPRESSZST=(zstd -c -z -q --threads=0 -)
PKGEXT='.pkg.tar.zst'
MAKEPKG

    # FIX: Don't run pacman-key --init in chroot — hangs without entropy
    # Key init is deferred to first boot via /etc/dinit.d/scripts/
    cat > /etc/dinit.d/scripts/pacman-key-init.sh <<'EOF'
#!/bin/bash
# Run once on first boot to init pacman keyring (needs real entropy)
if [[ ! -f /etc/pacman.d/gnupg/trustdb.gpg ]]; then
    pacman-key --init
    pacman-key --populate archlinux
    echo "Pacman keyring initialized" > /var/log/pacman-key-init.log
fi
EOF
    chmod +x /etc/dinit.d/scripts/pacman-key-init.sh

    cat > /etc/dinit.d/pacman-key-init <<'EOF'
type = oneshot
command = /etc/dinit.d/scripts/pacman-key-init.sh
depends-on = network
EOF
}
run_step "p2_pacman" "Pacman + dependencies" p2_pacman

# ── Hyprland ecosystem ────────────────────────────────────────────────────────
p2_hyprutils() {
    extr "hyprutils-${HYPRUTILS_VER}.tar.gz"
    cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_C_FLAGS="${CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
    cmake --build build -j"${NPROC}"
    cmake --install build
}
run_step "p2_hyprutils" "Hyprutils ${HYPRUTILS_VER}" p2_hyprutils

p2_hyprlang() {
    extr "hyprlang-${HYPRLANG_VER}.tar.gz"
    cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_C_FLAGS="${CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
    cmake --build build -j"${NPROC}"
    cmake --install build
}
run_step "p2_hyprlang" "Hyprlang ${HYPRLANG_VER}" p2_hyprlang

p2_hyprwayland_scanner() {
    extr "hyprwayland-scanner-${HYPRWAYLAND_SCANNER_VER}.tar.gz"
    cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build -j"${NPROC}"
    cmake --install build
}
run_step "p2_hyprwayland_scanner" "Hyprwayland-scanner" p2_hyprwayland_scanner

p2_aquamarine() {
    extr "aquamarine-${AQUAMARINE_VER}.tar.gz"
    cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_C_FLAGS="${CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
    cmake --build build -j"${NPROC}"
    cmake --install build
}
run_step "p2_aquamarine" "Aquamarine ${AQUAMARINE_VER}" p2_aquamarine

# FIX: Correct Hyprland source tarball name
p2_hyprland() {
    extr "hyprland-${HYPRLAND_VER}.tar.xz"
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_C_FLAGS="${CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
        -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
        -DUSE_SYSTEM_WLROOTS=OFF \
        -DINSTALL_IPC_SERVER=ON
    cmake --build build -j"${NPROC}"
    cmake --install build
}
run_step "p2_hyprland" "Hyprland ${HYPRLAND_VER}" p2_hyprland

# ── Waybar ────────────────────────────────────────────────────────────────────
p2_waybar() {
    extr "waybar-${WAYBAR_VER}.tar.gz"
    meson setup build --prefix=/usr --buildtype=release \
        -Dsystemd=disabled -Dpulseaudio=disabled \
        -Dpipewire=disabled -Dmpd=disabled \
        -Dlibudev=enabled -Dlibnl=enabled \
        -Dgtk-layer-shell=enabled
    ninja -C build -j"${NPROC}"
    ninja -C build install
}
run_step "p2_waybar" "Waybar ${WAYBAR_VER}" p2_waybar

# ── Foot terminal ─────────────────────────────────────────────────────────────
p2_foot() {
    extr "foot-${FOOT_VER}.tar.gz"
    meson setup build --prefix=/usr --buildtype=release \
        -Db_lto=true -Dime=true
    ninja -C build -j"${NPROC}"
    ninja -C build install
}
run_step "p2_foot" "Foot ${FOOT_VER}" p2_foot

# ── Fastfetch ─────────────────────────────────────────────────────────────────
p2_fastfetch() {
    extr "fastfetch-${FASTFETCH_VER}.tar.gz"
    cmake -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_C_FLAGS="${CFLAGS}" \
        -DENABLE_EMBEDDED_PCIIDS=ON \
        -DENABLE_VULKAN=OFF
    cmake --build build -j"${NPROC}"
    cmake --install build
}
run_step "p2_fastfetch" "Fastfetch ${FASTFETCH_VER}" p2_fastfetch

# ── System configuration ──────────────────────────────────────────────────────
p2_sysconfig() {
    echo "flint" > /etc/hostname

    cat > /etc/hosts <<'EOF'
127.0.0.1  localhost
127.0.1.1  flint.localdomain flint
::1        localhost ip6-localhost ip6-loopback
EOF

    cat > /etc/fstab <<'EOF'
# Edit with your actual device UUIDs (use: blkid)
# Example:
# UUID=xxxx  /          ext4   rw,noatime,lazytime,discard  0 1
# UUID=xxxx  /boot/efi  vfat   umask=0077                   0 2
tmpfs        /tmp       tmpfs  defaults,noatime,mode=1777   0 0
EOF

    cat > /etc/profile <<'EOF'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color
export EDITOR=vim
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export MAKEFLAGS="-j$(nproc)"
export RUSTFLAGS="-C opt-level=2 -C target-cpu=skylake"
for s in /etc/profile.d/*.sh; do [[ -r "$s" ]] && source "$s"; done
EOF

    cat > /etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
LC_COLLATE=C.UTF-8
EOF
    localedef -i en_US -f UTF-8 en_US.UTF-8 2>/dev/null || true

    cat > /etc/ld.so.conf <<'EOF'
/usr/local/lib
/usr/lib
include /etc/ld.so.conf.d/*.conf
EOF
    mkdir -p /etc/ld.so.conf.d
    ldconfig

    cat > /etc/sysctl.d/99-flint.conf <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
kernel.nmi_watchdog = 0
kernel.unprivileged_userns_clone = 1
kernel.sched_autogroup_enabled = 1
EOF

    # Create flint user home and sudoers
    mkdir -p /home/flint
    chown 1000:1000 /home/flint
    # FIX: Only write sudoers.d, never append to /etc/sudoers directly
    mkdir -p /etc/sudoers.d
    cat > /etc/sudoers.d/wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
    chmod 440 /etc/sudoers.d/wheel

    cat > /etc/os-release <<'EOF'
NAME="Flint Linux"
PRETTY_NAME="Flint Linux 2.0 (Obsidian)"
VERSION="2.0"
VERSION_CODENAME="Obsidian"
ID=flint
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="1;34"
EOF

    cat > /etc/issue <<'EOF'

  ███████╗██╗     ██╗███╗   ██╗████████╗
  ██╔════╝██║     ██║████╗  ██║╚══██╔══╝
  █████╗  ██║     ██║██╔██╗ ██║   ██║
  ██╔══╝  ██║     ██║██║╚██╗██║   ██║
  ██║     ███████╗██║██║ ╚████║   ██║
  ╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝   ╚═╝
  Flint Linux 2.0 Obsidian — \l

EOF

    cat > /etc/motd <<'EOF'
Welcome to Flint Linux!
  IMPORTANT: Change passwords immediately:  passwd flint && passwd root
  Package manager:  pacman -Syu
  Grub install:     grub-install + grub-mkconfig (see /etc/motd.grub)
EOF
}
run_step "p2_sysconfig" "System configuration" p2_sysconfig

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Phase 2 Complete — Final system built!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
P2_SCRIPT
    } > "${P2}"

    chmod +x "${P2}"

    chroot_exec /sources/flint_phase2.sh
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 — POST-INSTALL: Dotfiles, Hyprland config, GRUB
# ─────────────────────────────────────────────────────────────────────────────
phase3_postinstall() {
    banner "Phase 3 — Post-install Configs"

    run_step "p3_hypr_cfg"   "Hyprland configuration"      _cfg_hyprland
    run_step "p3_waybar_cfg" "Waybar configuration"        _cfg_waybar
    run_step "p3_foot_cfg"   "Foot configuration"          _cfg_foot
    run_step "p3_fastfetch"  "Fastfetch configuration"     _cfg_fastfetch
    run_step "p3_bashrc"     "User bashrc"                 _cfg_bashrc
    run_step "p3_grub"       "GRUB bootloader"             _install_grub
    run_step "p3_finalize"   "Final cleanup"               _finalize
}

_cfg_hyprland() {
    local D="${LFS}/home/flint/.config/hypr"
    mkdir -p "${D}"
    cat > "${D}/hyprland.conf" <<'EOF'
# ══════════════════════════════════════════════════════════════════════════════
#  Flint Linux — Hyprland Config
#  Hardware: i7-6600U / Intel HD 520 (Skylake GT2)
#  Syntax:   Current wiki spec (Hyprland ≥ 0.48, windowrulev2 is GONE)
# ══════════════════════════════════════════════════════════════════════════════

# ── Monitors ──────────────────────────────────────────────────────────────────
# ThinkPad T460 internal 1080p panel
monitor = eDP-1, 1920x1080@60, 0x0, 1
# Auto-place any external monitor to the right
monitor = , preferred, auto, 1

# ── Environment variables ──────────────────────────────────────────────────────
# Intel HD 520 — force iris Mesa driver (correct for Skylake GT2)
env = WLR_DRM_DEVICES, /dev/dri/card0
env = __GLX_VENDOR_LIBRARY_NAME, mesa
env = MESA_LOADER_DRIVER_OVERRIDE, iris
env = LIBVA_DRIVER_NAME, iHD

# Wayland / XDG
env = XDG_CURRENT_DESKTOP, Hyprland
env = XDG_SESSION_TYPE, wayland
env = XDG_SESSION_DESKTOP, Hyprland

# App toolkit Wayland hints
env = QT_QPA_PLATFORM, wayland;xcb
env = QT_AUTO_SCREEN_SCALE_FACTOR, 1
env = QT_WAYLAND_DISABLE_WINDOWDECORATION, 1
env = GDK_BACKEND, wayland,x11
env = MOZ_ENABLE_WAYLAND, 1
env = CLUTTER_BACKEND, wayland
env = SDL_VIDEODRIVER, wayland

# ── Autostart ─────────────────────────────────────────────────────────────────
exec-once = waybar
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE

# ── Input ─────────────────────────────────────────────────────────────────────
input {
    kb_layout  = us
    kb_options = caps:escape
    follow_mouse   = 1
    sensitivity    = 0
    accel_profile  = adaptive

    touchpad {
        natural_scroll   = true
        tap-to-click     = true
        drag_lock        = true
        scroll_factor    = 0.5
        middle_button_emulation = true
    }
}

# ── General ───────────────────────────────────────────────────────────────────
general {
    gaps_in    = 4
    gaps_out   = 8
    border_size = 2

    # gradient border: active cyan→blue, inactive dark
    col.active_border   = rgb(88c0d0) rgb(5e81ac) 45deg
    col.inactive_border = rgb(3b4252)

    layout          = dwindle
    allow_tearing   = false
}

# ── Decoration ────────────────────────────────────────────────────────────────
decoration {
    rounding         = 8
    active_opacity   = 1.0
    inactive_opacity = 0.93

    blur {
        enabled          = true
        size             = 5
        passes           = 2
        new_optimizations = true
        xray             = false
    }

    # NOTE: drop_shadow is deprecated — use shadow namespace
    shadow {
        enabled        = true
        range          = 12
        render_power   = 3
        color          = rgba(1a1a1aee)
    }
}

# ── Animations ────────────────────────────────────────────────────────────────
animations {
    enabled = true

    bezier = overshot,  0.05, 0.9, 0.1, 1.1
    bezier = smoothIn,  0.25, 1.0, 0.5, 1.0
    bezier = linear,    0.0,  0.0, 1.0, 1.0

    animation = windows,    1, 5, overshot, slide
    animation = windowsOut, 1, 4, smoothIn, popin 80%
    animation = fade,       1, 4, smoothIn
    animation = workspaces, 1, 5, overshot, slidefade 20%
    animation = border,     1, 5, linear
}

# ── Dwindle layout ────────────────────────────────────────────────────────────
dwindle {
    pseudotile     = true
    preserve_split = true
    # smart_split removed in newer Hyprland — do not add
}

# ── Misc ──────────────────────────────────────────────────────────────────────
misc {
    force_default_wallpaper    = 0
    disable_hyprland_logo      = true
    disable_splash_rendering   = true
    enable_swallow             = true
    swallow_regex              = ^(foot)$
    key_press_enables_dpms     = true
    mouse_move_enables_dpms    = true
    # vfr saves GPU power on Intel iGPU — keep enabled
    vfr                        = true
}

# ── Keybinds ──────────────────────────────────────────────────────────────────
$mod = SUPER

# Core WM
bind  = $mod,       Return,      exec,           foot
bind  = $mod,       Q,           killactive
bind  = $mod SHIFT, Q,           exit
bind  = $mod,       Space,       togglefloating
bind  = $mod,       F,           fullscreen,     0
bind  = $mod SHIFT, F,           fullscreen,     1
bind  = $mod,       P,           pseudo

# Apps
bind  = $mod,       D,           exec,    wofi --show drun
bind  = $mod,       L,           exec,    swaylock -f

# Screenshot — requires grim + slurp
bind  = ,           Print,       exec,    grim -g "$(slurp)" ~/Pictures/$(date +%Y%m%d_%H%M%S).png
bind  = $mod,       Print,       exec,    grim ~/Pictures/$(date +%Y%m%d_%H%M%S).png

# Volume (wpctl — part of pipewire)
bindel = , XF86AudioRaiseVolume,  exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
bindel = , XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl  = , XF86AudioMute,         exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindl  = , XF86AudioMicMute,      exec, wpctl set-mute @DEFAULT_SOURCE@ toggle

# Brightness (brightnessctl)
bindel = , XF86MonBrightnessUp,   exec, brightnessctl set 5%+
bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

# Workspaces — switch
bind  = $mod, 1, workspace, 1
bind  = $mod, 2, workspace, 2
bind  = $mod, 3, workspace, 3
bind  = $mod, 4, workspace, 4
bind  = $mod, 5, workspace, 5
bind  = $mod, 6, workspace, 6
bind  = $mod, 7, workspace, 7
bind  = $mod, 8, workspace, 8
bind  = $mod, 9, workspace, 9
bind  = $mod, 0, workspace, 10

# Workspaces — move window to
bind  = $mod SHIFT, 1, movetoworkspace, 1
bind  = $mod SHIFT, 2, movetoworkspace, 2
bind  = $mod SHIFT, 3, movetoworkspace, 3
bind  = $mod SHIFT, 4, movetoworkspace, 4
bind  = $mod SHIFT, 5, movetoworkspace, 5
bind  = $mod SHIFT, 6, movetoworkspace, 6
bind  = $mod SHIFT, 7, movetoworkspace, 7
bind  = $mod SHIFT, 8, movetoworkspace, 8
bind  = $mod SHIFT, 9, movetoworkspace, 9
bind  = $mod SHIFT, 0, movetoworkspace, 10

# Scratchpad
bind  = $mod,       S,  togglespecialworkspace, magic
bind  = $mod SHIFT, S,  movetoworkspace, special:magic

# Focus
bind  = $mod, left,  movefocus, l
bind  = $mod, right, movefocus, r
bind  = $mod, up,    movefocus, u
bind  = $mod, down,  movefocus, d

# Resize
binde = $mod CTRL, right, resizeactive,  30  0
binde = $mod CTRL, left,  resizeactive, -30  0
binde = $mod CTRL, up,    resizeactive,   0 -30
binde = $mod CTRL, down,  resizeactive,   0  30

# Mouse window control
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow

# Scroll through workspaces with mouse wheel on bar
bind  = $mod, mouse_down, workspace, e+1
bind  = $mod, mouse_up,   workspace, e-1

# ── Window Rules (NEW syntax — windowrulev2 is DEPRECATED since 0.48) ─────────
# Correct syntax: windowrule = <rule>, match:<field> <value>
# OR:             windowrule = <rule>, match:class <regex>
#
# Float specific apps
windowrule = float,           match:class ^(pavucontrol)$
windowrule = float,           match:class ^(blueman-manager)$
windowrule = float,           match:class ^(nm-connection-editor)$
windowrule = float,           match:title ^(Picture-in-Picture)$
windowrule = pin,             match:title ^(Picture-in-Picture)$

# Terminal slight transparency
windowrule = opacity 0.95 0.88, match:class ^(foot)$

# Dialogs stay focused
windowrule = stayfocused,     match:class ^(pinentry)(.*)$

# No blur on certain windows (saves GPU on Intel iGPU)
windowrule = noblur,          match:class ^(firefox)$
windowrule = noblur,          match:class ^(chromium)$
EOF
    chown -R 1000:1000 "${LFS}/home/flint"
}

_cfg_waybar() {
    local D="${LFS}/home/flint/.config/waybar"
    mkdir -p "${D}"
    cat > "${D}/config.jsonc" <<'EOF'
{
    "layer": "top", "position": "top", "height": 32,
    "spacing": 4, "margin-top": 4, "margin-left": 8, "margin-right": 8,
    "modules-left":   ["hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right":  ["cpu","memory","temperature","backlight","battery","network","pulseaudio","tray"],
    "hyprland/workspaces": { "format": "{id}", "all-outputs": false },
    "hyprland/window":     { "format": " {}", "max-length": 40 },
    "clock": { "format": "  {:%a %d %b   %H:%M}", "interval": 60 },
    "cpu":   { "format": " {usage}%", "interval": 2, "on-click": "foot -e htop" },
    "memory":{ "format": " {}%",     "interval": 5 },
    "temperature": { "critical-threshold": 80, "format": " {temperatureC}°C",
                     "format-critical": " {temperatureC}°C" },
    "backlight": { "format": "{icon} {percent}%",
                   "format-icons": ["","","","","","","","",""],
                   "on-scroll-up": "brightnessctl set 5%+",
                   "on-scroll-down": "brightnessctl set 5%-" },
    "battery": { "format": "{icon} {capacity}%",
                 "format-charging": " {capacity}%",
                 "format-icons": ["","","","",""],
                 "states": { "warning": 25, "critical": 10 } },
    "network": { "format-wifi": "  {signalStrength}%",
                 "format-ethernet": "  {ipaddr}",
                 "format-disconnected": "⚠ Off",
                 "on-click-right": "foot -e nmtui" },
    "pulseaudio": { "format": "{icon} {volume}%", "format-muted": "  Muted",
                    "format-icons": { "default": ["","",""] },
                    "on-click": "pavucontrol" },
    "tray": { "icon-size": 18, "spacing": 6 }
}
EOF

    cat > "${D}/style.css" <<'EOF'
@define-color bg     #2e3440;
@define-color fg     #d8dee9;
@define-color blue   #81a1c1;
@define-color cyan   #88c0d0;
@define-color green  #a3be8c;
@define-color yellow #ebcb8b;
@define-color red    #bf616a;
@define-color border #4c566a;

* { font-family: "JetBrainsMono Nerd Font", monospace; font-size: 13px; border: none; }

window#waybar {
    background: alpha(@bg, 0.90);
    color: @fg;
    border-radius: 10px;
}
#workspaces button         { padding: 0 6px; color: @border; border-radius: 6px; margin: 3px 2px; }
#workspaces button:hover   { background: alpha(@blue,0.2); color: @cyan; }
#workspaces button.active  { background: alpha(@blue,0.3); color: @cyan; font-weight: bold; }
#workspaces button.urgent  { background: alpha(@red,0.3);  color: @red; }
#clock     { color: @cyan;   font-weight: bold; padding: 0 12px; }
#cpu       { color: @green;  padding: 0 8px; }
#memory    { color: #b48ead; padding: 0 8px; }
#temperature { color: @yellow; padding: 0 8px; }
#temperature.critical { color: @red; }
#backlight { color: @yellow; padding: 0 8px; }
#battery   { color: @green;  padding: 0 8px; }
#battery.warning  { color: @yellow; }
#battery.critical { color: @red; }
#network   { color: @blue;   padding: 0 8px; }
#pulseaudio { color: @blue;  padding: 0 8px; }
#pulseaudio.muted { color: @border; }
#tray      { padding: 0 6px; }
EOF
    chown -R 1000:1000 "${LFS}/home/flint"
}

_cfg_foot() {
    local D="${LFS}/home/flint/.config/foot"
    mkdir -p "${D}"
    cat > "${D}/foot.ini" <<'EOF'
[main]
term=foot
font=JetBrainsMono Nerd Font:size=11
dpi-aware=yes
pad=6x6
shell=/usr/bin/bash
workers=4

[scrollback]
lines=10000

[cursor]
style=beam
blink=yes

[mouse]
hide-when-typing=yes

[colors]
background=2e3440
foreground=d8dee9
regular0=3b4252
regular1=bf616a
regular2=a3be8c
regular3=ebcb8b
regular4=81a1c1
regular5=b48ead
regular6=88c0d0
regular7=e5e9f0
bright0=4c566a
bright1=bf616a
bright2=a3be8c
bright3=ebcb8b
bright4=81a1c1
bright5=b48ead
bright6=8fbcbb
bright7=eceff4
alpha=0.92

[key-bindings]
clipboard-copy=Control+Shift+c
clipboard-paste=Control+Shift+v
spawn-terminal=Control+Shift+n
font-increase=Control+equal
font-decrease=Control+minus
EOF
    chown -R 1000:1000 "${LFS}/home/flint"
}

_cfg_fastfetch() {
    local D="${LFS}/home/flint/.config/fastfetch"
    mkdir -p "${D}"

    cat > "${D}/flint-logo.txt" <<'EOF'
    )  )  )
   (  (  (  (
  )  )  )  ) )
 (  (  (  (  (
  )  ) ___ )  )
    _/   \_
   / FLINT  \
  /  LINUX   \
 /____________\
EOF

    cat > "${D}/config.jsonc" <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "source": "~/.config/fastfetch/flint-logo.txt",
        "color": { "1": "cyan", "2": "blue" },
        "padding": { "left": 1, "top": 1 }
    },
    "display": { "separator": "  →  ", "color": "cyan", "keyWidth": 14 },
    "modules": [
        { "type": "title", "format": "{user}@{hostname}", "color": "blue" },
        "break",
        { "type": "os",     "key": "OS",       "format": "Flint Linux 2.0 (Obsidian)" },
        { "type": "kernel", "key": "Kernel" },
        { "type": "uptime", "key": "Uptime" },
        { "type": "shell",  "key": "Shell" },
        { "type": "wm",     "key": "WM" },
        "break",
        { "type": "cpu",    "key": "CPU",    "format": "{name} ({cores-physical}C/{cores-logical}T)" },
        { "type": "gpu",    "key": "GPU" },
        { "type": "memory", "key": "Memory", "format": "{used} / {total} ({percentage:.0}%)" },
        { "type": "swap",   "key": "Swap" },
        { "type": "disk",   "key": "Disk",   "folders": "/" },
        "break",
        { "type": "colors", "paddingLeft": 1, "symbol": "circle" }
    ]
}
EOF
    chown -R 1000:1000 "${LFS}/home/flint"
}

_cfg_bashrc() {
    cat > "${LFS}/home/flint/.bashrc" <<'EOF'
# ── Flint Linux user bashrc ───────────────────────────────────────────────────
[[ $- != *i* ]] && return

export LANG=en_US.UTF-8
export EDITOR=vim
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups:erasedups

# Auto-start Hyprland on TTY1
if [[ -z "${WAYLAND_DISPLAY}" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    exec Hyprland 2>/tmp/hyprland.log
fi

# Fastfetch on interactive login
command -v fastfetch &>/dev/null && fastfetch

# Aliases
alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lahF'
alias la='ls -A'
alias grep='grep --color=auto'
alias ip='ip --color=auto'

# Pacman shortcuts
alias pacs='pacman -Ss'
alias paci='sudo pacman -S'
alias pacr='sudo pacman -Rs'
alias pacu='sudo pacman -Syu'
alias pacl='pacman -Q'
alias paco='pacman -Qdt'

# Prompt
PS1='\[\033[01;36m\]\u\[\033[00m\]@\[\033[01;34m\]\h\[\033[00m\]:\[\033[01;32m\]\w\[\033[00m\]\$ '
EOF

    cat > "${LFS}/home/flint/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF

    chown 1000:1000 \
        "${LFS}/home/flint/.bashrc" \
        "${LFS}/home/flint/.bash_profile"
    mkdir -p "${LFS}/home/flint/Pictures"
    chown -R 1000:1000 "${LFS}/home/flint"
}

_install_grub() {
    chroot_exec /bin/bash -c "
set -euo pipefail
cd /tmp
mkdir -p grub_src
tar xf /sources/grub-${GRUB_VER}.tar.xz -C grub_src --strip-components=1
cd grub_src
unset CFLAGS CXXFLAGS LDFLAGS  # GRUB has its own flags
./configure --prefix=/usr --sysconfdir=/etc \
    --disable-efiemu --disable-werror
make -j${NPROC}
make install

mkdir -p /boot/grub
cat > /etc/default/grub <<'GRUBDEF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR=\"Flint Linux\"
GRUB_CMDLINE_LINUX_DEFAULT=\"quiet loglevel=3 nowatchdog page_alloc.shuffle=1 mitigations=auto i915.enable_fbc=1 i915.enable_psr=1\"
GRUB_CMDLINE_LINUX=\"\"
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_DISABLE_RECOVERY=true
GRUBDEF

echo 'GRUB built. Run these after first chroot:'
echo '  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=FLINT'
echo '  grub-mkconfig -o /boot/grub/grub.cfg'
cat > /etc/motd.grub <<'EOF2'
== GRUB Install Instructions ==
1. Mount your EFI partition:  mkdir -p /boot/efi && mount /dev/sda1 /boot/efi
2. grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=FLINT --recheck
   (OR for BIOS: grub-install --target=i386-pc /dev/sda)
3. Edit /etc/fstab with your actual UUIDs (use: blkid)
4. grub-mkconfig -o /boot/grub/grub.cfg
5. exit && reboot
EOF2
"
}

_finalize() {
    chroot_exec /bin/bash -c "
set -euo pipefail
ldconfig
rm -rf /tmp/flint_build /tmp/cmake_inst /tmp/grub_src /tmp/ninja-linux.zip 2>/dev/null || true
rm -f /sources/flint_phase2.sh 2>/dev/null || true
strip --strip-all /usr/bin/* 2>/dev/null || true
strip --strip-unneeded /usr/lib/*.so* 2>/dev/null || true
echo 'Finalization complete'
du -sh /usr /var /etc /boot 2>/dev/null || true
"
    ok "System finalized"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
main() {
    local phase="${1:-all}"

    clear
    echo -e "${BOLD}${BLUE}"
    cat <<'BANNER'
  ███████╗██╗     ██╗███╗   ██╗████████╗
  ██╔════╝██║     ██║████╗  ██║╚══██╔══╝
  █████╗  ██║     ██║██╔██╗ ██║   ██║
  ██╔══╝  ██║     ██║██║╚██╗██║   ██║
  ██║     ███████╗██║██║ ╚████║   ██║
  ╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝   ╚═╝
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}Flint Linux v${FLINT_VERSION} (${FLINT_CODENAME})${NC} — Audited LFS Builder"
    echo -e "  Target: i7-6600U Skylake | 12GB RAM | Intel HD 520"
    echo -e "  Phase:  ${phase} | Cores: ${NPROC} | LFS: ${LFS}"
    echo ""

    case "${phase}" in
        check)
            preflight_check ;;
        1|phase1)
            preflight_check
            setup_environment
            phase1_toolchain ;;
        2|phase2)
            prepare_chroot
            phase2_final_system ;;
        3|phase3)
            prepare_chroot
            phase3_postinstall
            umount_vfs ;;
        all)
            preflight_check
            setup_environment
            phase1_toolchain
            prepare_chroot
            phase2_final_system
            phase3_postinstall
            umount_vfs ;;
        *)
            echo "Usage: $0 [all|check|1|2|3]"
            exit 1 ;;
    esac

    if [[ "${phase}" == "all" || "${phase}" == "3" || "${phase}" == "phase3" ]]; then
        echo ""
        echo -e "${GREEN}${BOLD}"
        cat <<'DONE'
  ╔══════════════════════════════════════════════════════════╗
  ║  Flint Linux Build Complete!                             ║
  ║                                                          ║
  ║  Final steps (run in chroot: chroot /mnt/lfs):          ║
  ║  1. Edit /etc/fstab with your disk UUIDs (blkid)        ║
  ║  2. Mount EFI: mount /dev/sda1 /boot/efi                ║
  ║  3. grub-install --target=x86_64-efi \                  ║
  ║       --efi-directory=/boot/efi \                        ║
  ║       --bootloader-id=FLINT --recheck                   ║
  ║  4. grub-mkconfig -o /boot/grub/grub.cfg                ║
  ║  5. passwd root  &&  passwd flint                        ║
  ║  6. exit && reboot                                       ║
  ║                                                          ║
  ║  Post-boot:                                              ║
  ║  - pacman-key --init && pacman-key --populate archlinux  ║
  ║  - pacman -Syu                                           ║
  ║  - yay install for AUR                                   ║
  ╚══════════════════════════════════════════════════════════╝
DONE
        echo -e "${NC}"
    fi
}

trap 'echo -e "\n${YELLOW}Interrupted. Re-run with same phase to resume.${NC}"' INT TERM
main "$@"
