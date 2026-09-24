# Realign the governance import with governanceDUO's model refactor

## Context

`plans/governance_layer_import.md` (implemented, Implementation Report `677f249`)
vendors governanceDUO's governance layer through four `scripts/import.sh` modules
pinned at `240a1628a14f6f08d6e86444030ab20beddc5b4d`. governanceDUO has since done a
large model refactor (its `plans/model_refactor.md`, decisions R1-R6, phases 0-2,
commits `44fd41c`..`3b1f247` on `kg-conversion`). It replaced the files this repo
imports from. governanceDUO's own `sagebrain-contract-check`, run against this
checkout, now fails 2 of its 4 parts. Reproduced here: `OWL 2 DL (union)` and
`prov: types match sagebrain's prov.ttl` pass, and `SHACL (joined worked example)`
and `ControlLabel reaches sagebrain Association` fail. The root cause is the stale
pin, as governanceDUO's uncommitted Phase 2 addendum to
`plans/model_refactor_report.md` says.

### What changed upstream (verified against the files at `3b1f247`, not the docs)

- **Namespace (R1).** `gov:` is now `https://w3id.org/synapse/governance#`. The
  header prefixes of `shapes/governance.owl.ttl`, `shapes/governance.shacl.ttl`,
  `shapes/governance_duo.owl.ttl` and `shapes/governance_duo.shacl.ttl` all say so.
  Shapes live in their own namespace: `shape:` = `https://w3id.org/synapse/governance/shapes#`
  (`shape:UsageShape`, `shape:ActivityShape`, `shape:SynapseEntityShape`, ...).
  They no longer live in `gov:`.
- **One graph TBox and one shape set.** The files this repo imports from are
  deleted at HEAD: `shapes/governance_graph.owl.ttl`,
  `shapes/provenance_layer.shacl.ttl` and
  `linkml/examples/provenance/rdf/all_examples.ttl` (the raw URL at `3b1f247`
  returns 404). `shapes/governance.owl.ttl` (`owl:versionIRI
  <https://w3id.org/synapse/governance/0.2.0>`) now declares `gov:SynapseEntity`,
  `prov:Activity`, `prov:Usage` and every provenance property. `shapes/governance.shacl.ttl`
  holds their shapes. `governance_duo.owl.ttl` still exists, but it is the record
  layer only and no longer asserts anything on `prov:`. It must not be a source any
  more.
- **Term changes that reach this repo's data:**
  - `gov:url` is an `owl:ObjectProperty` (it was a DatatypeProperty), and
    `shape:UsageShape` requires `sh:nodeKind sh:IRI` on it.
  - Every Activity and Usage must be an IRI. `shape:ActivityShape` has
    `sh:nodeKind sh:IRI`, and so does its `prov:qualifiedUsage` value constraint.
    The blank-node Usages in this repo's example and fixtures fail.
  - `prov:Activity` has no `rdfs:subClassOf governanceduo:BaseEntity`, so the
    MIREOT `BaseEntity` root is obsolete.
  - `gov:SynapseEntity` carries its own `skos:closeMatch prov:Entity`. This repo
    has asserted that on governanceDUO's behalf until now. `model_refactor.md`'s
    downstream list says to drop it here.
  - `shape:SynapseEntityShape` is closed and has `gov:benefactor sh:minCount 1`.
    So any node typed `gov:SynapseEntity` in a graph validated against these shapes
    must carry a benefactor.
- **Instance IRIs (R2).** `scripts/graph_iris.py` mints activities as
  `https://w3id.org/synapse/governance/activity/<int>` and usages as
  `<activity IRI>/usage/<n>`. The canonical example
  (`linkml/examples/graph/rdf/governance_graph.ttl`) uses exactly these, for
  example `.../activity/1002/usage/1`. That supersedes `gov:activity-<n>`, which is
  D4 of governanceDUO's `plans/sagebrain_contract_and_owl_dl_fixes.md` and step 5
  of `plans/governance_layer_import.md`. Under a hash namespace,
  `gov:activity-reprocess01` would be an instance minted inside the term namespace,
  which R2 exists to prevent.
- **The Usage constraint got weaker (see Q2).** The hand-written `sh:xone` in the
  deleted `provenance_layer.shacl.ttl` required exactly one of (a) an entity
  reference or (b) `gov:url` + `gov:name`. The generated `shape:UsageShape` doesn't
  have it: every property is optional except `gov:wasExecuted`. `shape:ActivityShape`
  also lost `sh:minCount 1` on `prov:generated` and `prov:qualifiedUsage`. Checked
  with pySHACL against `shapes/governance.shacl.ttl`: a Usage with neither branch
  conforms, and so do a Usage carrying `prov:entity` + `gov:name` and an Activity
  with no inputs or outputs. The LinkML source (`linkml/graph/governance.yaml`,
  class `Usage`) has no `exactly_one_of`.

