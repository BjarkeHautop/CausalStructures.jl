@testitem "aid requires matching node sets" tags = [:unit, :metrics] begin
    @test_throws ArgumentError aid(DAG("A --> B"), DAG("A --> B --> C"))
end

@testitem "aid rejects unknown type" tags = [:unit, :metrics] begin
    @test_throws ArgumentError aid(DAG("A --> B"), DAG("A --> B"); type = :bogus)
end

@testitem "aid identical graphs is zero" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C, A --> C")
    for type in (:parent, :ancestor, :oset)
        @test aid(g, g; type) == 0
        @test aid(g, g; type, normalized = true) == 0.0
    end
end

@testitem "aid normalized is zero for graphs with < 2 nodes" tags = [:unit, :metrics] begin
    g = DAG(node(:A))
    @test aid(g, g; normalized = true) == 0.0
end

@testitem "aid parent-AID coincides with the SID paper example" tags = [:unit, :metrics] begin
    # Peters & Bühlmann (2015): Parent-AID between DAGs equals the SID.
    truth = DAG("A --> B, A --> C, A --> D, A --> E, B --> C, B --> D, B --> E")
    guess = DAG("A --> C, A --> D, A --> E, B --> A, B --> C, B --> D, B --> E")
    @test aid(truth, guess; type = :parent) == 8
    @test aid(truth, guess; type = :parent, normalized = true) == 0.4
end

@testitem "aid ancestor-AID is zero when guess respects the causal order" tags =
    [:unit, :metrics] begin
    truth = DAG("A --> B --> C, A --> C")
    guess = DAG("A --> B --> C")
    @test aid(truth, guess; type = :ancestor) == 0
    @test aid(truth, guess; type = :parent) != 0
end

@testitem "aid: non-amenable CPDAG guess/truth counts every ordered pair" tags =
    [:unit, :metrics] begin
    d = DAG("A --> B")
    c = CPDAG("A --- B")
    for type in (:parent, :ancestor, :oset)
        @test aid(d, c; type) == 2
        @test aid(c, d; type) == 2
        @test aid(d, c; type, normalized = true) == 1.0
    end
end

@testitem "aid: Example 18 from paper" tags = [:unit, :metrics] begin
    dag1_true = DAG("V1 --> V3, V2")
    dag2_guess = DAG("V1 --> V2 --> V3")
    dag3_true = DAG("V1 --> V2 --> V3, V1 --> V3")

    @test aid(dag1_true, dag2_guess) == 0
    @test aid(dag3_true, dag2_guess) == 1
end

@testitem "aid: Example 19 from paper" tags = [:unit, :metrics] begin
    # a fully connected CPDAG guess (no effect identifiable) is maximally
    # wrong for every strategy, while an empty CPDAG guess (claims every effect zero)
    # is wrong on exactly the descendant pairs, for strategies that use a descendant
    # check (Ancestor-AID, Oset-AID) but not for Parent-AID.
    dag_true = DAG("V1 --> V2 --> V3 --> V4, V1 --> V3, V1 --> V4, V2 --> V4")
    p = 4

    fully_connected_guess = dag_to_cpdag(dag_true)
    empty_guess = CPDAG(node(:V1), node(:V2), node(:V3), node(:V4))

    for type in (:parent, :ancestor, :oset)
        @test aid(dag_true, fully_connected_guess; type) == p * (p - 1)
    end
    for type in (:ancestor, :oset)
        @test aid(dag_true, empty_guess; type) == p * (p - 1) ÷ 2
    end
end
