using CausalStructures
using CairoMakie
using NetworkLayout

pos = Dict(:A => (0.0, 1.0), :B => (-0.87, -0.5), :C => (0.87, -0.5))
jl_purple = "#9558B2"
jl_red = "#CB3C33"
jl_green = "#389826"
node_color = Dict(:A => jl_purple, :B => jl_red, :C => jl_green)

cg = DAG(directed(:A, :B), directed(:A, :C), directed(:B, :C))
layout_positions = [pos[n] for n in nodes(cg)]

function make_logo(filename, ink)
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

    fig.scene.backgroundcolor[] = RGBAf(0, 0, 0, 0)
    for c in fig.content
        c isa Makie.Axis && (c.backgroundcolor[] = RGBAf(0, 0, 0, 0))
    end

    dir = joinpath(@__DIR__, "src", "assets")
    mkpath(dir)
    path = joinpath(dir, filename)
    save(path, fig)
    println("saved ", path)
end

make_logo("logo.svg", "#1C1A20")
make_logo("logo-dark.svg", "#E4E1E8")