### Stale upstream docs (not used as a source of truth)

- governanceDUO `README.md`, "Release artifacts and IRI policy". The artifact table
  lists the four pre-refactor files, three of them deleted. The IRI policy still
  gives `https://sagebionetworks.org/governance/` and `<kind>-<id>` instance IRIs
  (`gov:activity-1001`, `gov:AR-42`). Both disagree with `shapes/*.ttl` and
  `scripts/graph_iris.py` at `3b1f247`. This plan follows the files.
- governanceDUO `plans/sagebrain_contract_and_owl_dl_fixes.md`, "sagebrain-model
  follow-up". Its file names, namespace and D4 are superseded by the refactor. Its
  rationale still holds and is kept here: D1 (`gov:name`), D9 (one owner per term
  and shape; sagebrain owns only the bridge), and the reason the bridge and its
  `prov:wasDerivedFrom` declaration live in `ontology/governance/`.
- The Phase 2 addendum's fix list (refresh the two imports and the pipeline
  example) is incomplete. It leaves out `sagebrain.ttl`, `sagebrain-shapes.ttl`,
  `examples/AD-cohort.ttl` and `ontology/imports/governance_graph.ttl`, which are
  **default-build** files that also use the old `gov:` IRI (for `gov:SynapseEntity`).
  It also leaves out the Usage/Activity IRI requirement and the `SynapseEntityShape`
  benefactor obligation. Full inventory: `git grep -l sagebionetworks.org/governance`
  gives 13 files. Twelve are listed in the steps below. The thirteenth is
  `plans/gene_expression_de_metadata.md`, a historical record left as it is.

### The pin

