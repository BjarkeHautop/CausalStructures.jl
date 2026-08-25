```@meta
CurrentModule = CausalStructures
```

# CausalStructures.jl

CausalStructures.jl is a causality-first graph package for Julia, built for
performance and flexibility. Each graph class is its own type, validated on
construction. It aims to serve both experts and novices in causal inference.

## Supported Graph Classes

Currently implemented classes form the following type hierarchy:

```text
CausalGraph
    ├─ DAG            Directed Acyclic Graph
    ├─ UG             Undirected Graph
    ├─ AbstractPDAG   All Partially Directed Acyclic Graphs
    │  ├─ PDAG        Partially Directed Acyclic Graph
    │  ├─ CPDAG       Completed Partially Directed Acyclic Graph
    │  └─ MPDAG       Maximally Oriented Partially Directed Acyclic Graph
    ├─ ADMG           Acyclic Directed Mixed Graph
    ├─ AbstractAG     All Ancestral Graphs
    │  ├─ AG          Ancestral Graph
    │  └─ MAG         Maximal Ancestral Graph
    ├─ PAG            Partial Ancestral Graph
    └─ UNKNOWN        No structural constraints
```

`UNKNOWN` can be used for currently unsupported graph classes. The constraints
each class imposes are validated on construction, and an error is thrown if the
graph is invalid.

The following edge types exists:

- `directed(:A, :B)` for `A --> B`
- `undirected(:A, :B)` for `A --- B`
- `bidirected(:A, :B)` for `A <-> B`
- `partially_directed(:A, :B)` for `A o-> B`
- `partially_undirected(:A, :B)` for `A o-- B`
- `partial(:A, :B)` for `A o-o B`

These same markers can alternatively be used as a string, passed directly to a
graph type's constructor, see below.

## Quick Start

Construct graphs by specifying edges and the desired graph class. The
quickest way is to write edges directly as a string, using the markers above
(`+` fans a marker out to, or in from, several nodes at once):

```@example example
using CausalStructures

dag = DAG("U --> X + Y, X --> Y")
```

Edges can equivalently be built up from constructor calls, which is useful
when composing edges programmatically:

```@example example
dag = DAG(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y))
```

You can then run a variety of causal graph queries, transformations,
adjustment-set computations, and separation criteria. For example, if `U` is
unobserved, we can project it out to obtain an `ADMG`.

```@example example
admg = latent_project(dag, [:U])
```
