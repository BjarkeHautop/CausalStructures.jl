# Getting Started

We will show the basic usage of this package via directed acyclic
graphs (DAGs).

## Constructing a graph

Let's build a DAG with a confounder `A` that affects both `X` and `Y`, and a mediator `M` between `X` and `Y`:

```@example quick
using CausalStructures
using CairoMakie
using NetworkLayout

dag = DAG("A --> X + Y, X --> M --> Y")
```

!!! note "Validation on construction"

    All graphs you construct are validated on construction to be a valid graph according to your graph class. For a DAG this means all edges are directed edges (`-->`), and there are no cycles. Let's try to create a DAG with a cycle:

    ```@repl quick
    invalid_dag = DAG("A --> B --> C --> A")  # Creates a cycle!
    ```

Since, [a picture is worth a thousand words](https://en.wikipedia.org/wiki/A_picture_is_worth_a_thousand_words)[^1]
let's plot our DAG:

[^1]: Especially with causal graphs

```@example quick
plot(dag)
```

For more plotting details and customization options, see the [Plotting](@ref
plotting-guide) guide.

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
is_valid_adjustment(dag, :X, :Y, [:A])
```

And enumerate all minimal valid adjustment sets:

```@example quick
all_adjustment_sets(dag, :X, :Y)
```

In this case, `{A}` is the only minimal set that blocks the confounding.

## Next steps

This small quick guide barely scratched the surface of what you can do with this package:

- For more on working with DAGs in the context of causal identification, see
  [Causal Identification](@ref causal-identification-guide).
- To learn more about the different graph classes, see
  [Equivalence Classes](@ref equivalence-classes-guide) or the
  [Graph & Edge Types reference](@ref graph-types-reference).
- If you're already familiar with causal graphs, you might instead be interested in [Plotting](@ref plotting-guide) or [Benchmarks](@ref benchmarks).
