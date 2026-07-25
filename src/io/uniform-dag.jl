# a[m][k] = number of labelled DAGs on m nodes with exactly k outpoints, for
# all 1 <= m <= n and 1 <= k <= m. Needed for every core size the recursion
# below may recurse into, not just `n` itself, hence the full triangle.
function _uniform_dag_counts(n::Int)
    a = Vector{Vector{BigInt}}(undef, n)
    for m = 1:n
        counts = Vector{BigInt}(undef, m)
        counts[m] = BigInt(1)  # a_{m,m}: the single DAG on m nodes with no arcs
        for k = 1:(m-1)
            core = m - k
            pow2k = BigInt(2)^k
            twok_minus1 = pow2k - 1
            b = BigInt(0)
            for s = 1:core
                b += twok_minus1^s * pow2k^(core - s) * a[core][s]
            end
            counts[k] = binomial(BigInt(m), BigInt(k)) * b
        end
        a[m] = counts
    end
    return a
end

# Maps a uniformly drawn integer r in [1, sum(a[n])] to its outpoint
# sequence k_1,...,k_I (sum k_i = n), following Appendix C: find k_1 among
# a[n][1:n], rescale into the corresponding b_{n,k_1} range, then repeatedly
# find the next layer's outpoint count among the b-recursion's terms and
# rescale again, until the remaining core is empty.
function _uniform_dag_outpoints(a::Vector{Vector{BigInt}}, n::Int, r::BigInt)
    k1 = 1
    while r > a[n][k1]
        r -= a[n][k1]
        k1 += 1
    end
    r = cld(r, binomial(BigInt(n), BigInt(k1)))

    ks = Int[k1]
    prev_k = k1
    m = n - k1
    while m > 0
        pow2k = BigInt(2)^prev_k
        twok_minus1 = pow2k - 1
        s = 1
        t = twok_minus1^s * pow2k^(m - s) * a[m][s]
        while r > t
            r -= t
            s += 1
            t = twok_minus1^s * pow2k^(m - s) * a[m][s]
        end
        r = cld(r, binomial(BigInt(m), BigInt(s)) * twok_minus1^s * pow2k^(m - s))
        push!(ks, s)
        prev_k = s
        m -= s
    end
    return ks
end

_sample_uniform_dag_outpoints(rng::Random.AbstractRNG, a::Vector{Vector{BigInt}}, n::Int) =
    _uniform_dag_outpoints(a, n, rand(rng, big(1):sum(a[n])))

# Reconstructs the strictly-lower-triangular skeleton Q implied by an
# outpoint sequence k_1,...,k_I (Section 4.2). Nodes are grouped into
# contiguous index blocks from the base up: block I (indices 1:k_I) is the
# innermost core (no arcs), then block I-1 (k_{I-1} new outpoints) is added
# on top, and so on up to block 1 (the k_1 outpoints of the final DAG,
# which therefore never appear as a target column below). For each target
# column l in block i (i = I down to 2), the immediately new layer above it
# (block i-1) must contribute at least one arc to l, while any layer further
# above may optionally add one. Q[m, l] = true means an arc from the node at
# index m to the node at index l (m > l).
function _uniform_dag_skeleton(rng::Random.AbstractRNG, ks::Vector{Int}, n::Int)
    Q = falses(n, n)
    I = length(ks)
    I == 1 && return Q  # ks == [n]: every node is an outpoint, no arcs at all

    block_sizes = reverse(ks)  # [k_I, k_{I-1}, ..., k_1], base layer first
    block_end = cumsum(block_sizes)

    for idx = 1:(I-1)
        l_lo = idx == 1 ? 1 : block_end[idx-1] + 1
        l_hi = block_end[idx]
        forced_lo = block_end[idx] + 1
        forced_hi = block_end[idx+1]
        has_layers_above = idx + 1 < I

        for l = l_lo:l_hi
            any_forced = false
            while !any_forced
                for m = forced_lo:forced_hi
                    v = rand(rng, Bool)
                    Q[m, l] = v
                    any_forced |= v
                end
            end
            if has_layers_above
                for m = (forced_hi+1):n
                    Q[m, l] = rand(rng, Bool)
                end
            end
        end
    end
    return Q
end

"""
    uniform_dag([rng], n::Integer) -> DAG

Generate a random [`DAG`](@ref) on `n` observed nodes named `V1, …, Vn`
uniformly at random from the space of all labelled DAGs on `n` nodes.

Unlike [`generate_graph`](@ref), which samples edges independently (uniform
over graphs of a given size/density but *not* uniform over the space of
DAGs), this uses the recursive-enumeration algorithm of Kuipers & Moffa
(2015).

`rng` defaults to `Random.default_rng()` when omitted; pass an explicit
`AbstractRNG` (e.g. `Random.Xoshiro(seed)`) for reproducibility.

# Examples

```@repl
dag = uniform_dag(6)
```

# References

- [kuipers2015uniform](@cite)
"""
function uniform_dag(rng::Random.AbstractRNG, n::Integer)
    n = Int(n)
    if n <= 0
        error("n must be positive")
    end

    node_names = [Symbol("V$(i)") for i = 1:n]
    node_set = Set(node_names)

    a = _uniform_dag_counts(n)
    ks = _sample_uniform_dag_outpoints(rng, a, n)
    Q = _uniform_dag_skeleton(rng, ks, n)
    perm = randperm(rng, n)

    edges = CausalEdge[]
    for l = 1:n, m = (l+1):n
        if Q[m, l]
            push!(edges, directed(node_names[perm[m]], node_names[perm[l]]))
        end
    end

    # validate=false is safe here: every arc Q[m, l] has m > l, so arcs only
    # ever run from a higher to a lower Q-index -- acyclic by construction,
    # independent of the label permutation applied above.
    return DAG(node_set, edges; validate = false)
end

uniform_dag(n::Integer) = uniform_dag(Random.default_rng(), n)
