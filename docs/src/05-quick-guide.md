# Getting Started

This tutorial introduces the basic workflow using a simple directed acyclic
graph (DAG).

## Constructing a graph

Let's build a DAG with a confounder `A` that affects both `X` and `Y`, and a
mediator `M` between `X` and `Y`:

```@example quick
using CausalGraphInterface
using CairoMakie

dag = caugi(
       directed(:A, :X),
       directed(:A, :Y),
       directed(:X, :M),
       directed(:M, :Y);
       class = DAG,
)
```

and visualize it:

```@example quick
Makie.plot(dag)
```

For more plotting details and customization options, see the [Plotting](@ref
plotting-guide) guide.

## Validation on construction

Graphs are validated when you construct them. Here we make an invalid
DAG:

```@example quick
try
    invalid_dag = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:C, :A);  # Creates a cycle!
        class = DAG,
    )
catch e
    println("Error: $(e.msg)")
end
```

Since cycles are not allowed in DAGs, an error is thrown.

## Testing conditional independence

A central question in causal inference is whether two variables are
conditionally independent. For DAGs, this is determined using *d-separation*.

Are `X` and `Y` independent?

```@example quick
d_separated(dag, :X, :Y)
```

No, there is a directed path `X --> M --> Y`.

If we condition on the mediator `M`, does that make them independent?

```@example quick
d_separated(dag, :X, :Y, [:M])
```

Still no, the backdoor path via `A`: `X <-- A --> Y` remains open.

What if we condition on both `A` and `M`?

```@example quick
d_separated(dag, :X, :Y, [:A, :M])
```

Yes, now all paths are blocked.

## Finding adjustment sets

Now suppose we want to estimate the causal effect of `X` on `Y`. The backdoor
path `X <-- A --> Y` introduces confounding bias, so we need to block it by
conditioning on a valid adjustment set.

Let's find one automatically:

```@example quick
adjustment_set(dag, :X, :Y)
```

We can also verify that a specific set is valid:

```@example quick
is_valid_backdoor(dag, :X, :Y, [:A])
```

And enumerate all minimal valid adjustment sets:

```@example quick
all_backdoor_sets(dag, :X, :Y)
```

In this case, `{A}` is the only minimal set that blocks the backdoor.