`3b1f2475e34cd44ed12d811e1cc4db8338ff5830` (`kg-conversion` HEAD, "Fix Turtle/SPARQL
CURIE syntax in the sagebrain-contract fixture and check"). Verified:

- `git ls-remote origin kg-conversion` gives `3b1f2475e34cd44ed12d811e1cc4db8338ff5830`,
  so it is pushed. `240a162` is its ancestor.
- `https://raw.githubusercontent.com/mc2-center/governanceDUO/3b1f2475e34cd44ed12d811e1cc4db8338ff5830/`
  serves `shapes/governance.owl.ttl`, `shapes/governance.shacl.ttl` and
  `linkml/examples/graph/rdf/governance_graph.ttl` with HTTP 200, byte-identical to
  `git show 3b1f247:<path>`. Unlike the last import, no seeded cache is needed.
- It is a commit, not a tag. governanceDUO's `GRAPH_VERSION` is `0.2.0`, but no tag
  exists, and `model_refactor.md` Phase 4 (term metadata on every `gov:` term,
  release `v0.2.0`) hasn't run yet. Expect another bump when it does. It changes
  annotations only, so it shouldn't change anything this plan relies on.

### Prototype (scratch copy, not this tree)

The steps below were run on a `git archive` copy of this branch in the session
scratchpad. `import.sh` ran against a cache seeded from `git show 3b1f247:<path>`,
identical to the raw URLs. Results:

- The regenerated extracts have the expected size. `governance_graph` has 1 class
  (`gov:SynapseEntity`, with upstream's `skos:closeMatch prov:Entity`).
  `governance_layer` has 2 classes, 4 object properties (`prov:entity`,
  `prov:generated`, `prov:qualifiedUsage`, `gov:url`) and 3 datatype properties.
  It has no `BaseEntity` and no punning.
- `python3 tests/validate.py` passes all 7 default checks, including check 7 (DL).
- `make WITH_GOVERNANCE=1 json` builds with 329 classes (`MIN_CLASSES` 100).
- The contract check (run directly, see Verification) gives this after the
  namespace move and the example rewrite:
  - `OWL 2 DL (union)`: pass
  - `prov: types`: pass
  - `ControlLabel reaches sagebrain Association`: pass
  - `SHACL (joined worked example)`: **fail**, with exactly one result,
    `Less than 1 values on syn:syn26999999->gov:benefactor` (Q1).

  Adding `syn:syn26999999 a gov:SynapseEntity ; gov:benefactor syn:syn26999999` to
  the join's governance side makes that part pass too.
- Check 8 needs the fixture and test changes in steps 8-9. Before them it fails on
  blank-node Usages, the benefactor obligation on the fixtures' typed `syn:` nodes,
  (m)'s missing message, and (n)'s missing message (`shape:ActivityShape`'s
  `prov:generated` pattern still catches (n), but with pySHACL's default message).

## Decisions needing approval before implementation

- **Q1. Joined-example SHACL and `syn:syn26999999`'s benefactor.** It blocks
  contract part 3. `examples/AD-cohort.ttl` types `syn:syn26999999 a gov:SynapseEntity`.
  That typing is required: `sagebrain-shapes.ttl`'s `derived_from` `sh:or` uses
  `sh:class gov:SynapseEntity`, and pySHACL only sees `rdf:type` in the data graph.
  Under the new namespace, `shape:SynapseEntityShape` then demands a
  `gov:benefactor`. The options:
  - **(A) Recommended, the canonical fix, needs an upstream commit.** governanceDUO's
    contract fixture `tests/sagebrain_contract/governance_binding.ttl` also types and
    benefactors `syn:syn26999999`, as it already does for `syn:syn27000001`. That
    file's own comment anticipates this. The governance graph owns the entity's ACL
    facts, and sagebrain only references the entity (D9). This plan doesn't edit
    governanceDUO, and if A is chosen the pin moves to that later commit.
  - (B) This repo's `AD-cohort.ttl` asserts `syn:syn26999999 gov:benefactor
    syn:syn26999999`. That's a workaround: a core-model example would state an ACL
    fact it doesn't own. Not chosen without approval.
  - (C) Upstream drops `minCount 1` on `gov:benefactor`. This weakens the canonical
    graph. Not recommended.

  The rest of the plan doesn't depend on the choice. Without A or B, parts 1, 2 and
  4 pass and part 3 fails on that one result.
- **Q2. The lost Usage `xone`, fixture defects (m) and (o).** This repo's violating
  fixture plants (m) (a Usage with neither `prov:entity` nor `gov:url`) and (o) (a
  Usage with `prov:entity` + `gov:name`). The imported shapes no longer catch
  either. The options:
  - **(A) Recommended, the canonical fix, upstream.** governanceDUO restores the
    constraint in the shapes it owns. It could use `exactly_one_of` on `Usage` in
    `linkml/graph/governance.yaml`, if gen-shacl emits `sh:xone` for it, or a
    hand-written supplement, as `provenance_layer.shacl.ttl` was. Ideally it also
    restores `minCount 1` on `prov:generated`/`prov:qualifiedUsage`. (m) and (o)
    then stay as they are here. The fix could land in the same upstream commit as
    Q1(A), so the pin moves once.
  - (B) Interim: this plan retires (m) and (o) from `tests/governance_violating.ttl`
    and `tests/validate.py`, with a comment naming the upstream regression. The
    contract honestly gets weaker, and the tests are re-added when upstream fixes it.
  - (C) Workaround, not chosen: a sagebrain-local supplementary shape. That breaks
    D9 (one owner per shape).

  Step 8 and step 9 give the edits for (A) and for (B).
- **Q3. Which branch.** Recommended: implement on `governance-layer-import`, the
  current branch. It hasn't been PR'd yet, so the PR never ships a pin that
  governanceDUO has already moved past. The alternative is to open the PR at `240a162`
  first and do this on a follow-up branch.

Decided here, flagged for review but not blocking:

- **Keep the four module names and output paths, re-point their sources.** The
  modules keep their current names. `governance_graph` and `governance_layer` now
  both extract from `shapes/governance.owl.ttl`. The split never mirrored upstream
  files. It mirrors this repo's gating: `governance_graph.ttl` is in `MAIN_SOURCES`
  (the default build needs `gov:SynapseEntity` for `derived_from`'s range), and
  `governance_layer.ttl` is in `GOVERNANCE_SOURCES` (`WITH_GOVERNANCE=1`). One
  merged module would force the provenance terms into the default build or
  `SynapseEntity` out of it. So the split stays, from one source file.
  `ontology/shacl/governance_layer.shacl.ttl` keeps its path but now holds
  upstream's whole graph shape set, copied verbatim. Shapes can't be subset without
  hand-editing an owned artifact.
- **Rename the vendored example module.** `governance_provenance_examples`
  (`tests/governanceduo_provenance_examples.ttl`) becomes `governance_graph_example`
  (`tests/governanceduo_graph_example.ttl`). Its source is now the canonical graph
  example `linkml/examples/graph/rdf/governance_graph.ttl`, which also carries ACLs,
  ARs and approvals, so the old name would be wrong. It's byte-identical to
  `governance_graph_export/governance_graph.ttl`, the file upstream's own contract
  check reads. The `linkml/examples/...` path is the upstream source.
- **The pipeline example follows R2.** Activities become
  `<https://w3id.org/synapse/governance/activity/<n>>`, with fictional numeric
  Synapse activity ids, and usages become `<activity>/usage/<n>`. This is the same
  honest fiction the `syn:` ids already get: a real id would mint the identical node
  in both graphs.
- **The pipeline example stops typing its `syn:` nodes.** `a gov:SynapseEntity` is
  dropped for `syn:syn27000001/2` and `syn:syn26999999` in
  `examples/pipeline_provenance.ttl`, as it is in upstream's canonical example. The
  provenance shapes check entity references by IRI pattern, not `sh:class`. Keeping
  the typings would give each node a benefactor obligation (Q1) for no benefit.
  `AD-cohort.ttl` keeps its typing, which `sagebrain-shapes.ttl` needs.
- **No `owl:versionInfo` bump** on `sagebrain.ttl`. The ontology's own version is
  unchanged. This moves the IRI of a reused term, and the reuse annotations say so.

## Approach

One commit per step, in this order. `python3 tests/validate.py` (default) stays
green at every commit, because steps 2-3 move the default-build files together.
`WITH_GOVERNANCE=1` is red between steps 5 and 9 and green from step 9 on. That's
the same precedent the original import set (`8454abe`..`54c7fdc`): check 8 is
opt-in, and a granular sequence is preferred over one bundle.

1. **`scripts/import.sh`: re-pin and re-point the governanceDUO modules.**
   - `GOVERNANCEDUO_COMMIT="3b1f2475e34cd44ed12d811e1cc4db8338ff5830"`, or the
     upstream commit Q1(A)/Q2(A) lands in.
   - `governance_graph_URL` and `governance_layer_URL`:
     `${GOVERNANCEDUO_RAW}/shapes/governance.owl.ttl`.
   - `governance_graph_NS` and `governance_layer_NS`: `https://w3id.org/synapse/governance#`.
     Bare names still resolve against NS. The hash ends the string, so
     `${ns}${term}` stays correct.
   - `governance_layer_ROOTS=()`, dropping the `BaseEntity` root. Rewrite its
     comment: there's no named ancestor to stop at now.
   - `governance_layer_shapes_URL`: `${GOVERNANCEDUO_RAW}/shapes/governance.shacl.ttl`.
     Rewrite the comment: the whole generated graph shape set, `shape:` namespace.
   - Rename `governance_provenance_examples` to `governance_graph_example`, with
     URL `${GOVERNANCEDUO_RAW}/linkml/examples/graph/rdf/governance_graph.ttl`,
     OUTPUT `$ROOT/tests/governanceduo_graph_example.ttl`, and update `MODULES`.
     `copy_module()`'s `*_examples` dispatch glob becomes `*_example|*_examples`,
     or the module is named so it still matches. The implementer should pick the
     smaller diff.
   - Update every comment that names `shapes/governance_duo.owl.ttl`,
     `governance_graph.owl.ttl`, `provenance_layer.shacl.ttl`,
     `gov:UsageShape`/`gov:ActivityShape` or `BaseEntity`. Module *outputs* aren't
     regenerated in this commit, so the tree stays green.
2. **The core namespace move: `governance_graph.ttl` and its default-build users,
   together.**
   - Run `scripts/import.sh governance_graph`. It regenerates
     `ontology/imports/governance_graph.ttl` with the new versionIRI, `dcterms:source`,
     `gov:SynapseEntity` IRI, and upstream's label, definition and closeMatch.
   - Rebind `@prefix gov:` to `<https://w3id.org/synapse/governance#>` in
     `ontology/main/sagebrain.ttl`, `ontology/shacl/sagebrain-shapes.ttl` and
     `examples/AD-cohort.ttl`.

   These four must land in one commit: checks 2 (endpoint integrity), 6
   (`AD-cohort.ttl`) and 7 (DL) fail if the extract and its users disagree on the
   IRI. It's a prefix rebind, so no term's local name changes.
3. **`sagebrain.ttl`: drop the `gov:SynapseEntity` closeMatch governanceDUO now
   asserts.**
   - Remove `skos:closeMatch prov:Entity` from the `gov:SynapseEntity` reuse block.
     The regenerated extract carries upstream's own.
   - Rewrite its `skos:editorialNote`: `governance_graph.yaml/shapes/governance_graph.owl.ttl`
     becomes `shapes/governance.owl.ttl`, the graph layer's generated TBox.
   - Keep `skos:scopeNote` and `owl:versionInfo`, which are this repo's reuse
     annotations.
4. **Regenerate `ontology/imports/governance_layer.ttl`** with
   `scripts/import.sh governance_layer`. Same nine LOWER terms. `gov:url` becomes
   an ObjectProperty, the terms move to the new namespace, and `BaseEntity` goes.
   Check 8's union DL and PROV type-agreement parts still pass, since the old-namespace
   data doesn't collide with the new IRIs.
5. **Regenerate `ontology/shacl/governance_layer.shacl.ttl`** with
   `scripts/import.sh governance_layer_shapes`. From here until step 9,
   `WITH_GOVERNANCE=1` is red.
6. **Vendored example.** Run `scripts/import.sh governance_graph_example`, which
   writes `tests/governanceduo_graph_example.ttl`. Then
   `git rm tests/governanceduo_provenance_examples.ttl`, and repoint
   `GOVERNANCEDUO_PROVENANCE_EXAMPLES` in `tests/validate.py` (renamed
   `GOVERNANCEDUO_GRAPH_EXAMPLE`) and its print label.
7. **`examples/pipeline_provenance.ttl` and `examples/README.md`.**
   - `gov:` goes to the new namespace.
   - Activities become `<https://w3id.org/synapse/governance/activity/<n>>`, with
     `gov:name` on each Activity (optional, as in the canonical example). Usages
     become `<activity>/usage/1|2` IRIs, typed `prov:Usage`, not blank nodes.
   - `gov:url` values become IRIs (`<https://nf-co.re/rnaseq/3.11.1>`, and so on).
   - Drop the three `a gov:SynapseEntity` typings (see "decided here").
   - Rewrite the header comment: the new source file, R2 IRIs instead of
     `gov:activity-<id>`, and why the `syn:` nodes are untyped.
   - `examples/README.md`: same renames, plus the table row and the "Pipeline
     provenance" paragraph.
8. **Governance fixtures.**
   - `tests/governance_conforming.ttl`: new namespace, IRI Usages
     (`<https://example.org/sagebrain-test/activity1/usage/1>`, and so on), IRI
     `gov:url`s, `syn:` typings dropped. Keep the two-output Activity.
   - `tests/governance_violating.ttl`: new namespace and IRI Usages throughout, so
     each Activity still fails for exactly its planted reason.
     - (n) is unchanged in intent. It's caught by `shape:ActivityShape`'s
       `prov:generated` pattern.
     - Under Q2(A), (m) and (o) stay.
     - Under Q2(B), remove (m) and (o), leaving a comment block that names the
       upstream regression and the governanceDUO file to fix.
   - Header comments: `gov:UsageShape`/`gov:ActivityShape` become
     `shape:UsageShape`/`shape:ActivityShape`.
9. **`tests/validate.py`.**
   - `derivation_ancestors()`: the `PREFIX gov:` becomes the new namespace. The
     docstring points at upstream's `projections/provenance.rq` (same logic:
     `gov:wasExecuted false` usages) instead of the removed `add_was_derived_from()`.
   - Expected violations. The imported shapes carry no custom `sh:message`, so
     match on the report instead of message text:
     `(focus node, sh:resultPath, sh:sourceConstraintComponent)`. For (n) that's
     `ex:activityN`, `prov:generated`, `sh:PatternConstraintComponent`. Generalize
     `check_usage_name_leak()` into one focus-node helper used by every entry.
     - Under Q2(A), (m) and (o) use the same helper against whatever component
       upstream's restored constraint reports (`sh:XoneConstraintComponent` if it's
       an `sh:xone`).
     - Under Q2(B), drop them.
   - Comments and the module docstring (check 8): `shape:` shape names, "the whole
     graph shape set", and the renamed vendored example.
   - `GOVERNANCE_DL_SOURCES` and `check_prov_types()` are unchanged.
10. **`ontology/governance/provenance_bridge.ttl`: comments only, axiom re-verified.**
    - The axiom and the `prov:wasDerivedFrom a owl:ObjectProperty` declaration
      don't depend on the namespace. The reason for the declaration still holds:
      `prov.ttl` is still outside the DL-checked set (`GOVERNANCE_DL_SOURCES`,
      `EXTERNAL_VOCABULARIES` upstream).
    - Update the comment's `gov:UsageShape/gov:ActivityShape` to
      `shape:UsageShape/shape:ActivityShape`.
    - Verified by step 9's ancestry assertion (reachable with the bridge, not
      without) and by contract part 4.
