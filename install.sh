#!/usr/bin/env bash
# Install or update the private LivemoreBio research product from one pinned commit.
# Bash 3.2+ is intentional: it is the oldest Bash shipped by supported macOS hosts.
set -euo pipefail
IFS=$'\n\t'
umask 077

readonly REPOSITORY="MannyAmah/livemorebio"
readonly REQUESTED_REF="${LIVEMORE_REF-}"
# A published release needs no GitHub account: the archive and its checksum are
# fetched over plain HTTPS. LIVEMORE_REF selects a repository ref instead, which
# is the private path and does require an authorised GitHub CLI.
readonly DIST_BASE="${LIVEMORE_DIST_BASE-https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main}"
readonly DIST_CHANNEL="${LIVEMORE_CHANNEL-stable}"
readonly PINNED_SHA256="${LIVEMORE_SHA256-}"
# Seconds multiplied by the attempt number between dependency retries. Only the
# test harness lowers it; a real slow mirror needs the real wait.
RETRY_BACKOFF_SECONDS="${LIVEMORE_RETRY_BACKOFF_SECONDS-15}"
case "$RETRY_BACKOFF_SECONDS" in
    ""|*[!0-9]*) RETRY_BACKOFF_SECONDS=15 ;;
esac
readonly RETRY_BACKOFF_SECONDS
readonly HOME_DIRECTORY="${HOME-}"
readonly INSTALL_BASE="${LIVEMORE_INSTALL_DIR-${HOME_DIRECTORY}/.local/share/livemorebio}"
readonly BIN_DIRECTORY="${LIVEMORE_BIN_DIR-${HOME_DIRECTORY}/.local/bin}"
readonly INSTALL_MODELS="${LIVEMORE_INSTALL_MODELS-human-gem}"
readonly PATH_MARKER_BEGIN="# >>> LivemoreBio PATH >>>"
readonly PATH_MARKER_END="# <<< LivemoreBio PATH <<<"

validate_dist_base() {
    # This URL is where executable source comes from, so it is constrained to a
    # plain https origin and path. Anything else is refused rather than passed
    # to curl.
    case "$1" in
        https://*) ;;
        *) fail "LIVEMORE_DIST_BASE must be an https URL: $1" ;;
    esac
    case "$1" in
        *[!A-Za-z0-9./:_-]*) fail "LIVEMORE_DIST_BASE contains unsupported characters." ;;
        *..*) fail "LIVEMORE_DIST_BASE must not contain a relative path segment." ;;
    esac
}

CURRENT_PHASE="preflight"
RELEASE_DIRECTORY=""
OWNED_RELEASE_DIRECTORY=""
LOCK_DIRECTORY=""
LOCK_HELD=0
PATH_GUIDANCE=""

info() {
    printf '[LivemoreBio] %s\n' "$1"
}

fail() {
    printf '[LivemoreBio] ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    local exit_code=$?
    if [[ -n "$OWNED_RELEASE_DIRECTORY" && -d "$OWNED_RELEASE_DIRECTORY" ]]; then
        case "$OWNED_RELEASE_DIRECTORY" in
            "$INSTALL_BASE"/releases/*)
                if [[ "$OWNED_RELEASE_DIRECTORY" == "$RELEASE_DIRECTORY" ]]; then
                    rm -rf -- "$OWNED_RELEASE_DIRECTORY"
                else
                    printf '[LivemoreBio] WARNING: refusing to clean mismatched release path: %s\n' \
                        "$OWNED_RELEASE_DIRECTORY" >&2
                fi
                ;;
            *)
                printf '[LivemoreBio] WARNING: refusing to clean unexpected release path: %s\n' \
                    "$OWNED_RELEASE_DIRECTORY" >&2
                ;;
        esac
    fi
    if [[ "$LOCK_HELD" -eq 1 && -n "$LOCK_DIRECTORY" ]]; then
        rm -f -- "$LOCK_DIRECTORY/pid"
        rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
    fi
    if [[ "$exit_code" -ne 0 ]]; then
        printf '[LivemoreBio] Installation failed during %s. The active release was not changed.\n' \
            "$CURRENT_PHASE" >&2
    fi
    trap - EXIT
    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "$2"
}

validate_absolute_path() {
    local label="$1"
    local path_value="$2"
    [[ -n "$path_value" ]] || fail "$label cannot be empty."
    case "$path_value" in
        /*) ;;
        *) fail "$label must be an absolute path: $path_value" ;;
    esac
    case "$path_value" in
        *$'\n'*|*$'\r'*) fail "$label cannot contain a newline." ;;
    esac
    case "$path_value" in
        */|*//*|*/./*|*/.|*/../*|*/..)
            fail "$label must be a normalized absolute path: $path_value"
            ;;
    esac
}

