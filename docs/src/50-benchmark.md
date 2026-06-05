Here we will show the performance of various queries in CausalGraphInterface.

## Design choices

The core data structure in CausalGraphInterface is a compressed sparse row (CSR) representation of the graph. CSR representations store for each vertex a contiguous slice of neighbor IDs with a pointer (offset) array that marks the start/end of each slice. This format is memory efficient for sparse graphs.

The graph object also stores important query information in the object, leading to parent, child, and neighbor queries being done in O(1). This yields a larger memory footprint, but the trade-off is that queries are extremely fast.

## Performance

First, let's generate a random DAG with 1000 nodes and an edge probability of 0.25.

```@example performance
using CausalGraphInterface
graph = generate_graph(1000; p = 0.25, seed = 1405)
```

Let's see how fast common queries such as finding parents, children, ancestors, and descendants are:

```@repl performance
using BenchmarkTools
node_name = :V45

@btime parents(graph, $node_name);
@btime children(graph, $node_name);
@btime ancestors(graph, $node_name);
@btime descendants(graph, $node_name);
```

Let's try a more complex query: finding a valid adjustment set using Pearl's backdoor criterion, and verifying it:

```@repl performance
valid_adjustment_set = adjustment_set(graph, :V50, :V70, type = :backdoor)
@btime is_valid_backdoor(graph, $:V50, $:V70, $valid_adjustment_set)
```

And finally, checking d-separation:

```@repl performance
@btime d_separated(graph, $:V50, $:V70, $valid_adjustment_set)
```

## Comparison with common R packages

Link to code for R benchmark:

Table of results...
