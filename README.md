# CausalGraphInterface

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/CausalGraphInterface.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://BjarkeHautop.github.io/CausalGraphInterface.jl/dev)
[![Test workflow status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/BjarkeHautop/CausalGraphInterface.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/BjarkeHautop/CausalGraphInterface.jl)
[![Lint workflow Status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

## Quick Start

```julia
using CausalGraphInterface

graph = caugi(
 directed(:A, :B),
 directed(:A, :C),
 directed(:B, :D),
 directed(:C, :D);
 class = DAG,
)

ug = caugi(
 undirected(:A, :B),
 undirected(:B, :C);
 class = UG,
)
```

Use `directed`, `undirected`, `bidirected`, `partially_directed`, `partially_undirected`, and `partial` to define edges. `class = DAG`, `class = UG`, `class = PDAG`, `class = ADMG`, and `class = UNKNOWN` are supported; other classes currently error.

`caugi` graph objects are immutable. `caugi()` eagerly materializes the CSR-style adjacency backend up front, while mutations invalidate that cache and rebuild it on demand through queries or `build!`. That keeps the graph state consistent and makes adjacency queries fast.
