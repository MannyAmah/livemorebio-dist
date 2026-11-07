# LivemoreBio — Installation and Use

This guide covers stable maintenance release **0.1.0**. After installation,
run `livemore --version` to see the installed product version; this release
prints `LivemoreBio 0.1.0` without starting or contacting a service. For a
running Docker stack, use `docker compose exec aegle livemore --version`.

A guide for evaluating LivemoreBio on your own computer. It takes about
15 minutes, most of which is unattended.

Everything in this guide was run end to end on macOS, from a clean install on
an empty home directory. The sample outputs are real, not illustrations.

---

## 1. Which path do I use?

| Your computer | Use |
|---|---|
| Windows | **Path A — Docker** |
| macOS | Path A, or **Path B — native** |
| Linux | Path A, or Path B |

**Windows is not supported natively, on purpose.** LivemoreBio protects local
health-like data with owner-only file permissions that Windows cannot express.
Rather than pretend, it refuses to run and tells you to use Docker. Docker on
Windows gives you the identical product.

---

## 2. Path A — Docker (works on every operating system)

**You need:** Docker Desktop. Nothing else — no GitHub account, no `git`.

### Step 1 — Get the code

Ask the release author for the expected SHA-256 through a separately verified
channel. Set `LIVEMORE_SHA256` to that independently supplied 64-character digest
(`export LIVEMORE_SHA256='...'` in Bash, `$env:LIVEMORE_SHA256 = '...'` in
PowerShell). Do not derive it from the archive or a checksum served by the
same download origin. Start in a new empty directory; stop if verification
fails. A matching checksum binds the archive to your chosen digest; it does
not authenticate the download instructions or establish a signing identity.

```bash
(
  set -euo pipefail
  : "${LIVEMORE_SHA256:?Set LIVEMORE_SHA256 to the independently supplied release digest.}"
  [[ $LIVEMORE_SHA256 =~ ^[0-9a-fA-F]{64}$ ]] || { printf '%s\n' 'Invalid release digest.' >&2; exit 1; }
  archive=livemorebio-stable.tar.gz
  curl -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/livemorebio-stable.tar.gz -o "$archive" || exit $?
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum < "$archive") || exit $?
  else
    actual=$(shasum -a 256 < "$archive") || exit $?
  fi
  expected=$(printf '%s' "$LIVEMORE_SHA256" | tr 'A-F' 'a-f') || exit $?
  [[ ${actual%% *} == "$expected" ]] || { printf '%s\n' 'Archive checksum mismatch; refusing extraction.' >&2; exit 1; }
  tar -xzf "$archive" || exit $?
) && cd livemorebio-*/
```

