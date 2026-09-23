# Import the governance layer from mc2-center/governanceDUO instead of copying it

## Context

The governance graph built in mc2-center/governanceDUO is meant to be a layer of
this repo's graph: loaded into the same Neptune store, joined on the same IRIs, and
read by sagebrain-infra's authorizer. A cross-repo review (governanceDUO
`plans/sagebrain_contract_and_owl_dl_fixes.md` and its report, branch
`kg-conversion`) found that the two had drifted:

- **Duplicate term ownership.** `ontology/imports/governance_graph.ttl` hand-copies
  `gov:SynapseEntity`, and `ontology/governance/pipeline_provenance.ttl` re-declares
  `gov:wasExecuted`/`gov:url`/`gov:entityVersionNumber`, both pinned at governanceDUO
  `abf8c9f`. They were copied because governanceDUO published no importable release.
- **Diverging shapes.** `ontology/shacl/governance-shapes.ttl` requires `rdfs:label`
  on a URL Usage, while governanceDUO's graph uses `gov:name` (its name predicate
  everywhere). It also limits an Activity to exactly one `prov:generated`, but
  Synapse lets one Activity generate several entities
  (`GET /activity/{id}/generated` returns a list; verified in Synapse's OpenAPI
  spec). Neither repo's provenance data conforms to the other's shapes.
- **Activity IRIs.** `examples/pipeline_provenance.ttl` uses `syn:activity.*`; the
  agreed policy mints `gov:activity-<n>`.
- **No bridge between the derivation edges.** `sagebrain:derived_from` is not a
  sub-property of `prov:wasDerivedFrom`, so governanceDUO's derivation-policy builder,
  which computes access ControlLabels over `prov:wasDerivedFrom` ancestry, stops at
  Synapse files. Labels never reach this repo's Associations and Samples, and
  sagebrain-infra's query filter only gates results containing Synapse ids. This is
  the leakage case the 9-8-26 PROV-O note describes.

governanceDUO has since been changed to own these terms and publish them. Four
versioned artifacts, each with an `owl:Ontology` header carrying
`owl:versionIRI`/`owl:versionInfo` 0.1.0:

- `shapes/governance_duo.owl.ttl` (OWL generated from its LinkML schema: real
  `prov:`/`gov:` IRIs, passes the OWL 2 DL profile);
- `shapes/governance_graph.owl.ttl` (hand-written `gov:` TBox);
- `shapes/governance_graph.shacl.ttl`;
- `shapes/provenance_layer.shacl.ttl` (`gov:UsageShape`/`gov:ActivityShape`, moved
  there from this repo's `governance-shapes.ttl` with the `gov:name` and
  multi-output changes).

Its opt-in `make sagebrain-contract-check SAGEBRAIN_MODEL=<path>` checks this repo
from the other side. Against `provenance-features` (`8d04715`) it fails on exactly
the items above. Against a scratch copy with the changes below applied, it passes:
union OWL 2 DL, SHACL on a joined worked example, and a ControlLabel reaching
`association:apoe-expr-samp01`.

**Prerequisite:** the governanceDUO commit being pinned must be reachable on GitHub
(`kg-conversion` pushed, or merged to `main` and tagged `v0.1.0`). Until then the
pinned URLs below don't resolve.

### Revision (2026-09-23): pin `240a162`, not `9e398af`

Step 1 was first built against `9e398af`. Its `governance_duo.owl.ttl` typed
`prov:generated` and `prov:entity` as `owl:DatatypeProperty`, because LinkML
emits `range: uriorcurie` slots that way. W3C PROV-O (`ontology/imports/prov.ttl`,
already in `GOVERNANCE_SOURCES`) types them as `owl:ObjectProperty`. Loading
both punned them: 21 OWL 2 DL violations, on top of the 13 that `prov.ttl`
gives on its own (`prov:specializationOf`, `prov:wasRevisionOf`).

Keeping two owners in agreement beats dropping one, so `prov.ttl` stays and
the fix went upstream: governanceDUO
`plans/iri_valued_slots_as_object_properties.md` and its report, implemented
through `240a162`. That commit's OWL types all six IRI-valued slots as object
properties. It adds a PROV-O type-agreement check to its own `owl-profile`
and to `sagebrain-contract-check`. Measured against `240a162`:

