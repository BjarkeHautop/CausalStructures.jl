```@meta
CurrentModule = CausalStructures
```

# CausalStructures.jl

CausalStructures.jl is a Julia package for causal graphs and causal
inference. It provides graph representations for the structures used in
causal inference, along with algorithms for graphical queries, causal
identification, and transformations between graph classes.

## Supported graph classes

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

You can use [`UNKNOWN`](@ref) for graph classes that aren't supported yet. Each graph is validated against its class's constraints when you construct it, and an invalid graph throws an error.

The following edge types exist:

- `directed(:A, :B)` for `A --> B`
- `undirected(:A, :B)` for `A --- B`
- `bidirected(:A, :B)` for `A <-> B`
- `partially_directed(:A, :B)` for `A o-> B`
- `partially_undirected(:A, :B)` for `A o-- B`
- `partial(:A, :B)` for `A o-o B`

You can also write the same markers in a string and pass it directly to a graph type's constructor, as shown below.

## Quick start

Construct graphs by specifying edges and the desired graph class. The
quickest way is to write edges directly as a string, using the markers above (`+` fans a marker out to, or in from, several nodes at once):

```@example example
using CausalStructures

dag = DAG("U --> X + Y, X --> Y")
```

You can also build the edges with constructor calls, which is useful when you create edges programmatically:

```@example example
dag = DAG(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y)
)
```

You can then run a variety of causal graph queries, transformations, and causal identification methods such as
adjustment-set computations. For example, if `U` is unobserved, we can project it out to obtain an [`ADMG`](@ref):

```@example example
admg = latent_project(dag, :U)
```