On Windows PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
if ($env:LIVEMORE_SHA256 -notmatch '\A[0-9a-fA-F]{64}\z') { throw 'Set LIVEMORE_SHA256 to the independently supplied release digest.' }
curl.exe -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/livemorebio-stable.tar.gz -o livemorebio-stable.tar.gz
if ($LASTEXITCODE -ne 0) { throw 'Archive download failed.' }
$actual = (Get-FileHash -LiteralPath livemorebio-stable.tar.gz -Algorithm SHA256).Hash
if ($actual -cne $env:LIVEMORE_SHA256.ToUpperInvariant()) { throw 'Archive checksum mismatch; refusing extraction.' }
tar -xzf livemorebio-stable.tar.gz
if ($LASTEXITCODE -ne 0) { throw 'Archive extraction failed.' }
cd (Get-ChildItem -Directory livemorebio-*)[0]
```

### Step 2 — Create four independent secrets

These stay on your machine. Never commit them or email them.

macOS / Linux:

```bash
export LIVEMORE_API_TOKEN=$(openssl rand -hex 32)
export LIVEMORE_PATCH_STORAGE_KEY=$(openssl rand -base64 32 | tr '+/' '-_')
export LIVEMORE_PATCH_ADMISSION_HMAC_KEY=$(openssl rand -base64 32 | tr '+/' '-_')
export LIVEMORE_SERVICE_IDENTITY_KEY=$(openssl rand -base64 32 | tr '+/' '-_')
```

Windows PowerShell:

```powershell
function New-LivemoreKey {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_')
}
$env:LIVEMORE_API_TOKEN = New-LivemoreKey
$env:LIVEMORE_PATCH_STORAGE_KEY = New-LivemoreKey
$env:LIVEMORE_PATCH_ADMISSION_HMAC_KEY = New-LivemoreKey
$env:LIVEMORE_SERVICE_IDENTITY_KEY = New-LivemoreKey
```

The identity key uses canonical padded URL-safe base64 for exactly 32 random
bytes, without whitespace or a newline in the environment. Hex is not admitted
for this key. Preserve all four values privately for later restarts of this stack.
The extracted release's `docs/LAUNCH_GUIDE.md` explains identity rotation.

### Step 3 — Start it

```bash
docker compose up -d
```

First run downloads and builds; later runs take seconds.

### Step 4 — Check it is alive

```bash
curl -fsS http://127.0.0.1:8850/health
```

Then open <http://127.0.0.1:8850> in your browser.

**To stop:** `docker compose down`. Add `-v` to also erase all stored data.

---

## 3. Path B — Native install (macOS, Linux, WSL2)

**You need one thing:** **Python 3.11**.

```bash
python3.11 --version     # must print 3.11.x
```

If it does not: macOS `brew install python@3.11`; Ubuntu/Debian
`sudo apt install python3.11 python3.11-venv`.

No GitHub account, no `git`, no login, no Node.js.

Node.js is optional. With it installed, the browser-console diagnostics run as
well; without it they are skipped and everything else — the twins, the
programs, the metabolic engine, the notebooks — works exactly the same.

### Install

At each release go, the author publishes the installer SHA-256, archive SHA-256
and distribution commit on both a release in the **Livemore-Biosciences
organisation on GitHub** and a page on **livemorebiosciences.com**. These channels
must be independently administered from the GitHub account that owns the
download repository. Users may check either channel; the installer and archive
digests must match on both, as must the distribution commit. Stop if they differ.

The author fills the five placeholders below at the go in externally served
guides and the weekly workflow. For a bundled guide, replace the placeholders
with the published URLs and values before installation. Confirm the release
values against either channel before running this block. Do not take the expected
digests from the installer, archive or `stable.json` on the download host.
Unfilled placeholders, download failures and checksum mismatches stop before
the installer runs. L0 uses these digests without release signing (F-06).

```bash
(
  set -euo pipefail
  org_release_url='{ORG_RELEASE_URL}'
  livemorebiosciences_url='{LIVEMOREBIOSCIENCES_URL}'
  installer_sha256='{INSTALLER_SHA256}'
  archive_sha256='{ARCHIVE_SHA256}'
  dist_commit='{DIST_COMMIT}'
  [[ $org_release_url == https://github.com/Livemore-Biosciences/*/releases/* && $org_release_url != *'{'* && $org_release_url != *'}'* ]] || { printf '%s\n' 'Set the Livemore-Biosciences GitHub release URL.' >&2; exit 1; }
  [[ $livemorebiosciences_url == https://livemorebiosciences.com/* && $livemorebiosciences_url != *'{'* && $livemorebiosciences_url != *'}'* ]] || { printf '%s\n' 'Set the livemorebiosciences.com release page URL.' >&2; exit 1; }
  [[ $installer_sha256 =~ ^[0-9a-fA-F]{64}$ && $archive_sha256 =~ ^[0-9a-fA-F]{64}$ ]] || { printf '%s\n' 'Set both published SHA-256 digests.' >&2; exit 1; }
  [[ $dist_commit =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'Set the published distribution commit.' >&2; exit 1; }
  archive_sha256=$(printf '%s' "$archive_sha256" | tr 'A-F' 'a-f') || exit $?
  installer_file=$(mktemp) || exit $?
  trap 'rm -f "$installer_file"' EXIT
  curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 \
    "https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/$dist_commit/install.sh" >"$installer_file" || exit $?
  test -s "$installer_file" || { printf '%s\n' 'Empty installer; refusing execution.' >&2; exit 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum < "$installer_file") || exit $?
  else
    actual=$(shasum -a 256 < "$installer_file") || exit $?
  fi
  actual=${actual%% *}
  expected=$(printf '%s' "$installer_sha256" | tr 'A-F' 'a-f') || exit $?
  [[ $actual == "$expected" ]] || { printf '%s\n' 'Installer checksum mismatch; refusing execution.' >&2; exit 1; }
  LIVEMORE_SHA256="$archive_sha256" bash "$installer_file"
)
```

After its own digest is verified, the installer downloads the published release over
HTTPS, checks it against the release checksum before unpacking anything,
creates its own isolated Python environment, downloads the pinned scientific
reference models, runs the full test suite against a throwaway data directory,
and only then activates the `livemore` command.

If any step fails it stops, tells you which one, and leaves your previous
install untouched — it never half-installs.

Expect several minutes; most of that is the verification suite.

If `livemore` is not found afterwards, open a new terminal, or add
`~/.local/bin` to your `PATH`.

### Check it

```bash
livemore doctor
```

You want the last line to read `READY`. This checks Python packages, the
reference models, the data directory's permissions, your keys, and each
service. It exits non-zero if anything required is missing, so it is safe to
use in a script.

---

## 4. Start the product

```bash
livemore start      # starts all three services
livemore status     # shows what is up
livemore open       # opens the console in your browser
```

You should see:

```
  LivemoreBio infrastructure
  ----------------------------------------------------
  ● up   LIFE    :8851   20 diseases · 309 associated genes
  ● up   Aegle   :8850   twin: 
  ● up   Cendos  :8852   in-silico assays ready
  ----------------------------------------------------
```

Three services, each with one job:

- **Aegle** (:8850) — the digital twins, and the console you look at
- **LIFE** (:8851) — the patch / continuous-monitoring side
- **Cendos** (:8852) — the in-silico lab where experiments run

Stop everything with `livemore stop`.

---

## 5. Using it — five worked examples

Every output below is real output from this software.

### Example 1 — What can and cannot be run

```bash
livemore programs list
```

Six programs, and each one tells you its own state:

| Program | What it is | Result |
|---|---|---|
| Exogenous insulin | rapid-acting analogue | runs |
| LBHR-030 Burdock | arctigenin | runs |
| LBHR-135 Bilberry | cyanidin-3-glucoside | runs at the studied dose |
| LBHR-172 Lion's Mane | erinacine A | exposure only |
| LBHR-129 Yerba Santa | sterubin | blocked, reason given |
| LBHR-062 Rosemary | carnosic acid | blocked, reason given |

**The refusals are the product, not a gap.** When LivemoreBio cannot answer a
question from admitted evidence, it says which measurement is missing instead
of producing a plausible-looking number. You should test this deliberately.

### Example 2 — Run an insulin experiment

```bash
livemore programs run insulin --cohort 12 --seed 0
```

Twelve simulated people, each their own paired control and treated arm from an
identical starting state:

```json
"summary": {
  "member_count": 12,
  "mean_delta_glucose_auc_mmol_L_min": -1700.421,
  "delta_glucose_auc_range": [-2975.87, -937.221],
  "members_with_any_time_below_3_9_treated": 1
}
```

One of twelve went below 3.9 mmol/L — the hypoglycaemia threshold. The model
surfaces that rather than reporting only the average benefit.

Alongside every result you get:

```json
"evidence_state": "MODELED_ONLY",
"qualification_state": "NOT_QUALIFIED",
"applicability": "Insulin-deficient physiology only: the model has no
                  endogenous insulin secretion."
```

### Example 3 — See a refusal that names its own blocker

```bash
livemore programs run LBHR-135 --dose-mg 100
```

```json
"outcome": "EXPOSURE_NOT_COMPUTABLE",
"reason_code": "DOSE_NOT_MEASURED_AT_THIS_LEVEL",
"missing_measurement": "Measured human exposure exists only for the 500 mg dose
  in the cited study. Requesting 100 mg would require scaling a measured peak
  concentration through a kinetic model, which this program does not have."
```

Now ask the question the evidence can actually answer:

```bash
livemore programs run LBHR-135 --dose-mg 500
```

```json
"outcome": "REACHES_MEASURED_ACTIVE_RANGE",
"summary": {
  "unbound_cmax_um": 0.141,
  "margin_to_active_low": 1.41,
  "margin_at_one_standard_error_below_cmax": 0.71,
  "robust_to_one_standard_error": false
}
```

Read that last line carefully. The compound *does* reach its active range — the
margin is 1.41 — but drop one standard error and the margin falls to 0.71, i.e.
below the range. So the answer is "yes, and it is not robust", and the software
says the second half out loud.

Same program, same data, different question — and the difference between the
two answers is stated rather than hidden.

### Example 4 — A real metabolic calculation

This one solves a genome-scale model of human metabolism: 12,931 reactions,
8,461 metabolites, 2,848 genes. It asks how much ATP the network can make when
oxygen is restricted but glucose is not.

Run API examples from the extracted release directory with the Python environment
used for LivemoreBio. The helper proves the peer before sending credentials and
reads the existing token and identity configuration. These are technical
computational inputs, not physical measurements.

```bash
python3 tools/stack_request.py --role cendos --method POST \
  --url http://127.0.0.1:8852/protocols/human-gem-oxygen-capacity --expect-status 201 \
  --json '{"conditions":[{"condition_id":"normoxia","glucose_uptake":1.0,"oxygen_uptake":1.0},{"condition_id":"hypoxia","glucose_uptake":1.0,"oxygen_uptake":0.15}]}'
```

For a container-only install, use `docker compose exec -T cendos python` in place
of `python3`, and use `http://cendos:8852` as the URL origin. PowerShell users can
supply the payload with `--json-file` from a UTF-8 file inside the container.

| Condition | ATP capacity | Oxygen | Glucose |
|---|---|---|---|
| normoxia | **7.00** mmol/gDW/h | 1.00 | 1.00 |
| hypoxia | **2.75** mmol/gDW/h | 0.15 | 1.00 |

Restrict the oxygen and ATP capacity falls by about 60% on identical glucose —
the cell is pushed off oxidative phosphorylation toward the much lower
glycolytic yield. Takes about 16 seconds.

The result carries its own limits:

```json
"claims_allowed":   ["conditional stoichiometric ATP capacity",
                     "numerical conservation and constraint checks"],
"claims_prohibited": ["measured human response", "ATP concentration",
                      "unique flux prediction", "drug efficacy",
                      "patient-specific physiology", "clinical validation"]
```

### Example 5 — Open any result in Jupyter

Every run can be reopened as a notebook with the numbers frozen in:

```bash
livemore notebook
```

Or download a specific run:

```bash
RUN=$(python3 tools/stack_request.py --role cendos --method GET \
      --url http://127.0.0.1:8852/protocols/latest --expect-status 200 | python3 -c 'import json,sys;print(json.load(sys.stdin)["run_id"])')

python3 tools/stack_request.py --role cendos --method GET \
  --url "http://127.0.0.1:8852/protocols/$RUN/analysis.ipynb" --expect-status 200 > analysis.ipynb

python3 tools/stack_request.py --role cendos --method GET \
  --url "http://127.0.0.1:8852/protocols/$RUN" --expect-status 200 > run.json
python3 -c 'import json,sys; from livemorebio.cendos.protocol_runs import analysis_csv; sys.stdout.buffer.write(analysis_csv(json.load(sys.stdin.buffer)).encode("utf-8"))' < run.json > analysis.csv
```

The helper accepts JSON responses. CSV is therefore generated locally from the
proved saved result with the same exporter used by the service.
The shell redirects the input and output files on the host, including when the
exporter runs with `docker compose exec -T cendos python`.

The notebook reproduces the recorded result rather than recomputing it, so what
you review is what the system actually produced.

---

## 6. What to check if you are evaluating us

1. **Try to make it lie.** Ask for a dose nobody measured, a compound with no
   pharmacokinetic source, a twin with no admitted model. Every one should
   refuse with a reason code and a named missing measurement.
2. **Read the `controls` block** on any result. A zero-dose arm must reproduce
   the untreated arm exactly, and conservation identities must hold. These run
   on every execution, not on request.
3. **Read `evidence_state` and `qualification_state`.** Today everything is
   `MODELED_ONLY` and `NOT_QUALIFIED`. Nothing here claims otherwise.
4. **Check the provenance.** Every number carries the model's pinned commit and
   SHA-256, the solver and its version, and the literature citation behind each
   parameter.

---

## 7. If something goes wrong

| What you see | What to do |
|---|---|
| `livemore: command not found` | Open a new terminal, or add `~/.local/bin` to `PATH` |
| `doctor` is not `READY` | It names the failing check; fix that one thing and re-run |
| `PATCH_JOURNAL_INVALID` | `livemore patch-journal verify`, then `quarantine --apply` |
| `PATCH_BINDING_REQUIRED` | Bind the device to the twin before streaming |
| A service will not start | `livemore stop` then `livemore start`; logs are in `~/.livemore/<Service>.log` |
| Windows refuses to install | Expected — use Docker (Path A) |

Diagnostics for a support request:

```bash
livemore doctor --json > doctor.json
```

Safe to send: it reports check outcomes, never your data.

---

## 8. What this is, and what it is not

LivemoreBio is research infrastructure for precision medicine. It models human
physiology from published sources and states exactly how far each result can be
trusted.

**It is not** a medical device, clinical decision support, or dosing guidance.

The six programs are **0 of 6 validated in vivo**. Physical LIFE Patch hardware
and the Cendos wet lab do not exist yet. No output in this product is a
measurement taken from a person, and the software will tell you so on every
single result.

---

## Command reference

| Command | Does |
|---|---|
| `livemore doctor` | Readiness check; `READY` when good |
| `livemore start` / `stop` / `status` | Run the services |
| `livemore open` | Console in your browser |
| `livemore programs list` | The six programs and their state |
| `livemore programs run <id>` | Run one |
| `livemore notebook` | Jupyter with the SDK wired up |
| `livemore workspace` | Current twin and model selection |
| `livemore token` | API token for `curl` |
| `livemore patch-journal verify` | Check the telemetry journal |
| `livemore models status human-gem` | Reference model state |