- **Union with `prov.ttl`.** Only `prov.ttl`'s own violations remain (13 by
  this repo's count; governanceDUO's report counts 14 on the same union).
  None comes from the governance layer.
- **governanceDUO's contract check against this branch's step-1 state.** PROV
  type agreement and ControlLabel ancestry pass. The DL union failed only
  because the import was still the `9e398af` extract; regenerating at
  `240a162` fixes that. Joined-example SHACL fails on
  `examples/pipeline_provenance.ttl`'s `rdfs:label` Usages, and
  `gov:ActivityShape`'s `sh:node gov:UsageShape` carries the same failure up to
  both Activities. Step 5 fixes both.

**`240a162` is not pushed yet** (as of this revision, `kg-conversion` is 11
commits ahead of `origin`). The modules were regenerated from `CACHE_DIR`,
seeded with `git show 240a162:<path>` from a local checkout. Those are the
same bytes the raw URL will serve once pushed. The push must land before this
branch leaves the machine.

## Approach

1. **`scripts/import.sh`: add three governanceDUO modules** (done: `984b3ef`,
   `17e0d14`, `580379e`). As built: `governance_graph`, `governance_layer`, and
   `governance_layer_shapes` (copied verbatim, since shapes can't be
   MIREOT-extracted). `GOVERNANCEDUO_COMMIT` is shared by all three. It's three
   modules rather than the single `governance` module first planned, because
   each has its own source file and output path.
   - Fetch the governanceDUO artifacts by pinned URL
     (`https://raw.githubusercontent.com/mc2-center/governanceDUO/<commit-or-tag>/shapes/...`)
     into `CACHE_DIR`, same pinning discipline as Biolink.
   - ROBOT MIREOT-extract only the terms this repo uses, into two committed modules:
     - `ontology/imports/governance_graph.ttl` (regenerated, replacing the hand
       extract; stays in `MAIN_SOURCES`, since `sagebrain:derived_from`'s range
       needs it in the default build): `gov:SynapseEntity`.
     - `ontology/imports/governance_layer.ttl` (new; added to `GOVERNANCE_SOURCES`
       in the `Makefile` and `GOVERNANCE_IMPORTS` in `tests/validate.py`):
       `prov:Activity`, `prov:Usage`, `prov:generated`, `prov:qualifiedUsage`,
       `prov:entity`, `gov:wasExecuted`, `gov:url`, `gov:entityVersionNumber`,
       `gov:name`.
   - Copy `shapes/provenance_layer.shacl.ttl` verbatim to
     `ontology/shacl/governance_layer.shacl.ttl`. Shapes can't be MIREOT-extracted;
     the header comment records the source URL and pin, and import.sh re-copies it
     on a bump.
