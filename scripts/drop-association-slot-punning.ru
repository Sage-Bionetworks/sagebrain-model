# Drops the owl:DatatypeProperty declaration of biolink:association_slot that
# MIREOT extracts alongside the owl:ObjectProperty one it actually needs -- see
# the comment in import.sh's extract_module for why. Scoped to this single
# triple so it is a no-op for any other term or module.
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

DELETE DATA {
  <https://w3id.org/biolink/vocab/association_slot> rdf:type owl:DatatypeProperty .
}
