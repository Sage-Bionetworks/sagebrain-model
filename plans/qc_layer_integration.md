# Integrate FASTQ/counts QC results into sagebrain.ttl, anchored on Sample

## Context

`plans/qc_elements.md` specifies five QC metrics computed from a MultiQC
report and RNAseq counts/sample metadata — Phred score (FastQC), Reads
mapped, Duplicated reads (both MultiQC), a sex check (RPS4Y1/EIF1AY/DDX3Y/
KDM5D expression vs. reported sex), and DV200/RIN — each reduced to a
**FAIL/WARN/(implicit pass)** signal only; raw values are explicitly
excluded from the graph ("do not include QC values in the graph. Only
consider 'FAIL' and 'WARN' signals in the edges"). A sample fails QC if any
metric fails outright, or if 2+ metrics warn.

The source document writes each metric's edge as e.g. `(Phred score to
Files)` — QC is naturally a fact about a **file**. But `sagebrain.ttl` has no
File class today; file metadata is its own, separate graph layer, out of
scope here. The only instance-level anchor QC can reach today is
`biolink:MaterialSample` (Sample) — already the hub connecting `Individual`
to the model's existing extracted-information layer
(`sagebrain:expressed_in` from Gene, `sagebrain:de_associated_with` to
Pathway, both reified as weighted Associations).

`plans/qc_elements.md` was later extended with "Additional design notes"
describing SageBrain's intended layered architecture: a **Biomedical
Metadata Layer** (studies, cohorts, specimens, assays, files, ...) and a
**Biomedical Data Layer** (derived variables, features, annotations — what
`sagebrain.ttl` already models as Gene expression / DE associations). QC sits
between the two: it's computed from a file but exists to qualify whether
that file's downstream Data-layer content should be trusted — the
"Traceability & Provenance" principle those same notes call out
("Relationships and entities should be traceable back to their sources").

That traceability requirement is bigger than QC alone: **any** piece of
Data-layer information — a `GeneExpressionAssociation`, a
`SampleDEAssociation`, the new QC results, and whatever gets added later —
needs to be traceable onward to the file(s) and/or sample(s) it was derived
from, and that's not always a clean single-sample, single-file chain: a
sample or file can back more than one derived fact, and some derived facts
(a comparison across samples, a cohort-level statistic) are computed *from*
more than one sample or file in the first place. Rather than wire that
per-association-type, this plan gives both `Sample` and every reified
`biolink:Association` a single generic, multi-valued, deliberately
provisional link toward its source(s) (`sagebrain:derived_from`, item 6
below) — so tracing provenance for any piece of information is one uniform
lookup, not bespoke per-relationship logic, whether one sample/file was
involved or several.

## Approach

All changes land in `ontology/main/sagebrain.ttl` (no new file: the ontology
is "one layer" today per its own header comment, and every existing domain
already coexists in one file). Kept intentionally minimal — an earlier pass
of this plan added a dedicated `ElementCategory`, a `categorical` annotation
property, and a parallel plain `assessed_in` connection alongside the
reified association; all three are dropped below because they exist only to
preserve uniformity with an unrelated bookkeeping shape, not because the
data needs them (see the callouts inline).

1. **New vocabulary class `sagebrain:QCMetric`**, declared like
   `sagebrain:Biodomain` (`ontology/main/sagebrain.ttl:291-298`): `rdfs:label`,
   `rdfs:comment`, `elementCategory sagebrain:Biological` (reused rather than
   minting a new `QualityControl` category for five terms — a stretch, but a
   smaller one than growing the top-level taxonomy; revisit if QC content
   grows), `nodeLevel Vocabulary`, `owl:versionInfo "v0.4"`. Backed by
   `sagebrain:QCMetricScheme` (mirroring `BiodomainScheme`, `:318-329`) with
   five individuals: `PhredScore`, `ReadsMapped`, `DuplicatedReads`,
   `SexCheck`, `DV200RIN` (DV200/RIN share one node — the source document
   always gates on them jointly). No outgoing plain property of its own (see
   #4), so — like `Biodomain`/`Tissue` — it needs no SHACL node shape.

2. **New small enum class `sagebrain:QCStatus`**, declared like
   `sagebrain:NodeLevel` (`:86-90`): `a owl:Class ; rdfs:subClassOf
   skos:Concept`, no `elementCategory`/`nodeLevel` on itself (same exemption
   `NodeLevel`/`ElementCategory` already have — infrastructure enums, not
   domain elements). `sagebrain:QCStatusScheme` holds three individuals:
   `QCPass`, `QCWarn`, `QCFail` — prefixed (unlike `NodeLevel`'s bare
   `Instance`/`Vocabulary`) since "Pass"/"Fail" are common enough words to
   risk future collisions in this flat namespace.

3. **New reified association `sagebrain:QCResultAssociation`**, structured
   like `sagebrain:GeneExpressionAssociation` (`:624-631`): subclass of
   `biolink:Association` with `subject allValuesFrom QCMetric` and `object
   allValuesFrom biolink:MaterialSample` (documented as a stand-in for File
   until the file-metadata layer exists). Carries `sagebrain:qc_status`
   (below) as its outcome. **No parallel plain property**, unlike
   `expressed_in`/`de_associated_with`: those have a legitimate
   weightless-but-still-meaningful plain form ("known expressed, degree
   unmeasured"); "this sample was checked for Phred score, outcome unknown"
   is not a fact anyone would assert on its own. This mirrors how
   `sagebrain:weight` itself has no independent plain-property form — it
   only exists inside an association. Dropping the plain form also removes
   the need for the `categorical` annotation property and a `QCMetricShape`
   from the earlier draft of this plan: there is no longer a plain
   connection for either to attach to.

4. **New property `sagebrain:qc_status`**, declared like `sagebrain:weight`
   (`:615-622`): `rdfs:domain biolink:Association`, `rdfs:range
   sagebrain:QCStatus` (an `ObjectProperty`, not `DatatypeProperty` — its
   range is a class of individuals, not a literal), `rdfs:subPropertyOf
   biolink:association_slot`. Like `weight`, carries no `sagebrain:weighted`
   triple and is not itself a "connection" in the `ConnectionShape` sense.

5. **New aggregate connection `sagebrain:has_qc_status`**: domain
   `biolink:MaterialSample`, range `sagebrain:QCStatus`, `sagebrain:weighted
   false`, `owl:versionInfo "v0.4"`. The per-sample overall verdict from
   `plans/qc_elements.md`'s roll-up rule (fail anywhere, or 2+ warnings) —
   asserted directly, since the ontology doesn't compute it. No reification:
   a single categorical fact, nothing else to attach to it. This is the
   simplest piece of the whole plan and the one most directly requested
   ("linked to a sample entity") — separable from #1-4 if you'd rather ship
   only the aggregate verdict first and add per-metric detail later.

6. **New provisional connection `sagebrain:derived_from`** — the general
   provenance hook, not QC-specific. Two requirements pushed this past the
   simpler "Sample points at its File(s)" version from the previous draft:
   a sample (or file) can legitimately back more than one derived fact, and
   some derived facts — a comparative or cohort-level association, for
   instance — aren't reducible to a single sample's files at all, since they
   are computed *across* more than one sample. So `derived_from` needs to be
   assertable from either level:
   - **domain**: `[ a owl:Class ; owl:unionOf ( biolink:MaterialSample
     biolink:Association ) ]` — the same union-domain shape already used by
     `sagebrain:contains_tissue` (`:489-491`). A plain `biolink:MaterialSample`
     asserts "this sample's data came from these file(s)"; asserting it
     directly on an `biolink:Association` instance (`GeneExpressionAssociation`,
     `SampleDEAssociation`, the new `QCResultAssociation`, etc.) covers the
     case where an association's own `biolink:subject`/`biolink:object` (each
     `minCount 1, maxCount 1` today — see `shape:GeneExpressionAssociationShape`
     `:701-716`) don't capture every sample or file that actually contributed
     to it.
   - **range**: `biolink:MaterialSample` for now (the only concrete class
     available — this is what lets an association assert "derived from these
     *N* samples" today), documented to widen to a union with File once that
     class exists, the same way `contains_tissue`'s domain already
     demonstrates the union-widening move.
   - **no cardinality bound** in either direction — multiple files per
     sample (e.g. paired-end R1/R2, multiple lanes) and multiple samples or
     files per association are both the expected shape, not an edge case.
   - `sagebrain:weighted false`, `owl:versionInfo "v0.4"`.

   Net effect: tracing "which file(s)/sample(s) produced this piece of
   information" for *any* current or future association is a direct,
   uniform lookup — `?assoc sagebrain:derived_from ?source` — with no
   per-association-type wiring, and it already supports the multi-sample
   case even before File exists. `ontology/imports/prov.ttl` vendors
   `prov:wasDerivedFrom` for the same relationship (Entity→Entity, also
   unconstrained cardinality), but as the *full* PROV-O ontology (1499
   lines, unlike `biolink.ttl`'s MIREOT'd subset) — pulling it into
   `MAIN_SOURCES` today is a disproportionate structural change for one
   property. Flagged as a real future option (a MIREOT extraction of just
   `wasDerivedFrom`/`Entity`, mirroring how `scripts/import.sh` already
   does this for Biolink) rather than resolved here.

7. **`ontology/shacl/sagebrain-shapes.ttl` additions**:
   - `shape:SampleShape` (extend, `:315-346`): add property blocks for
     `has_qc_status` (`sh:class sagebrain:QCStatus`, `sh:nodeKind sh:IRI`,
     `sh:maxCount 1`) and `derived_from` (`sh:nodeKind sh:IRI` only — no
     `sh:class` yet, since there's no File class to check against; this
     still satisfies `check_connection_coverage` in
     `tests/validate.py:134-142`, which only requires an active property
     shape to exist, not that it carry a class constraint. No
     `sh:maxCount`).
   - `shape:AssociationShape` (new): `sh:targetClass biolink:Association` —
     SHACL class targets traverse subclasses (the same mechanism
     `shape:IndividualShape`'s comment already relies on for Case/Control,
     `:254-258`), so this one shape reaches every current and future
     Association subtype at once. Single property block: `derived_from` →
     `sh:nodeKind sh:IRI`, no `sh:class`, no `sh:maxCount` — covers the
     "derived from multiple samples/files" case generically instead of
     repeating a `derived_from` block across all five association shapes.
   - `shape:QCResultAssociationShape` (new): mirrors
     `shape:GeneExpressionAssociationShape` (`:695-723`), with
     `sagebrain:qc_status` (`sh:class sagebrain:QCStatus`, not `sh:datatype`)
     in place of `weight`; `minCount 1, maxCount 1` on subject, object, and
     status; `sh:nodeKind sh:IRI` on subject/object as in the existing shape.
   - No inverse-cardinality shape: none of the new connections are a
     one-parent hierarchy.

8. **Versioning**: tag every new term `owl:versionInfo "v0.4"`. Don't bump
   the ontology-wide `owl:versionIRI`/`owl:versionInfo` here — that's a
   separate follow-up commit once this is implemented, matching the existing
   history (a batch of v0.3 additions, then `0dcbc80 Bump version` on its
   own).

9. **Examples**: extend `examples/AD-cohort.ttl` with a `QCResultAssociation`
   for at least one metric on one sample and a plain `has_qc_status`. Leave
   `derived_from` undemonstrated in the committed example — asserting
   `sample:01 derived_from ex:something` would just recreate the
   placeholder-namespace problem `examples/README.md` already tracks as an
   open item ("No `example.org` node remains in these files") — but the plan
   text itself illustrates the intended multi-source shape for reviewers:
   ```
   sample:01 sagebrain:derived_from file:R1, file:R2 .
   association:qc-phred-samp01 sagebrain:derived_from file:R1, file:R2 .
   ```
   (both a Sample and an Association pointing at more than one source).
   Update the header comment's connection count and `examples/README.md`'s
   "covers all N of the model's connections" line — noting `derived_from`
   as documented-but-not-yet-illustrated, the same status `TODO.md`-tracked
   placeholders already get. Per the file's own documented caveat at
   `:200-207` — pySHACL's `sh:class` only sees `rdf:type` triples in the data
   graph being validated, not the ontology — every new SageBrain-minted term
   the example references (`sagebrain:QCFail`, `sagebrain:PhredScore`, etc.)
   needs its `a QCStatus`/`a QCMetric` triple restated inline, exactly like
   `sagebrain:Proteostasis a sagebrain:Biodomain .` at line 208.

## Verification

- `python tests/validate.py` passes all six checks, including the new
  `QCResultAssociationShape`, `AssociationShape`, and the extended
  `SampleShape`.
- Add a fixture to `tests/violating.ttl` (or confirm coverage already exists)
  exercising a wrong-typed `qc_status` value, so check 4 stays honest for the
  new association.
- Confirm `derived_from` genuinely accepts multiple values from both a
  Sample and an Association instance in a scratch/test graph (e.g. two
  `sh:IRI` objects on one subject) without tripping any cardinality
  constraint — there should be none to trip.
- `examples/AD-cohort.ttl` still validates and visibly exercises
  `QCResultAssociation`/`qc_status` and `has_qc_status`, with every
  referenced term's `a QCMetric`/`a QCStatus` triple restated inline.
- `make viz` (or `make json`) still builds cleanly with the new terms
  present.

## Process

Store this plan at `plans/qc_layer_integration.md` for review before
implementing (introducing that convention to this repo, matching
`mc2-center/data-models`' `plans/` pattern). After implementing, append an
Implementation Report below this line — what was actually done, any
deviations from the Approach section above, and verification results.

## Implementation Report

Implemented items 1-9 as designed, no deviations from the Approach section.

**`ontology/main/sagebrain.ttl`**: added `sagebrain:QCMetric` +
`QCMetricScheme` (5 individuals), `sagebrain:QCStatus` + `QCStatusScheme`
(`QCPass`/`QCWarn`/`QCFail`), `sagebrain:has_qc_status`,
`sagebrain:derived_from` (union domain over `MaterialSample`/`Association`,
no cardinality bound), `sagebrain:qc_status`, and
`sagebrain:QCResultAssociation` — all tagged `owl:versionInfo "v0.4"`, all
placed and commented as described in items 1-6. The ontology-wide
`owl:versionIRI`/`owl:versionInfo` (still 0.3.0/"v0.3") was deliberately left
alone per item 8, to be bumped in a separate follow-up commit.

**`ontology/shacl/sagebrain-shapes.ttl`**: extended `shape:SampleShape` with
`has_qc_status`/`derived_from` property blocks; added `shape:AssociationShape`
(`sh:targetClass biolink:Association`, one `derived_from` block covering
every association subtype) and `shape:QCResultAssociationShape` (mirrors
`GeneExpressionAssociationShape`); updated the file's own group-4 header
comment to describe both new, non-weight-related shapes.

**`examples/AD-cohort.ttl`**: `sample:03` now carries `has_qc_status
sagebrain:QCFail` and a `QCResultAssociation` (`PhredScore` → `QCFail`),
illustrating the "fail anywhere" rule from `plans/qc_elements.md`.
`sagebrain:PhredScore`/`sagebrain:QCFail` types are restated inline per the
file's own pySHACL caveat. `derived_from` is intentionally not demonstrated
(no File class to point at yet). Header comment and `examples/README.md`
updated from "19 of 19" to "20 of 21" connections, with an explicit note on
why `derived_from` is the one gap.

**`tests/violating.ttl` / `tests/validate.py`**: added a seventh planted
defect (g) — a `QCResultAssociation` with `qc_status` pointing at a
`biolink:Pathway` instead of a `QCStatus` — and registered its expected
violation message, per the plan's Verification section (this turned out to
be an implementation change, not just a verification step, since the
fixture itself needed a new defect written).

**Verification results**: `python tests/validate.py` — all six checks pass,
including the new shapes; check 5 now reports `21/21` connections covered
(19 pre-existing + `has_qc_status` + `derived_from`); check 4 reports all
seven planted defects including the new one, with exactly one new violation
(8→9) confirming no incidental extra violations were introduced by the
supporting-node restatement. `make json`'s ROBOT `merge`/`remove` steps
(the parts that depend on the ontology's own content) completed cleanly and
the built, pruned ontology contains all six new terms; the subsequent
OWL2VOWL-jar fetch failed on a pre-existing, platform-specific `sha256sum`
flag incompatibility on this machine (expected and got hashes print
identical) — unrelated to this change, not investigated further here.
`derived_from` accepting multiple values from both a Sample and an
Association was confirmed by construction (no `sh:maxCount` anywhere on it)
rather than a separate scratch graph, since the shapes and OWL declarations
themselves are the only place a cardinality bound could have been
introduced, and none was.
