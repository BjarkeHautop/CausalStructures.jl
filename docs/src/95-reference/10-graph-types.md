# [Graph & Edge Types](@id graph-types-reference)

Here we explain how to build a causal graph and briefly describe the meaning of
each causal graph class. For a comprehensive introduction to these and the
underlying theory, see, for instance, [pearl2009causality](@citet) or
[peters2017elements](@citet); [richardsonspirtes2002ancestral](@citet) covers
`AG`/`MAG` specifically, and [zhang2008completeness](@citet) covers `PAG`.

## [Constructing graphs](@id constructing-graphs)

Each graph type is its own constructor: call [`DAG`](@ref), [`ADMG`](@ref),
[`PAG`](@ref), etc. with some edges (and, if you have isolated
nodes, some [`node`](@ref)s).

```@docs
node
```

### String syntax

The string form uses a compact syntax instead of composing [`CausalEdge`](@ref)
values by hand. Statements are separated by commas (or newlines); each connects
node names with an edge marker built from `<`, `-`, `o`, `>`:

| Marker | Equivalent constructor              |
|:------:|:------------------------------------|
| `-->`  | `directed(src, dst)`                |
| `<--`  | `directed(dst, src)`                |
| `---`  | `undirected(src, dst)`              |
| `<->`  | `bidirected(src, dst)`              |
| `o->`  | `partially_directed(src, dst)`      |
| `<-o`  | `partially_directed(dst, src)`      |
| `o--`  | `partially_undirected(src, dst)`    |
| `--o`  | `partially_undirected(dst, src)`    |
| `o-o`  | `partial(src, dst)`                 |

`+` fans a marker out to (or in from) several nodes at once, and chaining
markers connects consecutive node groups pairwise, so `"A --> B --> C"` yields
two edges (`A-->B`, `B-->C`) while `"A --> B + C"` yields `A-->B` and `A-->C`.
A statement with no marker (e.g. `"F"`) declares isolated node(s).

## Graph classes

Every graph type is a subtype of [`CausalGraph`](@ref), and each graph class is
verified on construction to be a valid graph.

```@docs
CausalGraph
```

### Directed Acyclic Graphs

A [`DAG`](@ref) (Directed Acyclic Graph) is the standard causal graph. All
edges are directed (`-->`), and the graph contains no directed cycles.

```@docs
DAG
```

### Partially Directed Acyclic Graphs

The subtypes of [`AbstractPDAG`](@ref) all have directed (`-->`) and
undirected (`---`) edges, and the graph contains no directed cycles.
Undirected edges represent edges whose orientation is not specified. A
[`PDAG`](@ref) is the general case; a [`CPDAG`](@ref) is the special PDAG that
represents an entire Markov equivalence class of DAGs (an edge stays
undirected exactly when its orientation varies across the class); an
[`MPDAG`](@ref) is a PDAG in which background knowledge may specify
orientations that are not determined by the underlying equivalence class.

See [Equivalence Classes](@ref equivalence-classes-guide) for worked
examples of all three.

```@docs
AbstractPDAG
PDAG
CPDAG
MPDAG
```

### Acyclic Directed Mixed Graphs

An [`ADMG`](@ref) allows directed (`-->`) and bidirected (`<->`) edges.
Directed edges represent causal relations, while bidirected edges represent
unobserved confounding between their endpoints. For example, an ADMG is what
you obtain when you use [`latent_project`](@ref) to project latent variables
out of a DAG.

```@docs
ADMG
```

### Ancestral Graphs

[`AbstractAG`](@ref) allows for directed (`-->`), bidirected (`<->`), and
undirected edges (`---`). In an ancestral graph, an arrowhead at a node
indicates that the node is not an ancestor of the other endpoint. Thus, a
bidirected edge (`<->`) indicates that neither endpoint is an ancestor of the
other. In causal applications, such edges commonly represent unobserved
confounding. Undirected edges have a different meaning here than in a `PDAG`:
rather than representing uncertain orientation, they represent **selection
bias**, arising from conditioning on variables that induce associations
through common effects.

```@docs
AbstractAG
AG
MAG
```

### Partial Ancestral Graphs

A [`PAG`](@ref) plays a role for MAGs analogous to that of a CPDAG for DAGs:
it represents a Markov equivalence class of MAGs
[zhang2008completeness](@cite). PAG edges can have three endpoint marks: a
tail, an arrowhead, or a circle. A circle indicates that the corresponding
endpoint mark is not determined by the Markov equivalence class.

```@docs
PAG
```

### Undirected Graphs

Not commonly used in causal inference, but still present for users that want
it. Only undirected (`---`) edges are allowed.

```@docs
UG
```

### Unknown Graphs

[`UNKNOWN`](@ref) imposes no structural constraints on the graph. It accepts
all supported edge types, including self-loops and parallel edges. Use it when
you need to represent a graph that does not fit any of the other graph classes.

```@docs
UNKNOWN
```

## Edges

```@docs
CausalEdge
directed
undirected
bidirected
partially_directed
partially_undirected
partial
```

## Background knowledge

Sometimes you want to impose some knowledge into your graph, such as `A`
must cause `B`, or that `C` definitely doesn't cause `D`.

```@docs
RequiredEdge
ForbiddenEdge
required_directed
forbidden_directed
BackgroundKnowledge
```
