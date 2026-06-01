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
 class = DAG,
)

ug = caugi(
 undirected(:A, :B),
 undirected(:B, :C);
 class = UG,
)
```

`CausalGraph` is the base abstraction, and `DAG`, `UG`, `PDAG`, `ADMG`, and `UNKNOWN` are the supported concrete graph types for now. Use `directed`, `undirected`, `bidirected`, `partially_directed`, `partially_undirected`, and `partial` to define edges.

`caugi` graph objects are immutable. `caugi()` eagerly materializes the CSR-style adjacency backend up front, and later mutations invalidate it so the next query or `build!` call can rebuild it. That keeps queries fast and preserves a consistent graph state.

Use `neighbors`, `parents`, `children`, and `has_edge` when you want slice-based adjacency access without recomputing neighborhood structure every time.
