# sagebrain-model

The Sage Brain ontologies.

```
ontology/main/        the ontologies under active development -- built by default
ontology/governance/  the governance model (placeholder)
ontology/imports/     third-party vocabularies, as extracted modules
ontology/mappings/    claims we assert about external vocabularies
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

Six checks: the shapes graph is valid SHACL; the ontology satisfies its own
model-integrity shapes; the conforming and violating fixtures behave as expected;
every connection is constrained by at least one active property shape, so a
connection cannot be added without a constraint; and every file in `examples/`
still validates.

