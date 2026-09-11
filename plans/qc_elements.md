The pipeline we used to align RNA-seq data outputs a MultiQC report that we pull some of our QC metrics from. The other metrics come from the RNAseq counts or sample metadata.

For each metric, there are automatic failure conditions and optionally some warning conditions. Samples fail QC if:
- They hit a failure condition anywhere
- They have 2 or more warnings across all metrics

QC parameters to include
Note: do not include QC values in the graph. Only consider “FAIL” and “WARN” signals in the edges. For later versions, consider inclusion of values for parameters used in regression (DV200 / RIN, MultiQC)

FastQC (comes with MultiQC report)
Attribute: Phred score
Edge(s): (Phred score to Files)
Edge Value=Fail: Phred score >= 20 
Edge Value=Warn: base content is above Q3 + 1.5 * IQR for any base or Phred score is below Q1 - 1.5 * IQR

MultiQC
Attribute: Reads mapped (samtools_reads_mapped_percent)
Edge(s): (Reads mapped to Files)
Value=Fail: < 70% of reads mapped (samtools_reads_mapped_percent)
Value=Warn: less than Q1 - 1.5 * IQR mapped reads

Attribute: Duplicated reads (picard_PERCENT_DUPLICATION)
Edge(s): Duplicated reads to Files
Value=Fail: > 80% duplicated reads (picard_PERCENT_DUPLICATION)
Value=Warn: more than Q3 + 3 * IQR duplicated reads

Sex check (uses RNAseq counts of genes RPS4Y1, EIF1AY, DDX3Y, and KDM5D)
Calculate log2-CPM values for all 4 genes, then take the mean of the 4 values per individual
Attribute: sex check
Edge(s): Sex check to Files
Value=Fail: Reported sex is “Male” but mean_expr < 2-ish
Value=Fail: Reported sex is “Female” but mean_expr >= 2-ish
Threshold of 2 needs to be adjusted per dataset . Need to graph dataset and visually assess to determine threshold. Depends on counts distribution for the dataset.

DV200 / RIN
Assumes one or both of DV200 and RIN are available from the metadata
Attribute: DV200 / RIN
Edge(s): DV200 / RIN to Files
Value=Fail: both DV200 and RIN are missing
Value=Fail: DV200 < 50 if not missing
Value=Fail: RIN < 2.5 and DV200 is missing
If DV200 is not available at all for a data set, RIN threshold needs to be adjusted per dataset and should probably be based on Q1 - 1.5*IQR instead of a set number
The current QC requirements were determined based on DV200 being available for all but a few samples in DivCo, and using DV200 as the gold standard. Many other data sets don’t have DV200 values and provide RIN only.
Note: A standard RIN cut-off is not viable as values depend on the rnaSeq method.

---

Additional design notes

The core layers include:

Biomedical Metadata Layer  

Describes what data exists and its structure: studies, cohorts, specimens, assays, measures, files, locations, timepoints, etc. Connects to program metadata, CDM outputs, portals, and pipelines.

Biomedical Data Layer  

Represents higher-level abstractions of data (e.g., features, summary statistics, derived variables, annotations). Not intended to store every raw data point, but to model data entities and relationships that matter for queries and reasoning.

Publications & Scientific Knowledge Layer  

Captures links between the data/metadata and scientific outputs (papers, preprints, reports, analyses). Eventually supports tracing specific findings back to underlying data and context.

Research Communities & Collaborations Layer  

Represents people, teams, projects, collaborations, and their relationships to data, studies, and outputs. Helps answer questions like “who is working on what” and “which communities are connected by shared evidence?”

Governance & Policy Layer

Encodes dynamic governance and policy constraints: consent, access rules, data use agreements, privacy/ethics constraints. Cross-cuts all other layers; it influences how data and relationships can be queried or exposed.

(Future) Evidence & Reasoning Layer  

Represents scientific evidence (e.g., results, effect estimates, confidence levels, types of studies) and links between lines of evidence. Ultimately aims to help coalesce and navigate evidence to better understand disease, health, and interventions.

These layers are all implemented within or around a graph-based system, so that entities and relationships across layers can be traversed and queried flexibly.

External Systems & Integration Points
Sage Brain is not a replacement for existing systems at Sage. Instead, it is a knowledge infrastructure that integrates with them.

Systems that Feed Sage Brain
Examples (non-exhaustive):

Program Data & Pipelines, Disease-specific programs (e.g., NF, AD, ALS), Their data pipelines and curation processes  

Sage Common Data Model (CDM)  

The CDM is developed independently and is a major source of harmonized program metadata and structural knowledge. Sage Brain consumes CDM outputs when they are available, but does not own or develop the CDM itself.

Portals and Other Platforms  

Sage Brain’s architecture must be able to ingest and represent concepts and relationships derived from these systems, and to reflect back knowledge that can enrich them.

Systems that Use Sage Brain
Examples:

Synapse | Sage Bionetworks   

Uses the knowledge base to power richer search, navigation, or context for data and projects.

Disease & Domain-specific Portals  

Use knowledge-layer services to support more sophisticated discovery and cross-program exploration.

Internal Query Tools & APIs  

Power users, data scientists, and scientists query the graph directly or via APIs.

(Later) LLM & AI Interfaces  

Natural language interfaces that sit on top of the graph to answer biomedical questions.

Architectural Principles
Several principles guide the Sage Brain architecture:

Layered, Not Monolithic  

We explicitly think in layers (metadata, data, publications, communities, governance, evidence) to keep the architecture understandable and extensible.

Separation of Concerns  

Sage Brain focuses on the knowledge base and its representations, not on owning all upstream pipelines or downstream applications.  

The CDM, portals, and program pipelines remain responsible for their domains; Sage Brain integrates across them.

Flexibility & Extensibility  

The architecture must tolerate changing schemas, new entity types, and new relationships without constant re-architecture.  

We expect to iterate rapidly in early phases and refine over time.

Traceability & Provenance  

Relationships and entities should be traceable back to their sources (e.g., program, CDM version, pipeline, publication).  

This is critical for scientific integrity, governance, and future AI use.

Governance by Design  

Governance and policy are not an afterthought; they are incorporated conceptually as a governance layer that shapes what is visible and usable.

User-centric Interfaces  

Architecture decisions are informed by actual scientific and program use cases, not just technical elegance.  

The architecture is a means to support scientists, data managers, and program teams.