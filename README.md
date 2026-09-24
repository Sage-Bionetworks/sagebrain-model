# sagebrain-model

The Sage Brain ontologies.

```
ontology/main/        the ontologies under active development -- built by default
ontology/governance/  bridges from this model into the governance layer (opt-in)
ontology/imports/     third-party vocabularies, as extracted modules
ontology/mappings/    claims we assert about external vocabularies (placeholder)
ontology/shacl/       constraints over the above
examples/             validated example instance data that conforms to the model
scripts/import.sh     regenerates the import modules
tests/validate.py     SHACL validation and anti-drift checks
```

## Reused vocabulary

The model is tied to the [Biolink Model](https://biolink.github.io/biolink-model/)
in two different ways:

| Model term | Biolink term | Relation | Biolink's own anchor |
|---|---|---|---|
| gene | `biolink:Gene` | **reused by IRI** | SO_0000704 |
| pathway | `biolink:Pathway` | **reused by IRI** | PW_0000001 |
| disease label | `biolink:Disease` | **reused by IRI** | MONDO_0000001 |
| drug compound | `biolink:Drug` | **reused by IRI** | CHEBI_23888 |
| clinical trial | `biolink:ClinicalTrial` | **reused by IRI** | NCIT_C71104 |
| sample | `biolink:MaterialSample` | **reused by IRI** | OBI_0000747 |
| participates in | `biolink:participates_in` | `sagebrain:participates_in rdfs:subPropertyOf` it | RO_0000056 |
| used to treat | `biolink:treats` | `sagebrain:used_to_treat rdfs:subPropertyOf` it | — |

Classes reuse BioLink IRIs directly: a SageBrain graph is Biolink data for those terms, with
no mapping step, and each one brings the OBO anchor Biolink already records for it.

The properties are a different case; `sagebrain.ttl` prefers to narrow them.

`ontology/imports/biolink.ttl` is a MIREOT module holding reused terms and
the ancestors that make their hierarchy meaningful. 
It is meant to be committed and regenerated only when new versions are chosen.

```sh
$EDITOR scripts/import.sh    # biolink_VERSION=..., biolink_LOWER=(...)
make imports                 # re-extract; read the diff before committing
python tests/validate.py
```

### The governance layer (mc2-center/governanceDUO)

The governance graph (access requirements, ACLs, Synapse provenance) is owned
by [governanceDUO](https://github.com/mc2-center/governanceDUO) and is a layer of
this graph: same store, same IRIs. This repo imports it rather than keeping
copies. `scripts/import.sh` pins one governanceDUO commit (`GOVERNANCEDUO_COMMIT`)
for all four of its modules:

| module | output | what |
|---|---|---|
| `governance_graph` | `ontology/imports/governance_graph.ttl` | `gov:SynapseEntity`, the range of `sagebrain:derived_from`; default build |
| `governance_layer` | `ontology/imports/governance_layer.ttl` | `prov:Activity`/`prov:Usage` and the `prov:`/`gov:` properties the pipeline-provenance layer uses; `WITH_GOVERNANCE=1` only |
| `governance_layer_shapes` | `ontology/shacl/governance_layer.shacl.ttl` | governanceDUO's whole generated graph shape set (`shape:UsageShape`/`shape:ActivityShape` among them), copied verbatim from `shapes/governance.shacl.ttl` |
| `governance_graph_example` | `tests/governanceduo_graph_example.ttl` | governanceDUO's canonical graph example, a contract fixture |

`governance_graph` and `governance_layer` both extract from the same source file,
`shapes/governance.owl.ttl` -- governanceDUO's kg-conversion refactor merged its
hand-written `gov:` TBox and its LinkML-generated OWL into one graph TBox. The
split into two modules/outputs stays anyway, mirroring this repo's own build
gating rather than upstream's file layout.

The one thing this repo owns there is `ontology/governance/provenance_bridge.ttl`:
`sagebrain:derived_from rdfs:subPropertyOf prov:wasDerivedFrom`, so governanceDUO's
access labels carry from a Synapse file onto the Samples and Associations derived
from it. See `plans/governance_layer_import.md`.

## Visualization

The graph is rendered by [Sage-WebVOWL](https://github.com/anngvu/Sage-WebVOWL),
a fork of [WebVOWL](https://github.com/VisualDataWeb/WebVOWL) tailored to these
ontologies. It is vendored here as a git submodule at `webvowl/`.

This repo owns the ontology pipeline (merge → prune → convert → strip), because
the sources and the tooling (ROBOT / OWL2VOWL jars) live here; the submodule owns the
viewer. `make` installs the converted ontology into the submodule and builds it.

Clone with the submodule:

```sh
git clone --recurse-submodules https://github.com/<org>/sagebrain-model.git
```

Or, in a clone that already exists:

```sh
git submodule update --init --recursive
```

### Updating the viewer

The submodule is pinned to a specific commit; update deliberately with a commit:

```sh
git -C webvowl pull origin master
make viz                 # confirm the pinned version still builds
git add webvowl && git commit -m "Bump webvowl"
```

After pulling a commit that changes the submodule pointer, re-run
`git submodule update --init --recursive` to move your checkout to it.

## Building

Prerequisites: Java 11+ (ROBOT and OWL2VOWL), Node and Python 3 for the build;
`rdflib` and `pyshacl` for `tests/validate.py`.

```sh
make tools    # fetch the ROBOT (78 MB) and OWL2VOWL (10 MB) jars; neither is committed
make imports  # re-extract the import modules from upstream (needs network)
make json     # just the VOWL JSON -- no Node, no submodule needed
make viz      # convert the ontology and build the viewer into webvowl/deploy
make serve    # build, then serve it as a static site on :3000
make dev      # live-reloading: edit a .ttl and the open page updates itself
make config   # print the resolved paths and which sources are in play
make clean    # remove build artifacts (keeps the fetched ROBOT jar)
```

`make dev` runs a static server plus an ontology watcher. The dev bundle of the
viewer polls its own ontology JSON and reloads the graph when it changes, so no
livereload server is involved. If you are editing the viewer's own JS or CSS,
use `npm run webserver` inside `webvowl/` instead so those are rebuilt too.

Governance is excluded from the default build until it settles:

```sh
make WITH_GOVERNANCE=1 viz
```

Overridable variables: `ROBOT_JAR`, `OWL2VOWL_JAR`, `WEBVOWL_DIR`,
`WATCH_INTERVAL`, `DEV_PORT`, `MIN_CLASSES`, `VIEWER_BUILD`.

## Validating

```sh
python tests/validate.py
```

Seven checks by default: the shapes graph is valid SHACL; the ontology satisfies
its own model-integrity shapes; the conforming and violating fixtures behave as
expected; every connection is constrained by at least one active property shape,
so a connection cannot be added without a constraint; every file in `examples/`
still validates; and the merged ontology stays OWL 2 DL (needs `make tools`).

`WITH_GOVERNANCE=1 python tests/validate.py` adds the governance layer: its own
fixtures and example, plus contract checks against governanceDUO (its canonical
graph example conforms to the imported shapes, the union stays OWL 2 DL, `prov:`
types agree with W3C PROV-O, and the `derived_from` bridge carries derivation
ancestry).

