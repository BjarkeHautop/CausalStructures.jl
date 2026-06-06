# Getting Started

This tutorial introduces the basic workflow using a simple directed acyclic
graph (DAG).

## Constructing a graph

Suppose we have the following DAG:

```text
A --> X
A --> Y
X --> M --> Y
```

Construct the graph with [`caugi`](@ref):

```@example quick
using CausalGraphInterface

dag = caugi(directed(:A, :X), directed(:A, :Y), directed(:X, :M), directed(:M, :Y); class = DAG)
```

Graphs are validated when constructed. Invalid DAGs, such as graphs containing
directed cycles, raise an error immediately.

## Testing conditional independence

One of the central tasks in causal inference is determining whether two
variables are conditionally independent. For DAGs, this is done using
d-separation.

Consider the relationship between `X` and `Y`:

```@example quick
d_separated(dag, :X, :Y)
```

This is expected because there is a directed path from `X` to `Y`.

Conditioning on `A` blocks the backdoor path, but the path `X --> M --> Y`
remains open:

```@example quick
d_separated(dag, :X, :Y, [:A])
```

Conditioning on the `A` and `M` blocks every path between `X` and `Y`:

```@example quick
d_separated(dag, :X, :Y, [:A, :M])
```

## Finding adjustment sets

Suppose we want to estimate the causal effect of `X` on `Y`.

The backdoor path

```text
X <-- A --> Y
```

introduces confounding and must be blocked. A valid adjustment set can be
obtained automatically:

```@example quick
adjustment_set(dag, :X, :Y)
```

Candidate adjustment sets can also be verified explicitly:

```@example quick
is_valid_backdoor(dag, :X, :Y, [:A])
```

and all minimal valid backdoor adjustment sets can be enumerated (which is only
`A` in this case):

```@example quick
all_backdoor_sets(dag, :X, :Y)
```
