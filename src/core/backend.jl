# Backend construction (Packed CSR)
#
# Each graph class gets a type-specific backend with pre-sorted neighbor buckets,
# inspired by the Rust PackedBuckets pattern in caugi. Buckets are laid out
# contiguously per node in a single rowval array; colptr[i]:colptr[i+1]-1 is
# node i's full neighborhood, and deg[b,i] gives each bucket's width within it.
#
# Built via counting sort: two passes over `edges` (count, then place) into
# flat pre-sized arrays.
# `pairs_fn(edge, si, di)` returns a fixed-length tuple of (node_idx, bucket,
# value) triples describing every backend entry the edge contributes; a
# bucket of 0 means "no entry".

function _counting_csr(
    n::Int,
    B::Int,
    edges::Vector{CausalEdge},
    index,
    pairs_fn::F,
) where {F}
    deg_raw = zeros(Int, B, n)
    for edge in edges
        si = index[edge.src]
        di = index[edge.dst]
        for (node_idx, bucket, _) in pairs_fn(edge, si, di)
            bucket == 0 && continue
            deg_raw[bucket, node_idx] += 1
        end
    end

    bucket_start = Matrix{Int}(undef, B, n)
    colptr_raw = Vector{Int}(undef, n + 1)
    colptr_raw[1] = 1
    for i = 1:n
        off = colptr_raw[i]
        for b = 1:B
            bucket_start[b, i] = off
            off += deg_raw[b, i]
        end
        colptr_raw[i+1] = off
    end

    rowval_raw = Vector{Int}(undef, colptr_raw[n+1] - 1)
    cursor = copy(bucket_start)
    for edge in edges
        si = index[edge.src]
        di = index[edge.dst]
        for (node_idx, bucket, value) in pairs_fn(edge, si, di)
            bucket == 0 && continue
            pos = cursor[bucket, node_idx]
            rowval_raw[pos] = value
            cursor[bucket, node_idx] = pos + 1
        end
    end

    # Sort + dedup each (node, bucket) slice in place.
    deg = zeros(Int, B, n)
    for i = 1:n, b = 1:B
        len = deg_raw[b, i]
        len == 0 && continue
        s = bucket_start[b, i]
        v = view(rowval_raw, s:(s+len-1))
        sort!(v)
        w = 1
        for r = 2:len
            if v[r] != v[w]
                w += 1
                v[w] = v[r]
            end
        end
        deg[b, i] = w
    end

    colptr = Vector{Int}(undef, n + 1)
    colptr[1] = 1
    for i = 1:n
        node_total = 0
        for b = 1:B
            node_total += deg[b, i]
        end
        colptr[i+1] = colptr[i] + node_total
    end

    rowval = Vector{Int}(undef, colptr[n+1] - 1)
    pos = 1
    for i = 1:n
        for b = 1:B
            s = bucket_start[b, i]
            d = deg[b, i]
            for k = 0:(d-1)
                rowval[pos] = rowval_raw[s+k]
                pos += 1
            end
        end
    end

    return colptr, deg, rowval
end

function _ordered_index(nodes)
    ordered_nodes = sort!(unique(collect(nodes)))
    index = Dict(n => i for (i, n) in enumerate(ordered_nodes))
    return ordered_nodes, index, length(ordered_nodes)
end

function _dag_pairs(edge, si, di)
    if edge.src_end == Tail && edge.dst_end == Arrow
        return ((di, 1, si), (si, 2, di))
    elseif edge.src_end == Arrow && edge.dst_end == Tail
        return ((si, 1, di), (di, 2, si))
    else
        return ((0, 0, 0), (0, 0, 0))
    end
end

