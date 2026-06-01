```@meta
CurrentModule = CausalGraphInterface
```

# CausalGraphInterface

Documentation for [CausalGraphInterface](https://github.com/BjarkeHautop/CausalGraphInterface.jl).

## Quick Start

The `caugi()` constructor (short for *Cau*sal *G*raph *I*nterface, pronounced "corgi") builds a graph from a collection of edge specifications.

```julia
using CausalGraphInterface

graph = caugi(
 directed(:A, :B),
 directed(:A, :C),
 directed(:B, :D),
 directed(:C, :D);
 class = DAG,
)

ug = caugi(
 undirected(:A, :B),
 undirected(:B, :C);
 class = UG,
)
```

`CausalGraph` is the base abstraction, and `DAG`, `UG`, `PDAG`, `ADMG`, and `UNKNOWN` are the currently supported concrete graph types. Use `directed()`, `undirected()`, `bidirected()`, `partially_directed()`, `partially_undirected()`, and `partial()` to define edges.

Each graph type imposes its own constraints, such as permitted edge types and acyclicity requirements. These constraints are enforced when constructing or modifying a graph.

Graphs are stored using a Compressed Sparse Row (CSR) representation, together with additional slice-based metadata to accelerate common causal-graph queries such as `neighbors()`.

Graphs can be modified using functions such as `add_edges!()`. Structural updates are applied lazily: after a modification, the internal representation is rebuilt only when a query is executed.
