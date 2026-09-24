# LivemoreBio

Research infrastructure for precision medicine. It models human physiology from
published sources, and states exactly how far each result can be trusted.

**This is not a medical device, not clinical decision support, and not dosing
guidance.** Nothing it produces is a measurement taken from a person, and the
software says so on every result.

---

## Install

You need **Python 3.11**. Nothing else — no account, no `git`, no Node.js.

```bash
curl -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/install.sh | bash
```

The installer downloads the published release over HTTPS, verifies its SHA-256
**before unpacking anything**, builds its own isolated Python environment,
fetches the pinned scientific reference models, runs the full test suite against
a throwaway data directory, and only then activates the `livemore` command.

If any step fails it stops, names the step, and leaves any previous install
untouched. It never half-installs.

Expect several minutes; most of that is the verification suite.

### Pin the exact build

Every release publishes a checksum. Pinning it means the install refuses
anything that is not bit-for-bit what we published:

```bash
curl -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/install.sh \
  | LIVEMORE_SHA256=<checksum from the release notes> bash
```

### Windows

Windows is refused natively, on purpose: LivemoreBio protects local
health-like data with owner-only file permissions that Windows cannot express.
Rather than pretend, it stops and tells you to use Docker, which gives you the
identical product.

```bash
curl -fsSL https://raw.githubusercontent.com/MannyAmah/livemorebio-dist/main/livemorebio-stable.tar.gz | tar -xz
cd livemorebio-*/
docker compose up -d
```

See [INSTALL.md](INSTALL.md) for the full walkthrough, including the three
secrets Docker needs.

---

## First five minutes

```bash
livemore doctor          # readiness; the last line should read READY
livemore start           # Aegle :8850 · LIFE :8851 · Cendos :8852
livemore open            # the console
livemore programs list   # what can and cannot be run, and why
```

---

## What it does

Three services, each with one job:

| Service | Port | Role |
|---|---|---|
| **Aegle** | 8850 | the biological digital twins, and the console |
| **LIFE** | 8851 | the patch and continuous-monitoring side |
| **Cendos** | 8852 | the in-silico lab where experiments run |

### The refusals are the product

Ask a question the evidence cannot answer and LivemoreBio tells you which
measurement is missing, rather than returning a plausible-looking number:

```console
$ livemore programs run LBHR-135 --dose-mg 100
outcome=EXPOSURE_NOT_COMPUTABLE  reason=DOSE_NOT_MEASURED_AT_THIS_LEVEL
missing: Measured human exposure exists only for the 500 mg dose in the cited
study. Requesting 100 mg would require scaling a measured peak concentration
through a kinetic model, which this program does not have.
```

Ask the question the evidence *can* answer:

```console
$ livemore programs run LBHR-135 --dose-mg 500
outcome=REACHES_MEASURED_ACTIVE_RANGE
margin_to_active_low=1.41  margin_at_one_standard_error_below_cmax=0.71
robust_to_one_standard_error=False
```

Read that last field. The compound does reach its active range — and one
standard error below, it does not. The answer is "yes, and it is not robust",
and both halves are stated.

### Real computation, not lookup tables

The metabolic engine solves a genome-scale model of human metabolism — 12,931
reactions, 8,461 metabolites, 2,848 genes — under explicit constraints:

| Condition | ATP capacity | Oxygen | Glucose |
|---|---|---|---|
| normoxia | 7.00 mmol/gDW/h | 1.00 | 1.00 |
| hypoxia | 2.75 mmol/gDW/h | 0.15 | 1.00 |

Restrict oxygen and ATP capacity falls ~60% on identical glucose, as the
network is pushed off oxidative phosphorylation toward the lower glycolytic
yield. Roughly 16 seconds, GLPK, mass-balance residual ~1e-15.

Every result carries what may and may not be claimed from it:

```json
"claims_allowed":    ["conditional stoichiometric ATP capacity",
                      "numerical conservation and constraint checks"],
"claims_prohibited": ["measured human response", "ATP concentration",
                      "unique flux prediction", "drug efficacy",
                      "patient-specific physiology", "clinical validation"]
```

---

## Evidence status

Everything here is `MODELED_ONLY` and `NOT_QUALIFIED`.

The six reference programs are **0 of 6 validated in vivo**. Physical LIFE Patch
hardware and the Cendos wet lab do not exist yet. Where a program cannot be run
from admitted evidence, it refuses and names the missing measurement — that is
the intended behaviour, not a gap in a demo.

---

## What is in this repository

This is the **distribution** repository: the installer, the published release
archive, its checksum, and the documentation a user needs.

Development happens in a separate private repository. Internal material —
recorded walkthroughs, deliverable decks, QA screenshot evidence — is not
published here. The archive contains the runnable product and its complete test
suite, so an installed copy verifies itself exactly as we do.

| File | What it is |
|---|---|
| `install.sh` | the installer |
| `stable.json` | channel manifest: commit and checksum |
| `livemorebio-stable.tar.gz` | the current release archive |
| `livemorebio-<commit>.tar.gz` | an immutable build you can pin forever |
| `INSTALL.md` | full installation and usage guide |

---

## Support

Open an issue here for installation problems. Include the output of:

```bash
livemore doctor --json > doctor.json
```

That reports check outcomes only — never your data.

---

## Licence

See [LICENSE](LICENSE).
