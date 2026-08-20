@testitem "BackgroundKnowledge: construction from edges and string" tags =
    [:unit, :background_knowledge] begin
    bk = BackgroundKnowledge(required_directed(:A, :B), forbidden_directed(:C, :D))
    @test length(bk.required) == 1
    @test length(bk.forbidden) == 1
    @test bk.required[1] == required_directed(:A, :B)
    @test bk.forbidden[1] == forbidden_directed(:C, :D)

    bk_str = BackgroundKnowledge("A --> B, C !--> D")
    @test bk_str.required == bk.required
    @test bk_str.forbidden == bk.forbidden

    empty_bk = BackgroundKnowledge()
    @test isempty(empty_bk.required)
    @test isempty(empty_bk.forbidden)
end

@testitem "BackgroundKnowledge: string reversed markers" tags =
    [:unit, :background_knowledge] begin
    bk = BackgroundKnowledge("B <-- A, D !<-- C")
    @test bk.required == [required_directed(:A, :B)]
    # "D !<-- C" forbids C --> D, mirroring how "D <-- C" means C --> D
    @test bk.forbidden == [forbidden_directed(:C, :D)]
end

@testitem "BackgroundKnowledge: fan-out with + in string" tags =
    [:unit, :background_knowledge] begin
    bk = BackgroundKnowledge("A --> B + C, D !--> E + F")
    @test Set(bk.required) == Set([required_directed(:A, :B), required_directed(:A, :C)])
    @test Set(bk.forbidden) == Set([forbidden_directed(:D, :E), forbidden_directed(:D, :F)])
end

@testitem "BackgroundKnowledge: invalid inputs" tags = [:unit, :background_knowledge] begin
    # graph edges are rejected; constraints must use required_directed/forbidden_directed
    @test_throws ArgumentError BackgroundKnowledge(directed(:A, :B))
    @test_throws ArgumentError BackgroundKnowledge(undirected(:A, :B))
    @test_throws ArgumentError BackgroundKnowledge("A --- B")
    # negating a non-directed marker
    @test_throws ArgumentError BackgroundKnowledge("A !--- B")
    @test_throws ArgumentError BackgroundKnowledge("A !<-> B")
    # contradictory knowledge
    @test_throws ArgumentError BackgroundKnowledge("A --> B, B --> A")
    @test_throws ArgumentError BackgroundKnowledge("A --> B, A !--> B")
end

@testitem "cgraph rejects forbidden edges" tags = [:unit, :background_knowledge] begin
    @test_throws ArgumentError cgraph(forbidden_directed(:A, :B); class = DAG)
    @test_throws ArgumentError cgraph(required_directed(:A, :B); class = DAG)
    @test_throws ArgumentError cgraph("A !--> B"; class = DAG)
end

@testitem "dag_to_mpdag: empty background knowledge matches dag_to_cpdag" tags =
    [:unit, :background_knowledge] begin
    dag = cgraph("A --> B --> C, A --> D")
    mpdag = dag_to_mpdag(dag)
    cpdag = dag_to_cpdag(dag)
    @test mpdag isa MPDAG
    @test Set(nodes(mpdag)) == Set(nodes(cpdag))
    @test Set(edges(mpdag)) == Set(edges(cpdag))
end

@testitem "dag_to_mpdag: required edge propagates via Meek R1" tags =
    [:unit, :background_knowledge] begin
    dag = cgraph("A --> B --> C")
    # CPDAG is fully undirected; requiring A --> B compels B --> C by R1
    mpdag = dag_to_mpdag(dag, BackgroundKnowledge(required_directed(:A, :B)))
    @test mpdag isa MPDAG
    @test Set(edges(mpdag)) == Set([directed(:A, :B), directed(:B, :C)])

    # string form gives the same result
    mpdag_str = dag_to_mpdag(dag, "A --> B")
    @test Set(edges(mpdag_str)) == Set(edges(mpdag))
end

@testitem "dag_to_mpdag: forbidden edge orients the reverse direction" tags =
    [:unit, :background_knowledge] begin
    dag = cgraph("A --> B --> C")
    # forbidding B --> A orients A --> B, and R1 then compels B --> C
    mpdag = dag_to_mpdag(dag, "B !--> A")
    @test Set(edges(mpdag)) == Set([directed(:A, :B), directed(:B, :C)])
end

