# [Causal Identification](@id causal-identification-guide)

This guide expands on the [Getting Started](@ref) tutorial with more advanced identification techniques.

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
    "C --> X, A --> X + K, X --> F + D, K --> Y, D --> Y + G, Y --> H";
    class = DAG,
)
plot(dag; layout = :stress)
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
dag2 = cgraph("U --> X + Y, X --> M --> Y"; class = DAG)
plot(dag2; layout = :stress)
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

## Instrumental variables

When hidden confounders block backdoor adjustment and no suitable mediator exists
for the frontdoor criterion, an *instrumental variable* (IV) can still identify the causal effect. An instrument `Z` must satisfy two conditions: it must be associated with the treatment `X` (relevance), and it can only affect the
outcome `Y` through `X` (exclusion restriction).

Consider a graph where `U` is an unobserved confounder and `Z` is an available instrument, but there is no mediator on the path from `X` to `Y`:

```@example id
dag3 = cgraph("U --> X + Y, Z --> X --> Y"; class = DAG)
plot(dag3; layout = :stress)
```

Without a mediator, the frontdoor criterion cannot apply here:

```@example id
is_valid_frontdoor(dag3, :X, :Y, [:Z])
```

However, `Z` is a valid instrument since it is d-connected to `X` and d-separated from
`Y` given `X` in the interventional graph ``G_{\overline{X}}`` (the graph with all
incoming edges to `X` removed):

```@example id
is_valid_iv(dag3, :X, :Y, [:Z])
```

## ADMG adjustment

In an ADMG (Acyclic Directed Mixed Graph), bidirected edges `<->` represent
hidden common causes directly, without explicitly keeping the unobserved nodes in
the graph. An ADMG arises naturally by projecting unobserved variables out of a
DAG via [`latent_project`](@ref). Let's project `U` out of `dag3`:

```@example id
admg = latent_project(dag3, [:U])
```

Removing `U` introduces `X <-> Y`, which captures its confounding effect. The functions discussed here above also
work on ADMGs, e.g.:

```@example id
is_valid_iv(admg, :X, :Y, [:Z])
```