11. **`README.md`, the governance section and "Validating".** Update the module
    table: new source file, renamed example module, `shape:` shapes as "governanceDUO's
    graph shape set". Update the pin description, and the wording "its example ABox"
    to "its canonical graph example".
12. **`plans/governance_layer_import.md`: append a superseded note.** Same pattern
    as `959635e`. The note says the following were superseded by this plan:
    - its pin;
    - its source files;
    - step 5's `gov:activity-*` IRIs;
    - (m) and (o), if Q2(B).
13. **Implementation Report**, appended to *this* file as its own commit, the
    convention in `plans/governance_layer_import.md`.

Out of scope, noted: `tools/strip_external_flags.py`'s `OWN_IRIS` lists neither the
old nor the new `gov:` namespace (it has a stale `https://synapse.org/synbiont/governance`).
Whether governanceDUO terms render as first-party is a viewer decision, and it's
tied to `webvowl`'s `ontologyGroups.js` `RANK_OWN`. Nothing in this repo matches
`gov:SynapseEntity` by the old IRI outside the files above. sagebrain-infra was not
checked. It reads governanceDUO's `authorizer_v1` projection, which stays in the
old namespace by design (`model_refactor.md`, decision 1b).

## Verification

Run from this repo's root unless noted.

- **Pin reachability:**
  - `git -C /Users/obanks/mc2-center/governanceDUO ls-remote origin kg-conversion`
    shows the pinned hash (or the Q1/Q2 commit is an ancestor of it).
  - `curl -sI` on each of the three raw URLs returns 200.
