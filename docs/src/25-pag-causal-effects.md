# [PAG Causal Effects](@id pag-causal-effects-guide)

This guide builds on [Equivalence Classes](@ref equivalence-classes-guide) and
[Causal Identification](@ref causal-identification-guide) and covers causal
adjustment when the graph is known only as a [PAG](@ref), i.e. when the underlying
MAG is identified only up to Markov equivalence.

```@example pc
using CausalStructures
using CairoMakie
using NetworkLayout
```

## Adjustment with a PAG

Consider the MAG from [Equivalence Classes](@ref equivalence-classes-guide), where
`A` and `B` share a hidden common cause, and `C` and `B` each cause their successor:

```@example pc
mag = MAG("A <-> B, C --> B --> D")
pag = mag_to_pag(mag)
plot(pag)
```

The resulting PAG contains the circle-marked edge `A o-> B`. Depending on which MAG
in the equivalence class is the true graph, this edge can correspond to either
`A --> B` or `A <-> B`.

Consequently, [`backdoor_set`](@ref) cannot determine an adjustment set from the
PAG alone:

```@example pc
backdoor_set(pag, :A, :D) === nothing
```

In particular, whether `B` needs to be included in an adjustment set depends on how
the circle at `A` is resolved.

## Adjustment sets

[`pagcauses`](@ref) considers the MAGs compatible with the PAG and returns adjustment
sets that are valid for at least one of them [wang2025pagcauses](@cite):

```@example pc
pagcauses(pag, :A, :D)
```

For this example, the empty set is valid when `A --> B`, since there is then no
backdoor path from `A` to `D` through `B`. When `A <-> B`, `B` must instead be
included to block the path through the hidden common cause. If the ambiguity in the
graph also requires adjustment for `C`, `{B, C}` is returned as another possible
adjustment set.

The same procedure applies when the ambiguity occurs elsewhere in the graph. For
example:

```@example pc
pagcauses(pag, :C, :D)
```

If there is no MAG compatible with the PAG in which `A` can have a causal effect on
`D`, `pagcauses` returns no possible causal effect:

```@example pc
pagcauses(pag, :D, :A)
```

This is consistent with [`possible_ancestors`](@ref).

!!! note "No selection bias"

    [`pagcauses`](@ref), [`possible_local_structures`](@ref), and
    [`maximal_local_mag`](@ref) assume that `cg` has no selection bias, matching
    the assumptions in the source papers. Selection bias shows up as an
    undirected edge in a PAG, and all three functions throw an `ArgumentError`
    if `cg` has one:

    ```@repl pc
    selection_pag = PAG(
        undirected(:A, :B), undirected(:B, :C), undirected(:C, :D), undirected(:A, :D))
    pagcauses(selection_pag, :A, :B)
    ```

!!! note "Why not just enumerate the MAGs?"

    One could enumerate all MAGs with [`enumerate_mags`](@ref) and apply
    [`backdoor_set`](@ref) to each one. However, the number of MAGs in a Markov
    equivalence class grows as `O(3^((d^2-d)/2))` with the number of nodes `d`.

    `pagcauses` avoids constructing these MAGs. Instead, it uses graphical conditions
    to check whether a candidate adjustment set can be valid for a MAG compatible
    with the PAG. This reduces the complexity to `O(5^d d^6)`
    ([wang2025pagcauses](@citet), Section 3.4).

## Local structures

`pagcauses` builds on a smaller graphical primitive:
[`possible_local_structures`](@ref). For a single node `x`, this function enumerates
which subsets of its circle-marked neighbors could resolve to `x <-> v`, with the
remaining circle-marked edges resolving to `x --> v`, in some consistent MAG
[wang2023localbk](@cite):

```@example pc
possible_local_structures(pag, :A)
```

`A` has one circle-marked neighbor, `B`, so there are two local structures: the
empty set, corresponding to `A --> B`, and `{B}`, corresponding to `A <-> B`.
Pairing a local structure with [`maximal_local_mag`](@ref) resolves the edges around
`A` implied by this local background knowledge:

```@example pc
maximal_local_mag(pag, :A, Symbol[])
```

```@example pc
maximal_local_mag(pag, :A, [:B])
```

These correspond to the two cases considered by `pagcauses(pag, :A, :D)`: the first
gives `{}` as a valid adjustment set for `A` and `D`, while the second gives `{B}`.
The result is returned as [`UNKNOWN`](@ref) rather than `MAG`, since local
background knowledge about one node need not resolve every circle in the graph.