validate_ref() {
    local ref_value="$1"
    [[ -n "$ref_value" ]] || fail "LIVEMORE_REF cannot be empty."
    case "$ref_value" in
        -*|*..*|*[!A-Za-z0-9._/-]*)
            fail "Unsafe LIVEMORE_REF: $ref_value"
            ;;
    esac
}

validate_commit() {
    local commit_value="$1"
    [[ ${#commit_value} -eq 40 ]] || return 1
    case "$commit_value" in
        *[!0-9A-Fa-f]*) return 1 ;;
    esac
    return 0
}

acquire_lock() {
    LOCK_DIRECTORY="$INSTALL_BASE/.install.lock"
    if mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
        printf '%s\n' "$$" >"$LOCK_DIRECTORY/pid"
        LOCK_HELD=1
        return
    fi

    [[ ! -L "$LOCK_DIRECTORY" ]] || \
        fail "Installer lock cannot be a symbolic link: $LOCK_DIRECTORY"
    [[ -d "$LOCK_DIRECTORY" ]] || \
        fail "Installer lock path is not a directory: $LOCK_DIRECTORY"

    local recorded_pid=""
    if [[ -f "$LOCK_DIRECTORY/pid" ]]; then
        recorded_pid=$(sed -n '1p' "$LOCK_DIRECTORY/pid" 2>/dev/null || true)
    fi
    if [[ "$recorded_pid" =~ ^[0-9]+$ ]] && kill -0 "$recorded_pid" 2>/dev/null; then
        fail "Another LivemoreBio installer is already running (PID $recorded_pid)."
    fi

    info "Recovering a stale installer lock."
    rm -f -- "$LOCK_DIRECTORY/pid"
    rmdir "$LOCK_DIRECTORY" 2>/dev/null || \
        fail "The stale installer lock contains unexpected files: $LOCK_DIRECTORY"
    mkdir "$LOCK_DIRECTORY" 2>/dev/null || \
        fail "Could not acquire installer lock: $LOCK_DIRECTORY"
    printf '%s\n' "$$" >"$LOCK_DIRECTORY/pid"
    LOCK_HELD=1
}

replace_path_atomically() {
    local temporary_path="$1"
    local destination_path="$2"
    "$PYTHON" - "$temporary_path" "$destination_path" <<'PY'
import os
import sys

os.replace(sys.argv[1], sys.argv[2])
PY
}

shell_quote() {
    "$PYTHON" - "$1" <<'PY'
import shlex
import sys

print(shlex.quote(sys.argv[1]))
PY
}

compute_release_digest() {
    "$PYTHON" - "$RELEASE_DIRECTORY" <<'PY'
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1])
excluded = {".livemore-install-complete"}
digest = hashlib.sha256()
for path in sorted(root.rglob("*"), key=lambda candidate: candidate.as_posix()):
    relative = path.relative_to(root)
    if relative.as_posix() in excluded:
        continue
    encoded_relative = os.fsencode(relative.as_posix())
    mode = stat.S_IMODE(path.lstat().st_mode)
    if path.is_symlink():
        payload_digest = hashlib.sha256(os.fsencode(os.readlink(path))).digest()
        kind = b"L"
    elif path.is_file():
        file_digest = hashlib.sha256()
        with path.open("rb") as release_file:
            for chunk in iter(lambda: release_file.read(1024 * 1024), b""):
                file_digest.update(chunk)
        payload_digest = file_digest.digest()
        kind = b"F"
    else:
        continue
    digest.update(kind)
    digest.update(b"\0")
    digest.update(encoded_relative)
    digest.update(b"\0")
    digest.update(str(mode).encode("ascii"))
    digest.update(b"\0")
    digest.update(payload_digest)
print(digest.hexdigest())
PY
}