- **Import reproducibility:**
  - Delete the cached `build/governance_*-<pin>.source.ttl` files so the URLs are
    actually fetched, then run
    `scripts/import.sh governance_graph governance_layer governance_layer_shapes governance_graph_example`.
  - `git status` is clean afterwards: fetched bytes = committed bytes.
  - A second run from cache: still no diff.
- **No stale references:**
  - `git grep -n 'sagebionetworks.org/governance'` returns hits only under `plans/`.
  - `git grep -nE 'governance_graph\.owl|provenance_layer\.shacl|governance_duo\.owl|all_examples\.ttl|BaseEntity|gov:(Usage|Activity)Shape'`
    returns hits only under `plans/`.
- **Extract shape:**
  - `ontology/imports/governance_graph.ttl` declares exactly one class,
    `<https://w3id.org/synapse/governance#SynapseEntity>`, with `skos:closeMatch prov:Entity`.
  - `ontology/imports/governance_layer.ttl` declares `prov:Activity`, `prov:Usage`,
    `prov:entity`, `prov:generated`, `prov:qualifiedUsage` and `gov:url` as object
    properties, `gov:wasExecuted`, `gov:entityVersionNumber` and `gov:name` as
    datatype properties, and no `governance-duo/BaseEntity`.
- **Default suite:** `python3 tests/validate.py` gives "All checks passed", with
  check 7 (DL) not skipped (`make tools` first). Run it at every commit in the Approach.
