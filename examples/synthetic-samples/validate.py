"""Parse and validate the sample-level pathway fixture, then run its demo query.

The interesting assertions are the ones that would pass vacuously if the excerpt
were empty or malformed, so each states a count as well as a property. In
particular: the decoy must have NO results, and the control sample must exist
with none -- absences that a check written only over what IS present would miss.
"""

from pathlib import Path

from rdflib import Graph, Namespace, RDF, URIRef


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

BIOLINK = Namespace("https://w3id.org/biolink/vocab/")
SAGEBRAIN = Namespace("https://w3id.org/synapse/sagebrain#")
SBKG = Namespace("https://w3id.org/sagebrain/vocab/")
PROV = Namespace("http://www.w3.org/ns/prov#")
REACT = Namespace("https://identifiers.org/reactome:")

ALZHEIMER = URIRef("http://purl.obolibrary.org/obo/MONDO_0004975")
ALS = URIRef("http://purl.obolibrary.org/obo/MONDO_0004976")

DECOY = REACT["R-HSA-5368287"]           # Mitochondrial translation
DISCORDANT = REACT["R-HSA-8978868"]      # Fatty acid metabolism
SHARED_UP = REACT["R-HSA-166016"]        # TLR4 Cascade


def load_graph() -> Graph:
    """The fixture plus the Reactome graph it references.

    pathways.ttl is read from the repo rather than copied in: the pathway nodes
    belong to the other named graph, and duplicating them here would quietly
    turn a reference into a fork that stops tracking Reactome releases.
    """
    graph = Graph()
    for path in (HERE / "data.ttl", ROOT / "data/reactome/v97/ttl/pathways.ttl"):
        if not path.exists():
            raise SystemExit(
                f"missing required file: {path.relative_to(ROOT)}\n"
                f"  regenerate the fixture: python -m kg.synthetic.make_example\n"
                f"  or the Reactome graph:  python -m kg.reactome.pipeline "
                f"--version 97 --skip-download"
            )
        graph.parse(path, format="turtle")
    return graph


def validate_results(graph: Graph) -> int:
    results = set(graph.subjects(RDF.type, BIOLINK.StudyResult))
    if not results:
        raise AssertionError("no results in the fixture; nothing below tests anything")

    for result in results:
        pathways = list(graph.objects(result, BIOLINK.object))
        if len(pathways) != 1:
            raise AssertionError(f"{result} must have exactly one pathway object")
        if (pathways[0], RDF.type, BIOLINK.Pathway) not in graph:
            raise AssertionError(f"{pathways[0]} does not resolve to a Reactome pathway")
        for required in (BIOLINK.subject, BIOLINK.predicate, BIOLINK.z_score,
                         BIOLINK.p_value, BIOLINK.adjusted_p_value):
            if not list(graph.objects(result, required)):
                raise AssertionError(f"{result} is missing {required}")

        # B17: the number is meaningless without the group it is relative to.
        analyses = list(graph.objects(result, PROV.wasGeneratedBy))
        if len(analyses) != 1:
            raise AssertionError(f"{result} must reach exactly one analysis")
        if not list(graph.objects(analyses[0], SBKG.reference_group)):
            raise AssertionError(f"{analyses[0]} carries no reference group")
    return len(results)


def validate_dual_representation(graph: Graph) -> None:
    """The plain edge and the reified result must agree, exactly.

    Two representations of one fact is a standing invitation for them to drift,
    which is the cost of emitting both. This is the check that makes the
    traversal edge trustworthy enough to be worth having.
    """
    from_results = {(next(graph.objects(r, BIOLINK.subject)),
                     next(graph.objects(r, BIOLINK.object)))
                    for r in graph.subjects(RDF.type, BIOLINK.StudyResult)}
    from_edges = set(graph.subject_objects(SAGEBRAIN.has_altered_activity_in))
    if from_results != from_edges:
        only_edge = from_edges - from_results
        only_result = from_results - from_edges
        raise AssertionError(
            f"has_altered_activity_in and StudyResult disagree: "
            f"{len(only_edge)} edge(s) with no result, "
            f"{len(only_result)} result(s) with no edge"
        )


def validate_absences(graph: Graph) -> None:
    """What is NOT here, which is half the argument."""
    decoy_results = [r for r in graph.subjects(RDF.type, BIOLINK.StudyResult)
                     if (r, BIOLINK.object, DECOY) in graph]
    if decoy_results:
        raise AssertionError(
            f"the batch decoy {DECOY} has {len(decoy_results)} result(s); it must "
            f"have none -- within-cohort standardisation removes it exactly"
        )
    if (None, SAGEBRAIN.has_altered_activity_in, DECOY) in graph:
        raise AssertionError(f"the batch decoy {DECOY} has a traversal edge")

    controls = list(graph.subjects(RDF.type, SAGEBRAIN.Control))
    if not controls:
        raise AssertionError(
            "no control individual in the fixture; the reference group the z "
            "scores are measured against would be invisible"
        )
    for control in controls:
        for sample in graph.objects(control, SAGEBRAIN.has_sample):
            if list(graph.subjects(BIOLINK.subject, sample)):
                raise AssertionError(f"control sample {sample} has a result")


def validate_discordance(graph: Graph) -> None:
    """Down in AD, up in ALS -- altered in both, shared in neither."""
    seen: dict[URIRef, set[str]] = {}
    for result in graph.subjects(RDF.type, BIOLINK.StudyResult):
        if (result, BIOLINK.object, DISCORDANT) not in graph:
            continue
        sample = next(graph.objects(result, BIOLINK.subject))
        individual = next(graph.subjects(SAGEBRAIN.has_sample, sample))
        disease = next(graph.objects(individual, SAGEBRAIN.has_diagnosis))
        direction = next(graph.objects(result, BIOLINK.predicate))
        seen.setdefault(disease, set()).add(str(direction).rsplit("/", 1)[-1])

    expected = {
        ALZHEIMER: {"negatively_correlated_with"},
        ALS: {"positively_correlated_with"},
    }
    if seen != expected:
        raise AssertionError(
            f"the discordant pathway does not read as discordant: {seen}"
        )


def run_query(graph: Graph) -> None:
    rows = list(graph.query((HERE / "sample-to-pathway.rq").read_text()))
    if not rows:
        raise AssertionError("the demo query returned nothing")

    print(f"PASS: query returned {len(rows)} sample-to-pathway results\n")
    width = max(len(str(r.pathway_label)) for r in rows)
    for row in rows:
        sample = str(row.sample).rsplit("/", 1)[-1]
        arrow = "up  " if "positively" in str(row.direction) else "down"
        print(f"  {str(row.pathway_label):<{width}}  {arrow}  "
              f"z={float(row.z):+7.2f}  {sample:<20} {row.disease_label}")


if __name__ == "__main__":
    fixture = load_graph()
    n_results = validate_results(fixture)
    validate_dual_representation(fixture)
    validate_absences(fixture)
    validate_discordance(fixture)
    print(f"PASS: {n_results} results, each with a direction, a z score and a "
          f"reference group")
    print("PASS: plain edges and reified results agree exactly")
    print("PASS: batch decoy has no results; control sample has none")
    print("PASS: the discordant pathway is down in AD and up in ALS\n")
    run_query(fixture)
