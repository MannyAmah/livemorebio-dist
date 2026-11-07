# Third-party notices

This file indexes the third-party data and software used by this distribution. The LivemoreBio [MIT licence](LICENSE) covers Livemore-authored work;
it does not replace an upstream licence. Full notices beside bundled JavaScript
and source/citation records beside scientific assets are part of the distribution
and must be retained together.

Creative Commons full terms: [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode),
[CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/legalcode),
[CC-BY-3.0](https://creativecommons.org/licenses/by/3.0/legalcode),
[CC-BY-SA-3.0](https://creativecommons.org/licenses/by-sa/3.0/legalcode), and
[CC-BY-SA-2.1-JP](https://creativecommons.org/licenses/by-sa/2.1/jp/legalcode).

**Verification date:** 2026-10-04. Source terms below identify provider pages;
EFO terms are attributed to the Open Targets licence table. Upstream source
rights remain separate from Livemore's MIT licence.

## Offline reference seed

The matching JSON files in `livemorebio/life_system/reference/seed/` and
`livemorebio/life_system/seed/` are the same curated reference slice. Their
`meta.json` files record source releases, acquisition receipts, output hashes,
licence checks and explicit limitations. Livemore transforms upstream records
into its JSON schema. Disease identities come from exact Disease Ontology terms;
gene identities come from HGNC; gene–disease records are **associations**, not
causation, effect sizes or individual risk estimates.

Open Targets **26.09**, retrieved **2026-10-04**, supplies current direct
associations and drug identities through its public API. Each record retains
the query, release, retrieval date and response digest. Disease Ontology IDs
remain the disease identity keys, with verified current Open Targets mappings.
Datatype scores follow the 26.09 API taxonomy; counts unavailable from that API
are explicitly unavailable, not zero. Drug/indication association evidence may also originate from ChEMBL, beyond
the separate drug-name slice; source terms apply to both uses.

| Source / bundled content | Verified terms, attribution and scope |
| --- | --- |
| **Reactome**, pathway identifiers/names | **CC0-1.0 for database data and derived data files**, https://reactome.org/license (checked 2026-10-04). Credit Reactome and contributing authors. Software terms and CC BY 4.0 illustrations are separate; no illustrations are copied into this seed. |
| **Open Targets Platform**, association scores and metadata | **CC0-1.0**, https://platform-docs.opentargets.org/licence (checked 2026-10-04). Credit Open Targets Platform and contributing providers. CC0 marks Open Targets' own data; upstream source terms below remain recorded alongside it. No underlying publications are redistributed. |
| **ChEMBL / EMBL-EBI**, drug identifiers and preferred names via Open Targets | **CC-BY-SA-3.0**, https://www.ebi.ac.uk/chembl/ and the Open Targets licence table (checked 2026-10-04). Credit ChEMBL, EMBL-EBI and contributors. Livemore's selected identifier/name rows are normalized from Open Targets API drug records; this transformed ChEMBL slice remains CC BY-SA 3.0. Open Targets 26.09 uses **ChEMBL 37**; its configuration URL and response digest are recorded in seed metadata. Cite the ChEMBL release DOI https://doi.org/10.6019/CHEMBL.database.37 . The historical ChEMBL 34 release is https://doi.org/10.6019/CHEMBL.database.34 . |
| **Experimental Factor Ontology (EFO)**, identifiers and reviewed clinical synonyms through Open Targets | **Apache-2.0**, https://platform-docs.opentargets.org/licence (checked 2026-10-04). Credit EFO / EMBL-EBI, https://www.ebi.ac.uk/efo/ . Selected identifier and synonym facts only; no full ontology is bundled. |
| **Mondo Disease Ontology**, identifiers and reviewed clinical synonyms through Open Targets | **CC-BY-4.0**, https://raw.githubusercontent.com/monarch-initiative/mondo/master/LICENSE and the Open Targets licence table (checked 2026-10-04). Credit Mondo and the Monarch Initiative, https://mondo.monarchinitiative.org/ . Selected identifier and synonym facts only; no full ontology is bundled. |
| **HGNC / HUGO Gene Nomenclature Committee**, gene symbols, names and identifiers | **CC0-1.0**, https://www.genenames.org/about/license/ (checked 2026-10-04). Credit Seal et al., “Genenames.org: the HGNC resources in 2023,” https://doi.org/10.1093/nar/gkac888 . Identity normalization supplies no expression or pharmacological effects. |
| **Disease Ontology**, labels, identifiers, definitions and synonyms via EMBL-EBI OLS | **CC0-1.0**, https://raw.githubusercontent.com/DiseaseOntology/HumanDiseaseOntology/main/LICENSE (checked 2026-10-04). Credit Disease Ontology, https://disease-ontology.org/ , and OLS, https://www.ebi.ac.uk/ols4/ . EBI hosting is not itself the ontology licence. |
| **Human Reference Atlas / HuBMAP**, inherited organ labels | **CC-BY-4.0** for the provider-listed HuBMAP APIs, SmartAPI and CCF 3D Reference Object Library (data), https://docs.hubmapconsortium.org/faq.html (checked 2026-10-04). Credit Human Reference Atlas, https://humanatlas.io/ , Börner et al.; reference-organ creators Browne, Cross, Herr II, Record, Quardokus, Bueckle and Börner. Livemore retains normalized organ labels, not geometry, in this seed. |
| **Human Cell Atlas / Azul**, inherited catalog names and project counts | **CC-BY-4.0**, https://data.humancellatlas.org/about/data-use-agreement (checked 2026-10-04). Credit Human Cell Atlas contributors and Azul, https://www.humancellatlas.org/ and https://service.azul.data.humancellatlas.org/ . The provider scopes its grant to the release's datasets; future releases can differ. Only normalized public catalog metadata is retained here. |
| **RCSB PDB**, inherited entry summaries | **CC0-1.0 explicitly covering programmatic API data**, https://www.rcsb.org/pages/usage-policy (checked 2026-10-04). Credit RCSB PDB and depositing authors. This does not license articles or unrelated third-party content. |
| **NHGRI-EBI GWAS Catalog**, inherited association/risk-allele facts and derived weights | **EMBL-EBI Terms of Use**, https://www.ebi.ac.uk/gwas/docs/about and https://www.ebi.ac.uk/about/terms-of-use (checked 2026-10-04). EMBL-EBI adds no restrictions beyond those of contributing data owners and expects attribution; only summary statistics are expressly CC0 unless stated otherwise. Credit Cerezo et al., *Nucleic Acids Research* 53(D1), 2025, D998–D1005, https://doi.org/10.1093/nar/gkae1070 , as requested by https://www.ebi.ac.uk/gwas/docs/citation . Retrieved on or before 2026-07-11. Livemore normalizes these factual association values; they do not establish person-specific causal effects. |

The inherited `anatomy.json`, `structures.json` and `gwas.json` bytes remain
unchanged. They were retrieved **on or before 2026-07-11 (commit 78a70d8)**;
exact acquisition dates and release numbers are unknown. The current policy
checks do not invent historical per-record receipts. A receipt-bearing refresh
is a separate scientifically reviewed change, particularly for GWAS values used
by calibration. Underlying GWAS study/trait receipts remain incomplete and the
research scores do not claim scientific qualification.

The previous KEGG disease descriptions, categories, gene lists and pathway names
are absent. Human Protein Atlas enrichment is not distributed, and the old
Orphanet source-list claim has been removed. Search has reduced annotation
coverage; an empty annotation does not mean biological absence. Reactome pathway
nodes do not establish gene membership. Optional commercial connectors remain
licence-gated; catalog membership is not dataset admission.

## PDB archive coordinate references

The seven unchanged coordinate files in
`livemorebio/scientific_sources/data/molecular/` are original PDB archive material,
recorded under **CC0-1.0** at https://www.wwpdb.org/about/usage-policies
(checked 2026-10-04). Credit
**wwPDB, RCSB PDB, the depositing authors and the original structure publications**.
The accompanying `catalog.json` retains exact hashes, revision dates, authors,
source URLs, full citation records and reference-only limitations. Those records
must remain with the coordinate files.

| File | Depositing-author credit / publication |
| --- | --- |
| `1M17.cif` | Stamos, Sliwkowski and Eigenbrot; https://doi.org/10.1074/jbc.M207135200 |
| `1N7D.cif` | Rudenko, Henry, Henderson, Ichtchenko, Brown, Goldstein and Deisenhofer; https://doi.org/10.1126/science.1078124 |
| `1TUP.cif` | Cho, Gorina, Jeffrey and Pavletich; PubMed 8023157 (complete citation retained in catalog) |
| `4INS.cif` | Dodson, Dodson, Hodgkin, Isaacs and Vijayan; PubMed 2905485 (complete deposition and publication author lists retained in catalog) |
| `4OBE.cif` | Hunter, Gurbani, Chen and Westover; https://doi.org/10.1073/pnas.1404639111 |
| `5VA2.cif` | Wang and MacKinnon; https://doi.org/10.1016/j.cell.2017.03.048 |
| `6P2B.cif` | Walton, Pellock and Redinbo; https://doi.org/10.1021/acs.jmedchem.0c00012 |

CC0 here concerns archive coordinate material. It does not license the associated
journal articles, figures, DrugBank records or unrelated annotations.

## Anatomical source declarations and catalog metadata

`livemorebio/anatomy/atlas/bp3d-4.0-20130619-surface-core-v1.json` contains a pinned
**BodyParts3D** source declaration and mapping metadata, not its geometry archive.
Credit: **BodyParts3D, The Database Center for Life Science (DBCLS)**,
https://lifesciencedb.jp/bp3d/ . The declaration records current publisher
**CC-BY-4.0** and retains the embedded historical **CC-BY-SA-2.1-JP** notice as a
separate fact. The current publisher page, https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html
(updated 2025-02-27, checked 2026-10-04), specifies **CC-BY-4.0**.
Required credit: “BodyParts3D, © The Database Center for Life Science licensed
under CC Attribution 4.0 International”. Preserve the historical notice, source links and transformation
records. Geometry is acquired separately, with source-specific provenance and
attribution; geometry is not bundled in this archive.

The authored `livemorebio/anatomy/ontology/` scaffold cites HRA/HuBMAP, anatomical
ontologies and other resources in its `authoritative_resources` list. It is not a
bundled full release of those upstream ontologies. Do not infer an upstream
ontology licence from the scaffold's MIT licence.

`livemorebio/scientific_sources/data/source-catalog.v1.json` retains factual
names, endpoint URLs, provenance URLs and source IDs for **2,594 NAR Molecular
Biology Database Collection entries** and **39 ELIXIR Core Data Resources** from
the 2026-08-30 snapshot. Credit NAR/Oxford University Press,
https://www.oxfordjournals.org/nar/database/a/ , ELIXIR,
https://elixir-europe.org/platforms/data/core-data-resources , and resource owners.
Publisher descriptions and data-type text are **not distributed**:
`description` is blank, `data_types` is empty and `description_status` is
`not_distributed` on every row. Resource-name prefixes replace title-style names, and invalid endpoint values
are blank with an explicit status. Factual identifiers and workflow hints
are preserved; runtime routing depends on workflow and admitted lifecycle,
not description text. No licence to redistribute the publishers' prose or
linked datasets is asserted. The refresh tool preserves this boundary.

## Local JavaScript assets

| Asset | Source, licence and required notices |
| --- | --- |
| `livemorebio/aegle/console/lib/anatomy_vendor.js` and `anatomy_vendor_manifest.js` | **Three.js 0.160.0**, https://github.com/mrdoob/three.js , **MIT**, copyright **2010–2023 three.js authors**. The full permission/disclaimer text is retained in the JS banner and manifest, with source commit/archive and hashes. Preserve both. Livemore's bundled selection/build is recorded in `tools/build_anatomy_vendor.mjs`. |
| `livemorebio/aegle/console/lib/vendor/3dmol-2.5.5/` | **3Dmol.js 2.5.5**, https://3dmol.org/ , **BSD-3-Clause**, copyright **2014 University of Pittsburgh and contributors**. Preserve copyright, conditions, disclaimer and non-endorsement condition. Keep the unchanged bundle and all three notice files described below. |

The full 3Dmol notice set is:

- [Upstream LICENSE](livemorebio/aegle/console/lib/vendor/3dmol-2.5.5/LICENSE)
- [Generated bundle notice](livemorebio/aegle/console/lib/vendor/3dmol-2.5.5/3Dmol.es6-min.js.LICENSE.txt)
- [Complete embedded-component notices](livemorebio/aegle/console/lib/vendor/3dmol-2.5.5/THIRD_PARTY_NOTICES.txt)

Embedded-component credits, with full terms in those files:

- **GLmol 0.47** — copyright 2011–2012 biochem_fan, **MIT option** of MIT/LGPL3.
- **Three.js** — copyright 2010–2012 three.js Authors; **jQuery** — copyright
  2011 John Resig; both **MIT**.
- **iobuffer** — copyright 2015 Michaël Zasso; **netcdfjs** — copyright 2016
  cheminfo; **UPNG.js** — copyright 2017 Photopea; all **MIT**.
- **pako** — copyright 2014–2017 Vitaly Puzrin and Andrei Tuputcyn/Tupitsin;
  **MIT**, with inherited **zlib** copyright 1995–2013 Jean-loup Gailly and Mark
  Adler and zlib notice/altered-source/origin-retention conditions.
- **Mol\*** BinaryCIF/shader code — copyright 2017–2024 Mol* contributors;
  upstream notice 2017–now Mol* contributors; **MIT**.
- **Rendu FXAA** — copyright 2017 Simon Rodriguez; **MMTF JavaScript** — copyright
  2015–2016 Alexander S. Rose, with BinaryCIF packing credit 2016 Alexander Rose;
  **MIT**.
- **ProteinSurface / EDTSurf** — biochem_fan JavaScript port; custom permissive
  use/copy/modify/distribute grant requiring its copyright/reference information.
  Reference: **D. Xu and Y. Zhang (2009), “Generating Triangulated Macromolecular
  Surfaces by Euclidean Distance Transform,” PLoS ONE 4(12): e8140**.

The retained upstream notices and their source links were checked on 2026-10-04.
The delivered bundle is hash-pinned; the notices do not invent exact resolved
versions for embedded modules whose published package supplied only version ranges.

## Cardiac model source and attribution

The cardiac context references the **O'Hara–Rudy CiPA v1.0 (2017)** CellML
encoding, **unmodified**, SHA-256
`ed127e6737611eb1469ea32db0b9d102f0780fc286a29ca88d11d8a868a94175`.
The [PMR licence/citation page](https://models.physiomeproject.org/e/5a0/ohara_rudy_cipa_v1_2017.cellml/license_citation)
([CellML host](https://models.cellml.org/e/5a0/ohara_rudy_cipa_v1_2017.cellml/license_citation)),
checked **2026-10-04**, makes both of these statements:

- Its per-work licence field is **unspecified**.
- Its citation instructions license **all publicly accessible repository content
  under Creative Commons Attribution 3.0**,
  https://creativecommons.org/licenses/by/3.0/ .

Attribution: **KC Chang, S Dutta, GR Mirams, KA Beattie, J Sheng, PN Tran, M Wu,
WW Wu, T Colatsky, DG Strauss and Z Li (2017)**,
“Uncertainty Quantification Reveals the Importance of Data Variability and
Experimental Design Considerations for in Silico Proarrhythmia Risk Assessment,”
*Frontiers in Physiology* 8:917, https://doi.org/10.3389/fphys.2017.00917 .
Model exposure: https://models.physiomeproject.org/e/5a0 ; source workspace
changeset **2c2629a8e2b60c2cde677903e03c9c9be3f39a00**. The exact historical
download date and time were not recorded; these bytes were present in the
repository by **2026-07-11 04:52:30 −04:00** (commit `a4aa20e`).
CellML encoding: **PMR workspace 4e4, owner Gary Mirams**,
https://models.physiomeproject.org/workspace/4e4 .
Base model: **O’Hara T, Virág L, Varró A and Rudy Y (2011)**,
“Simulation of the Undiseased Human Cardiac Ventricular Action Potential:
Model Formulation and Experimental Validation,” *PLoS Computational Biology*
7(5):e1002061, https://doi.org/10.1371/journal.pcbi.1002061 .
The source and licence pages were checked on the date above. No modifications were made in this release. Repository citation:
**Lloyd CM, Lawson JR, Hunter PJ and Nielsen PF. “The CellML Model Repository.”
Bioinformatics 2008;24(18):2122–2123**, https://doi.org/10.1093/bioinformatics/btn390 .

The separate **FDA CiPA repository is GPL-3.0**, verified at
https://raw.githubusercontent.com/FDA/CiPA/master/LICENSE on 2026-10-04.
That repository's licence is **not the licence of this CellML file**.
## Separately installed dependencies, fonts and scientific models

These dependency declarations do not vendor wheels or binaries. The exact locked
versions' installed metadata and the primary package records were checked on
**2026-10-04**. Preserve the packages' full licence files when redistributing
an installed environment; Livemore's MIT licence does not relicense them.

| Package | Verified metadata and primary source |
| --- | --- |
| swiglpk 5.0.13 / GNU GLPK | **GPL-3.0**; the wheel includes GLPK. https://pypi.org/project/swiglpk/5.0.13/ ; https://www.gnu.org/software/glpk/ |
| GNU GMP, dependency of GLPK | **LGPL-3.0-or-later OR GPL-2.0-or-later**; preserve the actual redistributed binary's notices and corresponding-source obligations. https://gmplib.org/manual/Copying |
| libroadrunner 2.10.0 | **Apache-2.0**, with embedded components retaining their own notices. https://pypi.org/project/libroadrunner/2.10.0/ ; https://github.com/sys-bio/roadrunner/blob/develop/LICENSE.txt |
| cobra 0.32.1 | **LGPL-2.0-or-later OR GPL-2.0-or-later**. https://pypi.org/project/cobra/0.32.1/ |
| python-libsbml 5.21.1 | **LGPL**, as stated in package metadata; no more specific version inferred. https://pypi.org/project/python-libsbml/5.21.1/ |
| copasi-basico 0.86 | **Artistic-2.0**. https://pypi.org/project/copasi-basico/0.86/ |
| python-copasi 4.46.300 | **Artistic-2.0** (upstream full licence). https://pypi.org/project/python-copasi/4.46.300/ ; https://copasi.org/Download/License/ |
| certifi 2026.7.22 | **MPL-2.0**. https://pypi.org/project/certifi/2026.7.22/ |
| fqdn 1.5.1 | **MPL-2.0**. https://pypi.org/project/fqdn/1.5.1/ |

Corresponding-source obligations and any combined binary/container distribution
apply to the actual delivered artifacts and their complete dependency notices.

**No font files are bundled.** The Biology console requests **Fraunces, Geist
and JetBrains Mono** through Google Fonts at view time. Those network requests
are separate from locally bundled JavaScript assets. No font licence is inferred
from the Google Fonts service URL.

**Human-GEM/Human2 v2.0.0** is separately acquired with its pinned original
files, **CC-BY-4.0** licence and `citation.cff`. The exact upstream licence,
https://raw.githubusercontent.com/SysBioChalmers/Human-GEM/635f533152dc5f7290ce04d12700eaa882273c3e/LICENSE.md ,
was checked 2026-10-04. See the [Human-GEM source contract](docs/HUMAN_GEM_MODEL_SOURCES.md).
Credit the Human-GEM contributors and retained preferred citation. Beard CellML
and Open Systems Pharmacology runtime/model bytes are not bundled here; any
separate acquisition retains its own admitted source manifest, licence and
citation. Recon3D remains unadmitted and is neither bundled nor enabled.
Connector declarations never waive upstream terms.

Authored scientific modules retain citations for numerical facts and equations,
including Hovorka 2004 (https://doi.org/10.1088/0967-3334/25/4/010), Wilinska 2010
(https://doi.org/10.1177/193229681000400117) and lobeline assay evidence
(https://doi.org/10.1124/jpet.109.160275). Article text, figures, full tables and
author software are not licensed by those citations; no article redistribution
right is asserted.
