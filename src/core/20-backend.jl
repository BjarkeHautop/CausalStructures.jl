# Backend construction (CSR)

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

function build_csr(nodes::Set{Symbol}, edges::Vector{CausalEdge})
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

    return CSRBackend(
        ordered_nodes,
        index,
        incident_colptr,
        incident_rowval,
        parent_colptr,
        parent_rowval,
        child_colptr,
        child_rowval,
    )
end

csr(g::CausalGraph) = build_csr(g.nodes, g.edges)

function node_index(g::CausalGraph, node::Symbol)
    B = csr(g)
    idx = get(B.index, node, 0)

    idx == 0 && error("Unknown node: $(node)")

    return idx
end

function csr_slice(colptr::Vector{Int}, rowval::Vector{Int}, idx::Int)
    rowval[colptr[idx]:(colptr[idx + 1] - 1)]
end

symbols_from_slice(B::CSRBackend, row_slice) = B.nodes[row_slice]

function adjacency(g::CausalGraph, node::Symbol)
    B = csr(g)
    idx = get(B.index, node, 0)

    idx == 0 && error("Unknown node: $(node)")

    symbols_from_slice(
        B,
        csr_slice(B.incident_colptr, B.incident_rowval, idx),
    )
end

neighbors(g::CausalGraph, node::Symbol) = adjacency(g, node)

function parents(g::CausalGraph, node::Symbol)
    B = csr(g)
    idx = get(B.index, node, 0)

    idx == 0 && error("Unknown node: $(node)")

    symbols_from_slice(
        B,
        csr_slice(B.parents_colptr, B.parents_rowval, idx),
    )
end

function children(g::CausalGraph, node::Symbol)
    B = csr(g)
    idx = get(B.index, node, 0)

    idx == 0 && error("Unknown node: $(node)")

    symbols_from_slice(
        B,
        csr_slice(B.children_colptr, B.children_rowval, idx),
    )
end

function has_edge(g::CausalGraph, src::Symbol, dst::Symbol)
    B = csr(g)

    src_idx = get(B.index, src, 0)
    dst_idx = get(B.index, dst, 0)

    src_idx == 0 && error("Unknown node: $(src)")
    dst_idx == 0 && error("Unknown node: $(dst)")

    dst_idx in csr_slice(
        B.incident_colptr,
        B.incident_rowval,
        src_idx,
    )
end