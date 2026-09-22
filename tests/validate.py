#!/usr/bin/env python3
"""Validate the SageBrain model and its SHACL shapes.

Run from the repository root:

    python tests/validate.py

Requires rdflib and pyshacl.

Seven checks:

  1. The shapes graph is itself valid SHACL.
  2. The ontology satisfies its own model-integrity shapes -- catches
     transcription errors when the model is revised.
  3. tests/conforming.ttl validates cleanly.
  4. tests/violating.ttl reports exactly the expected violation set.
  5. Every connection in the ontology is exercised by at least one active
     property shape. This is the anti-drift check: add a connection to the
     model without constraining it and this fails.

     It used to be stronger. While the ontology carried sagebrain:sourceClass /
     sagebrain:targetClass on an EdgeSpecification per row, this check could
     compare each permitted (source, property, target) triple against the shapes
     and catch a *missing pair* -- a new target class for an existing property
     with no matching sh:class. Those annotations were removed as redundant, so
     the shapes graph is now the only record of the pairings and there is nothing
     independent left to compare them against. What survives is the weaker claim
     that no connection is entirely unconstrained.

  6. Every file in examples/ validates cleanly. These are demonstrations first --
     realistic data with real registry identifiers -- but validating them here
     means a model change that would break plausible curator data fails the test
     run rather than being discovered later.

  7. The merged ontology (sagebrain.ttl + its import modules, exactly as the
     build merges them) stays inside the OWL 2 DL profile. SHACL and pyshacl
     have nothing to say about this: punning a property between
     owl:ObjectProperty and owl:DatatypeProperty is an OWL-profile violation,
     not a shape violation, and entailment is off for every check above (see
     below) precisely so it does NOT get computed. Shells out to ROBOT, so it
     is skipped -- not failed -- when tools/robot.jar is absent; run
     `make tools` to fetch it. This check exists because exactly this kind of
     violation (PR #3, biolink:association_slot punned via a MIREOT ROOT) shipped
     silently until a human reviewer caught it with `robot reason` by hand.

Inference is deliberately OFF. The ontology is passed as ont_graph so class
hierarchies resolve, but no entailment is computed: rdfs:range is an entailment
rule, so an inferencer would derive the very types the sh:class constraints test
for and silently pass every range violation. See the VALIDATION CONFIGURATION
section of sagebrain-shapes.ttl.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from rdflib import Graph, Namespace, URIRef
from rdflib.namespace import RDF
import pyshacl

SAGEBRAIN = Namespace("https://w3id.org/synapse/sagebrain#")
SH = Namespace("http://www.w3.org/ns/shacl#")

ROOT = Path(__file__).resolve().parent.parent
# Same default and override as scripts/import.sh; `make tools` fetches it.
ROBOT_JAR = Path(os.environ.get("ROBOT_JAR", ROOT / "tools" / "robot.jar"))
ONTOLOGY = ROOT / "ontology" / "main" / "sagebrain.ttl"
# Merged into the ontology graph, exactly as the build merges them. sagebrain
# reuses six Biolink classes by IRI and declares none of them, so without this the
# endpoint-integrity shapes (check 2) see six undeclared IRIs, every
# sh:targetClass over them matches nothing, and sagebrain:participates_in and
# sagebrain:used_to_treat are subproperties of things that do not exist.
IMPORTS = [ROOT / "ontology" / "imports" / "biolink.ttl"]
# Claims this project asserts about other people's vocabularies, e.g. that a CERAD
# score specialises an HP finding. Loaded so they are parsed and shape-checked on
# every run, but deliberately not part of the visualized build: a mapping between two
# external vocabularies is not the SageBrain schema. Globbed, and an absent folder
# yields an empty list -- the checks below do not depend on any mapping existing.
MAPPINGS = sorted((ROOT / "ontology" / "mappings").glob("*.ttl"))
SHAPES = ROOT / "ontology" / "shacl" / "sagebrain-shapes.ttl"
CONFORMING = ROOT / "tests" / "conforming.ttl"
VIOLATING = ROOT / "tests" / "violating.ttl"
# Demonstrations, not fixtures: see examples/README.md for the division of
# labour. Globbed rather than listed, so a new example is covered by adding it.
EXAMPLES = sorted((ROOT / "examples").glob("*.ttl"))

SH_RESULT_MESSAGE = URIRef("http://www.w3.org/ns/shacl#resultMessage")

# One entry per planted defect in tests/violating.ttl. Substrings, so the
# wording of a message can be edited without breaking the test.
EXPECTED_VIOLATIONS = {
    "a: wrong target class, Sample de_associated_with to a DiseaseStage":
        "de_associated_with may only point to a Pathway",
    "b: forward cardinality, trial tests two compounds":
        "tests at most one DrugCompound",
    "c: wrong target class, has_diagnosis to a Pathway":
        "has_diagnosis must point to a DiseaseLabel",
    "d: Case/Control disjointness":
        "cannot be both a Case and a Control",
    "e: active inverse cardinality, shared Sample":
        "may belong to at most one Individual",
    "f: node kind, literal edge target":
        "participates_in must point to a Pathway",
    "g: wrong target class, Pathway de_associated_with_stage to a Drug":
        "de_associated_with_stage must point to a DiseaseStage",
    "h: wrong subject class, GeneExpressionAssociation subject is a Drug":
        "GeneExpressionAssociation needs exactly one subject, a Gene",
    "i: missing weight, GeneExpressionAssociation carries no sagebrain:weight":
        "GeneExpressionAssociation needs exactly one xsd:double weight",
    "j: wrong target class, QCResultAssociation qc_status to a Pathway":
        "needs exactly one QCStatus",
    "k: wrong target class, Sample derived_from_organ to a Tissue":
        "derived_from_organ must point to an Organ or an OrganSubregion",
    "l: wrong target class, Pathway de_associated_with_disease to a Drug":
        "de_associated_with_disease must point to a DiseaseLabel",
}


def load(*paths):
    g = Graph()
    for path in paths:
        g.parse(path, format="turtle")
    return g


def local_name(iri):
    """Last path or fragment segment of a term IRI, for readable messages."""
    return str(iri).rsplit("#", 1)[-1].rsplit("/", 1)[-1]


def messages(results_graph):
    return [str(o) for o in results_graph.objects(None, SH_RESULT_MESSAGE)]


def run(data_graph, shapes_graph, ontology_graph):
    """Validate with entailment off. See module docstring for why."""
    return pyshacl.validate(
        data_graph,
        shacl_graph=shapes_graph,
        ont_graph=ontology_graph,
        advanced=True,
    )


def constrained_paths(shapes):
    """Properties reached by an sh:path in some shape that is not deactivated."""
    paths = set()
    for node_shape in shapes.subjects(RDF.type, SH.NodeShape):
        if shapes.value(node_shape, SH.deactivated):
            continue
        for property_shape in shapes.objects(node_shape, SH.property):
            if shapes.value(property_shape, SH.deactivated):
                continue
            path = shapes.value(property_shape, SH.path)
            if path is not None:
                paths.add(path)
    return paths


def check_connection_coverage(ontology, shapes):
    """Every connection must be constrained by at least one active shape.

    A connection is a subject of sagebrain:weighted -- i.e. a property the source
    model's Connections sheet lists, rather than any property that happens to be
    declared.
    """
    connections = set(ontology.subjects(SAGEBRAIN.weighted, None))
    return sorted(local_name(c) for c in connections - constrained_paths(shapes))


def check_dl_profile():
    """Merge the ontology (as the build does) and check it is OWL 2 DL.

    Returns (available, in_profile, report): available is False when
    ROBOT_JAR or the `java` binary is missing (report then explains how to
    fetch/install it), otherwise True; in_profile mirrors
    `robot validate-profile`'s verdict and report is its output. Shells out
    rather than reimplementing OWL profile checking in Python --
    ObjectProperty/DatatypeProperty punning is exactly what an OWL reasoner is
    for.

    A crashed or errored ROBOT invocation must never read back as "in
    profile" -- that would silently defeat the one thing this check exists to
    catch (see the module docstring) -- so in_profile is only ever True when
    `validate-profile` both exits 0 and its report agrees; anything else
    (missing report, non-zero exit, unparseable output) is treated as a
    failure, not a pass.
    """
    if not ROBOT_JAR.exists():
        return False, None, f"ROBOT_JAR not found at '{ROBOT_JAR}' -- run 'make tools' to enable this check"
    if shutil.which("java") is None:
        return False, None, "'java' not found on PATH -- required to run ROBOT for this check"

    with tempfile.TemporaryDirectory() as tmp:
        merged = Path(tmp) / "merged.ttl"
        merge = subprocess.run(
            ["java", "-jar", str(ROBOT_JAR), "merge",
             "-i", str(ONTOLOGY), *(a for p in IMPORTS for a in ("-i", str(p))),
             "-o", str(merged)],
            capture_output=True, text=True,
        )
        if merge.returncode != 0:
            return True, False, f"robot merge failed:\n{merge.stdout}\n{merge.stderr}"

        report = Path(tmp) / "profile.txt"
        validate = subprocess.run(
            ["java", "-jar", str(ROBOT_JAR), "validate-profile",
             "--profile", "DL", "-i", str(merged), "-o", str(report)],
            capture_output=True, text=True,
        )
        if not report.exists():
            return True, False, (
                f"robot validate-profile produced no report (exit {validate.returncode}):\n"
                f"{validate.stdout}\n{validate.stderr}"
            )
        text = report.read_text()
        in_profile = validate.returncode == 0 and "NOT in profile" not in text
        return True, in_profile, text


def main():
    failures = []

    ontology = load(ONTOLOGY, *IMPORTS, *MAPPINGS)
    shapes = load(SHAPES)
    print(f"ontology  {len(ontology):>4} triples "
          f"({len(IMPORTS)} import module(s), {len(MAPPINGS)} mapping module(s))")
    print(f"shapes    {len(shapes):>4} triples")

    # 1. the shapes graph is valid SHACL
    conforms, _, text = pyshacl.validate(shapes, validate_shapes=True, advanced=True)
    print(f"\n[1] shapes graph is valid SHACL: {conforms}")
    if not conforms:
        failures.append("shapes graph is not valid SHACL")
        print(text)

    # 2. the ontology satisfies its own model-integrity shapes
    conforms, _, text = run(ontology, shapes, ontology)
    print(f"[2] ontology conforms to model-integrity shapes: {conforms}")
    if not conforms:
        failures.append("ontology violates its own model-integrity shapes")
        print(text)

    # 3. conforming fixture
    conforms, _, text = run(load(CONFORMING), shapes, ontology)
    print(f"[3] tests/conforming.ttl conforms: {conforms}")
    if not conforms:
        failures.append("conforming fixture reported violations")
        print(text)

    # 4. violating fixture -- every planted defect must be reported
    conforms, results, _ = run(load(VIOLATING), shapes, ontology)
    found = messages(results)
    print(f"[4] tests/violating.ttl conforms: {conforms} "
          f"({len(found)} violation(s) reported)")
    if conforms:
        failures.append("violating fixture reported no violations at all")
    for label, needle in sorted(EXPECTED_VIOLATIONS.items()):
        hit = any(needle in m for m in found)
        print(f"      {'PASS' if hit else 'FAIL'}  {label}")
        if not hit:
            failures.append(f"defect not caught -- {label}")

    # 5. every connection in the model has a constraint
    total = len(set(ontology.subjects(SAGEBRAIN.weighted, None)))
    uncovered = check_connection_coverage(ontology, shapes)
    print(f"[5] connections constrained by an active property shape: "
          f"{total - len(uncovered)}/{total}")
    for connection in uncovered:
        print(f"      MISSING  {connection}")
        failures.append(f"no property shape constrains {connection}")

    # 6. the examples are real data and must stay valid
    print(f"[6] examples/ ({len(EXAMPLES)} file(s)):")
    if not EXAMPLES:
        failures.append("no examples found -- examples/*.ttl is empty")
        print("      MISSING  nothing to validate")
    for example in EXAMPLES:
        conforms, _, text = run(load(example), shapes, ontology)
        print(f"      {'PASS' if conforms else 'FAIL'}  {example.name}")
        if not conforms:
            failures.append(f"example does not conform -- {example.name}")
            print(text)

    # 7. the merged ontology stays inside the OWL 2 DL profile
    available, in_profile, report = check_dl_profile()
    if not available:
        print(f"[7] OWL 2 DL profile: SKIPPED -- {report}")
    else:
        print(f"[7] merged ontology + imports in OWL 2 DL profile: {in_profile}")
        if not in_profile:
            failures.append("merged ontology is not in the OWL 2 DL profile")
            print(report)

    print()
    if failures:
        print(f"FAILED ({len(failures)})")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
