# Run with: julia --project=benchmarks benchmarks/benchmark.jl

using Random
using Graphs
using CausalStructures
using CausalInference
using Chairmarks

const CS = CausalStructures
const CI = CausalInference

function to_digraph(cg::CS.DAG)
    order = CS.nodes(cg)
    idx = Dict(order[i] => i for i in eachindex(order))
    g = SimpleDiGraph(length(order))
    for e in CS.edges(cg)
        if e.src_end == CS.Tail && e.dst_end == CS.Arrow
            add_edge!(g, idx[e.src], idx[e.dst])
        end
    end
    return g, idx, order
end

function prettycount(n)
    n >= 1_000_000_000 && return string(round(n / 1_000_000_000, digits = 2), "G")
    n >= 1_000_000 && return string(round(n / 1_000_000, digits = 2), "M")
    n >= 1_000 && return string(round(n / 1_000, digits = 2), "K")
    return string(round(Int, n))
end

cell(t, allocs, sets, w) = rpad(
    string(round(t, digits = 2), " s / ", prettycount(allocs), " allocs (", sets, " sets)"),
    w,
)

function warmup()
    cg = CS.DAG("X --> M --> Y")
    g, idx, _ = to_digraph(cg)
    x, y = :X, :Y
    xi, yi = idx[x], idx[y]

    CS.all_adjustment_sets(cg, x, y; minimal = false, max_size = 3)
    collect(CI.list_covariate_adjustment(g, xi, yi))
    CS.all_backdoor_sets(cg, x, y; minimal = false, max_size = 3)
    collect(CI.list_backdoor_adjustment(g, xi, yi))
    CS.all_frontdoor_sets(cg, x, y)
    collect(CI.list_frontdoor_adjustment(g, xi, yi))
    return nothing
end

# ---------------------------------------------------------------------------
# 1) Enumerate all valid adjustment sets
# ---------------------------------------------------------------------------

function bench_enumerate_adjustment()
    println("\n=== Enumerate all valid adjustment sets (uncapped) ===")
    println(
        rpad("", 8),
        rpad("CS all_adjustment_sets", 42),
        rpad("CI list_covariate_adjustment", 42),
    )

    n = 21
    cg = CS.generate_graph(MersenneTwister(3), n; p = 3.0 / n, class = CS.DAG)
    g, idx, order = to_digraph(cg)
    x, y = order[4], order[5]
    xi, yi = idx[x], idx[y]

    cs_val = Ref{Any}()
    cs_res =
        @b (cs_val[] = CS.all_adjustment_sets(cg, x, y; minimal = false, max_size = n)) evals =
            1 samples = 1
    ci_val = Ref{Any}()
    ci_res =
        @b (ci_val[] = collect(CI.list_covariate_adjustment(g, xi, yi))) evals = 1 samples =
            1

    n_cs = length(cs_val[])
    n_ci = length(ci_val[])
    @assert n_cs == n_ci "set count mismatch: CS=$n_cs CI=$n_ci"

    println(
        rpad("n=$n", 8),
        cell(cs_res.time, cs_res.allocs, n_cs, 42),
        cell(ci_res.time, ci_res.allocs, n_ci, 42),
    )
end

# ---------------------------------------------------------------------------
# 2) Enumerate all valid backdoor sets
# ---------------------------------------------------------------------------

function bench_enumerate_backdoor()
    println("\n=== Enumerate all valid backdoor sets ===")
    println(
        rpad("", 8),
        rpad("CS all_backdoor_sets", 42),
        rpad("CI list_backdoor_adjustment", 42),
    )

    n = 21
    cg = CS.generate_graph(MersenneTwister(4), n; p = 3.0 / n, class = CS.DAG)
    g, idx, order = to_digraph(cg)
    x, y = order[9], order[8]
    xi, yi = idx[x], idx[y]

    cs_val = Ref{Any}()
    cs_res =
        @b (cs_val[] = CS.all_backdoor_sets(cg, x, y; minimal = false, max_size = n)) evals =
            1 samples = 1
    ci_val = Ref{Any}()
    ci_res =
        @b (ci_val[] = collect(CI.list_backdoor_adjustment(g, xi, yi))) evals = 1 samples =
            1

    n_cs = length(cs_val[])
    n_ci = length(ci_val[])
    @assert n_cs == n_ci "set count mismatch: CS=$n_cs CI=$n_ci"

    println(
        rpad("n=$n", 8),
        cell(cs_res.time, cs_res.allocs, n_cs, 42),
        cell(ci_res.time, ci_res.allocs, n_ci, 42),
    )
end

# ---------------------------------------------------------------------------
# 3) Enumerate all valid frontdoor sets. Frontdoor-set enumeration cost tracks the
#    size of the candidate pool rather than n directly.
# ---------------------------------------------------------------------------

function bench_enumerate_frontdoor()
    println("\n=== Enumerate all valid frontdoor sets (uncapped) ===")
    println(
        rpad("", 8),
        rpad("CS all_frontdoor_sets", 42),
        rpad("CI list_frontdoor_adjustment", 42),
    )

    k = 19
    cg = CS.DAG("X --> M --> Y")
    cg = CS.add_nodes(cg, [Symbol("W$i") for i = 1:k]...)
    g, idx, _ = to_digraph(cg)
    x, y = :X, :Y
    xi, yi = idx[x], idx[y]

    cs_val = Ref{Any}()
    cs_res = @b (cs_val[] = CS.all_frontdoor_sets(cg, x, y)) evals = 1 samples = 1
    ci_val = Ref{Any}()
    ci_res =
        @b (ci_val[] = collect(CI.list_frontdoor_adjustment(g, xi, yi))) evals = 1 samples =
            1

    n_cs = length(cs_val[])
    n_ci = length(ci_val[])
    @assert n_cs == n_ci "set count mismatch: CS=$n_cs CI=$n_ci"

    println(
        rpad("k=$k", 8),
        cell(cs_res.time, cs_res.allocs, n_cs, 42),
        cell(ci_res.time, ci_res.allocs, n_ci, 42),
    )
end

warmup()
bench_enumerate_adjustment()
bench_enumerate_backdoor()
bench_enumerate_frontdoor()
