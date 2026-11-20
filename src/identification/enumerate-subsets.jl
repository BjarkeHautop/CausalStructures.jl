# Shared brute-force subset search used by `all_backdoor_sets` and
# `all_adjustment_sets` (PDAG/MPDAG/CPDAG, ADMG, AG/MAG): each enumerates
# candidate subsets of a "universe" of node indices up to a bounded size and
# keeps the ones a per-candidate validity check accepts.

# Below this many total candidate subsets, the fixed cost of spawning tasks
# outweighs any benefit.
const _SUBSET_SEARCH_PARALLEL_THRESHOLD = 4096

# Materialize every subset of `universe` of size `min_size:max_size`, in the
# same order the fused recursion in `_search_subsets_sequential` would visit
# them (size-by-size, lexicographic within each size).
function _all_subsets(universe::Vector{Int}, min_size::Int, max_size::Int)
    n = length(universe)
    out = Vector{Vector{Int}}()
    cur = Int[]

    for k = min_size:min(max_size, n)
        _all_subsets_rec!(out, cur, universe, n, 1, k)
    end
    return out
end

function _all_subsets_rec!(
    out::Vector{Vector{Int}},
    cur::Vector{Int},
    universe::Vector{Int},
    n::Int,
    start::Int,
    k_rem::Int,
)
    if k_rem == 0
        push!(out, copy(cur))
        return nothing
    end
    for i = start:n
        push!(cur, universe[i])
        _all_subsets_rec!(out, cur, universe, n, i + 1, k_rem - 1)
        pop!(cur)
    end
    return nothing
end

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
    n = length(universe)
    valid_sets = Vector{Vector{Symbol}}()
    checker = make_checker()
    cur = Int[]

    for k = min_size:min(max_size, n)
        _search_subsets_rec!(valid_sets, cur, universe, n, checker, to_symbols, 1, k)
    end
    return valid_sets
end

function _search_subsets_rec!(
    valid_sets::Vector{Vector{Symbol}},
    cur::Vector{Int},
    universe::Vector{Int},
    n::Int,
    checker::C,
    to_symbols::S,
    start::Int,
    k_rem::Int,
) where {C,S}
    if k_rem == 0
        checker(cur) && push!(valid_sets, to_symbols(cur))
        return nothing
    end
    for i = start:n
        push!(cur, universe[i])
        _search_subsets_rec!(
            valid_sets,
            cur,
            universe,
            n,
            checker,
            to_symbols,
            i + 1,
            k_rem - 1,
        )
        pop!(cur)
    end
    return nothing
end

# Positions (into a universe of size `n`) of the subset with 0-based rank `r`
# in the order `_search_subsets_sequential` visits them: size-by-size from
# `min_size`, lexicographic within each size.
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

# Advances `pos` in place to the next subset in the order of `_unrank_subset`,
# moving on to the first subset of the next size after the last of this one.
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
    else
        pos[i] += 1
        for j = (i+1):k
            pos[j] = pos[j-1] + 1
        end
    end
    return pos
end

# Threaded path: splits the candidate subsets, in the order the sequential
# path visits them, into `nthreads()` contiguous rank ranges. Each task
# unranks the first subset of its range and steps through the rest in place,
# so the candidates are never materialized.
function _search_subsets_threaded(
    universe::Vector{Int},
    min_size::Int,
    max_size::Int,
    make_checker::F1,
    to_symbols::F2,
) where {F1<:Function,F2<:Function}
    n = length(universe)
    # Not accumulated in a loop: a reassigned local captured by the
    # `@threads` closure would be boxed, making the loop body type-unstable.
    total = sum(k -> binomial(n, k), min_size:min(max_size, n); init = 0)
    nt = Threads.nthreads()
    per_thread = [Vector{Vector{Symbol}}() for _ = 1:nt]
    chunk = cld(total, nt)

    Threads.@threads for t = 1:nt
        lo = (t - 1) * chunk
        hi = min(lo + chunk, total) - 1
        if lo <= hi
            checker = make_checker()
            results = per_thread[t]
            pos = _unrank_subset(n, min_size, lo)
            cur = Int[]
            for r = lo:hi
                resize!(cur, length(pos))
                for i in eachindex(pos)
                    cur[i] = universe[pos[i]]
                end
                checker(cur) && push!(results, to_symbols(cur))
                r < hi && _next_subset!(pos, n)
            end
        end
    end
    # Rank ranges are contiguous, so concatenation preserves the same order
    # the sequential path produces.
    return reduce(vcat, per_thread)
end

# Brute-force every subset of `universe` (node indices) of size
# min_size:max_size`, keeping those for which `checker(cur)` returns `true`,
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
    n = length(universe)
    hi_size = min(max_size, n)

    total = 0
    for k = min_size:hi_size
        total += binomial(n, k)
    end

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