configure_interactive_path() {
    case ":${PATH-}:" in
        *":$BIN_DIRECTORY:"*) return ;;
    esac

    local profile=""
    case "${SHELL-}" in
        */zsh) profile="$HOME_DIRECTORY/.zshrc" ;;
        */bash) profile="$HOME_DIRECTORY/.bashrc" ;;
        *)
            PATH_GUIDANCE="Add this directory to PATH in your interactive shell: $BIN_DIRECTORY"
            return
            ;;
    esac

    if [[ -d "$profile" ]]; then
        fail "Shell profile path is a directory and cannot be updated: $profile"
    fi
    if [[ -L "$profile" ]]; then
        PATH_GUIDANCE="Add $BIN_DIRECTORY to PATH manually; the installer did not edit symlinked profile $profile."
        return
    fi
    if [[ -f "$profile" ]] && grep -Fq "$PATH_MARKER_BEGIN" "$profile"; then
        grep -Fq "$PATH_MARKER_END" "$profile" || \
            fail "LivemoreBio PATH block is incomplete in $profile"
        grep -Fq "$BIN_DIRECTORY" "$profile" || \
            fail "LivemoreBio PATH block in $profile points to a different command directory."
        return
    fi

    local quoted_bin
    quoted_bin=$(shell_quote "$BIN_DIRECTORY")
    local needs_separator=0
    [[ -s "$profile" ]] && needs_separator=1
    {
        [[ "$needs_separator" -eq 0 ]] || printf '\n'
        printf '%s\n' "$PATH_MARKER_BEGIN"
        printf '%s\n' "export PATH=${quoted_bin}:\"\$PATH\""
        printf '%s\n' "$PATH_MARKER_END"
    } >>"$profile" || fail "Could not update shell profile: $profile"
    PATH_GUIDANCE="Open a new terminal so $profile is loaded."
}

install_reference_models() {
    if [[ "$INSTALL_MODELS" == "none" ]]; then
        info "Base-only installation requested: genome-scale execution is unavailable until Human-GEM is installed."
        return
    fi
    CURRENT_PHASE="pinned Human-GEM asset verification"
    info "Installing/verifying pinned Human-GEM v2.0.0 and attribution (about 46 MB, private cache)..."
    "$RELEASE_DIRECTORY/source/.venv/bin/python" -I -B -m livemorebio.model_assets install human-gem
}

run_isolated_verification() {
    local genome_test_mode="$1"
    shift
    LIVEMORE_TEST_GENOME_MODELS="$genome_test_mode" "$PYTHON" -I -B - "$RELEASE_DIRECTORY/source" "$@" <<'PY'
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile

# Verification must neither populate operational stores nor modify an already
# hashed release. Only the fixed, separately verified model cache is shared.
sys.dont_write_bytecode = True
source = Path(sys.argv[1]).absolute()
configured_model_root = os.environ.get("LIVEMORE_MODEL_DIR")
if configured_model_root is None:
    configured_model_root = str(
        Path(os.environ.get("LIVEMORE_DATA_DIR", "~/.livemore")).expanduser() / "models"
    )
model_root = (
    str(Path(configured_model_root).expanduser().absolute())
    if configured_model_root else configured_model_root
)
if Path(tempfile.gettempdir()).resolve().is_relative_to(source.parent.resolve()):
    raise SystemExit("Installer verification requires a temporary directory outside the release.")
spec = importlib.util.spec_from_file_location(
    "livemore_installer_review_environment", source / "tools" / "run_review_stack.py"
)
if spec is None or spec.loader is None:
    raise SystemExit("Installer verification environment helper is unavailable.")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
verification_root, verification_env = helper.prepare_review_environment(None, inherited=os.environ)
verification_env["LIVEMORE_MODEL_DIR"] = model_root
print(f"[LivemoreBio] Private verification data retained at: {verification_root}", flush=True)
completed = subprocess.run(
    [str(source / ".venv" / "bin" / "python"), "-I", "-B", "-X", "utf8", "-m", "pytest",
     "-p", "no:cacheprovider", "-q", *sys.argv[2:]],
    cwd=source,
    env=verification_env,
    check=False,
)
raise SystemExit(completed.returncode)
PY
}

