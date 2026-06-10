# [Causal Identification](@id causal-identification-guide)

This guide demonstrates more of the package's identification capabilities,
building on the [Getting Started](@ref) tutorial.

## Adjustment Strategies

[`adjustment_set`](@ref) supports three strategies via the `type` keyword.
Consider a graph with multiple confounders and mediators:

```@example id
using CausalGraphInterface

dag = caugi(
       directed(:C, :X), directed(:A, :X), directed(:X, :F), directed(:X, :D),
       directed(:A, :K), directed(:K, :Y),
       directed(:D, :Y), directed(:D, :G), directed(:Y, :H);
       class = DAG,
)
```

`:parents` adjusts for all parents of `X`:

```@example id
adjustment_set(dag, :X, :Y; type = :parents)
```

`:optimal` computes the O-set, see documentation for more details:

```@example id
adjustment_set(dag, :X, :Y; type = :optimal)
```

## Minimal Separator

[`minimal_separator`](@ref) finds a minimal d-separating set between two nodes.

```@example id
dag2 = caugi(
       directed(:A, :X), directed(:X, :M), directed(:M, :Y), directed(:A, :Y);
       class = DAG,
)

minimal_separator(dag2, :X, :Y)
```

`restrict` limits the candidate pool, and `minimal_separator` returns `nothing`
if no separator exists:

```@example id
minimal_separator(dag2, :X, :Y; restrict = [:M])
```

`include` forces nodes into the result:

```@example id
minimal_separator(dag2, :X, :Y; include = [:M])
```

## Frontdoor Adjustment

When confounders are unobserved the backdoor criterion may not apply.
`M` is a descendant of `X` and therefore fails it:

```@example id
dag3 = caugi(
       directed(:U, :X), directed(:U, :Y),
       directed(:X, :M), directed(:M, :Y);
       class = DAG,
)

is_valid_backdoor(dag3, :X, :Y, [:M])
```

The frontdoor criterion handles this case. [`is_valid_frontdoor`](@ref) checks
whether a set satisfies it:

```@example id
is_valid_frontdoor(dag3, :X, :Y, [:M])
```

[`frontdoor_set`](@ref) finds a valid set automatically:

```@example id
frontdoor_set(dag3, :X, :Y)
```

### Multiple Candidates

[`all_frontdoor_sets`](@ref) enumerates every valid frontdoor set within a
candidate pool. With `restrict` the pool can be limited to observed nodes:

```@example id
dag4 = caugi(
         directed(:U1, :X), directed(:U1, :Y),
         directed(:U2, :X), directed(:U2, :D),
         directed(:X, :A),
         directed(:A, :B), directed(:A, :C), directed(:A, :D),
         directed(:B, :Y), directed(:C, :Y), directed(:D, :Y);
         class = DAG,
)

sort(all_frontdoor_sets(dag4, :X, :Y; restrict = [:A, :B, :C, :D]))
```

`include` forces specific nodes into every returned set:

```@example id
frontdoor_set(dag4, :X, :Y; include = [:C], restrict = [:A, :B, :C, :D])
```

## ADMG Adjustment

In an ADMG, bidirected edges represent hidden common causes directly, keeping
only the observed nodes in the graph. [`is_valid_adjustment`](@ref) and
[`all_adjustment_sets`](@ref) implement the Generalized Adjustment
Criterion for such graphs.

The bidirected edge `X <-> Z` represents a hidden common cause of `X` and `Z`.
Since `Z` also has a direct effect on `Y`, this opens the confounding path
`X <-> Z -> Y`:

```@example id
admg = caugi(
       directed(:X, :Y),
       directed(:Z, :Y),
       bidirected(:X, :Z);
       class = ADMG,
)
```

Without conditioning, this path remains open:

```@example id
is_valid_adjustment(admg, :X, :Y)
```

All valid adjustment sets, here only `{Z}`, which blocks the confounding path:

```@example id
all_adjustment_sets(admg, :X, :Y)
```

ADMGs also support [`m_separated`](@ref), which generalises d-separation to
graphs with bidirected edges. Consider a graph where `A --> B` and `A <-> C`:

```@example id
admg2 = caugi(directed(:A, :B), bidirected(:A, :C); class = ADMG)
```

Since `A --> B`, the two are directly connected and not m-separated:

```@example id
m_separated(admg2, :A, :B)
```

The only path between `B` and `C` runs through `A`; conditioning on it
m-separates them:

```@example id
m_separated(admg2, :B, :C, [:A])
```
