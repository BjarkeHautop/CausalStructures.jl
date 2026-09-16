```@meta
CurrentModule = Main
```

# [Plotting](@id plotting-reference)

Plotting is provided by an extension that loads when a [Makie](https://docs.makie.org/stable/)
backend is loaded. Node placement additionally requires
[NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl) or
[Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl) (or bring your own layout).
See the [Plotting guide](@ref plotting-guide) for full examples.

```@docs
Makie.plot(::CausalGraph)
layout
_makie_ext.CausalGraphPlot
_makie_ext.causalgraphplot
_makie_ext.causalgraphplot!
```
