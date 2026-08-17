#!/usr/bin/env python3
"""Un-flag our own ontologies as "external" in a converted VOWL JSON.

OWL2VOWL marks every element whose namespace differs from the merged graph's
ontology IRI as `external`, and WebVOWL then prints an "(external)" indication
under the node. Since the merged graph is a union of several Sage ontologies,
only one of them can be the graph's IRI -- so all the others get labelled
external, which is wrong for a first-party vocabulary.

The namespaces below are the ones we author. Keep them in sync with the
RANK_OWN entries in webvowl/src/webvowl/js/util/ontologyGroups.js, which is
where the viewer decides the same thing for grouping and colouring.

Usage: strip_external_flags.py <vowl.json>   (rewrites in place)
"""
import json
import sys
from pathlib import Path

OWN_IRIS = (
    "https://synapse.org/synbiont/governance",  # sagegov
    "https://w3id.org/synapse/sagebrain",       # sagebrain
)

# Where an element can carry the flag: `attributes` is what the converter emits,
# `indications` is the parsed form some elements arrive with.
FLAG_FIELDS = ("attributes", "indications")
ELEMENT_SECTIONS = ("class", "classAttribute", "datatype", "datatypeAttribute",
                    "property", "propertyAttribute")


def is_ours(base_iri):
    if not base_iri:
        return False
    # Prefix match, not equality: the shapes graph and any sub-namespace of an
    # ontology we author is also ours.
    return any(base_iri.startswith(own) for own in OWN_IRIS)


def strip(elements):
    stripped = 0
    for element in elements:
        if not is_ours(element.get("baseIri")):
            continue
        for field in FLAG_FIELDS:
            values = element.get(field)
            if isinstance(values, list) and "external" in values:
                element[field] = [v for v in values if v != "external"]
                stripped += 1
    return stripped


def main(path):
    data = json.loads(Path(path).read_text())
    stripped = sum(strip(data[key]) for key in ELEMENT_SECTIONS
                   if isinstance(data.get(key), list))
    if stripped:
        Path(path).write_text(json.dumps(data, indent=2))
    print(f"    un-flagged {stripped} first-party element(s) marked external")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[-1])
    main(sys.argv[1])