CURRENT_PHASE="preflight validation"
[[ -n "$HOME_DIRECTORY" ]] || fail "HOME must be set."
validate_absolute_path "LIVEMORE_INSTALL_DIR" "$INSTALL_BASE"
validate_absolute_path "LIVEMORE_BIN_DIR" "$BIN_DIRECTORY"
# An empty ref is the published-release path, which validates its own manifest.
[[ -z "$REQUESTED_REF" ]] || validate_ref "$REQUESTED_REF"
validate_dist_base "$DIST_BASE"
# Reject an unusable pin before doing any work, not after building a venv.
if [[ -n "$PINNED_SHA256" && ! "$PINNED_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    fail "LIVEMORE_SHA256 must be 64 hexadecimal characters."
fi
case "$INSTALL_MODELS" in
    human-gem|none) ;;
    *) fail "LIVEMORE_INSTALL_MODELS must be human-gem (default) or none (explicit base-only installation)." ;;
esac
[[ "$INSTALL_BASE" != "/" && "$INSTALL_BASE" != "$HOME_DIRECTORY" ]] || \
    fail "LIVEMORE_INSTALL_DIR is too broad: $INSTALL_BASE"
[[ "$BIN_DIRECTORY" != "/" && "$BIN_DIRECTORY" != "$HOME_DIRECTORY" ]] || \
    fail "LIVEMORE_BIN_DIR is too broad: $BIN_DIRECTORY"
[[ ! -L "$INSTALL_BASE" ]] || fail "Install root cannot be a symbolic link: $INSTALL_BASE"
[[ ! -L "$BIN_DIRECTORY" ]] || fail "Command directory cannot be a symbolic link: $BIN_DIRECTORY"
if [[ -e "$INSTALL_BASE" && ! -d "$INSTALL_BASE" ]]; then
    fail "Install root exists but is not a directory: $INSTALL_BASE"
fi

require_command curl "curl is required to download the LivemoreBio release."
require_command tar "tar is required to unpack the LivemoreBio release."
require_command python3.11 "Python 3.11 is required. Install Python 3.11 and retry."
PYTHON="$(command -v python3.11)"
readonly PYTHON
PYTHON_VERSION="$($PYTHON -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
readonly PYTHON_VERSION
[[ "$PYTHON_VERSION" == "3.11" ]] || \
    fail "Python 3.11 is required; selected interpreter reported $PYTHON_VERSION."

if [[ -n "$REQUESTED_REF" ]]; then
    require_command gh "Installing a repository ref needs the GitHub CLI. Install it from https://cli.github.com, or omit LIVEMORE_REF to install the published release."
    gh auth status >/dev/null 2>&1 || fail "GitHub authorization is required for LIVEMORE_REF. Run: gh auth login"
fi

readonly LAUNCHER_DIRECTORY="$INSTALL_BASE/launcher"
readonly EXPECTED_COMMAND_TARGET="$LAUNCHER_DIRECTORY/livemore"
readonly LEGACY_COMMAND_TARGET="$INSTALL_BASE/current/source/.venv/bin/livemore"
readonly COMMAND_PATH="$BIN_DIRECTORY/livemore"
if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
    [[ -L "$COMMAND_PATH" ]] || \
        fail "Existing command is not managed by this installer and will not be overwritten: $COMMAND_PATH"
    case "$(readlink "$COMMAND_PATH")" in
        "$EXPECTED_COMMAND_TARGET"|"$LEGACY_COMMAND_TARGET") ;;
        *) fail "Existing command is not managed by this installer and will not be overwritten: $COMMAND_PATH" ;;
    esac
