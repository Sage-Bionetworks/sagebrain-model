## Context

The user asked whether the current model captures data provenance for a reprocessing pipeline -- raw data input -> processed data output -> post-processing outputs (DE analysis, etc.) -- with processing *steps* themselves represented, e.g. `dataset -(is processed using)-> nf-core RNAseq v3.11.1 -(produces)-> intermediate output`.

**Answer: not yet.** Investigation of the current model found:

- `sagebrain:derived_from` (main provenance edge, v0.4) is a **flat, single-hop** edge: `Sample`/`Association` -> `MaterialSample`/`gov:SynapseEntity`. It says an output came from a file; it cannot say *how* -- no tool, no run, no distinguishing "input consumed" from "tool executed," and no way to chain raw -> intermediate -> DE as connected steps (every association's `derived_from` points at "the source file(s)," collapsing however many stages actually happened into one hop).
- `sagebrain:analysis_tool` (`GeneExpressionAssociation` only) is a single free-text string (e.g. `"DESeq2 v1.34.0"`) -- not a queryable node, not reusable across other association types, not attached to *which* input it ran against or *what* it produced.
- The full W3C PROV-O vocabulary is already vendored at `ontology/imports/prov.ttl` (`prov:Activity`, `prov:Usage`, `prov:Entity`, `prov:generated`, `prov:qualifiedUsage`, `prov:entity`, `prov:used`, `prov:wasGeneratedBy`, `prov:wasDerivedFrom`, `prov:wasAssociatedWith`, `prov:Agent`, etc. -- confirmed present at lines 1036, 1429, 1212, 269, 649, 256, 670, 777, 733, 688, 1066 respectively) but sits behind `make WITH_GOVERNANCE=1` and is never instantiated anywhere in the model.
- `ontology/governance/` is an empty placeholder ("unstable, NOT built by default" per the `Makefile`), reserved for exactly this. `sagebrain:derived_from`'s own doc-comment and `plans/gene_expression_de_metadata.md` both name "a full PROV-O Activity/Usage layer... mirroring mc2-center/governanceDUO's provenance.yaml" as the deferred, separate-scope fix for this gap.

**The anchor (per the standing "anchor before minting" rule, `CLAUDE.md`).** `mc2-center/governanceDUO` (pinned at commit `abf8c9f`, branch `kg-conversion` -- same commit `ontology/imports/governance_graph.ttl` already pins) has already designed and verified this exact layer: `linkml/provenance.yaml`, grounded directly against Synapse's real, live API (`org.sagebionetworks.repo.model.provenance.Activity`/`Used`/`UsedEntity`/`UsedURL`, `GET /entity/{id}/generatedBy`) rather than an invented shape. Its structure:

- `prov:Activity` (real PROV-O class, reused by IRI) -- one per pipeline run. Carries `prov:generated` (the output entity) and `prov:qualifiedUsage` (a set of `prov:Usage` blank nodes, one per input/tool it consumed).
- `prov:Usage` (real PROV-O class) -- flattens Synapse's `Used`/`UsedEntity`/`UsedURL` union: `prov:entity` (a `gov:SynapseEntity` IRI, when the thing consumed is itself a Synapse entity) *or* a URL-style reference (when it's external, e.g. a pipeline's own release page), plus a Synapse-specific `wasExecuted` boolean distinguishing an executed tool/workflow from a merely-consumed data input -- Synapse's own real distinction, with no PROV-O predicate equivalent (confirmed against `rest-docs.synapse.org` in governanceDUO's own grounding pass; left as a repo-local predicate the same way governanceDUO leaves other unmapped fields).

Mapped onto the prompt's own example:

```turtle
gov:activity.1042
    a prov:Activity ;
    prov:qualifiedUsage
        [ a prov:Usage ; prov:entity syn:syn11111111 ; gov:wasExecuted false ] ,
        [ a prov:Usage ; gov:url "https://nf-co.re/rnaseq/3.11.1" ;
          rdfs:label "nf-core/rnaseq v3.11.1" ; gov:wasExecuted true ] ;
    prov:generated syn:syn22222222 .

syn:syn11111111 a gov:SynapseEntity .   # raw dataset (input, not executed)
syn:syn22222222 a gov:SynapseEntity .   # intermediate output
```

A second `gov:Activity` individual, with `prov:qualifiedUsage`/`prov:entity` pointing at `syn:syn22222222` and its own `prov:generated` pointing at the file a `GeneExpressionAssociation.derived_from` already names, chains raw -> intermediate -> DE as two linked `prov:Activity` nodes joined through `prov:generated`/`prov:entity` -- exactly the multi-hop chaining `derived_from` alone cannot express.

**Deliberate scope limits, surfaced rather than glossed over (per the "surface problems, don't bury them" standing rule):**

1. **Not a typed, reusable Software/Tool node.** governanceDUO's own model (grounded in Synapse's real API) represents "the tool used" as a `prov:Usage`'s `url`/label pair, not a shared IRI-addressable entity -- there is no `Software` class to point two different Activities' Usage at and get a real graph join. Querying "everything nf-core/rnaseq v3.11.1 touched" means matching the `gov:url` string across `Usage` nodes, not walking an edge. This mirrors Synapse's own API shape faithfully; inventing a `sagebrain:Software` class *would* be a real improvement but is a bigger step than this plan's anchor supports, and is called out here as an explicit, separate future option rather than silently designed around.
2. **Stays behind `WITH_GOVERNANCE=1`, additive to (not a replacement for) `derived_from`.** `derived_from`'s own comment already commits to this: the plain edge remains the fast path; the Activity/Usage layer is the detailed path, reachable from the same `gov:SynapseEntity` nodes `derived_from` already points at. Nothing here changes `derived_from`'s declaration except its doc-comment, which currently describes the future layer in the abstract and should instead point at the real file once it exists.
3. **`ontology/governance/` has never been validated.** Confirmed by reading `tests/validate.py`: `IMPORTS` and `EXAMPLES` never reference `ontology/governance/` or `ontology/imports/prov.ttl` at all -- there is no test path today that would catch a broken governance module. This plan does not leave that gap in place; see step 3 below.

## Approach

**0. Write and commit this plan** as `plans/pipeline_provenance_layer.md` (its own commit).

**1. `ontology/governance/pipeline_provenance.ttl`** (new file -- its own commit; picked up automatically by the `Makefile`'s `GOVERNANCE_MODULES = $(wildcard ontology/governance/*.ttl)`, no `Makefile` edit needed):

- File header explaining the module: reuses `prov:Activity`/`prov:Usage`/`prov:generated`/`prov:qualifiedUsage`/`prov:entity` directly by IRI (already vendored in `ontology/imports/prov.ttl`, gated behind `WITH_GOVERNANCE=1` same as this module); hand-curates exactly the Synapse-specific extensions governanceDUO's `linkml/provenance.yaml` already commits to via `slot_uri` (pinned at commit `abf8c9f`, branch `kg-conversion` -- **re-check this pin at implementation time**, same discipline as `ontology/imports/governance_graph.ttl`) but that governanceDUO itself has not yet rendered as OWL (no `provenance.owl.ttl` counterpart exists there today, only `governance_graph.owl.ttl`/`governance_duo.owl.ttl`) -- so this module is the first OWL declaration of these two `gov:` predicates, faithful to an already-pinned IRI, not a fresh invention:
  - `gov:wasExecuted` -- `owl:DatatypeProperty`, `rdfs:domain prov:Usage`, `rdfs:range xsd:boolean`. "Distinguishes a Usage that was executed (a tool/workflow) from one that was merely consumed as data," mirroring `Used.wasExecuted` verbatim (governanceDUO's own wording).
  - `gov:url` -- `owl:DatatypeProperty`, `rdfs:domain prov:Usage`, `rdfs:range xsd:string`. "The external URL of the tool/resource used, when the Usage is not itself a `gov:SynapseEntity`" (mirrors `UsedURL.url`).
  - **`rdfs:label` (not a new `gov:name`/`governanceduo:name` predicate)** for the human-readable tool name paired with `gov:url` (e.g. `"nf-core/rnaseq v3.11.1"`) -- deliberate deviation from governanceDUO's own `Usage.name`, which reuses its `governanceduo:` schema's shared display-name slot. Pulling in that namespace for one cosmetic field is a second cross-repo dependency this model doesn't otherwise need; `rdfs:label` is already used pervasively in `sagebrain.ttl` and needs no import.
  - `gov:entityVersionNumber` -- `owl:DatatypeProperty`, `rdfs:domain prov:Usage`, `rdfs:range xsd:integer`, optional. Mirrors `UsedEntity.reference.targetVersionNumber`; PROV-O has no version-scoping equivalent (per governanceDUO's own note).
  - No new classes: `prov:Activity`/`prov:Usage` are reused as-is (governanceDUO's own pattern -- typed directly, no subclass), so nothing here needs `owl:allValuesFrom` restrictions for OWL2VOWL the way `derived_from`/`derived_from_organ` did (this module is validated by SHACL and `tests/validate.py`, not rendered in the default WebVOWL build, since it only loads under `WITH_GOVERNANCE=1`).

**2. `ontology/main/sagebrain.ttl` -- point `derived_from`'s comment at the real layer** (its own commit, no functional change): rewrite the sentence "a full PROV-O Activity/Usage layer... is a separate, larger effort tracked on its own, not part of this property" to reference `ontology/governance/pipeline_provenance.ttl` by name now that it exists, keeping the same meaning (still optional, still additive, still not part of this property's own declaration).

**3. `ontology/shacl/governance-shapes.ttl`** (new file, its own commit -- kept separate from `ontology/shacl/sagebrain-shapes.ttl`, mirroring the repo's existing main/governance split, so the "opt-in, unstable" boundary is consistent across ontology, imports, and shapes alike):
   - `shape:UsageShape` (`sh:targetClass prov:Usage`): `sh:xone` between (a) `prov:entity` present (`sh:class gov:SynapseEntity`, `sh:maxCount 1`) and (b) `gov:url` + `rdfs:label` present (both `sh:datatype xsd:string`, `sh:maxCount 1`) -- a Usage is either a Synapse entity or an external tool reference, never both, never neither. `gov:wasExecuted` required (`sh:datatype xsd:boolean`, `sh:minCount 1`, `sh:maxCount 1`). `gov:entityVersionNumber` optional (`sh:datatype xsd:integer`, `sh:maxCount 1`).
   - `shape:ActivityShape` (`sh:targetClass prov:Activity`): `prov:generated` required exactly one (`sh:class gov:SynapseEntity`, `sh:minCount 1`, `sh:maxCount 1`); `prov:qualifiedUsage` at least one (`sh:minCount 1`, `sh:node shape:UsageShape`).

**4. `tests/validate.py`** (its own commit): add an opt-in governance check path, gated on the same `WITH_GOVERNANCE` name the `Makefile` already uses (read via `os.environ.get("WITH_GOVERNANCE")`), so the new layer is actually validated rather than left as untested `.ttl` the way the rest of `ontology/governance/` is today:
   - When set: extend `IMPORTS` with `ontology/imports/prov.ttl` and every `ontology/governance/*.ttl` module (mirrors `GOVERNANCE_SOURCES` in the `Makefile`); extend the shapes graph with `ontology/shacl/governance-shapes.ttl`; additionally load and check `tests/governance_conforming.ttl` (must conform) and `tests/governance_violating.ttl` (each planted defect must produce the expected `sh:resultMessage`, same `EXPECTED_VIOLATIONS`-substring pattern as the existing suite, in a separate `EXPECTED_GOVERNANCE_VIOLATIONS` dict so the two suites don't share numbering).
   - When unset (the default): behavior is completely unchanged -- same `IMPORTS`, same shapes, same fixtures as today.
   - Print a line either way (`"[6] governance layer: skipped (set WITH_GOVERNANCE=1 to check)"` or the pass/fail detail), so a reader of the test output always knows whether this layer was actually exercised.

**5. `tests/governance_conforming.ttl` + `tests/governance_violating.ttl`** (new fixtures, one commit): the conforming file states one clean two-hop chain (raw `gov:SynapseEntity` -> `gov:Activity` -> intermediate `gov:SynapseEntity` -> a second `gov:Activity` -> DE-result `gov:SynapseEntity`), exercising both `shape:UsageShape`'s `sh:xone` branches (one `prov:entity` Usage, one `gov:url` Usage) and the chain itself. The violating file plants two defects: (a) a `prov:Usage` with neither `prov:entity` nor `gov:url` (violates `sh:xone`); (b) a `prov:Activity` whose `prov:generated` points at something that isn't a `gov:SynapseEntity` (e.g. a `biolink:Gene`).

**6. `examples/pipeline_provenance.ttl`** (new file, its own commit) -- the prompt's own worked example, made concrete and tied back into the existing `AD-cohort` data: an nf-core-style `gov:Activity` consuming a raw dataset entity plus the `"nf-core/rnaseq v3.11.1"` tool reference, producing `syn:syn26999999` -- the exact file `association:apoe-expr-samp01` (in `examples/AD-cohort.ttl`) already names via `derived_from`, so the new example plugs directly into the existing one rather than inventing disconnected data. `tests/validate.py`'s `EXAMPLES` glob is narrowed to exclude this one file by name (or moved under `examples/governance/`, whichever reads cleaner at implementation time) and instead loaded only in the `WITH_GOVERNANCE` branch added in step 4 -- otherwise the default (non-`WITH_GOVERNANCE`) test run would fail on undeclared `prov:Activity`/`prov:Usage` classes, the same problem `gov:SynapseEntity` caused before it was promoted into `IMPORTS`.

**7. `examples/README.md`** (its own commit): note the new example and, explicitly, that it is the one example requiring `WITH_GOVERNANCE=1` to validate -- following the same "what's exercised, what isn't" convention the file already uses for `derived_from` before this plan's predecessor exercised it.

**8. Append an "## Implementation Report"** to this plan file after implementing, as its own final commit.

## Verification

- `python3 tests/validate.py` (default, no flag) -- unchanged behavior: all existing checks pass exactly as before this plan, confirming the new layer is genuinely additive.
- `WITH_GOVERNANCE=1 python3 tests/validate.py` -- new check group passes: both governance fixtures load against `prov.ttl` + the new governance module + `governance-shapes.ttl`; `governance_conforming.ttl` conforms; both planted defects in `governance_violating.ttl` are caught with their expected messages.
- `make WITH_GOVERNANCE=1 json` -- confirm `build/sage.json` includes `prov:Activity`/`prov:Usage`/`gov:wasExecuted`/`gov:url`/`gov:entityVersionNumber` as real (non-orphan) nodes, and that `MIN_CLASSES` (100 under `WITH_GOVERNANCE=1`) still passes.
- Spot check: trace the chain in `examples/pipeline_provenance.ttl` by hand (or a one-off script over the merged graph, the same technique used for the earlier `contains_tissue`/`derived_from_organ` OWL2VOWL check) from the raw input entity through both `gov:Activity` nodes to `syn:syn26999999`, confirming it joins with `association:apoe-expr-samp01`'s existing `derived_from` edge in `examples/AD-cohort.ttl`.

## Process

Store this plan for review, then implement in the granular commits described above. Append the Implementation Report when done.
