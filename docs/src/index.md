```@meta
CurrentModule = CausalGraphInterface
```

CausalGraphInterface.jl provides a type-driven interface for representing,
validating, and manipulating causal graphs. Rather than treating every graph as
an arbitrary collection of nodes and edges, graph classes explicitly encode
their structural assumptions and invariants.

The package is inspired by the R package [caugi](https://caugi.org/) and aims to
provide a similarly expressive and extensible foundation for causal graphs in
Julia.

## Design Philosophy

Different causal graph classes represent different assumptions, both on the
allowed edge types and on the graph structure itself. For example, a DAG must be
acyclic, while a CPDAG must satisfy additional equivalence-class constraints.
Graphs are validated during construction, ensuring that every graph instance satisfies the invariants required by its class.

## Supported Graph Classes

Currently implemented:

- Directed Acyclic Graphs (`DAG`)
- Undirected Graphs (`UG`)
- Partially Directed Acyclic Graphs (`PDAG`)
- Completed Partially Directed Acyclic Graphs (`CPDAG`)
- Maximally Partially Directed Acyclic Graphs (`MPDAG`)
- Acyclic Directed Mixed Graphs (`ADMG`)
- Ancestral Graphs (`AG`)
- Maximal Ancestral Graphs (`MAG`)
- Partial Ancestral Graphs (`PAG`)
- Arbitrary graphs (`UNKNOWN`)

`UNKNOWN` can be used for currently unsupported graph classes.

The following edge types exists:

- `directed(:A, :B)` for `A --> B`
- `undirected(:A, :B)` for `A --- B`
- `bidirected(:A, :B)` for `A <-> B`
- `partially_directed(:A, :B)` for `A o-> B`
- `partially_undirected(:A, :B)` for `A o-- B`
- `partial(:A, :B)` for `A o-o B`

## Quick Start

Construct graphs by specifying edges and the desired graph class:

```@example example
using CausalGraphInterface

dag = caugi(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y);
    class = DAG,
)
```

You can then run a variety of causal graph queries, transformations,
adjustment-set computations, and separation criteria. For example, if `U` is
unobserved, we can project it out to obtain an `ADMG`.

```@example example
admg = latent_project(dag, [:U])
```