fi

[[ ! -L "$LAUNCHER_DIRECTORY" ]] || \
    fail "Launcher directory cannot be a symbolic link: $LAUNCHER_DIRECTORY"
if [[ -e "$EXPECTED_COMMAND_TARGET" || -L "$EXPECTED_COMMAND_TARGET" ]]; then
    if [[ ! -f "$EXPECTED_COMMAND_TARGET" || -L "$EXPECTED_COMMAND_TARGET" ]] || \
       ! grep -Fq "# LivemoreBio managed launcher v1" "$EXPECTED_COMMAND_TARGET"; then
        fail "Existing launcher is not managed by this installer: $EXPECTED_COMMAND_TARGET"
    fi
fi

if [[ -e "$INSTALL_BASE/current" || -L "$INSTALL_BASE/current" ]]; then
    if [[ ! -L "$INSTALL_BASE/current" ]]; then
        fail "Existing activation path is not a managed symbolic link: $INSTALL_BASE/current"
    fi
    case "$(readlink "$INSTALL_BASE/current")" in
        "$INSTALL_BASE"/releases/*) ;;
        *) fail "Existing activation link is not managed by this installer: $INSTALL_BASE/current" ;;
    esac
fi

CURRENT_PHASE="source resolution"
# The published channel manifest is three fixed fields. It is parsed with a
# strict pattern rather than a JSON tool, so the installer needs no extra
# dependency and a manifest cannot smuggle anything past these two variables.
manifest_field() {
    printf '%s' "$2" | tr -d '\r\n' \
        | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([A-Za-z0-9._-]\{1,200\}\)\".*/\1/p"
}

RELEASE_SHA256=""
if [[ -n "$REQUESTED_REF" ]]; then
    SOURCE_ORIGIN="repository ref $REQUESTED_REF"
    info "Resolving $REPOSITORY at $REQUESTED_REF..."
    COMMIT=$(gh api "repos/$REPOSITORY/commits/$REQUESTED_REF" --jq .sha)
    validate_commit "$COMMIT" || fail "GitHub returned an invalid commit identifier."
else
    SOURCE_ORIGIN="published $DIST_CHANNEL release"
    info "Resolving the published $DIST_CHANNEL release..."
    manifest=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 60 \
        "$DIST_BASE/$DIST_CHANNEL.json" 2>/dev/null) || manifest=""
    [[ -n "$manifest" ]] || fail \
        "Could not reach the published release at $DIST_BASE/$DIST_CHANNEL.json. Check your network, or set LIVEMORE_DIST_BASE."
    COMMIT=$(manifest_field commit "$manifest")
    RELEASE_SHA256=$(manifest_field sha256 "$manifest")
    validate_commit "$COMMIT" || fail "The published release manifest has no valid commit identifier."
    [[ "$RELEASE_SHA256" =~ ^[0-9a-f]{64}$ ]] || \
        fail "The published release manifest has no valid archive checksum."
fi
if [[ -n "$PINNED_SHA256" ]]; then
    # An out-of-band checksum outranks the manifest, which travels the same path
    # as the archive it describes.
    if [[ -n "$RELEASE_SHA256" && "$RELEASE_SHA256" != "$PINNED_SHA256" ]]; then
        fail "LIVEMORE_SHA256 does not match the published release checksum. Refusing to install."
    fi
    RELEASE_SHA256="$PINNED_SHA256"
fi
readonly COMMIT RELEASE_SHA256 SOURCE_ORIGIN
readonly RELEASES_DIRECTORY="$INSTALL_BASE/releases"
readonly INTEGRITY_DIRECTORY="$INSTALL_BASE/integrity"
RELEASE_DIRECTORY="$RELEASES_DIRECTORY/$COMMIT"
readonly RELEASE_DIRECTORY
readonly INTEGRITY_PATH="$INTEGRITY_DIRECTORY/$COMMIT.sha256"

