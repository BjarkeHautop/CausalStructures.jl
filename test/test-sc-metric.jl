@testitem "sc_metric requires matching node sets" tags = [:unit, :metrics] begin
    @test_throws ArgumentError sc_metric(DAG("A --> B"), DAG("A --> B --> C"))
end

@testitem "sc_metric identical graphs is zero" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test sc_metric(g, g) == 0.0

    mag = MAG("A <-> B, C --> B --> D")
    @test sc_metric(mag, mag) == 0.0
end

@testitem "sc_metric is symmetric" tags = [:unit, :metrics] begin
    chain = DAG("A --> B --> C")
    collider = DAG("A --> B <-- C")
    @test sc_metric(chain, collider) == sc_metric(collider, chain)
end

@testitem "sc_metric detects a lost separation" tags = [:unit, :metrics] begin
    # Chain vs collider agree on marginal (dis)connection for every pair except
    # (A, C), and disagree on separation given {B} for that same pair (open in
    # the collider, blocked in the chain) -- 2 of 6 ordered triples at each order.
    chain = DAG("A --> B --> C")
    collider = DAG("A --> B <-- C")
    @test sc_metric(chain, collider) == 1 / 3
    @test sc_metric(chain, collider; max_order = 0) == 1 / 3
    @test sc_metric(chain, collider; max_order = 1) == 1 / 3
end

@testitem "sc_metric rejects an out-of-range max_order" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test_throws ArgumentError sc_metric(g, g; max_order = -1)
    @test_throws ArgumentError sc_metric(g, g; max_order = 2)
end

@testitem "sc_metric works across graph classes within the same separation family" tags =
    [:unit, :metrics] begin
    @test sc_metric(DAG("A --> B"), PDAG("A --> B")) == 0.0
    @test sc_metric(ADMG("A --> B"), MAG("A --> B")) == 0.0
end

@testitem "sc_metric rejects graphs from different separation families" tags =
    [:unit, :metrics] begin
    @test_throws ArgumentError sc_metric(DAG("A --> B"), ADMG("A --> B"))
    pag = mag_to_pag(MAG(directed(:A, :B)))
    @test_throws ArgumentError sc_metric(PDAG("A --> B"), pag)
end

@testitem "sc_metric on a single node is zero" tags = [:unit, :metrics] begin
    g = DAG(node(:A))
    @test sc_metric(g, g) == 0.0
end

@testitem "markov_metric requires matching node sets and separation family" tags =
    [:unit, :metrics] begin
    @test_throws ArgumentError markov_metric(DAG("A --> B"), DAG("A --> B --> C"))
    @test_throws ArgumentError markov_metric(DAG("A --> B"), ADMG("A --> B"))
end

@testitem "markov_metric identical graphs is zero" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test markov_metric(g, g) == 0.0
end

@testitem "markov_metric counts missed connections against ground truth" tags =
    [:unit, :metrics] begin
    # Chain (truth): every pair is connected at order 0 (2/6 of which the
    # collider misses -- (A, C) becomes separated there); at order 1, the two
    # (A, C)-with-{B} triples are excluded (chain reports them separated, not
    # connected), so the 4 remaining triples all agree. Full = mean(1/3, 0/4).
    chain = DAG("A --> B --> C")
    collider = DAG("A --> B <-- C")
    @test markov_metric(chain, collider; max_order = 0) == 1 / 3
    @test markov_metric(chain, collider; max_order = 1) == 1 / 6
    @test markov_metric(chain, collider) == 1 / 6
end

@testitem "faithfulness_metric requires matching node sets and separation family" tags =
    [:unit, :metrics] begin
    @test_throws ArgumentError faithfulness_metric(DAG("A --> B"), DAG("A --> B --> C"))
    @test_throws ArgumentError faithfulness_metric(DAG("A --> B"), ADMG("A --> B"))
end

@testitem "faithfulness_metric identical graphs is zero" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test faithfulness_metric(g, g) == 0.0
end

@testitem "faithfulness_metric counts spurious connections against ground truth" tags =
    [:unit, :metrics] begin
    # Chain (truth) reports no separations at all at order 0 (so that order
    # contributes 0), and only the two (A, C)-with-{B} triples as separated at
    # order 1 -- both of which the collider wrongly reports connected
    # (conditioning on its collider opens the path). Full = mean(0/0, 2/2).
    chain = DAG("A --> B --> C")
    collider = DAG("A --> B <-- C")
    @test faithfulness_metric(chain, collider; max_order = 0) == 0.0
    @test faithfulness_metric(chain, collider; max_order = 1) == 0.5
    @test faithfulness_metric(chain, collider) == 0.5
end
