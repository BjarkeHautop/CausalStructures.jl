@testitem "separation_distance requires matching node sets" tags = [:unit, :metrics] begin
    @test_throws ArgumentError separation_distance(DAG("A --> B"), DAG("A --> B --> C"))
end

@testitem "separation_distance rejects an unknown DAG strategy" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test_throws ArgumentError separation_distance(g, g; strategy = :bogus)
end

@testitem "separation_distance identical DAGs is zero, for every strategy" tags =
    [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test separation_distance(g, g) == 0
    @test separation_distance(g, g; strategy = :parents) == 0
    @test separation_distance(g, g; strategy = :ancestors) == 0
    @test separation_distance(g, g; strategy = :zl) == 0
    @test separation_distance(g, g; mb_enhanced = true) == 0
end

@testitem "separation_distance on DAGs supports :zl (ZL-separation is DAG-valid too)" tags =
    [:unit, :metrics] begin
    # ZL-separation is proven valid for MAGs, and every DAG is a MAG, so it's a
    # valid DAG strategy too.
    collider = DAG("A --> C <-- B")
    chain = DAG("A --> B --> C")
    @test separation_distance(collider, chain; strategy = :zl) == 1
    @test separation_distance(collider, chain; strategy = :zl) ==
          separation_distance(collider, chain; strategy = :parents)
end

@testitem "separation_distance detects a lost separation" tags = [:unit, :metrics] begin
    # Collider A --> C <-- B vs chain A --> B --> C: the chain's separator for
    # (A, C) is {B}, which does not separate A and C in the collider (they're
    # adjacent there).
    collider = DAG("A --> C <-- B")
    chain = DAG("A --> B --> C")
    @test separation_distance(collider, chain) == 1
end

@testitem "separation_distance is not symmetric in general" tags = [:unit, :metrics] begin
    empty_dag = DAG(node(:A), node(:B), node(:C))
    chain = DAG("A --> B --> C")

    # Separators from `chain` ({B} for the only non-adjacent pair (A, C))
    # trivially separate everything in `empty_dag` (there are no edges at all).
    @test separation_distance(empty_dag, chain) == 0

    # Separators from `empty_dag` (always the empty set) fail to separate any
    # of `chain`'s three node pairs, including the two adjacent ones.
    @test separation_distance(chain, empty_dag) == 3

    @test separation_distance(empty_dag, chain; symmetric = true) == 1.5
    @test separation_distance(chain, empty_dag; symmetric = true) == 1.5
end

@testitem "separation_distance normalized divides by the number of node pairs" tags =
    [:unit, :metrics] begin
    empty_dag = DAG(node(:A), node(:B), node(:C))
    chain = DAG("A --> B --> C")
    @test separation_distance(chain, empty_dag; normalized = true) == 1.0
    @test separation_distance(empty_dag, chain; normalized = true) == 0.0
end

@testitem "separation_distance normalized is zero for graphs with < 2 nodes" tags =
    [:unit, :metrics] begin
    g = DAG(node(:A))
    @test separation_distance(g, g; normalized = true) == 0.0
end

@testitem "separation_distance on MAGs uses ZL-separation" tags = [:unit, :metrics] begin
    mag = MAG("A <-> B, C --> B --> D")
    @test separation_distance(mag, mag) == 0
    @test separation_distance(mag, mag; mb_enhanced = true) == 0
    @test separation_distance(mag, mag; symmetric = true) == 0.0
end

@testitem "separation_distance handles AGs with no valid separator" tags = [:unit, :metrics] begin
    # A non-maximal AG: some non-adjacent pair has no separating subset at all,
    # so minimal_separator returns `nothing`; separation_distance must not error.
    ag = AG("C <-> A <-> B <-> D, A --> D, B --> C")
    @test separation_distance(ag, ag) isa Integer
end

@testitem "separation_distance on CPDAGs/MPDAGs uses p-parent separation" tags =
    [:unit, :metrics] begin
    cpdag = CPDAG("A --- B --- C")
    @test separation_distance(cpdag, cpdag) == 0
    @test separation_distance(cpdag, cpdag; mb_enhanced = true) == 0
    @test separation_distance(cpdag, cpdag; symmetric = true) == 0.0

    mpdag = MPDAG("A --> B --> C")
    @test separation_distance(mpdag, mpdag) == 0
end

@testitem "separation_distance on PAGs uses ZL-separation" tags = [:unit, :metrics] begin
    pag = mag_to_pag(MAG("A --> X --> M --> Y, A --> Y"))
    @test separation_distance(pag, pag) == 0
    @test separation_distance(pag, pag; normalized = true) == 0.0
    @test separation_distance(pag, pag; symmetric = true) == 0.0
    @test separation_distance(pag, pag; mb_enhanced = true) == 0
end
