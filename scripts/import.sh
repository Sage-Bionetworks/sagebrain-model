#!/usr/bin/env bash
#
# Regenerate the checked-in import modules in ontology/imports/ (and, for the
# governance layer's shapes, ontology/shacl/).
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
SHACL_DIR="$ROOT/ontology/shacl"

DCTERMS_TITLE="http://purl.org/dc/terms/title"
DCTERMS_DESCRIPTION="http://purl.org/dc/terms/description"
DCTERMS_SOURCE="http://purl.org/dc/terms/source"

# governanceDUO owns the gov:/prov: governance-layer terms and shapes SageBrain
# reuses (plans/governance_layer_import.md), and publishes them as versioned
# artifacts under shapes/ -- but has not yet tagged a release. Pinned at a
# commit hash instead, same as any pre-tag consumer; bump to a v0.1.0 tag once
# one exists (governanceDUO's own release process, not this repo's).
#
# governanceDUO's `kg-conversion` did a large model refactor since the last pin
# (plans/governance_layer_realignment.md): one graph TBox/shape set under a new
# namespace (gov: is now https://w3id.org/synapse/governance#), instance IRIs
# minted under it (activity/<n>, activity/<n>/usage/<n>), and a restored
# exactly_one_of on Usage / minCount 1 on Activity.generated/qualifiedUsage.
#
# That restored exactly_one_of still had a gap: its generated sh:xone branches
# only asserted presence (entity required, OR name+url both required), with no
# exclusion, so a Usage carrying prov:entity *and* gov:name (fixture defect (o)
# in tests/governance_violating.ttl) conformed anyway -- see the Implementation
# Report follow-up note in plans/governance_layer_realignment.md. Commit
# 41c17e1 fixes it: add_exactly_one_of() now also emits sh:maxCount 0 on each
# xone branch's other alternatives' slots, so the entity branch forbids
# gov:name/gov:url and vice versa. This pin is that commit.
GOVERNANCEDUO_COMMIT="41c17e13581aeb969895df1249a665921052e501"
GOVERNANCEDUO_RAW="https://raw.githubusercontent.com/mc2-center/governanceDUO/${GOVERNANCEDUO_COMMIT}"

MODULES=(biolink governance_graph governance_layer governance_layer_shapes governance_graph_example)

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
# Association, subject, object: reused so the four weighted connections (see
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

# --- governance_graph --------------------------------------------------------
#
# gov:SynapseEntity is the one governance-graph term SageBrain reuses (see
# sagebrain:derived_from's range in ontology/main/sagebrain.ttl): a reference
# to a Synapse file/entity, joined by IRI against governanceDUO's own exported
# graph. Replaces a hand copy of the identical declaration (same source class,
# same rdfs:comment) that predates governanceDUO publishing this file as a
# versioned artifact -- see plans/governance_layer_import.md.
#
# governanceDUO's kg-conversion refactor (plans/governance_layer_realignment.md)
# merged its hand-written gov: TBox and its LinkML-generated OWL into one file,
# shapes/governance.owl.ttl, under one namespace, gov: =
# https://w3id.org/synapse/governance# -- so this module and governance_layer
# below now share both a source file and a namespace. They stay separate
# modules/outputs regardless: the split mirrors this repo's own build gating
# (this one is in MAIN_SOURCES, governance_layer is WITH_GOVERNANCE=1 only),
# not upstream's file layout.
#
# No ROOTS: gov:SynapseEntity has no rdfs:subClassOf parent in the source
# file, so MIREOT's ancestor walk has nowhere to climb.
governance_graph_VERSION="$GOVERNANCEDUO_COMMIT"
governance_graph_URL="${GOVERNANCEDUO_RAW}/shapes/governance.owl.ttl"
governance_graph_NS="https://w3id.org/synapse/governance#"
governance_graph_LOWER=(SynapseEntity)
governance_graph_ROOTS=()
governance_graph_TITLE="Sage governance graph -- SageBrain import module"
governance_graph_DESCRIPTION="MIREOT extract of the governanceDUO governance-graph term SageBrain reuses (gov:SynapseEntity). Generated by scripts/import.sh from governanceDUO commit ${GOVERNANCEDUO_COMMIT}; do not edit by hand."

