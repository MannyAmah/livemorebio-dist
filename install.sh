#!/usr/bin/env bash
# Install or update the private LivemoreBio research product from one pinned commit.
# Bash 3.2+ is intentional: it is the oldest Bash shipped by supported macOS hosts.
set -euo pipefail
IFS=$'\n\t'
umask 077

readonly REPOSITORY="MannyAmah/livemorebio"
readonly REQUESTED_REF="${LIVEMORE_REF-}"
# Release gates can install locally built bytes without a distribution server.
# The same checksum and full install/verification path still apply.
readonly LOCAL_ARCHIVE="${LIVEMORE_ARCHIVE-}"
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
readonly INSTALL_MODELS="${LIVEMORE_INSTALL_MODELS-human-gem,cardiac}"
INSTALL_HUMAN_GEM=0
INSTALL_CARDIAC=0
CARDIAC_TEST_MODE=0
readonly CARDIAC_MODEL_RELATIVE="models/cardiac/ohara_rudy_cipa_2017.cellml"
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
MODEL_STAGE_DIRECTORY=""
MODEL_SOURCE_DIRECTORY=""
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
    if [[ -n "$MODEL_STAGE_DIRECTORY" && -d "$MODEL_STAGE_DIRECTORY" ]]; then
        case "$MODEL_STAGE_DIRECTORY" in
            "$INSTALL_BASE"/releases/.*.models.*) rm -rf -- "$MODEL_STAGE_DIRECTORY" ;;
            *) printf '[LivemoreBio] WARNING: refusing unexpected model-stage cleanup.\n' >&2 ;;
        esac
    fi
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

