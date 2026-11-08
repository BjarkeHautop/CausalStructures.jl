module TrimCheck

using CausalStructures
using Random: Xoshiro

# Covers the calls TrimTrace cannot check: those allowlisted in test/trim-allow.txt, written
# with literal values, and public names no test calls directly.

# --- generate_graph with a literal `class` ----------------------------------

function _check_generate_graph()
    generate_graph(6; m = 5)
    generate_graph(6; m = 5, class = DAG)
    generate_graph(6; m = 5, class = CPDAG)
    generate_graph(10; p = 0.3, class = ADMG, latents = 2)
    generate_graph(10; p = 0.3, class = MAG, latents = 2)
    generate_graph(10; p = 0.3, class = PAG, latents = 2)

    generate_graph(Xoshiro(1), 6; m = 5, class = DAG)
    generate_graph(Xoshiro(1), 6; m = 5, class = CPDAG)
    generate_graph(Xoshiro(1), 10; p = 0.3, class = ADMG, latents = 2)
    generate_graph(Xoshiro(1), 10; p = 0.3, class = MAG, latents = 2)
    generate_graph(Xoshiro(1), 10; p = 0.3, class = PAG, latents = 2)
    return nothing
end

# --- public names no test calls directly ------------------------------------

function _check_uncovered()
    uniform_dag_counts(5)
    return nothing
end

Base.@ccallable function trim_check_run()::Cint
    _check_generate_graph()
    _check_uncovered()
    return Cint(0)
end

end # module
