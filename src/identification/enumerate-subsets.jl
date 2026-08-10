# Shared brute-force subset search used by `all_backdoor_sets`,
# `all_adjustment_sets` (PDAG/MPDAG/CPDAG, ADMG, AG/MAG), and `all_iv_sets`:
# each enumerates candidate subsets of a "universe" of node indices up to a
# bounded size and keeps the ones a per-candidate validity check accepts.

# Below this many total candidate subsets, the fixed cost of materializing
# the candidate list and spawning tasks outweighs any benefit.
const _SUBSET_SEARCH_PARALLEL_THRESHOLD = 4096

# Materialize every subset of `universe` of size `min_size:max_size`, in the
# same order the fused recursion in `_search_subsets_sequential` would visit
# them (size-by-size, lexicographic within each size).
function _all_subsets(universe::Vector{Int}, min_size::Int, max_size::Int)
    n = length(universe)
    out = Vector{Vector{Int}}()
    cur = Int[]

    function rec(start::Int, k_rem::Int)
        if k_rem == 0
            push!(out, copy(cur))
            return
        end
        for i = start:n
            push!(cur, universe[i])
            rec(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = min_size:min(max_size, n)
        rec(1, k)
    end
    return out
end

# Kept as its own function because giving the sequential and
# threaded code paths their own local variable named `checker` inside a
# single function made Julia's
# closure-lowering share one box for both, so parallel tasks ended up
# aliasing each other's "fresh" scratch buffers.
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

    function rec(start::Int, k_rem::Int)
        if k_rem == 0
            checker(cur) && push!(valid_sets, to_symbols(cur))
            return
        end
        for i = start:n
            push!(cur, universe[i])
            rec(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = min_size:min(max_size, n)
        rec(1, k)
    end
    return valid_sets
end

# Threaded path: materializes every candidate subset up front, then splits
# them into `nthreads()` contiguous chunks.
function _search_subsets_threaded(
    universe::Vector{Int},
    min_size::Int,
    max_size::Int,
    make_checker::F1,
    to_symbols::F2,
) where {F1<:Function,F2<:Function}
    candidates = _all_subsets(universe, min_size, max_size)
    nt = Threads.nthreads()
    per_thread = [Vector{Vector{Symbol}}() for _ = 1:nt]
    chunk = cld(length(candidates), nt)

    Threads.@threads for t = 1:nt
        lo = (t - 1) * chunk + 1
        hi = min(t * chunk, length(candidates))
        if lo <= hi
            checker = make_checker()
            results = per_thread[t]
            for idx = lo:hi
                c = candidates[idx]
                checker(c) && push!(results, to_symbols(c))
            end
        end
    end
    # Chunks are contiguous slices of `candidates` assigned in increasing
    # order, so this concatenation preserves the same global size-then-
    # lexicographic order the sequential path produces.
    return reduce(vcat, per_thread)
end

# Brute-force every subset of `universe` (node indices) of size
# min_size:max_size`, keeping those for which `checker(cur)` returns `true`,
# where `checker = make_checker()`.

# `make_checker` must be side-effect-free and return a *fresh* closure each
# time it is called: on the sequential path it is called once, on the
#threaded path once per task, so that each task gets its own scratch buffers
# instead of racing on shared ones. `to_symbols(cur)` converts an accepted
# candidate to the sorted `Vector{Symbol}` that gets returned; it may be
# called concurrently from different tasks and must not share mutable state
# with `checker`.
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

# Shared brute-force search used by the `adjustment_set` methods for ADMG,
# AG/MAG, and PAG: finds the smallest subset of `universe` (node indices) for
# which `is_valid(z_idxs)` holds, trying sizes 0, 1, 2, ... in order and
# stopping at the first valid set. Returns `nothing` if no subset up to
# `length(universe)` is valid, distinct from a valid empty set (`Int[]`).
function _smallest_valid_subset(universe::Vector{Int}, is_valid::F) where {F<:Function}
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            is_valid(cur) && return copy(cur)
            return nothing
        end
        for i = start:length(universe)
            push!(cur, universe[i])
            result = enumerate!(i + 1, k_rem - 1)
            pop!(cur)
            result !== nothing && return result
        end
        return nothing
    end

    for k = 0:length(universe)
        result = enumerate!(1, k)
        result !== nothing && return result
    end
    return nothing
end
