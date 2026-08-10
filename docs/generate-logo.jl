using CausalStructures
using CairoMakie
using NetworkLayout

pos = Dict(:A => (0.0, 1.0), :B => (-0.87, -0.5), :C => (0.87, -0.5))
jl_purple = "#9558B2"
jl_red = "#CB3C33"
jl_green = "#389826"
ink = "#1C1A20"
node_color = Dict(:A => jl_purple, :B => jl_red, :C => jl_green)

cg = cgraph(directed(:A, :B), directed(:A, :C), directed(:B, :C); class = DAG)
layout_positions = [pos[n] for n in nodes(cg)]

fig = Makie.plot(
    cg;
    layout = layout_positions,
    node_color = node_color,
    node_strokecolor = node_color,
    node_strokewidth = 0.0,
    node_radius = 0.30,
    edge_color = ink,
    arrow_fill = ink,
    linewidth = 3.0,
    arrow_size = 0.16,
    label_color = node_color,
    fig_size = (480, 460),
    outer_margin = 20,
)

dir = joinpath(@__DIR__, "src", "assets")
mkpath(dir)
save(joinpath(dir, "logo.svg"), fig)
println("saved ", joinpath(dir, "logo.svg"))
