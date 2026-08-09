# [Equivalence Classes](@id equivalence-classes-guide)

Equivalence classes of graphs arise in several settings, for instance, during causal discovery algorithms. This
guide covers the graph types that represent such classes and how to work with them.

```@example ec
using CausalStructures
using CairoMakie
using NetworkLayout
```

## Equivalence classes of DAGs

A [`PDAG`](@ref) (partially directed acyclic graph) is a graph whose edges may be directed or undirected, with no directed cycles. Two [`DAG`](@ref)s are Markov equivalent if and only if they have the same skeleton and the same v-structures (unshielded colliders).

Each Markov equivalence class of DAGs has a unique [`CPDAG`](@ref) (completed partially directed acyclic graph) representation. In a CPDAG, an edge is directed precisely when it has the same orientation in every DAG in the equivalence class; otherwise it remains undirected.

In CausalStructures, all PDAG types are encoded as subtypes of [`AbstractPDAG`](@ref).

Given a DAG, [`dag_to_cpdag`](@ref) computes its CPDAG:

```@example ec
dag = cgraph("C --> X, A --> X + Y, Y --> Z"; class = DAG)
cpdag = dag_to_cpdag(dag)
plot(cpdag)
```

The v-structure `C --> X <-- A` appears in every DAG in the equivalence class and therefore remains directed. The edges `A --- Y` and `Y --- Z` are undirected because no v-structure or Meek rule forces their orientation.
[`count_dags`](@ref) tells us how many DAGs are in the class, and
[`enumerate_dags`](@ref) lists them all:

```@example ec
count_dags(cpdag)
```

```@example ec
enumerate_dags(cpdag)
```

When you need one concrete DAG to work with, [`dag_from_pdag`](@ref) picks one:

```@example ec
dag_from_pdag(cpdag)
```

Adjustment sets can be computed on CPDAGs and the result is then valid for every DAG in the equivalence class:

```@example ec
all_adjustment_sets(cpdag, :X, :Z)
```

An [`MPDAG`](@ref) (maximally oriented partially directed acyclic graph) can, for instance, arise when background knowledge is incorporated during causal discovery, orienting some edges of a CPDAG.

[`meek_closure`](@ref) propagates all further orientations implied by Meek's rules on a PDAG to obtain an MPDAG:

```@example ec
pdag = cgraph("C --- X, A --> X, A --- Y, Y --> Z"; class = PDAG)
cpdag = meek_closure(pdag)
```

Here, `X --- C` was oriented to `X --> C` using Meek's rules.

All the methods shown above work on any subtype of [`AbstractPDAG`](@ref):

```@example ec
count_dags(pdag)
all_adjustment_sets(cpdag, :X, :Z)
```

!!! note "Only CPDAGs are guaranteed to be extendable"
    Every [`CPDAG`](@ref) represents a non-empty Markov equivalence class, so it
    always admits at least one consistent DAG extension and [`dag_from_pdag`](@ref)
    is guaranteed to succeed. This is not true for a general [`PDAG`](@ref) or
    [`MPDAG`](@ref): being acyclic (and, for an MPDAG, closed under Meek's rules)
    is not sufficient to ensure a consistent extension exists. For example, a
    chordless undirected cycle is a valid PDAG and MPDAG, yet it cannot be oriented
    into a DAG without introducing a new v-structure:

    ```@repl ec
    cg = cgraph("A --- B --- C --- D --- A"; class = PDAG)
    is_cpdag(cg)
    is_mpdag(cg)
    dag_from_pdag(cg)
    ```

## Equivalence classes of MAGs

Maximal Ancestral Graphs ([`MAG`](@ref)s) naturally arise when some common causes are
unobserved: every latent common cause between two observed nodes becomes a bidirected edge (`<->`)
in the MAG. Two MAGs are Markov equivalent if they
encode the same conditional independence structure over the observed variables.

Each Markov equivalence class of MAGs has a unique [`PAG`](@ref) (Partial Ancestral Graph). Like a PDAG for DAGs, the PAG marks each endpoint with the symbol shared by every MAG in the class. A circle (`o`) at an endpoint means that mark is not invariant; some MAGs in the class have a tail there and others have an arrowhead.

Consider a MAG where `A` and `B` share a hidden common cause, `C` directly causes `B`, and `B` directly causes `D`:

```@example ec
mag = cgraph("A <-> B, C --> B --> D"; class = MAG)
```

[`mag_to_pag`](@ref) computes the PAG representing the Markov equivalence class of this MAG, so all MAGs that encode the same conditional independences:

```@example ec
pag = mag_to_pag(mag)
```

The arrowheads at `B` on the `A`-`B` and `C`-`B` edges are invariant: `A`,
`B`, and `C` form an unshielded collider at `B` (since `A` and `C` are
non-adjacent), so every MAG in the class has an edge pointing into `B` from
both sides. The circle marks at `A` and `C` are not invariant; the `A`-`B`
edge could be `A --> B` or `A <-> B`, and similarly for
`C`. The `B --> D` edge is invariant via Zhang's orientation rule R1: since `A`
and `D` are non-adjacent and `A o-> B --> D`, the tail at `B` is forced in all MAGs.

[`enumerate_mags`](@ref) lets you explore the equivalence class:

```@example ec
enumerate_mags(pag)
```

On a PAG, possible ancestors and possible descendants answer the
question: in which MAGs in the equivalence class could `V` be an ancestor
(or descendant) of `W`?

```@example ec
possible_ancestors(pag, :D)
```

All three of `A`, `B`, and `C` are possible ancestors of `D` because there is
at least one MAG in the class where each lies on a directed path to `D`. `B` is
a definite ancestor (the `B --> D` edge is invariant); `A` and `C` are possible
ancestors because their circle marks can resolve to tails, yielding `A --> B --> D`
and `C --> B --> D`.

```@example ec
possible_ancestors(pag, :A)
```

`A` has no possible ancestors because every neighbor of `A` in the PAG has an invariant arrowhead at that neighbor's end, so no edge can be oriented to point into `A`.

[`possible_descendants`](@ref) is the symmetric counterpart:

```@example ec
possible_descendants(pag, :A)
```

```@example ec
possible_descendants(pag, :D)
```
