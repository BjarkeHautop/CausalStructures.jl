# [Queries](@id queries-reference)

## Basic accessors

```@docs
nodes
edges
has_edge
topological_sort
```

## Traversal

```@docs
ancestors
descendants
anteriors
posteriors
exogenous_nodes
```

## Local structure

```@docs
parents
children
spouses
neighbors
markov_blanket
districts
```

## Separation

```@docs
d_separated
m_separated
minimal_separator
possible_d_sep
```

## Equivalence-class queries

```@docs
possible_ancestors
possible_descendants
possible_parent_sets
possible_joint_parent_sets
possible_local_structures
```

## Graph class predicates

```@docs
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