function build_backend(::Type{DAG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes, index, n = _ordered_index(nodes)

    colptr, deg, rowval = _counting_csr(n, 2, edges, index, _dag_pairs)  # [parents, children]
    return DAGBackend(ordered_nodes, index, colptr, deg, rowval)
end

_ug_pairs(_edge, si, di) = ((si, 1, di), (di, 1, si))

function build_backend(::Type{UG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes, index, n = _ordered_index(nodes)

    colptr, _, rowval = _counting_csr(n, 1, edges, index, _ug_pairs)
    return UGBackend(ordered_nodes, index, colptr, rowval)
end

function _pdag_pairs(edge, si, di)
    if edge.src_end == Tail && edge.dst_end == Arrow
        return ((di, 1, si), (si, 3, di))
    elseif edge.src_end == Arrow && edge.dst_end == Tail
        return ((si, 1, di), (di, 3, si))
    elseif edge.src_end == Tail && edge.dst_end == Tail
        return ((si, 2, di), (di, 2, si))
    else
        return ((0, 0, 0), (0, 0, 0))
    end
end

function build_backend(::Type{<:AbstractPDAG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes, index, n = _ordered_index(nodes)

    # [parents, undirected, children]
    colptr, deg, rowval = _counting_csr(n, 3, edges, index, _pdag_pairs)
    return PDAGBackend(ordered_nodes, index, colptr, deg, rowval)
end

function _admg_pairs(edge, si, di)
    if edge.src_end == Tail && edge.dst_end == Arrow
        return ((di, 1, si), (si, 3, di))
    elseif edge.src_end == Arrow && edge.dst_end == Tail
        return ((si, 1, di), (di, 3, si))
    elseif edge.src_end == Arrow && edge.dst_end == Arrow
        return ((si, 2, di), (di, 2, si))
    else
        return ((0, 0, 0), (0, 0, 0))
    end
end

function build_backend(::Type{ADMG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes, index, n = _ordered_index(nodes)

    # [parents, spouses, children]
    colptr, deg, rowval = _counting_csr(n, 3, edges, index, _admg_pairs)
    return ADMGBackend(ordered_nodes, index, colptr, deg, rowval)
end

function _ag_pairs(edge, si, di)
    if edge.src_end == Tail && edge.dst_end == Arrow
        return ((di, 1, si), (si, 4, di))
    elseif edge.src_end == Arrow && edge.dst_end == Tail
        return ((si, 1, di), (di, 4, si))
    elseif edge.src_end == Tail && edge.dst_end == Tail
        return ((si, 2, di), (di, 2, si))
    elseif edge.src_end == Arrow && edge.dst_end == Arrow
        return ((si, 3, di), (di, 3, si))
    else
        return ((0, 0, 0), (0, 0, 0))
    end
end

function build_backend(::Type{<:AbstractAG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes, index, n = _ordered_index(nodes)

    # [parents, undirected, spouses, children]
    colptr, deg, rowval = _counting_csr(n, 4, edges, index, _ag_pairs)
    return AGBackend(ordered_nodes, index, colptr, deg, rowval)
end

function _unknown_pairs(edge, si, di)
    if edge.src_end == Tail && edge.dst_end == Arrow
        return ((di, 1, si), (si, 4, di))
    elseif edge.src_end == Arrow && edge.dst_end == Tail
        return ((si, 1, di), (di, 4, si))
    elseif edge.src_end == Arrow && edge.dst_end == Arrow
        return ((si, 3, di), (di, 3, si))
    else
        # Tail-Tail, and circle-endpoint edges, land in the undirected bucket.
        return ((si, 2, di), (di, 2, si))
    end
end

function build_backend(::Type{UNKNOWN}, nodes, edges::Vector{CausalEdge})
    ordered_nodes, index, n = _ordered_index(nodes)

    # [parents, undirected, spouses, children]; Circle-endpoint edges --> undirected bucket
    colptr, deg, rowval = _counting_csr(n, 4, edges, index, _unknown_pairs)
    return UNKNOWNBackend(ordered_nodes, index, colptr, deg, rowval)
end

function _pag_bucket(near::Endpoint, far::Endpoint)
    near == Arrow && far == Tail && return 1    # X <-- Y  (parents)
    near == Tail && far == Arrow && return 2    # X --> Y  (children)
    near == Tail && far == Tail && return 3     # X --- Y  (undirected)
    near == Arrow && far == Arrow && return 4   # X <-> Y  (spouses)
    near == Circle && far == Arrow && return 5  # X o-> Y
    near == Arrow && far == Circle && return 6  # X <-o Y
    near == Circle && far == Tail && return 7   # X o-- Y
    near == Tail && far == Circle && return 8   # X --o Y
    return 9                                     # X o-o Y
end

function _pag_pairs(edge, si, di)
    # At src the near mark is src_end; at dst the near mark is dst_end.
    return (
        (si, _pag_bucket(edge.src_end, edge.dst_end), di),
        (di, _pag_bucket(edge.dst_end, edge.src_end), si),
    )
end

function build_backend(::Type{PAG}, nodes, edges::Vector{CausalEdge})
    ordered_nodes, index, n = _ordered_index(nodes)

    colptr, deg, rowval = _counting_csr(n, 9, edges, index, _pag_pairs)
    return PAGBackend(ordered_nodes, index, colptr, deg, rowval)
end

# Slice into bucket b (1-indexed) of node i for backends with a deg matrix
function bucket_slice(
    B::Union{DAGBackend,PDAGBackend,ADMGBackend,AGBackend,UNKNOWNBackend,PAGBackend},
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
_all_nbrs_slice(B::CausalBackend, i::Int) = @view B.rowval[B.colptr[i]:(B.colptr[i+1]-1)]

# Named bucket accessors

_parents_slice(B::DAGBackend, i::Int) = bucket_slice(B, i, 1)
_children_slice(B::DAGBackend, i::Int) = bucket_slice(B, i, 2)

_undirected_slice(B::UGBackend, i::Int) = _all_nbrs_slice(B, i)

_parents_slice(B::PDAGBackend, i::Int) = bucket_slice(B, i, 1)
_undirected_slice(B::PDAGBackend, i::Int) = bucket_slice(B, i, 2)
_children_slice(B::PDAGBackend, i::Int) = bucket_slice(B, i, 3)

_parents_slice(B::ADMGBackend, i::Int) = bucket_slice(B, i, 1)
_spouses_slice(B::ADMGBackend, i::Int) = bucket_slice(B, i, 2)
_children_slice(B::ADMGBackend, i::Int) = bucket_slice(B, i, 3)

_parents_slice(B::AGBackend, i::Int) = bucket_slice(B, i, 1)
_undirected_slice(B::AGBackend, i::Int) = bucket_slice(B, i, 2)
_spouses_slice(B::AGBackend, i::Int) = bucket_slice(B, i, 3)
_children_slice(B::AGBackend, i::Int) = bucket_slice(B, i, 4)

_parents_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 1)
_undirected_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 2)
_spouses_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 3)
_children_slice(B::UNKNOWNBackend, i::Int) = bucket_slice(B, i, 4)

# Definite (non-circle) relations.
_parents_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 1)
_children_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 2)
_undirected_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 3)
_spouses_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 4)
# Circle-endpoint relations (from focal node X to neighbor Y).
_circle_children_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 5)         # X o-> Y
_circle_parents_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 6)          # X <-o Y
_circle_undirected_out_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 7)   # X o-- Y
_circle_undirected_in_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 8)    # X --o Y
_circle_circle_slice(B::PAGBackend, i::Int) = bucket_slice(B, i, 9)           # X o-o Y