validate_model_selection() {
    local accepted="LIVEMORE_INSTALL_MODELS must be a comma/space-separated set of human-gem and cardiac (default: human-gem,cardiac), or none alone (explicit base-only installation)."
    local selection=""
    local IFS=$' ,\t'
    local -a selections
    case "$INSTALL_MODELS" in
        ""|*$'\n'*|*$'\r'*) fail "$accepted" ;;
    esac
    read -r -a selections <<< "$INSTALL_MODELS"
    [[ ${#selections[@]} -gt 0 ]] || fail "$accepted"
    for selection in "${selections[@]}"; do
        case "$selection" in
            human-gem) INSTALL_HUMAN_GEM=1 ;;
            cardiac) INSTALL_CARDIAC=1 ;;
            none) [[ ${#selections[@]} -eq 1 ]] || fail "$accepted" ;;
            *) fail "$accepted" ;;
        esac
    done
}

install_reference_models() {
    CARDIAC_TEST_MODE="$INSTALL_CARDIAC"
    # L0-R2 requires every retained installed asset's numerical tests.
    local cardiac_path="$MODEL_SOURCE_DIRECTORY/$CARDIAC_MODEL_RELATIVE"
    if [[ -e "$cardiac_path" || -L "$cardiac_path" ]]; then
        CARDIAC_TEST_MODE=1
    fi
    if [[ "$INSTALL_HUMAN_GEM" -eq 0 && "$INSTALL_CARDIAC" -eq 0 ]]; then
        info "No model acquisition requested (base-only choice LIVEMORE_INSTALL_MODELS=none); any retained cardiac asset remains subject to verification."
        return
    fi
    if [[ "$INSTALL_CARDIAC" -eq 1 ]]; then
        CURRENT_PHASE="pinned cardiac asset verification"
        info "Installing/verifying pinned cardiac CellML and attribution..."
        if ! "$MODEL_SOURCE_DIRECTORY/.venv/bin/python" -I -B -m livemorebio.model_assets install cardiac; then
            # L0-R2: a requested pinned asset is mandatory before activation.
            fail "CARDIAC_MODEL_UNAVAILABLE: cardiac (O'Hara-Rudy CiPA 2017) acquisition failed. Source: https://models.physiomeproject.org/workspace/4e4/rawfile/2c2629a8e2b60c2cde677903e03c9c9be3f39a00/ohara_rudy_cipa_v1_2017.cellml ; pinned SHA-256: ed127e6737611eb1469ea32db0b9d102f0780fc286a29ca88d11d8a868a94175 . Retry, or explicitly choose LIVEMORE_INSTALL_MODELS=none for a base-only installation."
        fi
    fi
    if [[ "$INSTALL_HUMAN_GEM" -eq 1 ]]; then
        CURRENT_PHASE="pinned Human-GEM asset verification"
        info "Installing/verifying pinned Human-GEM v2.0.0 and attribution (about 46 MB, private cache)..."
        "$MODEL_SOURCE_DIRECTORY/.venv/bin/python" -I -B -m livemorebio.model_assets install human-gem
    fi
}

stage_reused_cardiac_upgrade() {
    local original_source="$RELEASE_DIRECTORY/source"
    local cardiac_path="$original_source/$CARDIAC_MODEL_RELATIVE"
    if [[ "$INSTALL_CARDIAC" -ne 1 || -e "$cardiac_path" || -L "$cardiac_path" ]]; then
        return
    fi
    # An active base-only release must never expose the acquired file until
    # the complete asset-enabled gate has passed in detached source.
    [[ ! -L "$original_source/.venv" ]] || fail "Cannot stage a release with a symlinked Python environment."
    MODEL_STAGE_DIRECTORY=$(mktemp -d "$INSTALL_BASE/releases/.$COMMIT.models.XXXXXX")
    MODEL_SOURCE_DIRECTORY="$MODEL_STAGE_DIRECTORY/source"
    CURRENT_PHASE="detached cardiac upgrade preparation"
    "$PYTHON" -I -B - "$original_source" "$MODEL_SOURCE_DIRECTORY" <<'PY'
from pathlib import Path
import shutil
import sys

shutil.copytree(Path(sys.argv[1]), Path(sys.argv[2]), symlinks=True)
PY
    # Reinstall into the COPY of the venv so isolated children resolve staged
    # source too. A parent-only sys.path override would leave those children
    # importing the active editable checkout. No dependency is resolved here.
    "$MODEL_SOURCE_DIRECTORY/.venv/bin/python" -I -B -m pip install \
        --disable-pip-version-check --no-index --no-deps --no-build-isolation \
        -e "$MODEL_SOURCE_DIRECTORY"
}

publish_staged_cardiac_upgrade() {
    [[ -n "$MODEL_STAGE_DIRECTORY" ]] || return 0
    [[ "$(compute_release_digest)" == "$expected_digest" ]] || \
        fail "The original release changed during detached verification; refusing cardiac publication."
    CURRENT_PHASE="verified cardiac asset publication"
    "$PYTHON" -I -B - "$MODEL_SOURCE_DIRECTORY/$CARDIAC_MODEL_RELATIVE" \
        "$RELEASE_DIRECTORY/source/$CARDIAC_MODEL_RELATIVE" "$RELEASE_DIRECTORY/source" <<'PY'
import hashlib
import importlib.util
import os
from pathlib import Path
import stat
import sys
import tempfile

source, destination, original_source = map(Path, sys.argv[1:])
# The original source just passed its recorded full-tree digest. Its manifest
# is authoritative even if a staged payload changed after numerical testing.
spec = importlib.util.spec_from_file_location(
    "livemore_installer_publication_manifest", original_source / "livemorebio" / "model_assets.py"
)
if spec is None or spec.loader is None:
    raise ValueError("Pinned cardiac publication manifest is unavailable.")
manifest_module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = manifest_module
spec.loader.exec_module(manifest_module)
asset = manifest_module.asset_manifest("cardiac")["assets"]["cellml"]
if source.name != asset["filename"] or destination.name != asset["filename"]:
    raise ValueError("Pinned cardiac publication filename differs.")
created = []
temporary = []
try:
    entries = []
    for name in (source.name + ".attribution.json", ".install.lock", source.name):
        candidate = source.parent / name
        descriptor = os.open(candidate, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as handle:
            info = os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid():
                raise ValueError("Staged cardiac entry is not a regular owned file.")
            payload = handle.read(1_048_577)
        if len(payload) > 1_048_576:
            raise ValueError("Staged cardiac entry exceeds its publication bound.")
        if name == source.name and (len(payload) != asset["size_bytes"] or hashlib.sha256(payload).hexdigest() != asset["sha256"]):
            raise ValueError("CARDIAC_MODEL_HASH_MISMATCH: staged cardiac publication differs from the pinned bytes.")
        entries.append((name, payload))
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if destination.parent.is_symlink():
        raise ValueError("Cardiac destination directory must not be a symlink.")
    for name, payload in entries:
        target = destination.parent / name
        if target.exists() or target.is_symlink():
            descriptor = os.open(target, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(descriptor, "rb") as handle:
                info = os.fstat(handle.fileno())
                if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid()
                        or handle.read(1_048_577) != payload):
                    raise ValueError("Existing cardiac entry differs; replacement is refused.")
            continue
        descriptor, temporary_name = tempfile.mkstemp(prefix=".cardiac-publication-", dir=destination.parent)
        staged = Path(temporary_name)
        temporary.append(staged)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.link(staged, target, follow_symlinks=False)
        created.append(target)
        staged.unlink()
        temporary.remove(staged)
except BaseException:
    for path in reversed(created):
        path.unlink()
    raise
finally:
    for path in temporary:
        path.unlink()
PY
    # The staged source and copied venv are installer-owned scratch only.
    rm -rf -- "$MODEL_STAGE_DIRECTORY"
    MODEL_STAGE_DIRECTORY=""
    MODEL_SOURCE_DIRECTORY="$RELEASE_DIRECTORY/source"
}

run_isolated_verification() {
    LIVEMORE_TEST_GENOME_MODELS="$INSTALL_HUMAN_GEM" \
    LIVEMORE_TEST_CARDIAC="$CARDIAC_TEST_MODE" \
    "$PYTHON" -I -B - "$MODEL_SOURCE_DIRECTORY" "$@" <<'PY'
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
# The suite owns its listeners and identities. Review-stack authorities describe
# fixed operator ports and would reject the tests' independently chosen origins.
for name in tuple(verification_env):
    if name.startswith("LIVEMORE_SERVICE_IDENTITY_") or name in (
        "LIVEMORE_AEGLE_URL", "LIVEMORE_LIFE_URL", "LIVEMORE_CENDOS_URL",
        "LIVEMORE_AEGLE_IDENTITY_AUTHORITY", "LIVEMORE_LIFE_IDENTITY_AUTHORITY",
        "LIVEMORE_CENDOS_IDENTITY_AUTHORITY",
    ):
        verification_env.pop(name)
# The install gate must not inherit a caller's test selection or plugin injection.
for pytest_setting in ("PYTEST_ADDOPTS", "PYTEST_PLUGINS"):
    verification_env.pop(pytest_setting, None)
# These two describe the container image to the suite, and are never true of an
# install. Inherited from the caller's shell, the first is refused by the suite
# in a tree that is not an image, and the second takes a tool away from it.
for image_only in ("LIVEMORE_TEST_TREE", "LIVEMORE_TEST_ABSENT_TOOLS"):
    verification_env.pop(image_only, None)
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
if [[ -n "$LOCAL_ARCHIVE" ]]; then
    validate_absolute_path "LIVEMORE_ARCHIVE" "$LOCAL_ARCHIVE"
    [[ -f "$LOCAL_ARCHIVE" && ! -L "$LOCAL_ARCHIVE" ]] || \
        fail "LIVEMORE_ARCHIVE must name a regular file, not a symbolic link."
    validate_commit "$REQUESTED_REF" || \
        fail "LIVEMORE_ARCHIVE requires a full commit in LIVEMORE_REF."
    [[ -n "$PINNED_SHA256" ]] || fail "LIVEMORE_ARCHIVE requires LIVEMORE_SHA256."
fi
validate_model_selection
[[ "$INSTALL_BASE" != "/" && "$INSTALL_BASE" != "$HOME_DIRECTORY" ]] || \
    fail "LIVEMORE_INSTALL_DIR is too broad: $INSTALL_BASE"
[[ "$BIN_DIRECTORY" != "/" && "$BIN_DIRECTORY" != "$HOME_DIRECTORY" ]] || \
    fail "LIVEMORE_BIN_DIR is too broad: $BIN_DIRECTORY"
[[ ! -L "$INSTALL_BASE" ]] || fail "Install root cannot be a symbolic link: $INSTALL_BASE"
[[ ! -L "$BIN_DIRECTORY" ]] || fail "Command directory cannot be a symbolic link: $BIN_DIRECTORY"
if [[ -e "$INSTALL_BASE" && ! -d "$INSTALL_BASE" ]]; then
    fail "Install root exists but is not a directory: $INSTALL_BASE"
fi

if [[ -z "$LOCAL_ARCHIVE" ]]; then
    require_command curl "curl is required to download the LivemoreBio release."
fi
require_command tar "tar is required to unpack the LivemoreBio release."
require_command python3.11 "Python 3.11 is required. Install Python 3.11 and retry."
PYTHON="$(command -v python3.11)"
readonly PYTHON
PYTHON_VERSION="$($PYTHON -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
readonly PYTHON_VERSION
[[ "$PYTHON_VERSION" == "3.11" ]] || \
    fail "Python 3.11 is required; selected interpreter reported $PYTHON_VERSION."

if [[ -n "$REQUESTED_REF" && -z "$LOCAL_ARCHIVE" ]]; then
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
if [[ -n "$LOCAL_ARCHIVE" ]]; then
    SOURCE_ORIGIN="local archive $LOCAL_ARCHIVE"
    COMMIT="$REQUESTED_REF"
elif [[ -n "$REQUESTED_REF" ]]; then
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
MODEL_SOURCE_DIRECTORY="$RELEASE_DIRECTORY/source"
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
    stage_reused_cardiac_upgrade
    install_reference_models
    if [[ "$CARDIAC_TEST_MODE" -eq 1 ]]; then
        CURRENT_PHASE="pinned cardiac execution verification"
        info "Running the complete release test suite before cardiac-capability activation..."
        run_isolated_verification
        publish_staged_cardiac_upgrade
        # The cardiac acquisition is inside the release's fixed model path.
        # Admit those bytes into its digest only after the full suite passes.
        temporary_integrity="$INTEGRITY_DIRECTORY/.$COMMIT.$$"
        [[ ! -e "$temporary_integrity" && ! -L "$temporary_integrity" ]] || \
            fail "Temporary release integrity path already exists: $temporary_integrity"
        compute_release_digest >"$temporary_integrity"
        replace_path_atomically "$temporary_integrity" "$INTEGRITY_PATH"
    elif [[ "$INSTALL_HUMAN_GEM" -eq 1 ]]; then
        CURRENT_PHASE="pinned Human-GEM execution verification"
        info "Checking numerical execution before full-capability activation..."
        run_isolated_verification livemorebio/tests/test_stoichiometry_integration.py
    fi
else
    CURRENT_PHASE="inactive release creation"
    mkdir "$RELEASE_DIRECTORY"
    OWNED_RELEASE_DIRECTORY="$RELEASE_DIRECTORY"
    readonly ARCHIVE_PATH="$RELEASE_DIRECTORY/source.tar.gz"
    readonly SOURCE_DIRECTORY="$RELEASE_DIRECTORY/source"
    mkdir -p "$SOURCE_DIRECTORY"

    info "Acquiring the source archive ($SOURCE_ORIGIN)..."
    if [[ -n "$LOCAL_ARCHIVE" ]]; then
        cp "$LOCAL_ARCHIVE" "$ARCHIVE_PATH"
    elif [[ -n "$REQUESTED_REF" ]]; then
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
    run_isolated_verification

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
