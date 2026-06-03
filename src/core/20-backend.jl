# Backend construction (Packed CSR)
#
# Each graph class gets a type-specific backend with pre-sorted neighbor buckets,
# inspired by the Rust PackedBuckets pattern in caugi. Buckets are laid out
# contiguously per node in a single rowval array; colptr[i]:colptr[i+1]-1 is
# node i's full neighborhood, and deg[b,i] gives each bucket's width within it.

function _build_packed_csr(n::Int, B::Int, bucket_rows::Vector{Vector{Vector{Int}}})
    for i = 1:n
        for b = 1:B
            sort!(unique!(bucket_rows[i][b]))
        end
    end

    deg = zeros(Int, B, n)
    colptr = Vector{Int}(undef, n + 1)
    colptr[1] = 1
    for i = 1:n
        node_total = 0
        for b = 1:B
            d = length(bucket_rows[i][b])
            deg[b, i] = d
            node_total += d
        end
        colptr[i+1] = colptr[i] + node_total
    end

    total = colptr[n+1] - 1
    rowval = Vector{Int}(undef, total)
    pos = 1
    for i = 1:n
        for b = 1:B
            for v in bucket_rows[i][b]
                rowval[pos] = v
                pos += 1
            end
        end
    end

    return colptr, deg, rowval
end

