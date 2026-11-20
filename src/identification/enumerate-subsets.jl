# Bounded-size subset enumeration, plus the brute-force subset search built on
# it that `all_backdoor_sets` and `all_adjustment_sets` (PDAG/MPDAG/CPDAG,
# ADMG, AG/MAG) share: each enumerates candidate subsets of a "universe" of
# node indices up to a bounded size and keeps the ones a per-candidate
# validity check accepts.
#
# Subsets are visited size-by-size from `min_size`, lexicographic (by position
# in `universe`) within each size, and numbered by 0-based rank in that order.

# Below this many total candidate subsets, the fixed cost of spawning tasks
# outweighs any benefit.
const _SUBSET_SEARCH_PARALLEL_THRESHOLD = 4096

# Number of subsets of a universe of size `n` with size `min_size:max_size`.
_subset_count(n::Int, min_size::Int, max_size::Int) =
    sum(k -> binomial(n, k), min_size:min(max_size, n); init = 0)

# Positions (into a universe of size `n`) of the subset with rank `r`.
function _unrank_subset(n::Int, min_size::Int, r::Int)
    k = min_size
    while r >= (c = binomial(n, k))
        r -= c
        k += 1
    end
    pos = Vector{Int}(undef, k)
    v = 1
    for i = 1:k
        # binomial(n - v, k - i) subsets have `v` at position `i`.
        while r >= (c = binomial(n - v, k - i))
            r -= c
            v += 1
        end
        pos[i] = v
        v += 1
    end
    return pos
end

# Advances `pos` in place to the subset with the next rank, moving on to the
# first subset of the next size after the last of this one. Returns the first
# position that changed; every position before it is unchanged.
function _next_subset!(pos::Vector{Int}, n::Int)
    k = length(pos)
    i = k
    while i >= 1 && pos[i] == n - k + i
        i -= 1
    end
    if i == 0
        resize!(pos, k + 1)
        for j = 1:(k+1)
            pos[j] = j
        end
        return 1
    end
    pos[i] += 1
    for j = (i+1):k
        pos[j] = pos[j-1] + 1
    end
    return i
end

# Calls `f(cur)` for each subset of `universe` with rank in `lo:hi`, in rank
# order. `cur` is one buffer reused for every subset, so `f` must copy it to
# keep it, and must not modify it.
function _foreach_subset(
    f::F,
    universe::Vector{Int},
    min_size::Int,
    lo::Int,
    hi::Int,
) where {F}
    lo <= hi || return nothing
    n = length(universe)
    pos = _unrank_subset(n, min_size, lo)
    cur = universe[pos]
    for r = lo:hi
        f(cur)
        r == hi && break
        k = length(pos)
        # Fast path for the common step, where only the last position moves.
        if k > 0 && pos[k] < n
            pos[k] += 1
            cur[k] = universe[pos[k]]
            continue
        end
        # Only the tail from the first changed position needs refreshing.
        first_changed = _next_subset!(pos, n)
        first_changed == 1 && resize!(cur, length(pos))
        for i = first_changed:length(pos)
            cur[i] = universe[pos[i]]
        end
    end
    return nothing
end

# Calls `f(cur)` for every subset of `universe` of size `min_size:max_size`.
_foreach_subset(f::F, universe::Vector{Int}, min_size::Int, max_size::Int) where {F} =
    _foreach_subset(
        f,
        universe,
        min_size,
        0,
        _subset_count(length(universe), min_size, max_size) - 1,
    )

# Kept as its own function: a shared `checker` local between the sequential
# and threaded paths made Julia's closure-lowering box them together, so
# parallel tasks ended up aliasing each other's "fresh" scratch buffers.
function _search_subsets_sequential(
    universe::Vector{Int},
    min_size::Int,
    max_size::Int,
    make_checker::F1,
    to_symbols::F2,
) where {F1<:Function,F2<:Function}
    valid_sets = Vector{Vector{Symbol}}()
    checker = make_checker()
    _foreach_subset(universe, min_size, max_size) do cur
        checker(cur) && push!(valid_sets, to_symbols(cur))
    end
    return valid_sets
