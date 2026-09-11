#!/usr/bin/env bash
#
# Regenerate the checked-in import modules in ontology/imports/.
#
#   scripts/import.sh            # every module
#   scripts/import.sh biolink    # just one
#
# We reuse a handful of terms from large external vocabularies. Importing those
# whole is not an option -- Biolink alone is 690 classes against our 10, and it
# would bury the model in the rendered graph -- so each one is reduced to a
# MIREOT-style module: the terms we actually use, plus the ancestor chain that
# makes their hierarchy meaningful, and nothing else.
#
# The modules are COMMITTED, and the build never regenerates them: `make json`
# must not depend on the network, and an import that changes silently under a
# build is how a model stops being reproducible. Bumping an upstream version is
# a deliberate act -- edit the version below, run this, read the diff, commit it.
#
# MIREOT rather than `--method STAR`: the syntactic locality methods pull in every
# axiom mentioning a term, and Biolink's LinkML-generated OWL wires each class to
# its mixins through owl:Restrictions, so STAR on three terms dragged in 55
# classes (GeneProduct, ReagentTargetedGene, ...) with no bearing on our model.
# MIREOT takes the terms and their ancestors and leaves the axioms behind, which
# for a vocabulary we reuse by IRI is the contract we want: their names and their
# hierarchy, not their modelling commitments.
#
# Environment: ROBOT_JAR (default tools/robot.jar), CACHE_DIR (default build/).
#
# Requires bash 4.3+ (namerefs).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROBOT_JAR="${ROBOT_JAR:-$ROOT/tools/robot.jar}"
CACHE_DIR="${CACHE_DIR:-$ROOT/build}"
IMPORTS_DIR="$ROOT/ontology/imports"

DCTERMS_TITLE="http://purl.org/dc/terms/title"
DCTERMS_DESCRIPTION="http://purl.org/dc/terms/description"
DCTERMS_SOURCE="http://purl.org/dc/terms/source"

MODULES=(biolink)

# --- biolink ----------------------------------------------------------------
#
# The classes are reused by IRI: sagebrain asserts no axioms about Gene, Pathway,
# Disease, Drug, ClinicalTrial or MaterialSample, it uses them where it would
# otherwise have minted its own. The two properties are here for a different
# reason -- sagebrain:participates_in and sagebrain:used_to_treat are declared
# subproperties of biolink:participates_in and biolink:treats, so the module has
# to declare those or the axioms point at nothing. See the "Reused terms" section
# of ontology/main/sagebrain.ttl.
#
# LOWER is what the model uses; ROOTS stop the ancestor walk, and a term can be
# both. Without Entity, MIREOT climbs past biolink:Entity into
# linkml:ClassDefinition -- LinkML generator plumbing that would show up as a node
# in the rendered graph. Listing each property as its own root stops the property
# walk dead: their ancestors are biolink:related_to_at_instance_level,
# biolink:related_to and biolink:treats_or_applied_or_studied_to_treat, generic
# roots we gain nothing from, and VOWL draws a property with no domain or range as
# an edge between two owl:Thing nodes.
#
# What MIREOT drops here is worth knowing: upstream, biolink:participates_in
# carries `rdfs:domain biolink:Occurrent`, and a gene is not an Occurrent in
# Biolink's own hierarchy -- so importing that axiom would entail that every gene
# we relate to a pathway is a process. MIREOT keeps the property and its
# subPropertyOf chain but not its domain/range, so the wart does not travel down
# into ours.
#
# Association, subject, object: reused so the six weighted connections (see
# sagebrain:weight in ontology/main/sagebrain.ttl) can be reified as Biolink-style
# association instances instead of needing a bespoke reification class or an
# unconstrainable plain-triple weight. biolink:Association carries dozens of
# owl:Restriction axioms on StringDB/evidence/qualifier slots we never declare --
# MIREOT drops those (it keeps hierarchy and labels, not axioms), so extracting the
# class does not pull those properties in as anything more than unresolved IRIs
# inside restrictions we discard. association_slot is listed as a ROOT because it
# is the immediate, and only, ancestor of subject/object -- without it MIREOT would
# still stop there (it has no further named superproperty) but the module would
# then carry a dangling subPropertyOf reference to a term it never declares, the
# same pitfall the treats/participates_in roots exist to avoid.
biolink_VERSION="4.4.4"
biolink_URL="https://raw.githubusercontent.com/biolink/biolink-model/v${biolink_VERSION}/project/owl/biolink_model.owl.ttl"
biolink_NS="https://w3id.org/biolink/vocab/"
biolink_LOWER=(Gene Pathway Disease Drug ClinicalTrial MaterialSample participates_in treats Association subject object)
biolink_ROOTS=(Entity participates_in treats association_slot)
biolink_TITLE="Biolink Model -- SageBrain import module"
biolink_DESCRIPTION="MIREOT extract of the Biolink Model terms SageBrain reuses (gene, pathway, disease, drug, clinical trial, material sample, participates in, treats, association, subject, object) and their ancestors. Generated by scripts/import.sh from Biolink v${biolink_VERSION}; do not edit by hand."

