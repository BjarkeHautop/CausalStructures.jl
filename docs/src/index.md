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
Graphs are validated during construction, ensuring that every graph instance
satisfies the invariants of its class.

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
- Arbitrary graphs (`UNKNOWN`)

`UNKNOWN` can be used for currently unsupported graph classes.

Planned future additions include

- Partial Ancestral Graphs (`PAG`)

The following edge types exists:

- `directed()`
- `undirected()`
- `bidirected()`
- `partially_directed()`
- `partially_undirected()`
- `partial()`

## Quick Start

Construct graphs by specifying edges and the desired graph class:

```@repl example
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

```@repl example
admg = latent_project(dag, [:U])
```
