module TrimCheck

using CausalStructures

function _check_construction()
    DAG("A --> B --> C, B --> D")
    UG("A --- B --- C")
    PDAG("A --> B, B --- C")
    CPDAG("A --> B <-- C, X --> Y")
    MPDAG("A --> B --> C")
    ADMG("A --> X, X --> Y, U <-> Y, U <-> X")
    AG("A --> B, B --> C")
    MAG("A <-> X, A --> Y, X --> Y")
    PAG("A o-o B, B o-o C")
    UNKNOWN("A --> B, A <-> B")
    return nothing
end

function _check_queries()
    dag = DAG("A --> X, B --> X, X --> Y, A --> Y")
    nodes(dag)
    neighbors(dag, :X)
    ancestors(dag, :Y)
    descendants(dag, :A)
    parents(dag, :Y)
    children(dag, :A)
    markov_blanket(dag, :X)
    topological_sort(dag)
    d_separated(dag, :A, :B, Symbol[])
    is_valid_adjustment(dag, :X, :Y, [:A])
    all_adjustment_sets(dag, :X, :Y)

    admg = ADMG("A --> X, X --> Y, U <-> Y, U <-> X")
    spouses(admg, :X)
    m_separated(admg, :A, :Y, Symbol[])

    pag = PAG("A o-o B, B o-o C, C o-o D, D o-o A, A o-o C")
    is_valid_adjustment(pag, :A, :C, Symbol[])
    all_adjustment_sets(pag, :A, :C)
    return nothing
end

Base.@ccallable function trim_check_run()::Cint
    _check_construction()
    _check_queries()
    return Cint(0)
end

end # module