function build_backend(::Type{DAG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes = sort!(unique(collect(nodes)))
    index = Dict(n => i for (i, n) in enumerate(ordered_nodes))
    n = length(ordered_nodes)

    bucket_rows = [[Int[], Int[]] for _ = 1:n]  # [parents, children]

    for edge in edges
        si = index[edge.src]
        di = index[edge.dst]
        if edge.src_end == Tail && edge.dst_end == Arrow
            push!(bucket_rows[di][1], si)
            push!(bucket_rows[si][2], di)
        elseif edge.src_end == Arrow && edge.dst_end == Tail
            push!(bucket_rows[si][1], di)
            push!(bucket_rows[di][2], si)
        end
    end

    colptr, deg, rowval = _build_packed_csr(n, 2, bucket_rows)
    return DAGBackend(ordered_nodes, index, colptr, deg, rowval)
end

function build_backend(::Type{UG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes = sort!(unique(collect(nodes)))
    index = Dict(n => i for (i, n) in enumerate(ordered_nodes))
    n = length(ordered_nodes)

    rows = [Int[] for _ = 1:n]
    for edge in edges
        si = index[edge.src]
        di = index[edge.dst]
        push!(rows[si], di)
        push!(rows[di], si)
    end

    colptr = Vector{Int}(undef, n + 1)
    colptr[1] = 1
    for i = 1:n
        sort!(unique!(rows[i]))
        colptr[i+1] = colptr[i] + length(rows[i])
    end

    total = colptr[n+1] - 1
    rowval = Vector{Int}(undef, total)
    pos = 1
    for i = 1:n
        for v in rows[i]
            rowval[pos] = v
            pos += 1
        end
    end

    return UGBackend(ordered_nodes, index, colptr, rowval)
end

function build_backend(::Type{PDAG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes = sort!(unique(collect(nodes)))
    index = Dict(n => i for (i, n) in enumerate(ordered_nodes))
    n = length(ordered_nodes)

    bucket_rows = [[Int[], Int[], Int[]] for _ = 1:n]  # [parents, undirected, children]

    for edge in edges
        si = index[edge.src]
        di = index[edge.dst]
        if edge.src_end == Tail && edge.dst_end == Arrow
            push!(bucket_rows[di][1], si)
            push!(bucket_rows[si][3], di)
        elseif edge.src_end == Arrow && edge.dst_end == Tail
            push!(bucket_rows[si][1], di)
            push!(bucket_rows[di][3], si)
        elseif edge.src_end == Tail && edge.dst_end == Tail
            push!(bucket_rows[si][2], di)
            push!(bucket_rows[di][2], si)
        end
    end

    colptr, deg, rowval = _build_packed_csr(n, 3, bucket_rows)
    return PDAGBackend(ordered_nodes, index, colptr, deg, rowval)
end

function build_backend(::Type{ADMG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes = sort!(unique(collect(nodes)))
    index = Dict(n => i for (i, n) in enumerate(ordered_nodes))
    n = length(ordered_nodes)

    bucket_rows = [[Int[], Int[], Int[]] for _ = 1:n]  # [parents, spouses, children]

    for edge in edges
        si = index[edge.src]
        di = index[edge.dst]
        if edge.src_end == Tail && edge.dst_end == Arrow
            push!(bucket_rows[di][1], si)
            push!(bucket_rows[si][3], di)
        elseif edge.src_end == Arrow && edge.dst_end == Tail
            push!(bucket_rows[si][1], di)
            push!(bucket_rows[di][3], si)
        elseif edge.src_end == Arrow && edge.dst_end == Arrow
            push!(bucket_rows[si][2], di)
            push!(bucket_rows[di][2], si)
        end
    end

    colptr, deg, rowval = _build_packed_csr(n, 3, bucket_rows)
    return ADMGBackend(ordered_nodes, index, colptr, deg, rowval)
end

function build_backend(::Type{UNKNOWN}, nodes, edges::Vector{CausalEdge})
    ordered_nodes = sort!(unique(collect(nodes)))
    index = Dict(n => i for (i, n) in enumerate(ordered_nodes))
    n = length(ordered_nodes)

    # [parents, undirected, spouses, children]; Circle-endpoint edges → undirected bucket
    bucket_rows = [[Int[], Int[], Int[], Int[]] for _ = 1:n]

    for edge in edges
        si = index[edge.src]
        di = index[edge.dst]
        if edge.src_end == Tail && edge.dst_end == Arrow
            push!(bucket_rows[di][1], si)
            push!(bucket_rows[si][4], di)
        elseif edge.src_end == Arrow && edge.dst_end == Tail
            push!(bucket_rows[si][1], di)
            push!(bucket_rows[di][4], si)
        elseif edge.src_end == Tail && edge.dst_end == Tail
            push!(bucket_rows[si][2], di)
            push!(bucket_rows[di][2], si)
        elseif edge.src_end == Arrow && edge.dst_end == Arrow
            push!(bucket_rows[si][3], di)
            push!(bucket_rows[di][3], si)
        else
            push!(bucket_rows[si][2], di)
            push!(bucket_rows[di][2], si)
        end
    end

    colptr, deg, rowval = _build_packed_csr(n, 4, bucket_rows)
    return UNKNOWNBackend(ordered_nodes, index, colptr, deg, rowval)
end

# Slice into bucket b (1-indexed) of node i for backends with a deg matrix
@inline function bucket_slice(
    B::Union{DAGBackend,PDAGBackend,ADMGBackend,UNKNOWNBackend},
    i::Int,
    bucket::Int,
)
    start = B.colptr[i]
    for b = 1:(bucket-1)
        start += B.deg[b, i]
    end
    @view B.rowval[start:(start+B.deg[bucket, i]-1)]
end

# All neighbors of node i across all buckets
@inline _all_nbrs_slice(B::CausalBackend, i::Int) =
    @view B.rowval[B.colptr[i]:(B.colptr[i+1]-1)]

# Named bucket accessors — the bucket index is statically known per backend type

@inline _parents_slice(B::DAGBackend, i::Int) = bucket_slice(B, i, 1)
@inline _children_slice(B::DAGBackend, i::Int) = bucket_slice(B, i, 2)

@inline _undirected_slice(B::UGBackend, i::Int) = _all_nbrs_slice(B, i)

@inline _parents_slice(B::PDAGBackend, i::Int) = bucket_slice(B, i, 1)
@inline _undirected_slice(B::PDAGBackend, i::Int) = bucket_slice(B, i, 2)
@inline _children_slice(B::PDAGBackend, i::Int) = bucket_slice(B, i, 3)

@inline _parents_slice(B::ADMGBackend, i::Int) = bucket_slice(B, i, 1)
@inline _spouses_slice(B::ADMGBackend, i::Int) = bucket_slice(B, i, 2)
@inline _children_slice(B::ADMGBackend, i::Int) = bucket_slice(B, i, 3)

@inline _parents_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 1)
@inline _undirected_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 2)
@inline _spouses_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 3)
@inline _children_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 4)

# Public query functions

function node_index(g::CausalGraph, node::Symbol)
    idx = get(g.backend.index, node, 0)
    idx == 0 && error("Unknown node: $(node)")
    return idx
end

function adjacency(g::CausalGraph, node::Symbol)
    B = g.backend
    idx = get(B.index, node, 0)
    idx == 0 && error("Unknown node: $(node)")
    return B.nodes[_all_nbrs_slice(B, idx)]
end

neighbors(g::CausalGraph, node::Symbol) = adjacency(g, node)

function parents(g::Union{DAG,PDAG,ADMG,UNKNOWN}, node::Symbol)
    B = g.backend
    idx = get(B.index, node, 0)
    idx == 0 && error("Unknown node: $(node)")
    return B.nodes[_parents_slice(B, idx)]
end

function children(g::Union{DAG,PDAG,ADMG,UNKNOWN}, node::Symbol)
    B = g.backend
    idx = get(B.index, node, 0)
    idx == 0 && error("Unknown node: $(node)")
    return B.nodes[_children_slice(B, idx)]
end

function has_edge(g::CausalGraph, src::Symbol, dst::Symbol)
    B = g.backend
    src_idx = get(B.index, src, 0)
    dst_idx = get(B.index, dst, 0)
    src_idx == 0 && error("Unknown node: $(src)")
    dst_idx == 0 && error("Unknown node: $(dst)")
    dst_idx ∈ _all_nbrs_slice(B, src_idx)
end