- **Governance suite:** `WITH_GOVERNANCE=1 python3 tests/validate.py` gives "All
  checks passed":
  - the conforming fixture;
  - (n) by focus node and pattern component, plus (m)/(o) under Q2(A);
  - `pipeline_provenance.ttl`;
  - `governanceduo_graph_example.ttl`;
  - governance-layer union DL;
  - PROV type agreement;
  - `apoe-expr-samp01 reaches Synapse:syn27000001 ... (with bridge: True, without: False)`.
- **Bite checks** (edit, observe the failure, revert):
  - Pointing `ex:activityN`'s `prov:generated` back at a `syn:` IRI makes (n)'s
    assertion fail.
  - Removing `provenance_bridge.ttl`'s `rdfs:subPropertyOf` makes the ancestry check
    fail.
  - Setting `gov:url` back to `owl:DatatypeProperty` in `governance_layer.ttl` makes
    the governance-layer union DL check fail.
- **Builds:**
  - `make json` builds, meeting the `MIN_CLASSES` 30 floor.
  - `make WITH_GOVERNANCE=1 json` builds, meeting the 100 floor. The prototype gave
    329 classes.
  - `build/sage.json` carries `https://w3id.org/synapse/governance#SynapseEntity`,
    `#wasExecuted`, `#url` and `#name`, plus `prov:Activity` and `prov:Usage`.
- **governanceDUO's contract check (read-only there).** Prefer the direct
  invocation. The `make sagebrain-contract-check` target first runs `graph-tbox`
  and `governance-graph`, which rewrite tracked files in that checkout:
  ```sh
  cd /Users/obanks/mc2-center/governanceDUO && \
    python3 scripts/check_sagebrain_contract.py \
      --sagebrain-model /Users/obanks/sagebrain-model --robot-jar tools/robot.jar
  ```
  - Expected with Q1(A) or Q1(B): `pass` on all four parts, then "sagebrain contract
    check passed".
  - Expected without either: parts 1, 2 and 4 `pass`, and part 3 `FAIL` with the
    single message `Less than 1 values on syn:syn26999999->gov:benefactor`.
  - Anything else is a regression in this plan's changes.
  - Afterwards, `git -C /Users/obanks/mc2-center/governanceDUO status --short` shows
    nothing new beyond the pre-existing `plans/model_refactor_report.md` edit.