mkdir -p "$INSTALL_BASE"
acquire_lock

[[ ! -L "$RELEASES_DIRECTORY" ]] || \
    fail "Releases directory cannot be a symbolic link: $RELEASES_DIRECTORY"
if [[ -e "$RELEASES_DIRECTORY" && ! -d "$RELEASES_DIRECTORY" ]]; then
    fail "Releases path exists but is not a directory: $RELEASES_DIRECTORY"
fi
if [[ ! -d "$RELEASES_DIRECTORY" ]]; then
    mkdir "$RELEASES_DIRECTORY"
    printf '%s\n' 'LivemoreBio installer-owned releases directory v1' \
        >"$RELEASES_DIRECTORY/.livemore-installer-owned-v1"
elif [[ ! -f "$RELEASES_DIRECTORY/.livemore-installer-owned-v1" ]]; then
    fail "Existing releases directory is not marked as installer-managed: $RELEASES_DIRECTORY"
fi

[[ ! -L "$INTEGRITY_DIRECTORY" ]] || \
    fail "Integrity directory cannot be a symbolic link: $INTEGRITY_DIRECTORY"
if [[ -e "$INTEGRITY_DIRECTORY" && ! -d "$INTEGRITY_DIRECTORY" ]]; then
    fail "Integrity path exists but is not a directory: $INTEGRITY_DIRECTORY"
fi
if [[ ! -d "$INTEGRITY_DIRECTORY" ]]; then
    mkdir "$INTEGRITY_DIRECTORY"
    printf '%s\n' 'LivemoreBio installer-owned integrity directory v1' \
        >"$INTEGRITY_DIRECTORY/.livemore-installer-owned-v1"
elif [[ ! -f "$INTEGRITY_DIRECTORY/.livemore-installer-owned-v1" ]]; then
    fail "Existing integrity directory is not marked as installer-managed: $INTEGRITY_DIRECTORY"
fi
[[ ! -L "$INTEGRITY_PATH" ]] || \
    fail "Release integrity path cannot be a symbolic link: $INTEGRITY_PATH"
if [[ -e "$INTEGRITY_PATH" && ! -f "$INTEGRITY_PATH" ]]; then
    fail "Release integrity path is not a regular file: $INTEGRITY_PATH"
fi

if [[ -L "$RELEASE_DIRECTORY" ]]; then
    fail "Release path cannot be a symbolic link: $RELEASE_DIRECTORY"
fi

if [[ -e "$RELEASE_DIRECTORY" && ! -d "$RELEASE_DIRECTORY" ]]; then
    fail "Release path exists but is not a directory: $RELEASE_DIRECTORY"
fi

release_rebuild_reason=""
if [[ -d "$RELEASE_DIRECTORY" ]]; then
    if [[ ! -f "$RELEASE_DIRECTORY/.livemore-install-complete" || \
          ! -f "$INTEGRITY_PATH" || \
          ! -x "$RELEASE_DIRECTORY/source/.venv/bin/livemore" ]]; then
        release_rebuild_reason="incomplete"
    else
        expected_digest=$(sed -n '1p' "$INTEGRITY_PATH")
        actual_digest=$(compute_release_digest)
        if [[ "$expected_digest" != "$actual_digest" ]]; then
            release_rebuild_reason="integrity verification failed"
        fi
    fi
fi

if [[ -n "$release_rebuild_reason" ]]; then
    if [[ -L "$INSTALL_BASE/current" && \
          "$(readlink "$INSTALL_BASE/current")" == "$RELEASE_DIRECTORY" ]]; then
        fail "Active release $COMMIT is $release_rebuild_reason; refusing to delete it in place."
    fi
    CURRENT_PHASE="inactive release recovery"
    info "Removing an installer-owned inactive release because it is $release_rebuild_reason."
    rm -rf -- "$RELEASE_DIRECTORY"
fi

