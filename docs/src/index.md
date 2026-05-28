```@meta
CurrentModule = CausalGraphInterface
```

# CausalGraphInterface

Documentation for [CausalGraphInterface](https://github.com/BjarkeHautop/CausalGraphInterface.jl).

## Quick Start

```julia
using CausalGraphInterface

graph = caugi(
	directed(:A, :B),
	directed(:A, :C),
	directed(:B, :D),
	directed(:C, :D);
	class = :DAG,
)

ug = caugi(
	undirected(:A, :B),
	undirected(:B, :C);
	class = :UG,
)
```

`CausalGraph` is the base abstraction, and `DAG`, `UG`, and `PDAG` are the supported concrete graph types for now. Use `directed`, `undirected`, `bidirected`, `partially_directed`, `partially_undirected`, and `partial` to define edges.

`caugi` graph objects are immutable, so any full rebuild happens by creating a fresh graph state rather than mutating in place. The CSR-style adjacency backend is materialized lazily: it is rebuilt on the first query, or eagerly with `build!` when you want to force consistency up front. That keeps queries fast, preserves a consistent graph state, and avoids wasting work while you are assembling a graph.

Use `neighbors`, `parents`, `children`, and `has_edge` when you want slice-based adjacency access without recomputing neighborhood structure every time.