- **Pre-PR:** per this repo's standing convention, an independent SME-framed review
  (OWL 2 DL / RDF / SHACL, PROV-O usage, and the governanceDUO contract) runs on the
  branch after the Implementation Report. Its findings are addressed before
  `gh pr create`.

## Process

Commit this plan on its own. Get approval on Q1-Q3; if Q1(A)/Q2(A) are chosen,
wait for the upstream commit and use its hash in step 1. Implement in the granular
commits above, one per numbered step. Append an Implementation Report to this file
as its own commit, covering commits, deviations, and verification actually run
with results. Then run the pre-PR SME review before `gh pr create`.

## Implementation Report (2026-09-24)

Implemented on `governance-layer-import`, one commit per numbered step:

| step | commit | message |
|---|---|---|
| 1 | `0c9b635` | import.sh: re-pin governanceDUO and re-point the governance modules |
| 2 | `eede778` | imports+sagebrain: move the core namespace to https://w3id.org/synapse/governance# |
| 3 | `63564c0` | sagebrain.ttl: drop the gov:SynapseEntity closeMatch governanceDUO now asserts |
| 4 | `33d5e04` | imports: regenerate governance_layer.ttl from governanceDUO's merged TBox |
| 5 | `dbeca98` | shacl: regenerate governance_layer.shacl.ttl from governanceDUO's graph shapes |
| 6 | `12eef14` | tests: vendor governanceDUO's canonical graph example, not the deleted ABox |
| 7 | `8fcde0b` | examples: move pipeline_provenance.ttl onto governanceDUO's R2 IRI policy |
| 8 | `40821ee` | tests: move governance fixtures onto the new namespace and IRI Usages |
| 9 | `2e30d0d` | tests: match governance defects structurally, not by message text |
| 10 | `d413e9d` | governance: update provenance_bridge.ttl's comment to shape:UsageShape/ActivityShape |
| 11 | `8344606` | README: describe the realigned governance import |
| 12 | `8efca60` | plans: note governance_layer_import.md is superseded by the realignment |

**Q1/Q2 resolution used:** the corrected pin
`04825a2ed2341e6b10c5ad6d118d3e6e48a3fe71` (not the plan's originally-prototyped
`3b1f247`), the commit both Q1(A) (`syn:syn26999999` benefactor in
governanceDUO's own sagebrain-contract fixture) and Q2(A) (restored `exactly_one_of`
on `Usage`, restored `minCount 1` on `Activity.generated`/`qualifiedUsage`) land
in. Confirmed reachable: `git ls-remote origin kg-conversion` at governanceDUO
gives this hash exactly, and `git merge-base --is-ancestor` confirms it.

