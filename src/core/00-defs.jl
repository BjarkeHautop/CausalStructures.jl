# Basic definitions: endpoints, edge and graph types

@enum Endpoint begin
    Tail
    Arrow
    Circle
end

struct CausalEdge
    src::Symbol
    dst::Symbol
    src_end::Endpoint
    dst_end::Endpoint
end

struct CSRBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    incident_colptr::Vector{Int}
    incident_rowval::Vector{Int}
    parents_colptr::Vector{Int}
    parents_rowval::Vector{Int}
    children_colptr::Vector{Int}
    children_rowval::Vector{Int}
end

abstract type CausalGraph end

struct DAG <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::Base.RefValue{Union{Nothing,CSRBackend}}

    function DAG(nodes::Set{Symbol}, edges::Vector{CausalEdge})

        g = new(nodes, edges, Base.RefValue{Union{Nothing,CSRBackend}}(nothing))

        validate!(g)

        return g
    end
end

struct UG <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::Base.RefValue{Union{Nothing,CSRBackend}}

    function UG(nodes::Set{Symbol}, edges::Vector{CausalEdge})

        g = new(nodes, edges, Base.RefValue{Union{Nothing,CSRBackend}}(nothing))

        validate!(g)

        return g
    end
end

struct PDAG <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::Base.RefValue{Union{Nothing,CSRBackend}}

    function PDAG(nodes::Set{Symbol}, edges::Vector{CausalEdge})

        g = new(nodes, edges, Base.RefValue{Union{Nothing,CSRBackend}}(nothing))

        validate!(g)

        return g
    end
end

struct UNKNOWN <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::Base.RefValue{Union{Nothing,CSRBackend}}
    simple::Bool

    function UNKNOWN(nodes::Set{Symbol}, edges::Vector{CausalEdge}; simple::Bool = true)

        g = new(nodes, edges, Base.RefValue{Union{Nothing,CSRBackend}}(nothing), simple)

        validate!(g)

        return g
    end
end

function collect_nodes(edges::AbstractVector{CausalEdge})
    nodes = Set{Symbol}()
    sizehint!(nodes, 2 * length(edges))

    for e in edges
        push!(nodes, e.src)
        push!(nodes, e.dst)
    end

    return nodes
end

backend_ref(g::DAG) = g.backend
backend_ref(g::UG) = g.backend
backend_ref(g::PDAG) = g.backend
backend_ref(g::UNKNOWN) = g.backend
