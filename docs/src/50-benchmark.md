Here we will show the performance of various queries in CausalGraphInterface.

## Design choices

The core data structure in CausalGraphInterface is a compressed sparse row (CSR)
representation of the graph. This is memory efficient, but does mean that any
rebuilding of the graph would be expensive.

The graph object also stores important query information in the object, leading
to parent, child, and neighbor queries being done in $O(1)$. While this
increases the memory footprint, many causal graph algorithms are built from
repeated applications of these basic queries, making the additional storage
worthwhile.

## Performance

First, let's generate a random DAG with 1000 nodes and an edge probability of
0.25.

```@example performance
using CausalGraphInterface
dag = generate_graph(1000; p = 0.25, seed = 1405)
```

Let's see how fast common queries such as finding parents, children, ancestors,
and descendants are:

```@example performance
using BenchmarkTools
node_name = :V45
parents(dag, node_name); children(dag, node_name); ancestors(dag, node_name); descendants(dag, node_name);

@btime parents(dag, $node_name);
@btime children(dag, $node_name);
@btime ancestors(dag, $node_name);
@btime descendants(dag, $node_name);
```

Let's try a more complex query: finding a valid adjustment set using Pearl's
backdoor criterion, and verifying it:

```@example performance
valid_adjustment_set = adjustment_set(dag, :V50, :V70, type = :backdoor)
is_valid_backdoor(dag, :V50, :V70, valid_adjustment_set);
@btime is_valid_backdoor(dag, $:V50, $:V70, $valid_adjustment_set)
```

And finally, checking d-separation:

```@example performance
d_separated(dag, :V50, :V70, valid_adjustment_set)
@btime d_separated(dag, $:V50, $:V70, $valid_adjustment_set)
```

## Comparison with common R packages

Here we compare the performance of CausalGraphInterface to various popular R
packages\[^1\].

\[^1\]: Please let me know if there are any Julia packages I should compare
against as well.

In particular we compare against [caugi](https://caugi.org/index.html),
[igraph](https://r.igraph.org/), [bnlearn](https://www.bnlearn.com/),
[dagitty](https://dagitty.net/), and
[ggm](https://cran.r-project.org/package=ggm).

Like in the Julia code above, we generate a DAG with 1000 nodes and edge
probability 0.25. We then see how fast each package is to find the parents of a
random node:

Benchmarks were performed on a system running Linux Mint 22.3 with an AMD Ryzen
7 8845HS processor and 14 GB RAM. Reported runtimes are median values obtained
using BenchmarkTools.jl (Julia) and bench (R) after an initial warm-up run.

```@raw html
<details><summary>Click to see R code</summary>
```

```r
generate_graphs <- function(n, p) {
  cg <- caugi::generate_graph(n = n, p = p, class = "DAG")
  ig <- caugi::as_igraph(cg)
  ggmg <- caugi::as_adjacency(cg)
  bng <- caugi::as_bnlearn(cg)
  dg <- caugi::as_dagitty(cg)
  list(cg = cg, ig = ig, ggmg = ggmg, bng = bng, dg = dg)
}

graphs <- generate_graphs(1000, p = 0.25)
cg <- graphs$cg
ig <- graphs$ig
ggmg <- graphs$ggmg
bng <- graphs$bng
dg <- graphs$dg

# build the caugi to reflect correct runtime
cg <- caugi::build(cg)

node_name = "V45"

bench::mark(
  caugi = {
    caugi::parents(cg, node_name)
  },
  igraph = {
    igraph::neighbors(ig, node_name, mode = "in")
  },
  bnlearn = {
    bnlearn::parents(bng, node_name)
  },
  ggm = {
    ggm::pa(node_name, ggmg)
  },
  dagitty = {
    dagitty::parents(dg, node_name)
  },
  check = FALSE # igraph returns igraph object
)
```

```@raw html
</details>
```

Here we compare the speed of retrieving parent nodes across different packages:

\| **Median** \| **Package** \| \| ---------- \| --------------------- \| \|
0.17 µs \| CausalGraphInterface \| \| 2.8 µs \| caugi \| \| 12µs \| bnlearn \|
\| 127 µs \| igraph \| \| 5.1ms \| ggm \| \| 887ms \| daggity \|

As shown above, CausalGraphInterface is substantially faster than the competing
R packages for a simple query such as retrieving parent nodes. The same pattern
holds across all other benchmarked operations.
