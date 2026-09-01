# Synthetic Alzheimer–ALS contrast results

This self-contained fixture demonstrates the contrast-level model for the
question:

> Which pathways are altered in both Alzheimer disease and amyotrophic lateral
> sclerosis (ALS)?

It is separate from **kg/synthetic/**, which generates sample-level pathway
activity calls. Nothing here changes the production SageBrain ontology.

## Contents

| File | Purpose |
|---|---|
| **model.ttl** | Small, explicitly provisional vocabulary for contrasts, groups and results |
| **data.ttl** | Two synthetic case-versus-control contrasts and ten pathway results |
| **shared-altered-pathways.rq** | The Alzheimer/ALS intersection query |
| **validate.py** | Parses the RDF, checks result/edge consistency and asserts the query answer |

The fixture references real MONDO, UBERON and Reactome identifiers, but every
study, group, effect estimate and p-value is synthetic. All fixture-owned IRIs
contain **/synthetic/contrast/**, and the dataset and analysis nodes carry the
synthetic flag.

## Representation

The primary statement is a reified result:

    Contrast → PathwayContrastResult → Reactome pathway
                           ├── direction
                           ├── effect size
                           ├── p-value
                           └── adjusted p-value

The Biolink subject points from the result to the contrast and the Biolink object
points to the Reactome pathway. The Biolink predicate records whether pathway
activity increased or decreased in cases relative to controls.

For convenient traversal, significant results are also materialized as:

    Contrast → sagebrain:de_associated_with → Pathway

This reuses the existing SageBrain predicate with a contrast as its subject, and
**as of model v0.3 that is what the ontology declares.** `rdfs:domain` on
`sagebrain:de_associated_with` is now `sagebrain:PathwayActivityContrast`, and
`model.ttl` declares the fixture's class a subclass of it.

Earlier revisions of this file carried a warning instead: the domain was
`biolink:MaterialSample`, so loading this fixture alongside the production
ontology under RDFS inference would have typed every contrast as a material
sample. The fixture made the intended migration visible without silently
performing it. That migration has now landed, and the per-sample claim it
displaced lives on `sagebrain:has_altered_activity_in` — see
[../synthetic-samples/](../synthetic-samples/README.md), which is the same
biology one granularity down.

## Planted answer

The adjusted-p threshold is stored on the dataset as 0.05. The ten results
include two shared signals, one Alzheimer-only signal, one ALS-only signal and
one null pathway:

| Pathway | Alzheimer | ALS | Expected in shared answer? |
|---|---|---|---|
| Toll Like Receptor 4 (TLR4) Cascade | increased, q=0.004 | increased, q=0.012 | yes |
| Transmission across Chemical Synapses | decreased, q=0.009 | decreased, q=0.006 | yes |
| Regulation of cholesterol biosynthesis by SREBP | decreased, q=0.018 | q=0.31 | no |
| Glutamate Neurotransmitter Release Cycle | q=0.67 | decreased, q=0.002 | no |
| Mitochondrial translation | q=0.44 | q=0.51 | no |

The biological-looking labels make the demo readable; they are not claims about
observed Alzheimer or ALS biology.

## Run

The validation loads the fixture together with the existing Reactome v97 pathway
file, proving that every result lands on a pathway already present in the graph:

    python examples/synthetic-contrasts/validate.py

Expected query answer: exactly the TLR4 cascade and Transmission across Chemical
Synapses, with the direction, effect size and adjusted p-value for each disease.

This answers cross-disease overlap. With only one contrast per disease it does
not demonstrate within-disease replication across independent cohorts; that
would require at least two Alzheimer contrasts and two ALS contrasts.
