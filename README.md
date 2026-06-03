# CausalGraphInterface

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/CausalGraphInterface.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://BjarkeHautop.github.io/CausalGraphInterface.jl/dev)
[![Test workflow status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/BjarkeHautop/CausalGraphInterface.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/BjarkeHautop/CausalGraphInterface.jl)
[![Lint workflow Status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

CausalGraphInterface provides a common interface for working with causal graphs in Julia. Graphs are validated during construction to ensure they satisfy the constraints of their graph class,
and the package provides a collection of common causal-graph operations and queries.

The package is heavily inspired by the R package [caugi](https://caugi.org/), which I co-authored, and aims to bring similar functionality to the Julia ecosystem.

Currently supported graph classes include:

* Directed Acyclic Graphs (DAGs)
* Undirected Graphs (UGs)
* Partially Directed Acyclic Graphs (PDAGs)
* Acyclic Directed Mixed Graphs (ADMGs)

If you need a different graph class, you can make an arbitary one using UNKNOWN. We plan to extend this to more graph classes, such as PAGs, MPDAGs, CPDAGs, etc.

## Quick Start

Construct graphs by specifying edges and the desired graph class:

```julia
using CausalGraphInterface

dag = caugi(
    directed(:A, :B),
    directed(:A, :C),
    directed(:B, :D),
    directed(:C, :D);
    class = DAG,
)

graph = caugi(
    directed(:A, :B),
    directed(:B, :A),
    class = UNKNOWN,
    simple = false
)

ug = caugi(
    undirected(:A, :B),
    undirected(:B, :C);
    class = UG,
)
```

Available edge types include:

* `directed`
* `undirected`
* `bidirected`
* `partially_directed`
* `partially_undirected`
* `partial`

Graphs are validated as they are constructed. For example, a graph declared as a `DAG` cannot contain cycles, and graph classes only permit the edge types that are valid for that class.

See the documentation for additional graph classes, supported operations, and implementation details.

## To Do

Figure out a better syntax than using `directed(), undirected()`, etc. Ideally, we would support edge operators similar to the syntax used in R:
```r
%-->% (directed)
%---% (undirected)
%<->% (bidirected)
%o->% (partially directed)
%o--% (partially undirected)
%o-o% (partial)
```
Such operators are easier to read and allow concise specification of multiple edges. Note, that especially for the partial edge types, no close unicode alternative exists.
For example:
```julia
graph = caugi(
    :A %-->% :B + :C,
	:B + :C %o-o% :D,
    class = UNKNOWN
)
```
would be equivalent to:
```julia
graph = caugi(
	directed(:A, :B),
	directed(:A, :C),
	partial(:B, :D),
	partial(:C, :D),
	class = UNKNOWN
)
```

Use `Edge(..., directed)` instead of `directed(...)`?