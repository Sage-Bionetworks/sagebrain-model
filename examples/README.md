# Examples

Instance data that conforms to the model. These files are documentation first —
this is the answer to "what does a SageBrain graph actually look like?" — and a
test second: `tests/validate.py` validates every `*.ttl` in this directory on
every run (check 6), so a model change that would break data a curator could
plausibly have written fails the test run.

| File | What it is |
|---|---|
| `minimal.ttl` | One gene in one pathway. A one-screen answer to "show me the format" |
| `AD-cohort.ttl` | Two participants, three samples, three genes, two pathways, a drug and a trial — 76 triples exercising 17 of the model's 19 connections |

## Identifiers

Every external identifier in these files was resolved against its source
registry — genenames.org, OLS, Reactome, ClinicalTrials.gov — rather than
pattern-matched from memory, because a plausible-looking wrong CURIE in an
example is worse than no example. Prefixes follow Biolink's prefix map, since
the model reuses Biolink terms.

Pathology draws on both tiers, because its two findings differ in kind. Plaque
burden is graded, and CERAD is a scale of graded categories, so `adkp:FrequentDefiniteC3`
and `adkp:NoADC0` carry the grade in the node's identity — which is how the model
expresses burden at all, given that `sagebrain:has_pathology` has no weight (`B11`).
An HP term cannot do that: `HP:0100256` asserts senile plaques are present, full
stop. Tangles are the qualitative case, so they stay `HP:0002185`.

Nodes with no external identifier split in two. **Participants and samples** are
study-local particulars, minted under `https://w3id.org/synapse/ad/individual/` and
`https://w3id.org/synapse/ad/sample/` — one path per collection, so the local name
is the identifier within it.

