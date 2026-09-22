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

function prettytime(t)
    t < 1e-3 && return string(round(t * 1_000_000, digits = 1), " us")
    t < 1 && return string(round(t * 1_000, digits = 2), " ms")
    return string(round(t, digits = 2), " s")
end

cell(t, w) = rpad(prettytime(t), w)

# ---------------------------------------------------------------------------
# 1) Enumerate all valid adjustment sets
# ---------------------------------------------------------------------------

function bench_enumerate_adjustment()
    println("\n=== Enumerate all valid adjustment sets ===")
    println(
        rpad("", 8),
        rpad("sets", 12),
        rpad("CS all_adjustment_sets", 34),
        rpad("CI list_covariate_adjustment", 34),
    )

    for n in (15, 18, 21)
        cg = CS.generate_graph(MersenneTwister(3), n; p = 3.0 / n, class = CS.DAG)
        g, idx, order = to_digraph(cg)
        x, y = order[4], order[5]
        xi, yi = idx[x], idx[y]

        cs_val = Ref{Any}()
        cs_res =
            @b (cs_val[] = CS.all_adjustment_sets(cg, x, y; minimal = false, max_size = n)) evals =
                1
        ci_val = Ref{Any}()
        ci_res = @b (ci_val[] = collect(CI.list_covariate_adjustment(g, xi, yi))) evals = 1

        n_cs = length(cs_val[])
        n_ci = length(ci_val[])
        @assert n_cs == n_ci "set count mismatch: CS=$n_cs CI=$n_ci"

        println(
            rpad("n=$n", 8),
            rpad(string(n_cs), 12),
            cell(cs_res.time, 34),
            cell(ci_res.time, 34),
        )
    end
end

# ---------------------------------------------------------------------------
# 2) Enumerate all valid backdoor sets
# ---------------------------------------------------------------------------

function bench_enumerate_backdoor()
    println("\n=== Enumerate all valid backdoor sets ===")
    println(
        rpad("", 8),
        rpad("sets", 12),
        rpad("CS all_backdoor_sets", 34),
        rpad("CI list_backdoor_adjustment", 34),
    )

    for n in (15, 18, 21)
        cg = CS.generate_graph(MersenneTwister(4), n; p = 3.0 / n, class = CS.DAG)
        g, idx, order = to_digraph(cg)
        x, y = order[9], order[8]
        xi, yi = idx[x], idx[y]

        cs_val = Ref{Any}()
        cs_res =
            @b (cs_val[] = CS.all_backdoor_sets(cg, x, y; minimal = false, max_size = n)) evals =
                1
        ci_val = Ref{Any}()
        ci_res = @b (ci_val[] = collect(CI.list_backdoor_adjustment(g, xi, yi))) evals = 1

        n_cs = length(cs_val[])
        n_ci = length(ci_val[])
        @assert n_cs == n_ci "set count mismatch: CS=$n_cs CI=$n_ci"

        println(
            rpad("n=$n", 8),
            rpad(string(n_cs), 12),
            cell(cs_res.time, 34),
            cell(ci_res.time, 34),
        )
    end
end

# ---------------------------------------------------------------------------
# 3) Enumerate all valid frontdoor sets. Frontdoor-set enumeration cost tracks the
#    size of the candidate pool rather than n directly.
# ---------------------------------------------------------------------------

function bench_enumerate_frontdoor()
    println("\n=== Enumerate all valid frontdoor sets ===")
    println(
        rpad("", 8),
        rpad("sets", 12),
        rpad("CS all_frontdoor_sets", 34),
        rpad("CI list_frontdoor_adjustment", 34),
    )

    for k in (13, 16, 19)
        cg = CS.DAG("X --> M --> Y")
        cg = CS.add_nodes(cg, [Symbol("W$i") for i = 1:k]...)
        g, idx, _ = to_digraph(cg)
        x, y = :X, :Y
        xi, yi = idx[x], idx[y]

        cs_val = Ref{Any}()
        cs_res = @b (cs_val[] = CS.all_frontdoor_sets(cg, x, y)) evals = 1
        ci_val = Ref{Any}()
        ci_res = @b (ci_val[] = collect(CI.list_frontdoor_adjustment(g, xi, yi))) evals = 1

        n_cs = length(cs_val[])
        n_ci = length(ci_val[])
        @assert n_cs == n_ci "set count mismatch: CS=$n_cs CI=$n_ci"

        println(
            rpad("k=$k", 8),
            rpad(string(n_cs), 12),
            cell(cs_res.time, 34),
            cell(ci_res.time, 34),
        )
    end
end

bench_enumerate_adjustment()
bench_enumerate_backdoor()
bench_enumerate_frontdoor()