@testitem "dag_to_mpdag: partial knowledge leaves other edges undirected" tags =
    [:unit, :background_knowledge] begin
    dag = cgraph("A --> B, A --> C")
    # requiring B --> A leaves A --- C undirected (no rule applies)
    mpdag = dag_to_mpdag(dag, "B !--> A")

    @test directed(:A, :B) in edges(mpdag)
    @test undirected(:A, :C) in edges(mpdag)
end

@testitem "dag_to_mpdag: background knowledge inconsistent with DAG errors" tags =
    [:unit, :background_knowledge] begin
    dag = cgraph("A --> B --> C")
    # DAG has B --> C, so requiring C --> B / forbidding B --> C contradicts it
    @test_throws ErrorException dag_to_mpdag(dag, "C --> B")
    @test_throws ErrorException dag_to_mpdag(dag, "B !--> C")
    # required edge between non-adjacent nodes
    @test_throws ErrorException dag_to_mpdag(dag, "A --> C")
end

@testitem "dag_to_mpdag: enumerate_dags respects background knowledge" tags =
    [:unit, :background_knowledge] begin
    dag = cgraph("A --> B --> C, B --> D")
    bk = BackgroundKnowledge("A --> B, C !--> B")
    mpdag = dag_to_mpdag(dag, bk)

    dags = enumerate_dags(mpdag)
    @test !isempty(dags)
    # the input DAG is in the restricted class
    @test any(d -> Set(edges(d)) == Set(edges(dag)), dags)
    # every member satisfies the background knowledge
    for d in dags
        es = Set((e.src, e.dst) for e in edges(d))
        @test (:A, :B) in es
        @test (:C, :B) ∉ es
        @test markov_equivalent(d, dag)
    end
    # and the restricted class is smaller than the full MEC
    @test length(dags) < count_dags(dag_to_cpdag(dag))
end

@testitem "apply_background_knowledge: on a CPDAG directly" tags =
    [:unit, :background_knowledge] begin
    cpdag = dag_to_cpdag(cgraph("A --> B --> C"))
    mpdag = apply_background_knowledge(cpdag, "C --> B")
    @test mpdag isa MPDAG
    @test Set(edges(mpdag)) == Set([directed(:C, :B), directed(:B, :A)])
end

@testitem "apply_background_knowledge: no-op and error cases" tags =
    [:unit, :background_knowledge] begin
    cpdag = dag_to_cpdag(cgraph("A --> C, B --> C"))  # v-structure: fully compelled

    # required edge already directed: no-op
    mpdag = apply_background_knowledge(cpdag, "A --> C")
    @test Set(edges(mpdag)) == Set(edges(cpdag))

    # forbidden edge already absent (reverse directed / non-adjacent): no-op
    mpdag2 = apply_background_knowledge(cpdag, "C !--> A, A !--> B")
    @test Set(edges(mpdag2)) == Set(edges(cpdag))

    # conflicts with compelled orientations
    @test_throws ErrorException apply_background_knowledge(cpdag, "C --> A")
    @test_throws ErrorException apply_background_knowledge(cpdag, "A !--> C")
    # required edge cannot add an adjacency
    @test_throws ErrorException apply_background_knowledge(cpdag, "A --> B")
    # unknown node
    @test_throws ArgumentError apply_background_knowledge(cpdag, "A --> Z")
end

@testitem "apply_background_knowledge: incremental refinement of an MPDAG" tags =
    [:unit, :background_knowledge] begin
    dag = cgraph("A --> B, A --> C")
    m1 = dag_to_mpdag(dag, "B !--> A")
    @test undirected(:A, :C) in edges(m1)
    m2 = apply_background_knowledge(m1, "A --> C")
    @test Set(edges(m2)) == Set([directed(:A, :B), directed(:A, :C)])
    # accumulated knowledge in one step gives the same graph
    m12 = dag_to_mpdag(dag, "B !--> A, A --> C")
    @test Set(edges(m2)) == Set(edges(m12))
end

@testitem "BackgroundKnowledge and ForbiddenEdge printing" tags =
    [:unit, :background_knowledge] begin
    @test sprint(show, required_directed(:A, :B)) == "A --> B"
    @test sprint(show, forbidden_directed(:C, :D)) == "C !--> D"
    bk = BackgroundKnowledge("A --> B, C !--> D")
    out = sprint(show, bk)
    @test occursin("1 required and 1 forbidden", out)
    @test occursin("required: A --> B", out)
    @test occursin("forbidden: C !--> D", out)
end
