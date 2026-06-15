# [Equivalence Classes](@id equivalence-classes-guide)

Equivalence classes of graphs arise in several settings, for instance, during causal discovery algorithms. This
guide covers the graph types that represent such classes and how to work with them.

```@example ec
using CausalGraphInterface
using CairoMakie
using NetworkLayout
```

## Equivalence classes of DAGs

A PDAG (partially directed acyclic graph) is a graph whose edges may be directed or undirected, with no directed cycles. Two DAGs are **Markov equivalent** if and only if they have the same skeleton and the same v-structures (unshielded colliders).

Each Markov equivalence class of DAGs has a unique **CPDAG** (completed partially directed acyclic graph) representation. In a CPDAG, an edge is directed precisely when it has the same orientation in every DAG in the equivalence class; otherwise it remains undirected.

In CausalGraphInterface, all PDAG types are encoded as subtypes of
[`AbstractPDAG`](@ref).

Given a DAG, [`dag_to_cpdag`](@ref) computes its CPDAG:

```@example ec
dag = caugi(
    directed(:C, :X), directed(:A, :X),
    directed(:A, :Y), directed(:Y, :Z);
    class = DAG,
)
cpdag = dag_to_cpdag(dag)
Makie.plot(cpdag; layout = :stress)
```

The v-structure `C --> X <-- A` appears in every DAG in the equivalence class and therefore remains directed. The edges `A --- Y` and `Y --- Z` are undirected because no v-structure or Meek rule forces their orientation.
[`count_dags`](@ref) tells us how many DAGs are in the class, and
[`enumerate_dags`](@ref) lists them all:

```@example ec
count_dags(cpdag)
```

```@example ec
enumerate_dags(cpdag)
```

When you need one concrete DAG to work with, [`dag_from_pdag`](@ref) picks one:

```@example ec
dag_from_pdag(cpdag)
```

Adjustment sets can be computed on CPDAGs and the result is then valid for every DAG in the equivalence class:

```@example ec
all_adjustment_sets(cpdag, :X, :Z)
```

An MPDAG (maximally oriented partially directed acyclic graph) can, for instance, arise when background knowledge is incorporated during causal discovery, orienting some edges of a CPDAG.

[`meek_closure`](@ref) propagates all further orientations implied by Meek's rules on a PDAG to obtain an MPDAG:

```@example ec
pdag = caugi(
    undirected(:C, :X), directed(:A, :X),
    undirected(:A, :Y), directed(:Y, :Z);
    class = PDAG,
)
cpdag = meek_closure(pdag)
```

Here, `X --- C` was oriented to `X --> C` using Meek's rules.

All the methods shown above work on any subtype of [`AbstractPDAG`](@ref):

```@example ec
count_dags(pdag)
all_adjustment_sets(cpdag, :X, :Z)
```

## Equivalence classes of MAGs

PAGs are not yet implemented.
