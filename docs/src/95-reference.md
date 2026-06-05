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
DAG
UG
PDAG
CPDAG
MPDAG
ADMG
AG
UNKNOWN
CausalEdge
caugi
node
directed
undirected
bidirected
partially_directed
partially_undirected
partial
```

## Queries

```@docs
nodes
topological_sort
ancestors
descendants
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
is_simple
is_acyclic
```

## Operations

```@docs
skeleton
moralize
subgraph
dag_from_pdag
dag_to_cpdag
meek_closure
latent_project
exogenize
normalize_latent_structure
condition_marginalize
enumerate_dags
count_dags
```

## Separation & Adjustment

```@docs
d_separated
m_separated
minimal_separator
adjustment_set
is_valid_backdoor
all_backdoor_sets
is_valid_adjustment_admg
all_adjustment_sets_admg
```

## Simulation

```@docs
generate_graph
simulate_data
```

## Mutatation

```@docs
add_edge
remove_edge
add_node
remove_node
reclass
```