# LivemoreBio — Installation and Use

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

```bash
curl -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/livemorebio-stable.tar.gz | tar -xz
cd livemorebio-*/
```

On Windows PowerShell:

```powershell
curl.exe -fsSLO https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/livemorebio-stable.tar.gz
tar -xzf livemorebio-stable.tar.gz
cd (Get-ChildItem -Directory livemorebio-*)[0]
```

### Step 2 — Create three secrets

These stay on your machine. Never commit them or email them.

macOS / Linux:

```bash
export LIVEMORE_API_TOKEN=$(openssl rand -hex 32)
export LIVEMORE_PATCH_STORAGE_KEY=$(openssl rand -base64 32 | tr '+/' '-_')
export LIVEMORE_PATCH_ADMISSION_HMAC_KEY=$(openssl rand -base64 32 | tr '+/' '-_')
```

Windows PowerShell:

```powershell
$env:LIVEMORE_API_TOKEN = -join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
$env:LIVEMORE_PATCH_STORAGE_KEY = [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Max 256 })).Replace('+','-').Replace('/','_')
$env:LIVEMORE_PATCH_ADMISSION_HMAC_KEY = [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Max 256 })).Replace('+','-').Replace('/','_')
```

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

```bash
curl -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/install.sh | bash
```

That is the whole install. The installer downloads the published release over
HTTPS, checks it against the release checksum before unpacking anything,
creates its own isolated Python environment, downloads the pinned scientific
reference models, runs the full test suite against a throwaway data directory,
and only then activates the `livemore` command.

If any step fails it stops, tells you which one, and leaves your previous
install untouched — it never half-installs.

Expect several minutes; most of that is the verification suite.

**To pin the exact build** (recommended if you were sent a checksum):

```bash
curl -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/install.sh \
  | LIVEMORE_SHA256=<the checksum we gave you> bash
```

The install refuses if the downloaded archive does not match.

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
  ● up   LIFE    :8851   20 diseases · 172 risk loci
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

```bash
curl -fsS -X POST -H "Authorization: Bearer $(livemore token)" \
  -H 'Content-Type: application/json' \
  -d '{"conditions":[
        {"condition_id":"normoxia","glucose_uptake":1.0,"oxygen_uptake":1.0},
        {"condition_id":"hypoxia","glucose_uptake":1.0,"oxygen_uptake":0.15}]}' \
  http://127.0.0.1:8852/protocols/human-gem-oxygen-capacity
```

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
RUN=$(curl -fsS -H "Authorization: Bearer $(livemore token)" \
      http://127.0.0.1:8852/protocols/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["run_id"])')

curl -fsS -H "Authorization: Bearer $(livemore token)" \
  "http://127.0.0.1:8852/protocols/$RUN/analysis.ipynb" -o analysis.ipynb

curl -fsS -H "Authorization: Bearer $(livemore token)" \
  "http://127.0.0.1:8852/protocols/$RUN/analysis.csv" -o analysis.csv
```

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
