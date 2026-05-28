# Backend construction and lightweight lazy materialization (CSR)

function csr_from_rows(rows::Vector{Vector{Int}})
    colptr = Vector{Int}(undef, length(rows) + 1)
    rowval = Int[]

    colptr[1] = 1

    for i in eachindex(rows)
        sort!(rows[i])
        unique!(rows[i])
        append!(rowval, rows[i])
        colptr[i + 1] = length(rowval) + 1
    end

    return colptr, rowval
end

function build_backend(nodes::Set{Symbol}, edges::Vector{CausalEdge})
    ordered_nodes = sort!(collect(nodes))
    index = Dict(node => i for (i, node) in enumerate(ordered_nodes))

    incident_rows = [Int[] for _ in ordered_nodes]
    parent_rows = [Int[] for _ in ordered_nodes]
    child_rows = [Int[] for _ in ordered_nodes]

    for edge in edges
        src_idx = index[edge.src]
        dst_idx = index[edge.dst]

        push!(incident_rows[src_idx], dst_idx)
        push!(incident_rows[dst_idx], src_idx)

        if edge.src_end == Tail && edge.dst_end == Arrow
            push!(child_rows[src_idx], dst_idx)
            push!(parent_rows[dst_idx], src_idx)
        elseif edge.src_end == Arrow && edge.dst_end == Tail
            push!(child_rows[dst_idx], src_idx)
            push!(parent_rows[src_idx], dst_idx)
        end
    end

    incident_colptr, incident_rowval = csr_from_rows(incident_rows)
    parent_colptr, parent_rowval = csr_from_rows(parent_rows)
    child_colptr, child_rowval = csr_from_rows(child_rows)

    return CSRBackend(ordered_nodes,
                      index,
                      incident_colptr,
                      incident_rowval,
                      parent_colptr,
                      parent_rowval,
                      child_colptr,
                      child_rowval)
end

function materialize_backend!(g::CausalGraph)
    backend = backend_ref(g)[]

    if backend === nothing
        # Re-validate class constraints whenever we need to rebuild the cache.
        # This enables mutable workflows that only invalidate on edits.
        validate!(g)
        backend = build_backend(g.nodes, g.edges)
        backend_ref(g)[] = backend
    end

    return backend
end

function invalidate_backend!(g::CausalGraph)
    backend_ref(g)[] = nothing
    return g
end

function build!(g::CausalGraph)
    materialize_backend!(g)
    return g
end

function node_index(g::CausalGraph, node::Symbol)
    backend = materialize_backend!(g)
    index = get(backend.index, node, 0)

    index == 0 && error("Unknown node: $(node)")

    return index
end

function csr_slice(colptr::Vector{Int}, rowval::Vector{Int}, index::Int)
    return rowval[colptr[index]:(colptr[index + 1] - 1)]
end

function symbols_from_slice(backend::CSRBackend, row_slice)
    return backend.nodes[row_slice]
end

function adjacency(g::CausalGraph, node::Symbol)
    backend = materialize_backend!(g)
    node_idx = node_index(g, node)
    return symbols_from_slice(backend, csr_slice(backend.incident_colptr, backend.incident_rowval, node_idx))
end

neighbors(g::CausalGraph, node::Symbol) = adjacency(g, node)

function parents(g::CausalGraph, node::Symbol)
    backend = materialize_backend!(g)
    node_idx = node_index(g, node)
    return symbols_from_slice(backend, csr_slice(backend.parents_colptr, backend.parents_rowval, node_idx))
end

function children(g::CausalGraph, node::Symbol)
    backend = materialize_backend!(g)
    node_idx = node_index(g, node)
    return symbols_from_slice(backend, csr_slice(backend.children_colptr, backend.children_rowval, node_idx))
end

function has_edge(g::CausalGraph, src::Symbol, dst::Symbol)
    backend = materialize_backend!(g)
    src_idx = node_index(g, src)
    dst_idx = node_index(g, dst)
    return dst_idx in csr_slice(backend.incident_colptr, backend.incident_rowval, src_idx)
end