2. **`ontology/governance/`: replace `pipeline_provenance.ttl` with
   `provenance_bridge.ttl`.** The `gov:` re-declarations go away (now imported).
   The new module holds only what this repo owns:
   - `sagebrain:derived_from rdfs:subPropertyOf prov:wasDerivedFrom`;
   - `prov:wasDerivedFrom a owl:ObjectProperty`. Only the term used, as done for
     `gov:SynapseEntity`. The DL-checked set doesn't import `prov.ttl`, and without
     the declaration OWLAPI reads the axiom as an annotation sub-property, so the
     DL check fails (confirmed by the contract check's simulation).

   It lives in `ontology/governance/`, not `ontology/main/`, so the default build
   doesn't gain an undeclared PROV property.

   Also wire in the imported module: add `ontology/imports/governance_layer.ttl`
   to `GOVERNANCE_SOURCES` in the `Makefile` and `GOVERNANCE_IMPORTS` in
   `tests/validate.py`. `prov.ttl` stays in both (see the 2026-09-23 revision).
3. **Shapes.** Delete `ontology/shacl/governance-shapes.ttl` (superseded by
   `governance_layer.shacl.ttl`). Point `GOVERNANCE_SHAPES` in `tests/validate.py`
   at the new file.
4. **`sagebrain.ttl`.** Update `derived_from`'s comment: it now bridges into
   `prov:wasDerivedFrom` (declared in `ontology/governance/provenance_bridge.ttl`),
   and the provenance layer is imported from governanceDUO, not mirrored.
5. **Examples.** `examples/pipeline_provenance.ttl`:
   - `rdfs:label` → `gov:name` on the two URL Usages;
   - `syn:activity.reprocess01/02` → `gov:activity-reprocess01/02`.
   `examples/README.md`: same renames; describe the import.
6. **Test fixtures.**
   - `tests/governance_conforming.ttl`: same renames, plus one Activity with two
     `prov:generated` outputs.
   - `tests/governance_violating.ttl`, defect (o): `rdfs:label` → `gov:name`.
     (n) stays a Gene output; it now fails the absolute-Synapse-IRI pattern
     instead of `sh:class`.
7. **`tests/validate.py`.**
   - Update `EXPECTED_GOVERNANCE_VIOLATIONS` to the imported shapes' messages:
     - (m): "must be either a Synapse entity reference";
     - (n): "at least one prov:generated output, an absolute Synapse IRI".
   - Update `check_usage_label_leak()` for `gov:name`.
   - Add, under `WITH_GOVERNANCE=1`:
     - a DL profile check of the governance-layer union (the DL-checked set plus
       `ontology/governance/` and `ontology/imports/governance_layer.ttl`),
       merge-to-file then validate. Chaining `robot merge ... validate-profile`
       in one call reports spurious violations.
     - a SHACL check of a vendored copy of governanceDUO's provenance example
       ABox (`linkml/examples/provenance/rdf/all_examples.ttl` at the pin,
       copied verbatim to `tests/governanceduo_provenance_examples.ttl` by a
       fourth import.sh module, `governance_provenance_examples`, so a pin bump
       refreshes it) against `governance_layer.shacl.ttl`, so contract drift
       fails here too. `copy_shapes_module()` generalizes to a `copy_module()`
       with a per-module output path.
     - a PROV type-agreement check: every `prov:` term declared in
       `ontology/imports/governance_layer.ttl` or `ontology/governance/` must
       have the same OWL property/class type as in `ontology/imports/prov.ttl`.
       This repo is where the two files are loaded together, so a future pin
       bump that brings the pun back fails here, not only in governanceDUO's
       opt-in contract check. It compares declarations directly, not with a DL
       run over a union with `prov.ttl`, since `prov.ttl` has puns of its own.
     - an assertion that `association:apoe-expr-samp01` reaches
       `syn:syn27000001` through `prov:wasDerivedFrom*`, with the bridge axiom
       loaded (SPARQL property path over the merged graph).
8. **Plans.** `plans/pipeline_provenance_layer.md`: append a note that its
   "mirrors governanceDUO" claims (`rdfs:label`, exactly one output) were
   superseded by this plan.

## Verification

- `python3 tests/validate.py`: all default checks pass. The DL profile check
  still passes with the regenerated `ontology/imports/governance_graph.ttl`.
- `WITH_GOVERNANCE=1 python3 tests/validate.py` passes:
  - the conforming fixture conforms;
  - (m)/(n)/(o) are caught with their new messages or focus nodes;
  - `examples/pipeline_provenance.ttl` conforms;
  - the new union DL, vendored-ABox, PROV type-agreement and ancestry checks
    pass;
  - pointing the type-agreement check at the `9e398af` extract makes it fail
    on `prov:entity`/`prov:generated`.
- `make WITH_GOVERNANCE=1 json` builds (`MIN_CLASSES` floor holds); `build/sage.json`
  still shows `prov:Activity`/`prov:Usage`/`gov:wasExecuted` as real nodes.
- From governanceDUO: `make sagebrain-contract-check SAGEBRAIN_MODEL=<this checkout>`
  passes all three parts: union OWL 2 DL, joined-example SHACL, and the
  ControlLabel reaching `association:apoe-expr-samp01`.
- `scripts/import.sh governance_graph governance_layer governance_layer_shapes
  governance_provenance_examples` is reproducible: a re-run with the same pin
  gives no diff.

## Process

Store this plan for review, then implement in granular commits: import.sh module,
regenerated imports, bridge module, shapes swap, examples, fixtures, tests, docs.
Append an Implementation Report to this file when done.