if [[ -d "$RELEASE_DIRECTORY" ]]; then
    info "Commit $COMMIT is already verified; repairing activation."
    install_reference_models
    if [[ "$INSTALL_MODELS" != "none" ]]; then
        CURRENT_PHASE="pinned Human-GEM execution verification"
        info "Checking numerical execution before full-capability activation..."
        run_isolated_verification 1 livemorebio/tests/test_stoichiometry_integration.py
    fi
else
    CURRENT_PHASE="inactive release creation"
    mkdir "$RELEASE_DIRECTORY"
    OWNED_RELEASE_DIRECTORY="$RELEASE_DIRECTORY"
    readonly ARCHIVE_PATH="$RELEASE_DIRECTORY/source.tar.gz"
    readonly SOURCE_DIRECTORY="$RELEASE_DIRECTORY/source"
    mkdir -p "$SOURCE_DIRECTORY"

    info "Downloading the source archive ($SOURCE_ORIGIN)..."
    if [[ -n "$REQUESTED_REF" ]]; then
        gh api "repos/$REPOSITORY/tarball/$COMMIT" >"$ARCHIVE_PATH"
    else
        curl -fsSL --proto '=https' --tlsv1.2 --max-time 900 \
            "$DIST_BASE/livemorebio-$COMMIT.tar.gz" -o "$ARCHIVE_PATH" \
            || fail "Could not download the release archive from $DIST_BASE."
    fi
    [[ -s "$ARCHIVE_PATH" ]] || fail "The source archive is empty."
    if [[ -n "$RELEASE_SHA256" ]]; then
        # Verify before unpacking: a failed checksum must never reach the disk
        # as extracted files.
        observed=$("$PYTHON" -c 'import hashlib,sys;h=hashlib.sha256()
with open(sys.argv[1],"rb") as f:
    for chunk in iter(lambda: f.read(1048576), b""): h.update(chunk)
print(h.hexdigest())' "$ARCHIVE_PATH")
        [[ "$observed" == "$RELEASE_SHA256" ]] || fail \
            "Release archive checksum mismatch. Expected $RELEASE_SHA256, got $observed. Refusing to install."
        info "Archive checksum verified."
    fi
    tar -xzf "$ARCHIVE_PATH" --strip-components=1 -C "$SOURCE_DIRECTORY"
    rm -f -- "$ARCHIVE_PATH"
    [[ -f "$SOURCE_DIRECTORY/pyproject.toml" ]] || fail "Release archive has no pyproject.toml."
    [[ -f "$SOURCE_DIRECTORY/requirements-python311.lock" ]] || \
        fail "Release archive has no hashed Python 3.11 dependency lock."
    [[ -d "$SOURCE_DIRECTORY/livemorebio" ]] || fail "Release archive has no livemorebio package."

    CURRENT_PHASE="Python environment creation"
    info "Creating the Python 3.11 environment..."
    "$PYTHON" -m venv "$SOURCE_DIRECTORY/.venv"
    readonly VENV_PYTHON="$SOURCE_DIRECTORY/.venv/bin/python"
    [[ -x "$VENV_PYTHON" ]] || fail "Python venv did not create an executable interpreter."

    CURRENT_PHASE="dependency installation"
    info "Installing the hash-locked scientific, server, notebook, and test dependencies..."
    # This set is roughly a gigabyte of scientific wheels. pip's own --retries
    # covers a failed connection but not a stall part-way through a large body,
    # which is exactly how a slow mirror failed installs here. Retry the whole
    # command instead: pip's HTTP cache means a second attempt reuses whatever
    # already arrived rather than starting over. --require-hashes still decides
    # what is acceptable, so a retry can never widen what gets installed.
    dependency_attempt=1
    until "$VENV_PYTHON" -m pip install --require-hashes --retries 10 --timeout 120 \
        --requirement "$SOURCE_DIRECTORY/requirements-python311.lock"; do
        if (( dependency_attempt >= 4 )); then
            fail "Dependency download failed after $dependency_attempt attempts. This is usually a slow or blocked network; re-run the installer to resume."
        fi
        backoff=$(( dependency_attempt * RETRY_BACKOFF_SECONDS ))
        info "Dependency download did not complete (attempt $dependency_attempt). Retrying in ${backoff}s..."
        sleep "$backoff"
        dependency_attempt=$(( dependency_attempt + 1 ))
    done
    "$VENV_PYTHON" -m pip install --no-deps --no-build-isolation -e \
        "$SOURCE_DIRECTORY"

    install_reference_models

    CURRENT_PHASE="test verification"
    info "Running the complete release test suite..."
    genome_test_mode=0
    [[ "$INSTALL_MODELS" == "none" ]] || genome_test_mode=1
    run_isolated_verification "$genome_test_mode"

    CURRENT_PHASE="compile verification"
    info "Compiling the LivemoreBio package..."
    (cd "$SOURCE_DIRECTORY" && "$VENV_PYTHON" -m compileall -q livemorebio)

    CURRENT_PHASE="CLI verification"
    "$VENV_PYTHON" -I -B -m livemorebio.cli --help >/dev/null
    "$VENV_PYTHON" -I -B "$SOURCE_DIRECTORY/.venv/bin/livemore" --help >/dev/null
    printf 'commit=%s\nverified_at=%s\n' "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        >"$RELEASE_DIRECTORY/.livemore-install-complete"
    temporary_integrity="$INTEGRITY_DIRECTORY/.$COMMIT.$$"
    [[ ! -e "$temporary_integrity" && ! -L "$temporary_integrity" ]] || \
        fail "Temporary release integrity path already exists: $temporary_integrity"
    compute_release_digest >"$temporary_integrity"
    replace_path_atomically "$temporary_integrity" "$INTEGRITY_PATH"

    OWNED_RELEASE_DIRECTORY=""
fi

CURRENT_PHASE="terminal command setup"
mkdir -p "$BIN_DIRECTORY"
configure_interactive_path

mkdir -p "$LAUNCHER_DIRECTORY"
quoted_current_python=$(shell_quote "$INSTALL_BASE/current/source/.venv/bin/python")
temporary_launcher="$LAUNCHER_DIRECTORY/.livemore.$$"
[[ ! -e "$temporary_launcher" && ! -L "$temporary_launcher" ]] || \
    fail "Temporary launcher path already exists: $temporary_launcher"
{
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' '# LivemoreBio managed launcher v1'
    printf 'exec %s -I -B -m livemorebio.cli "$@"\n' "$quoted_current_python"
} >"$temporary_launcher"
chmod 755 "$temporary_launcher"
replace_path_atomically "$temporary_launcher" "$EXPECTED_COMMAND_TARGET"

temporary_command="$BIN_DIRECTORY/.livemore.$$"
[[ ! -e "$temporary_command" && ! -L "$temporary_command" ]] || \
    fail "Temporary command path already exists: $temporary_command"
ln -s "$EXPECTED_COMMAND_TARGET" "$temporary_command"
replace_path_atomically "$temporary_command" "$COMMAND_PATH"

CURRENT_PHASE="atomic activation"
temporary_current="$INSTALL_BASE/.current.$$"
[[ ! -e "$temporary_current" && ! -L "$temporary_current" ]] || \
    fail "Temporary activation path already exists: $temporary_current"
ln -s "$RELEASE_DIRECTORY" "$temporary_current"
replace_path_atomically "$temporary_current" "$INSTALL_BASE/current"

CURRENT_PHASE="completion"
printf '\n[LivemoreBio] Installation complete.\n'
printf '[LivemoreBio] Verified commit: %s\n' "$COMMIT"
printf '[LivemoreBio] Managed command: %s\n' "$COMMAND_PATH"
if [[ -n "$PATH_GUIDANCE" ]]; then
    printf '[LivemoreBio] %s\n' "$PATH_GUIDANCE"
fi
printf '\nStart the product:\n'
printf '  livemore start all\n'
printf '  livemore open\n'
printf '\nThe workspace starts without admitted twins, cohorts, or experiments. Existing user data are preserved.\n'
printf 'Inspect metabolic reference readiness: livemore models status human-gem\n'