Beside the model, not inside it: the model is `.../synapse/sagebrain`, its parts are
`sagebrain/shapes` and `sagebrain/imports/biolink`, and the data it describes is
`synapse/ad/`. Data outlives any one model of it, and these participants may end up
described by something other than SageBrain, so putting them under `sagebrain/` would
assert an affiliation that is hard to take back. Separating costs nothing here:
`w3id.org/synapse/` is a single registered namespace Sage controls through
[one .htaccess](https://github.com/perma-id/w3id.org/blob/master/synapse/.htaccess),
so a sibling path is an entry in that file rather than a new registration.

Everything else keeps a placeholder `ex:` namespace, because each is an open
question in `TODO.md` rather than something we have decided not to anchor:

- **tissue** — the source model states that tissue names are not standardised
  across diseases (`A3`)
- **disease status, disease stage** — no anchor identified. Verified gaps, not
  unfinished searching: Braak staging has no term in any ontology on OLS, and
  ALSFRS-R exists only in SNOMED CT, which needs an affiliate licence (`B15`).
  Biolink also models these as attributes rather than nodes (`B1c`)
- **biodomain** — deliberately SageBrain-native; names come from the AD biodomain
  paper cited on `sagebrain:belongs_to` (`B5`)

**The example does not have to cover the model.** It covers 17 of 19 connections, and
the two it drops are findings rather than gaps in the example: `has_status` and
`belongs_to` could not be written without inventing a vocabulary, so they were left
out. The model is a work in progress, and a statement that cannot be written honestly
is a signal about where to look — see "What is missing" below.

### Where a term comes from

1. **A grounding vocabulary**, if it has the term — HP for pathology, HGNC for
   genes, MONDO for disease, UBERON for anatomy, Reactome for pathways.
2. **The [AD Knowledge Portal data model](https://github.com/adknowledgeportal/data-models)**,
   if the grounding vocabulary does not. The term gets minted *there*, through that
   repo's PR process, not here — this model does not mint disease-specific
   vocabulary. Braak staging is the worked case: no ontology on OLS has a Braak term
   at all, while `AD.model.csv` has `Braak` with values `BRAAK Stage 1`–`6` (sourced
   from ADSP), so `adkp:BRAAKStage3` is the stage node in the example.
3. **Nothing.** If neither tier has the term, the statement is left out rather than
   given a placeholder IRI. No `example.org` node remains in these files.

Tier order holds even where the portal has its own value. Tissue is `UBERON:0000956`,
not the AD model's `cerebral cortex` value — the AD model's own `Source` for that row
*is* `UBERON_0000956`, so the ontology term is the real one and the portal value is an
annotation-layer alias. Worth knowing that their `hippocampus` row cites `BTO_0000601`
instead, so the portal list is not uniformly UBERON-backed; each tissue term needs
checking rather than assuming.

### What is missing

- **`sagebrain:has_status` / `DiseaseStatus`.** No vocabulary anywhere. The AD model's
  nearest terms — `no cognitive impairment`, `mild cognitive impairment`, `dementia` —
  are values of its `diagnosis` column, not a separate status axis. So either
  `DiseaseStatus` is a diagnosis under another name, in which case it duplicates
  `has_diagnosis`, or it is the symptomatic/pre-symptomatic axis it appears to be, in
  which case nobody has a vocabulary for it. Resolve that before minting one
  (`B2`, `B7`, `B15`).
- **`sagebrain:belongs_to` / `Biodomain`.** No ontology term and no AD model column.
  The names come from the AD biodomain paper cited on the property, which is a citation
  rather than a term list, so the 19 biodomains have to be minted somewhere first
  (`B5`).

**The `adkp:` namespace is provisional.** The AD model is a CSV today, published as
Synapse JSON Schemas, with no term IRIs at all. The example assumes the most likely
setup — schematic converts the CSV to JSON-LD, that file is served from the repo, and
terms hang off it as fragments:

    https://raw.githubusercontent.com/adknowledgeportal/data-models/refs/heads/main/AD.model#BRAAKStage3

The local name follows schematic's own label derivation, so `BRAAK Stage 3` →
`BRAAKStage3`. Three things to raise with the AD DCC before anyone depends on it
(`B15`):

- schematic has **two** derivation modes and they disagree. The default strips
  whitespace then camelizes (`cerebral cortex` → `Cerebralcortex`); strict mode
  converts whitespace to underscores first (`CerebralCortex`). Values already
  capitalized in the CSV come out the same either way, so tissue is where the choice
  shows. This file assumes strict.
- a `raw.githubusercontent.com` base ties term identity to a branch of a GitHub repo,
  which is not a persistence story.
- label-derived local names break on rename, which is exactly why OBO uses opaque
  numeric IDs.

So the policy these files demonstrate, which `B5` still has to ratify, has three
tiers: a registry identifier where the thing is in a registry, a Synapse-minted
IRI under `w3id.org/synapse/` where we own the thing, and a placeholder where the
modelling is still open. The third tier is meant to shrink — when `B1c` settles
what a disease status is, those nodes move up a tier.

## Why these are not the test fixtures

`tests/conforming.ttl` and `tests/violating.ttl` stay where they are. They are
fixtures, not examples: synthetic, minimal, and pinned to specific validator
behaviour. `violating.ttl` carries six planted defects that the shapes must
report, and `conforming.ttl` deliberately exercises the shared-vocabulary-node
pattern so that wrongly activating an `ISSUE-1` inverse shape breaks a test.
Neither reads as data anyone would collect.

These files are the opposite trade: realistic enough to hand to a curator, and
therefore not pinned to any particular validator edge case. Both roles are worth
having — but a fixture that drifts toward being a demo stops testing what it was
written to test.

## Adding an example

Write the `.ttl`, run `python tests/validate.py`, and check that `[6]` lists it.
No registration step: the check globs this directory.

Two things worth doing while you are there. Resolve any new identifier against
its registry and record what it resolved to in a header comment. And say why any
new `ex:` node had to be local — if the answer is "no reason", it should not be.