# --- governance_layer ---------------------------------------------------------
#
# The provenance-graph terms SageBrain's opt-in governance layer
# (ontology/governance/, WITH_GOVERNANCE=1) reuses to describe a pipeline run:
# prov:Activity/prov:Usage and their properties, plus gov:wasExecuted/url/
# entityVersionNumber/name. Both this module and governance_graph above now
# extract from the same source file, shapes/governance.owl.ttl -- upstream's
# kg-conversion refactor folded its LinkML-generated OWL (previously
# governance_duo.owl.ttl) and its hand-written gov: TBox (previously
# governance_graph.owl.ttl) into one graph TBox. See governance_graph's own
# comment above for why the split into two modules/outputs stays anyway.
#
# Two namespaces in one module (prov: and gov:), unlike biolink's single-NS
# LOWER/ROOTS: a bare name is resolved against governance_layer_NS as usual,
# but a term already written as a full IRI (starts with "http") is used as-is
# -- see extract_module()'s term-building loop.
#
# ROOTS=(): prov:Activity no longer has any rdfs:subClassOf in the source file
# -- governanceduo:BaseEntity, the LinkML "abstract root" artifact MIREOT used
# to be rooted at to avoid climbing into, doesn't exist any more (Q1/Q2 context
# in plans/governance_layer_realignment.md). Nothing else here (Usage, or any
# of the *_LOWER properties) has a named ancestor to stop at either.
governance_layer_VERSION="$GOVERNANCEDUO_COMMIT"
governance_layer_URL="${GOVERNANCEDUO_RAW}/shapes/governance.owl.ttl"
governance_layer_NS="https://w3id.org/synapse/governance#"
governance_layer_LOWER=(
  "http://www.w3.org/ns/prov#Activity"
  "http://www.w3.org/ns/prov#Usage"
  "http://www.w3.org/ns/prov#generated"
  "http://www.w3.org/ns/prov#qualifiedUsage"
  "http://www.w3.org/ns/prov#entity"
  wasExecuted
  url
  entityVersionNumber
  name
)
governance_layer_ROOTS=()
governance_layer_TITLE="Sage governance layer (provenance) -- SageBrain import module"
governance_layer_DESCRIPTION="MIREOT extract of the governanceDUO provenance-layer terms SageBrain's opt-in governance layer reuses (prov:Activity, prov:Usage, prov:generated, prov:qualifiedUsage, prov:entity, gov:wasExecuted, gov:url, gov:entityVersionNumber, gov:name) and their ancestors. Generated by scripts/import.sh from governanceDUO commit ${GOVERNANCEDUO_COMMIT}; do not edit by hand."

# --- governance_layer_shapes --------------------------------------------------
#
# governanceDUO owns and publishes the SHACL shapes for the provenance layer
# above. Previously a hand-authored supplement scoped to just
# shape:UsageShape/shape:ActivityShape (provenance_layer.shacl.ttl, moved there
# from this repo per plans/governance_layer_import.md, decision D9: one owner
# per governance-layer term and shape); upstream's kg-conversion refactor
# replaced it with gen-shacl output for its whole graph model,
# shapes/governance.shacl.ttl, shape: = https://w3id.org/synapse/governance/shapes# --
# UsageShape/ActivityShape live on in it, alongside every other graph shape
# (SynapseEntityShape, AccessRequirementShape, ...). Shapes are constraints,
# not a class/property hierarchy, so there is nothing for MIREOT to extract --
# this is a verbatim copy, handled by copy_module() below, not
# extract_module().
governance_layer_shapes_VERSION="$GOVERNANCEDUO_COMMIT"
governance_layer_shapes_URL="${GOVERNANCEDUO_RAW}/shapes/governance.shacl.ttl"
governance_layer_shapes_OUTPUT="$SHACL_DIR/governance_layer.shacl.ttl"

# --- governance_graph_example --------------------------------------------------
#
# governanceDUO's own canonical graph example, at the same pin as the shapes
# above. Not part of the ontology: a test fixture, checked by tests/validate.py
# (WITH_GOVERNANCE=1) against governance_layer.shacl.ttl, so data written by
# the shapes' owner conforms to them as imported here -- contract drift fails
# in this repo's own test run, not only in governanceDUO's opt-in
# sagebrain-contract-check. Verbatim copy, same as the shapes.
#
# Renamed from governance_provenance_examples: its old source,
# linkml/examples/provenance/rdf/all_examples.ttl, is deleted upstream (folded
# into the one graph model, same as governance_graph/governance_layer above).
# The new source, linkml/examples/graph/rdf/governance_graph.ttl, also carries
# ACLs, Access Requirements and Approvals alongside the prov: Activities/Usages
# this repo's governance layer reuses, so "provenance_examples" would no longer
# describe what it vendors.
governance_graph_example_VERSION="$GOVERNANCEDUO_COMMIT"
governance_graph_example_URL="${GOVERNANCEDUO_RAW}/linkml/examples/graph/rdf/governance_graph.ttl"
governance_graph_example_OUTPUT="$ROOT/tests/governanceduo_graph_example.ttl"

