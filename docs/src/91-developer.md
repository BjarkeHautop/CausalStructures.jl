# Developer Docs

Some notes on performance. Before doing any of these, please profile the code, to see if it affects the performance.

## Skipping validation

Every graph constructor takes `validate::Bool`. You can use `validate=false` if the algorithm is proven to give a valid
graph type, e.g. [`dag_to_cpdag`](@ref)'s last step.

There's a stronger version of the same idea: constructing a graph directly from `(edges, backend)`, bypassing `build_backend` too. This can be useful when the algorithm already has the information needed to construct the backend, so rebuilding it from scratch would be unnecessarily expensive.

For example, [`enumerate_dags`](@ref) assembles `colptr`/`deg`/`rowval` directly from index sets it already knows are sorted, rather than rebuilding the backend from scratch.

## Index-based traversal

[`parents`](@ref), [`children`](@ref), [`spouses`](@ref), and [`neighbors`](@ref) are the public API and work with `Symbol` node names. Internally, algorithm code should not call these in hot loops, since each call involves a dictionary lookup and an array allocation.

Instead, work directly with the backend using `_parents_slice` and related functions. These return a `@view` of node indices into the backend's CSR `rowval` array, avoiding the repeated lookups and allocations.

```@docs
CausalStructures.bucket_slice
CausalStructures._all_nbrs_slice
CausalStructures._parents_slice
CausalStructures._children_slice
CausalStructures._spouses_slice
CausalStructures._undirected_slice
CausalStructures._circle_children_slice
CausalStructures._circle_parents_slice
CausalStructures._circle_undirected_out_slice
CausalStructures._circle_undirected_in_slice
CausalStructures._circle_circle_slice
```
