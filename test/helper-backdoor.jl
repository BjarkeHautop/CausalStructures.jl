# Figure 6.5 from Elements of Causal Inference (p. 115)
# C-->X, X-->F, X-->D, A-->X, A-->K, K-->Y, D-->Y, D-->G, Y-->H
function _eci_graph()
    cgraph(
        directed(:C, :X),
        directed(:X, :F),
        directed(:X, :D),
        directed(:A, :X),
        directed(:A, :K),
        directed(:K, :Y),
        directed(:D, :Y),
        directed(:D, :G),
        directed(:Y, :H);
        class = DAG,
    )
end