extract_module() {
  [ -f "$ROBOT_JAR" ] || {
    echo "ERROR: ROBOT not found at '$ROBOT_JAR'. Run 'make tools' first." >&2
    exit 1
  }

  local name="$1"
  local -n version="${name}_VERSION"
  local -n url="${name}_URL"
  local -n ns="${name}_NS"
  local -n lower="${name}_LOWER"
  local -n roots="${name}_ROOTS"
  local -n title="${name}_TITLE"
  local -n description="${name}_DESCRIPTION"

  # Keyed by URL, not module name: governance_graph and governance_layer both
  # extract from the same upstream file (shapes/governance.owl.ttl), so keying
  # by name would fetch and cache that one file twice under two names. The
  # URL already encodes the version (biolink's path includes its VERSION,
  # governanceDUO's includes the pinned commit), so a version bump still
  # busts the cache; the hash just keeps the filename short and collision-free.
  local url_hash
  url_hash="$(printf '%s' "$url" | cksum | cut -d' ' -f1)"
  local source_ttl="$CACHE_DIR/$(basename "$url")-${url_hash}.source.ttl"
  local module="$IMPORTS_DIR/${name}.ttl"
  local iri="https://w3id.org/synapse/sagebrain/imports/${name}"

  # Cached by URL, so re-running after a failed extract does not re-download.
  if [ -f "$source_ttl" ]; then
    echo "--- $name $version: using cached source"
  else
    echo "--- $name $version: fetching $url"
    mkdir -p "$CACHE_DIR"
    curl -L --fail -o "$source_ttl.tmp" "$url"
    mv "$source_ttl.tmp" "$source_ttl"
  fi

  # A term already written as a full IRI (governance_layer's prov:* terms,
  # which live outside its own gov: NS) is used as-is; a bare name is resolved
  # against NS as biolink's always were.
  local terms=()
  for term in "${roots[@]}"; do
    case "$term" in http*) terms+=(--upper-term "$term") ;; *) terms+=(--upper-term "${ns}${term}") ;; esac
  done
  for term in "${lower[@]}"; do
    case "$term" in http*) terms+=(--lower-term "$term") ;; *) terms+=(--lower-term "${ns}${term}") ;; esac
  done

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
  # `query --update` is chained on the end to fix a punning artifact specific to
  # this extract: biolink:association_slot is a ROOT here (see the comment above),
  # and MIREOT declares it both owl:ObjectProperty (inferred from subject/object,
  # which are object properties under it) and owl:DatatypeProperty (upstream's own
  # declaration, since Biolink itself types association_slot as a DatatypeProperty
  # while treating subject/object as ObjectProperties under it -- upstream is
  # itself DL-invalid here). OWL 2 DL forbids punning a property this way, so the
  # update deletes the single spurious DatatypeProperty triple; it is a no-op for
  # modules or terms it does not match. Expect this to resurface on every biolink
  # version bump -- re-check with `robot validate-profile --profile DL` after
  # bumping.
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
    query \
      --update "$ROOT/scripts/drop-association-slot-punning.ru" \
      --output "$module.tmp.ttl"
  mv "$module.tmp.ttl" "$module"

  printf '    %s classes, %s object properties\n' \
    "$(grep -c 'rdf:type owl:Class' "$module" || true)" \
    "$(grep -c 'rdf:type owl:ObjectProperty' "$module" || true)"
}

# Verbatim copy of a file MIREOT can't extract from (shapes, example ABoxes),
# behind a generated header recording where it came from -- the copy's
# counterpart to the dcterms:source/owl:versionIRI extract_module() stamps.
copy_module() {
  local name="$1"
  local -n version="${name}_VERSION"
  local -n url="${name}_URL"
  local -n output="${name}_OUTPUT"

  local source_ttl="$CACHE_DIR/${name}-${version}.source.ttl"
  local module="$output"

  if [ -f "$source_ttl" ]; then
    echo "--- $name $version: using cached source"
  else
    echo "--- $name $version: fetching $url"
    mkdir -p "$CACHE_DIR"
    curl -L --fail -o "$source_ttl.tmp" "$url"
    mv "$source_ttl.tmp" "$source_ttl"
  fi

  echo "--- $name: copying verbatim to ${output#"$ROOT"/}"
  {
    echo "# Copied verbatim by scripts/import.sh (module '$name') from"
    echo "# $url"
    echo "# Do not edit by hand: bump the pin in scripts/import.sh and re-run it."
    echo "#"
    cat "$source_ttl"
  } > "$module.tmp"
  mv "$module.tmp" "$module"
}

main() {
  local requested=("$@")
  [ ${#requested[@]} -eq 0 ] && requested=("${MODULES[@]}")

  for name in "${requested[@]}"; do
    case " ${MODULES[*]} " in
      *" $name "*)
        case "$name" in
          *_shapes|*_example|*_examples) copy_module "$name" ;;
          *) extract_module "$name" ;;
        esac
        ;;
      *) echo "ERROR: unknown module '$name'. Known: ${MODULES[*]}" >&2; exit 1 ;;
    esac
  done
}

main "$@"
