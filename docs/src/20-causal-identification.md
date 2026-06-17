# [Causal Identification](@id causal-identification-guide)

This guide expands on the [Getting Started](@ref) tutorial with more advanced
identification techniques. We'll explore different adjustment strategies, minimal
separators, and frontdoor adjustment — all using the same running example graph.

```@example id
using CausalStructures
using CairoMakie
using NetworkLayout
```

## Adjustment strategies

The [`adjustment_set`](@ref) function supports three different strategies for
finding adjustment sets. Let's build a DAG with multiple confounders and mediators:

```@example id
dag = cgraph(
       directed(:C, :X), directed(:A, :X), directed(:X, :F), directed(:X, :D),
       directed(:A, :K), directed(:K, :Y),
       directed(:D, :Y), directed(:D, :G), directed(:Y, :H);
       class = DAG,
)
Makie.plot(dag; layout = :stress)
```

**Parents strategy**: Adjusts for all parents of `X`. Simple but often includes
unnecessary variables:

```@example id
adjustment_set(dag, :X, :Y; type = :parents)
```

**Backdoor strategy**: Applies Pearl's backdoor criterion to find valid adjustment
sets that block all confounding paths:

```@example id
adjustment_set(dag, :X, :Y; type = :backdoor)
```

**Optimal strategy** (default): Computes the O-set, which minimizes the
asymptotic variance of the causal effect estimator:

```@example id
adjustment_set(dag, :X, :Y; type = :optimal)
```

## Minimal separator

Sometimes we need the smallest set of variables that d-separates two nodes.
The [`minimal_separator`](@ref) function finds one:

```@example id
minimal_separator(dag, :X, :Y)
```

The `restrict` keyword limits the search to a specific pool of variables. If no
separator exists within that pool, the function returns `nothing`:

```@example id
minimal_separator(dag, :X, :Y; restrict = [:D, :K])
```

```@example id
minimal_separator(dag, :X, :Y; restrict = [:D])
```

The `include` keyword forces certain variables to always be in the result:

```@example id
minimal_separator(dag, :X, :Y; include = [:K])
```

## Frontdoor adjustment

When confounders are unobserved, the backdoor criterion doesn't apply. Consider
a graph where an unobserved confounder `U` affects both the treatment `X` and
outcome `Y`:

```@example id
dag2 = cgraph(
       directed(:U, :X), directed(:U, :Y),
       directed(:X, :M), directed(:M, :Y);
       class = DAG,
)
Makie.plot(dag2; layout = :stress)
```

The mediator `M` is a descendant of `X`, so adjusting for it violates the
backdoor criterion:

```@example id
is_valid_backdoor(dag2, :X, :Y, [:M])
```

However, `M` intercepts every causal path from `X` to `Y` and is itself
unconfounded, this is exactly the *frontdoor criterion*:

```@example id
is_valid_frontdoor(dag2, :X, :Y, [:M])
```

```@example id
frontdoor_set(dag2, :X, :Y)
```

## ADMG adjustment

In an ADMG (Acyclic Directed Mixed Graph), bidirected edges `<->` represent
hidden common causes directly, without explicitly keeping the unobserved nodes in
the graph. An ADMG arises naturally by projecting unobserved variables out of a
DAG via [`latent_project`](@ref). Let's project `U` out of `dag2`:

```@example id
admg = latent_project(dag2, [:U])
```

Removing `U` introduces `X <-> Y`, which captures its confounding effect. The
[`is_valid_adjustment`](@ref) and [`all_adjustment_sets`](@ref) functions
implement the Generalized Adjustment Criterion for ADMGs. With a direct
bidirected edge between treatment and outcome, no valid adjustment set exists:

```@example id
is_valid_adjustment(admg, :X, :Y)
```

```@example id
all_adjustment_sets(admg, :X, :Y)
```

This is why the frontdoor approach was needed in the first place. Once we
project out `U`, backdoor adjustment becomes impossible.