function node_index(cg::CausalGraph, node::Symbol)
    idx = get(cg.backend.index, node, 0)
    idx == 0 && error("Unknown node: $(node)")
    return idx
end

_node_indices(cg::CausalGraph, x::Symbol) = [node_index(cg, x)]
_node_indices(cg::CausalGraph, x::AbstractVector{Symbol}) = [node_index(cg, v) for v in x]

_as_symbol_set(x::Symbol) = Set{Symbol}((x,))
_as_symbol_set(x::AbstractVector{Symbol}) = Set{Symbol}(x)

"""
    neighbors(cg::CausalGraph, node::Symbol; mode::Symbol = :all) -> Vector{Symbol}

Return neighbors of `node` in `cg`, filtered by edge type via `mode`.

`mode` values:

- `:all`: all adjacent nodes
- `:in`: parents: nodes `p` with `p --> node`
- `:out`: children: nodes `c` with `node --> c`
- `:undirected`: undirected neighbors `node --- c`
- `:bidirected`: bidirected neighbors `node <-> c`

For a [`PAG`](@ref) the `:in`, `:out`, `:undirected`, and `:bidirected` modes return
only neighbors joined by the corresponding *definite* (circle-free) edge. Neighbors
joined by circle-mark edges (`o->`, `o--`, `o-o`) are reported by `:all` only.

# Examples

```jldoctest
julia> cg = cgraph("A --> B <-- C"; class = DAG);

julia> neighbors(cg, :B)
2-element Vector{Symbol}:
 :A
 :C

julia> neighbors(cg, :B, mode = :in)
2-element Vector{Symbol}:
 :A
 :C

julia> neighbors(cg, :A, mode = :out)
1-element Vector{Symbol}:
 :B

julia> pdag = cgraph("A --> B --- C"; class = PDAG);

julia> neighbors(pdag, :B, mode = :undirected)
1-element Vector{Symbol}:
 :C
```
"""
function neighbors(cg::CausalGraph, node::Symbol; mode::Symbol = :all)
    B = cg.backend
    idx = get(B.index, node, 0)
    idx == 0 && error("Unknown node: $(node)")
    if mode === :all
        return B.nodes[_all_nbrs_slice(B, idx)]
    elseif mode === :in
        B isa
        Union{DAGBackend,PDAGBackend,ADMGBackend,AGBackend,UNKNOWNBackend,PAGBackend} ||
            error("mode :in is not supported for $(nameof(typeof(cg)))")
        return B.nodes[_parents_slice(B, idx)]
    elseif mode === :out
        B isa
        Union{DAGBackend,PDAGBackend,ADMGBackend,AGBackend,UNKNOWNBackend,PAGBackend} ||
            error("mode :out is not supported for $(nameof(typeof(cg)))")
        return B.nodes[_children_slice(B, idx)]
    elseif mode === :undirected
        B isa Union{UGBackend,PDAGBackend,AGBackend,UNKNOWNBackend,PAGBackend} ||
            error("mode :undirected is not supported for $(nameof(typeof(cg)))")
        return B.nodes[_undirected_slice(B, idx)]
    elseif mode === :bidirected
        B isa Union{ADMGBackend,AGBackend,UNKNOWNBackend,PAGBackend} ||
            error("mode :bidirected is not supported for $(nameof(typeof(cg)))")
        return B.nodes[_spouses_slice(B, idx)]
    else
        error(
            "Unknown mode :$(mode). Valid modes: :all, :in, :out, :undirected, :bidirected",
        )
    end