**Deviation: defect (o) is not fully restored, and this repo's checks do not
claim it is.** `tests/governance_violating.ttl`'s (o) -- a Usage carrying both
`prov:entity` and `gov:name` -- was expected (per Q2's framing, and per the
superseded plan's own verification notes) to be caught by the restored
`shape:UsageShape` via `sh:XoneConstraintComponent`, the same way (m) is.
Verified directly with pyshacl against `shapes/governance.shacl.ttl` at the
pinned commit: it is not. The restored shape comes from a LinkML
`exactly_one_of` with only presence conditions (`entity` required, OR
`name`+`url` both required) and no exclusions -- unlike the old hand-written
`sh:xone` (`provenance_layer.shacl.ttl`), which explicitly zeroed out
`gov:url`/`gov:name` inside the entity branch. So the entity branch of the
restored shape conforms whenever `prov:entity` is present, regardless of an
extraneous `gov:name`, and (o) produces zero SHACL violations. This is a real
gap in the upstream restoration, not a bug in this plan's checks or fixtures.
Handled by keeping (o) in the fixture (undisturbed, as data) but not asserting
it in `EXPECTED_GOVERNANCE_VIOLATIONS`; `tests/validate.py`'s check 8 instead
prints a `NOTE` line naming the gap so it stays visible rather than silently
dropped. `python3 tests/validate.py` and `WITH_GOVERNANCE=1 python3
tests/validate.py` both report all-checks-passed with this in place. This
should be flagged in the pre-PR SME review, and is a candidate for a further
upstream fix (out of scope here: no governanceDUO file was touched).

No other deviations from the Approach or the corrected Q1/Q2 branch. Step 2's
four files landed together in one commit; `python3 tests/validate.py` stayed
green at every commit; `WITH_GOVERNANCE=1 python3 tests/validate.py` was red
from step 5 through step 8 and green from step 9 on, as specified.

**Verification results:**

- **Pin reachability.** `git -C /Users/obanks/mc2-center/governanceDUO
  ls-remote origin kg-conversion` returns `04825a2ed2341e6b10c5ad6d118d3e6e48a3fe71`
  exactly (current branch HEAD); `git merge-base --is-ancestor` confirms it.
  `curl -sI` on all three raw URLs (`shapes/governance.owl.ttl`,
  `shapes/governance.shacl.ttl`, `linkml/examples/graph/rdf/governance_graph.ttl`)
  returned HTTP 200.
- **Import reproducibility.** Deleted the four cached
  `build/governance_*-04825a2e....source.ttl` files, re-ran
  `scripts/import.sh governance_graph governance_layer governance_layer_shapes
  governance_graph_example`: `git status` was clean afterwards (fetched bytes =
  committed bytes). A second run from cache: still no diff.
- **No stale references.** `git grep -n 'sagebionetworks.org/governance'`
  returns no hits at all outside `plans/` (none inside the changed files).
  `git grep -nE 'governance_graph\.owl|provenance_layer\.shacl|governance_duo\.owl|all_examples\.ttl|BaseEntity|gov:(Usage|Activity)Shape'`
  returns hits only in `plans/` and in explanatory "previously X"/"superseded"
  comments in `scripts/import.sh`, `tests/governance_violating.ttl` and
  `tests/validate.py` -- no live reference to the old files/IRIs/namespace.
- **Extract shape.** `ontology/imports/governance_graph.ttl` declares exactly
  one class, `<https://w3id.org/synapse/governance#SynapseEntity>`, with
  `skos:closeMatch prov:Entity`. `ontology/imports/governance_layer.ttl`
  declares `prov:Activity`, `prov:Usage`, `prov:entity`, `prov:generated`,
  `prov:qualifiedUsage` and `gov:url` as object properties (4 real ones plus
  `owl:topObjectProperty`), `gov:wasExecuted`/`gov:entityVersionNumber`/`gov:name`
  as datatype properties, and no `governance-duo/BaseEntity`.
- **Default suite:** `python3 tests/validate.py` -- "All checks passed.",
  8 checks (check 7/DL not skipped, ROBOT present).
- **Governance suite:** `WITH_GOVERNANCE=1 python3 tests/validate.py` -- "All
  checks passed.": conforming fixture; (m)/(n) by focus node + constraint
  component (`sh:XoneConstraintComponent` / `sh:PatternConstraintComponent`);
  (o) printed as a documented `NOTE`, not asserted; `pipeline_provenance.ttl`;
  `governanceduo_graph_example.ttl`; governance-layer union OWL 2 DL;
  PROV type agreement; `apoe-expr-samp01 reaches Synapse:syn27000001` (with
  bridge: True, without: False).
- **Bite checks**, each edited, observed to fail, and reverted (`git diff
  --stat` clean afterwards):
  - Pointing `ex:activityN`'s `prov:generated` back at a `syn:` IRI: (n)'s
    assertion fails as expected.
  - Removing `provenance_bridge.ttl`'s `rdfs:subPropertyOf`: the ancestry
    check fails (`with bridge: False`) as expected.
  - Setting `gov:url` back to `owl:DatatypeProperty` in `governance_layer.ttl`:
    the governance-layer union OWL 2 DL check fails as expected.
- **Builds.** `make json`: 50 classes (`MIN_CLASSES` 30 floor). `make
  WITH_GOVERNANCE=1 json`: 329 classes (`MIN_CLASSES` 100 floor) -- matches the
  plan's prototype exactly. `build/sage.json` (governance build) carries
  `https://w3id.org/synapse/governance#SynapseEntity`, `#wasExecuted`, `#url`
  and `#name`, plus `prov:Activity` and `prov:Usage`; confirmed by direct
  string search. Rebuilt the default (non-governance) `build/sage.json`
  afterwards so the working tree's build artifact matches a plain `make json`.
- **governanceDUO's contract check** (read-only there):
  ```
  pass  OWL 2 DL (union)
  pass  prov: types match sagebrain's prov.ttl
  pass  SHACL (joined worked example)
  pass  ControlLabel reaches sagebrain Association
  sagebrain contract check passed against /Users/obanks/sagebrain-model.
  ```
  All four parts pass, as expected now that both Q1(A) and Q2(A) are landed
  upstream and this plan realigns sagebrain-model's side. Afterwards,
  `git -C /Users/obanks/mc2-center/governanceDUO status --short` showed only
  the pre-existing `plans/model_refactor_report.md` edit that was already
  present before this work started -- nothing new.

**Not yet done:** the pre-PR SME-framed review (OWL 2 DL / RDF / SHACL,
PROV-O usage, and the governanceDUO contract), which should specifically weigh
in on the (o) deviation above before `gh pr create`.
