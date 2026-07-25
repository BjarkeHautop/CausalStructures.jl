```@meta
CurrentModule = CausalStructures
```

# CausalStructures.jl

CausalStructures.jl provides a type-driven interface for representing,
validating, and manipulating causal graphs. Rather than treating every graph as
an arbitrary collection of nodes and edges, graph classes explicitly encode
their structural assumptions and invariants.

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

`UNKNOWN` can be used for currently unsupported graph classes. The graph constrains each class imposes are validated on construction, and errors
if invalid.

The following edge types exists:

- `directed(:A, :B)` for `A --> B`
- `undirected(:A, :B)` for `A --- B`
- `bidirected(:A, :B)` for `A <-> B`
- `partially_directed(:A, :B)` for `A o-> B`
- `partially_undirected(:A, :B)` for `A o-- B`
- `partial(:A, :B)` for `A o-o B`

These same markers can alternatively be used as a string in `cgraph`, see below.

## Quick Start

Construct graphs by specifying edges and the desired graph class:

```@example example
using CausalStructures

dag = cgraph(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y);
    class = DAG,
)
```

Edges can also be written directly as a string using the same markers as above
(`+` fans a marker out to, or in from, several nodes at once):

```@example example
dag = cgraph("U --> X + Y, X --> Y"; class = DAG)
```

You can then run a variety of causal graph queries, transformations,
adjustment-set computations, and separation criteria. For example, if `U` is
unobserved, we can project it out to obtain an `ADMG`.

```@example example
admg = latent_project(dag, [:U])
```
