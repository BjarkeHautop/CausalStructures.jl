# [Benchmarks](@id benchmarks)

Every graph in CausalStructures is stored as a packed CSR (compressed sparse row)
layout. Each node's parents, children, spouses, and neighbors occupy a contiguous
slice of a single flat array. Querying a node's parents requires only index
arithmetic into that array, so [`parents`](@ref), [`children`](@ref),
[`spouses`](@ref), and [`neighbors`](@ref) are effectively O(1): compute the
slice boundaries and return the corresponding entries. Many higher-level
algorithms, including [`d_separated`](@ref), [`ancestors`](@ref), and
adjustment-set search, are built on these primitive operations, so their
performance depends directly on the efficiency of these basic queries.

```@example bench
using CausalStructures
using BenchmarkTools
using Random
```

## Queries stay fast as graphs grow

Single-hop queries such as [`children`](@ref) are just slice lookups, so their
runtime is essentially unchanged whether the graph has 100 nodes or 10,000:

```@example bench
for n in (100, 1_000, 10_000)
    dag = generate_graph(Random.Xoshiro(1), n; p = 5 / n, class = DAG)
    x = Symbol("V", n ÷ 2)
    t = @benchmark children($dag, $x) samples = 200 evals = 1
    println(rpad("n=$n", 10), "children: ", median(t))
end
```

The same design carries through the rest of the query layer. Functions such as
[`ancestors`](@ref), [`d_separated`](@ref), [`m_separated`](@ref),
[`topological_sort`](@ref), [`minimal_separator`](@ref), and
[`markov_blanket`](@ref) are all built on the same primitive operations and
remain fast on graphs with hundreds of nodes:

```@example bench
dag = generate_graph(Random.Xoshiro(1), 500; p = 0.1, class = DAG)
x, y = :V10, :V290

rows = [
    ("d_separated", () -> d_separated(dag, x, y)),
    ("ancestors", () -> ancestors(dag, x)),
    ("topological_sort", () -> topological_sort(dag)),
    ("minimal_separator", () -> minimal_separator(dag, x, y)),
    ("markov_blanket", () -> markov_blanket(dag, x)),
]
for (label, f) in rows
    t = @benchmark $f() samples = 200 evals = 1
    println(rpad(label, 20), median(t))
end
```

## Searching for adjustment sets

[`all_backdoor_sets`](@ref), [`all_adjustment_sets`](@ref),
[`all_iv_sets`](@ref), and [`all_frontdoor_sets`](@ref) search subsets of the
candidate universe up to `max_size`, checking each one against the relevant
validity criterion. Consequently, the runtime grows exponentially with
`max_size`:

```@example bench
admg = generate_graph(Random.Xoshiro(1), 35; p = 0.25, class = ADMG, latents = 8)
x, y = :V3, :V33

for ms in (2, 3, 4)
    t = @benchmark all_adjustment_sets($admg, $x, $y; minimal = false, max_size = $ms) samples =
        20 evals = 1
    r = all_adjustment_sets(admg, x, y; minimal = false, max_size = ms)
    println("max_size=$ms  ", median(t), "  (", length(r), " sets)")
end
```

## Expensive algorithms

Here we will show the performance of some of the most expensive
algorithms.

### Exact uniform DAG sampling

[`generate_graph`](@ref) uses an Erdős–Rényi model and therefore does not sample
uniformly from the space of DAGs. [`uniform_dag`](@ref) instead draws exactly
uniformly from all labelled DAGs on `n` nodes using the recursive enumeration
algorithm of [kuipers2015uniform](@cite).

```@example bench
for n in (10, 20, 40)
    t = @benchmark uniform_dag(Random.Xoshiro(1), $n) samples = 20 evals = 1
    println("n=$n  ", median(t))
end
```

### Markov equivalence class enumeration

[`count_dags`](@ref) and [`enumerate_dags`](@ref) operate on a
[`CPDAG`](@ref), [`PDAG`](@ref), or [`MPDAG`](@ref) by considering every DAG in
its Markov equivalence class. The size of that class grows combinatorially with
the number of undirected edges. For example, a clique on ``k`` nodes has
``k!`` consistent orientations, so the class can grow very large very
quickly:

```@example bench
for k in (5, 7, 9)
    names = [Symbol("V$i") for i = 1:k]
    clique_edges = [undirected(names[i], names[j]) for i = 1:k for j = (i+1):k]
    pdag = cgraph(clique_edges...; class = PDAG)
    c = count_dags(pdag)
    t = @benchmark count_dags($pdag) samples = 5 evals = 1
    println("k=$k  DAGs=$c  ", median(t))
end
```

[`enumerate_dags`](@ref) is slower than [`count_dags`](@ref), since it must
materialize every DAG rather than simply count them:

```@example bench
for k in (5, 6, 7)
    names = [Symbol("V$i") for i = 1:k]
    clique_edges = [undirected(names[i], names[j]) for i = 1:k for j = (i+1):k]
    pdag = cgraph(clique_edges...; class = PDAG)
    d = length(enumerate_dags(pdag))
    t = @benchmark enumerate_dags($pdag) samples = 5 evals = 1
    println("k=$k  DAGs=$d  ", median(t))
end
```

### MAG equivalence class enumeration

[`enumerate_mags`](@ref) is the PAG/MAG counterpart to [`enumerate_dags`](@ref),
but the algorithm behind it is not the same: it brute-forces every
tail/arrowhead assignment for each circle endpoint in the PAG (`2^k`
candidates for `k` circle endpoints), validates each candidate as a MAG, and
keeps the ones that map back to the original PAG. There's no analog of
Chickering's recursive pruning here, so it's considerably more expensive than
[`count_dags`](@ref)/[`enumerate_dags`](@ref) at a comparable scale:

```@example bench
for k in (3, 4, 5)
    names = [Symbol("V$i") for i = 1:k]
    circle_edges = [partial(names[i], names[j]) for i = 1:k for j = (i+1):k]
    pag = cgraph(circle_edges...; class = PAG)
    m = length(enumerate_mags(pag))
    t = @benchmark enumerate_mags($pag) samples = 5 evals = 1
    println("k=$k  MAGs=$m  ", median(t))
end
```

[`count_dags`](@ref), [`enumerate_dags`](@ref), [`enumerate_mags`](@ref), and
the whole `all_*_sets` family all parallelize their search across
`Threads.nthreads()` automatically once the problem is large enough to
benefit.