end

"""
    parents(cg, node::Symbol) -> Vector{Symbol}

Return the parents of `node` in `cg`: nodes `p` such that `p --> node` is an edge in `cg`.

Equivalent to `neighbors(cg, node; mode = :in)`. Applicable to [`DAG`](@ref),
[`AbstractPDAG`](@ref), [`ADMG`](@ref), [`AbstractAG`](@ref), [`PAG`](@ref), and
[`UNKNOWN`](@ref). For a [`PAG`](@ref) only *definite* parents (`p --> node`) are
returned; a circle endpoint at `node` is not a parent.

# Examples

```jldoctest
julia> cg = cgraph("A --> B <-- C"; class = DAG);

julia> parents(cg, :B)
2-element Vector{Symbol}:
 :A
 :C

julia> parents(cg, :A)
Symbol[]
```
"""
parents(cg::Union{DAG,AbstractPDAG,ADMG,AbstractAG,PAG,UNKNOWN}, node::Symbol) =
    neighbors(cg, node; mode = :in)

"""
    children(cg, node::Symbol) -> Vector{Symbol}

Return the children of `node` in `cg`: nodes `c` such that `node --> c` is an edge in `cg`.

Equivalent to `neighbors(cg, node; mode = :out)`. Applicable to [`DAG`](@ref),
[`AbstractPDAG`](@ref), [`ADMG`](@ref), [`AbstractAG`](@ref), [`PAG`](@ref), and
[`UNKNOWN`](@ref). For a [`PAG`](@ref) only *definite* children (`node --> c`) are
returned; a circle endpoint at the child is not a definite child.

# Examples

```jldoctest
julia> cg = cgraph("A --> B + C"; class = DAG);

julia> children(cg, :A)
2-element Vector{Symbol}:
 :B
 :C

julia> children(cg, :B)
Symbol[]
```
"""
children(cg::Union{DAG,AbstractPDAG,ADMG,AbstractAG,PAG,UNKNOWN}, node::Symbol) =
    neighbors(cg, node; mode = :out)

"""
    has_edge(cg::CausalGraph, src::Symbol, dst::Symbol) -> Bool

Return `true` if there is any edge between `src` and `dst` in `cg`.

# Examples

```jldoctest
julia> cg = cgraph("A --> B"; class = DAG);

julia> has_edge(cg, :A, :B)
true
```
"""
function has_edge(cg::CausalGraph, src::Symbol, dst::Symbol)
    B = cg.backend
    src_idx = get(B.index, src, 0)
    dst_idx = get(B.index, dst, 0)
    src_idx == 0 && error("Unknown node: $(src)")
    dst_idx == 0 && error("Unknown node: $(dst)")
    dst_idx ∈ _all_nbrs_slice(B, src_idx)
end
