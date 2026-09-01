"""Parse and validate the synthetic contrast fixture, then run its demo query."""

from pathlib import Path

from rdflib import Graph, Namespace, RDF, URIRef


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

BIOLINK = Namespace("https://w3id.org/biolink/vocab/")
SAGEBRAIN = Namespace("https://w3id.org/synapse/sagebrain#")
SYNV = Namespace("https://w3id.org/synapse/synthetic/contrast/vocab/")

EXPECTED = {
    URIRef("https://identifiers.org/reactome:R-HSA-112315"): (
        "Transmission across Chemical Synapses",
        "decreased in case group",
        "decreased in case group",
    ),
    URIRef("https://identifiers.org/reactome:R-HSA-166016"): (
        "Toll Like Receptor 4 (TLR4) Cascade",
        "increased in case group",
        "increased in case group",
    ),
}


def load_graph() -> Graph:
    graph = Graph()
    for path in (
        HERE / "model.ttl",
        HERE / "data.ttl",
        ROOT / "data/reactome/v97/ttl/pathways.ttl",
    ):
        if not path.exists():
            raise SystemExit(f"missing required file: {path.relative_to(ROOT)}")
        graph.parse(path, format="turtle")
    return graph


def validate_results(graph: Graph) -> None:
    results = set(graph.subjects(RDF.type, SYNV.PathwayContrastResult))
    if len(results) != 10:
        raise AssertionError(f"expected 10 contrast results, found {len(results)}")

    for result in results:
        pathways = list(graph.objects(result, BIOLINK.object))
        if len(pathways) != 1:
            raise AssertionError(f"{result} must have exactly one pathway object")
        if (pathways[0], RDF.type, BIOLINK.Pathway) not in graph:
            raise AssertionError(f"{pathways[0]} does not resolve to a Reactome pathway")
        for required in (
            BIOLINK.subject,
            BIOLINK.predicate,
            BIOLINK.effect_size,
            BIOLINK.p_value,
            BIOLINK.adjusted_p_value,
        ):
            if not list(graph.objects(result, required)):
                raise AssertionError(f"{result} is missing {required}")

    threshold = next(
        graph.objects(
            URIRef("https://w3id.org/synapse/synthetic/contrast/dataset-v1"),
            SYNV.significance_threshold,
        )
    ).toPython()

    expected_edges = set()
    for result in results:
        adjusted_p = next(graph.objects(result, BIOLINK.adjusted_p_value)).toPython()
        if adjusted_p <= threshold:
            contrast = next(graph.objects(result, BIOLINK.subject))
            pathway = next(graph.objects(result, BIOLINK.object))
            expected_edges.add((contrast, pathway))

    actual_edges = set(graph.subject_objects(SAGEBRAIN.de_associated_with))
    if actual_edges != expected_edges:
        raise AssertionError(
            "materialized contrast-to-pathway edges do not match significant results"
        )


def run_query(graph: Graph) -> None:
    rows = list(graph.query((HERE / "shared-altered-pathways.rq").read_text()))
    observed = {
        row.pathway: (
            str(row.pathway_label),
            str(row.ad_direction),
            str(row.als_direction),
        )
        for row in rows
    }
    if observed != EXPECTED:
        raise AssertionError(f"unexpected shared-pathway answer: {observed}")

    print("PASS: RDF parsed, 10 results and 6 significant traversal edges validated")
    print("PASS: shared-altered-pathways.rq returned exactly 2 pathways")
    for row in rows:
        print(
            f"  {row.pathway_label}: AD {row.ad_direction} "
            f"(effect={row.ad_effect}, q={row.ad_adjusted_p}); "
            f"ALS {row.als_direction} "
            f"(effect={row.als_effect}, q={row.als_adjusted_p})"
        )


if __name__ == "__main__":
    fixture = load_graph()
    validate_results(fixture)
    run_query(fixture)