extract_module() {
  local name="$1"
  local -n version="${name}_VERSION"
  local -n url="${name}_URL"
  local -n ns="${name}_NS"
  local -n lower="${name}_LOWER"
  local -n roots="${name}_ROOTS"
  local -n title="${name}_TITLE"
  local -n description="${name}_DESCRIPTION"

  local source_ttl="$CACHE_DIR/${name}-${version}.source.ttl"
  local module="$IMPORTS_DIR/${name}.ttl"
  local iri="https://w3id.org/synapse/sagebrain/imports/${name}"

  # Cached by version, so re-running after a failed extract does not re-download.
  if [ -f "$source_ttl" ]; then
    echo "--- $name $version: using cached source"
  else
    echo "--- $name $version: fetching $url"
    mkdir -p "$CACHE_DIR"
    curl -L --fail -o "$source_ttl.tmp" "$url"
    mv "$source_ttl.tmp" "$source_ttl"
  fi

  local terms=()
  for term in "${roots[@]}"; do terms+=(--upper-term "${ns}${term}"); done
  for term in "${lower[@]}"; do terms+=(--lower-term "${ns}${term}"); done

  echo "--- $name: extracting ${#lower[@]} term(s) into ontology/imports/${name}.ttl"
  # Written via a temp file so a failed extract cannot leave a half-module in the
  # tree, where it would be committed as though it were generated output. The
  # temp name keeps the .ttl suffix -- ROBOT picks its serialisation off the
  # output extension and rejects anything it does not recognise.
  #
  # `annotate` is chained onto `extract` in the same JVM. Without it the module
  # inherits Biolink's own ontology IRI -- literally
  # <https://w3id.org/biolink/vocab/.owl.ttl>, an artefact of how the LinkML
  # generator names its output -- which would make our extract indistinguishable
  # from the real thing to anything that resolves it.
  java -jar "$ROBOT_JAR" extract \
      --input "$source_ttl" \
      --method MIREOT \
      "${terms[@]}" \
    annotate \
      --ontology-iri "$iri" \
      --version-iri "$iri/$version" \
      --annotation "$DCTERMS_TITLE" "$title" \
      --annotation "$DCTERMS_DESCRIPTION" "$description" \
      --link-annotation "$DCTERMS_SOURCE" "$url" \
      --output "$module.tmp.ttl"
  mv "$module.tmp.ttl" "$module"

  printf '    %s classes, %s object properties\n' \
    "$(grep -c 'rdf:type owl:Class' "$module" || true)" \
    "$(grep -c 'rdf:type owl:ObjectProperty' "$module" || true)"
}

main() {
  [ -f "$ROBOT_JAR" ] || {
    echo "ERROR: ROBOT not found at '$ROBOT_JAR'. Run 'make tools' first." >&2
    exit 1
  }

  local requested=("$@")
  [ ${#requested[@]} -eq 0 ] && requested=("${MODULES[@]}")

  for name in "${requested[@]}"; do
    case " ${MODULES[*]} " in
      *" $name "*) extract_module "$name" ;;
      *) echo "ERROR: unknown module '$name'. Known: ${MODULES[*]}" >&2; exit 1 ;;
    esac
  done
}

main "$@"
