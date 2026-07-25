# [Reference](@id reference)

## Contents

```@contents
Pages = ["95-reference.md"]
```

## Index

```@raw html
<details><summary>Click to Expand</summary>
```

```@index
Pages = ["95-reference.md"]
```

```@raw html
</details>
```

## Graph & Edge Types

```@docs
CausalGraph
AbstractPDAG
AbstractAG
DAG
UG
PDAG
CPDAG
MPDAG
ADMG
AG
MAG
PAG
UNKNOWN
CausalEdge
cgraph
node
directed
undirected
bidirected
partially_directed
partially_undirected
partial
RequiredEdge
ForbiddenEdge
required_directed
forbidden_directed
BackgroundKnowledge
```

## Queries

```@docs
nodes
edges
topological_sort
ancestors
descendants
possible_ancestors
possible_descendants
anteriors
posteriors
exogenous_nodes
markov_blanket
spouses
districts
neighbors
parents
children
has_edge
is_dag
is_pdag
is_cpdag
is_mpdag
is_ug
is_admg
is_ag
is_mag
is_pag
is_simple
is_acyclic
markov_equivalent
```

## Operations

```@docs
skeleton
moralize
subgraph
dag_from_pdag
dag_to_cpdag
dag_to_mpdag
apply_background_knowledge
meek_closure
latent_project
exogenize
normalize_latent_structure
condition_marginalize
enumerate_dags
count_dags
ag_to_mag
enumerate_mags
mag_to_pag
mag_from_pag
```

## Separation & Adjustment

See the [Causal Identification guide](@ref causal-identification-guide) for
worked examples.

```@docs
d_separated
m_separated
minimal_separator
adjustment_set
is_valid_adjustment
all_adjustment_sets
is_valid_backdoor
all_backdoor_sets
frontdoor_set
is_valid_frontdoor
all_frontdoor_sets
is_valid_iv
all_iv_sets
```

## Simulation

```@docs
generate_graph
uniform_dag
simulate_data
```

## Mutation

```@docs
add_edges
remove_edges
add_nodes
remove_nodes
reclass
```

## Plotting

See the [Plotting guide](@ref plotting-guide) for full examples.

```@docs
layout
```

## Bibliography

```@bibliography
```