end

# Threaded path: splits the ranks into `nthreads()` contiguous ranges, one
# task each, so the candidates are never materialized.
function _search_subsets_threaded(
    universe::Vector{Int},
    min_size::Int,
    max_size::Int,
    make_checker::F1,
    to_symbols::F2,
) where {F1<:Function,F2<:Function}
    total = _subset_count(length(universe), min_size, max_size)
    nt = Threads.nthreads()
    per_thread = [Vector{Vector{Symbol}}() for _ = 1:nt]
    chunk = cld(total, nt)

    Threads.@threads for t = 1:nt
        lo = (t - 1) * chunk
        hi = min(lo + chunk, total) - 1
        checker = make_checker()
        results = per_thread[t]
        _foreach_subset(universe, min_size, lo, hi) do cur
            checker(cur) && push!(results, to_symbols(cur))
        end
    end
    # Rank ranges are contiguous, so concatenation preserves the same order
    # the sequential path produces.
    return reduce(vcat, per_thread)
end

# Brute-force every subset of `universe` (node indices) of size
# `min_size:max_size`, keeping those for which `checker(cur)` returns `true`,
# where `checker = make_checker()`.
#
# `make_checker` must be side-effect-free and return a *fresh* closure each
# time, so each task on the threaded path gets its own scratch buffers instead
# of racing on shared ones. `to_symbols(cur)` may be called concurrently and
# must not share mutable state with `checker`.
function _search_subsets(
    universe::Vector{Int},
    min_size::Int,
    max_size::Int,
    make_checker::F1,
    to_symbols::F2,
) where {F1<:Function,F2<:Function}
    total = _subset_count(length(universe), min_size, max_size)
    if Threads.nthreads() == 1 || total < _SUBSET_SEARCH_PARALLEL_THRESHOLD
        return _search_subsets_sequential(
            universe,
            min_size,
            max_size,
            make_checker,
            to_symbols,
        )
    end
    return _search_subsets_threaded(universe, min_size, max_size, make_checker, to_symbols)
end

# Applies `include`/`restrict` to a search `universe` (node indices). Returns
# `(inc, universe′)`, where `universe′` is `universe ∩ restrict` minus `inc`,
# or `nothing` if some `include` node is not in `universe ∩ restrict`.
function _constrain_universe(cg::CausalGraph, universe::Vector{Int}, include, restrict)
    n = length(cg.backend.nodes)
    allowed = falses(n)
    for v in universe
        allowed[v] = true
    end
    if restrict !== nothing
        in_restrict = falses(n)
        for v in _node_indices(cg, restrict)
            in_restrict[v] = true
        end
        allowed .&= in_restrict
    end
    inc = _node_indices(cg, include)
    all(v -> allowed[v], inc) || return nothing
    for v in inc
        allowed[v] = false
    end
    return inc, [v for v in universe if allowed[v]]
end

# `_search_subsets` over sets `inc ∪ S`, `S ⊆ universe`, of total size at most
# `max_size`.
function _search_subsets_including(
    universe::Vector{Int},
    inc::Vector{Int},
    max_size::Int,
    make_checker::F1,
    to_symbols::F2,
) where {F1<:Function,F2<:Function}
    isempty(inc) && return _search_subsets(universe, 0, max_size, make_checker, to_symbols)
    function make_inc_checker()
        checker = make_checker()
        buf = Int[]
        return function (cur::Vector{Int})
            empty!(buf)
            append!(buf, inc)
            append!(buf, cur)
            return checker(buf)
        end
    end
    inc_to_symbols(cur) = to_symbols([inc; cur])
    return _search_subsets(
        universe,
        0,
        max_size - length(inc),
        make_inc_checker,
        inc_to_symbols,
    )
end
