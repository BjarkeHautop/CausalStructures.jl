@testitem "hd requires matching node sets" tags = [:unit, :metrics] begin
    @test_throws ArgumentError hd(DAG("A --> B"), DAG("A --> B --> C"))
end

@testitem "hd ignores orientation" tags = [:unit, :metrics] begin
    @test hd(DAG("A --> B --> C"), DAG("A --> B <-- C")) == 0
    @test hd(DAG("A --> B"), DAG("B --> A")) == 0
end

@testitem "hd counts skeleton mismatches" tags = [:unit, :metrics] begin
    g1 = DAG(directed(:A, :B), node(:C))
    g2 = DAG("A --> B --> C")
    @test hd(g1, g2) == 1
    @test hd(g1, g2; normalized = true) == 1 / 3
end

@testitem "hd identical graphs is zero" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test hd(g, g) == 0
    @test hd(g, g; normalized = true) == 0.0
end

@testitem "hd works across graph classes" tags = [:unit, :metrics] begin
    @test hd(DAG("A --> B"), ADMG("A <-> B")) == 0
    @test hd(DAG("A --> B"), PDAG("A --- B")) == 0
end

@testitem "hd normalized is zero for graphs with < 2 nodes" tags = [:unit, :metrics] begin
    g = DAG(node(:A))
    @test hd(g, g; normalized = true) == 0.0
end

@testitem "shd requires matching node sets" tags = [:unit, :metrics] begin
    @test_throws ArgumentError shd(DAG("A --> B"), DAG("A --> B --> C"))
end

@testitem "shd counts orientation mismatches" tags = [:unit, :metrics] begin
    @test shd(DAG("A --> B --> C"), DAG("A --> B <-- C")) == 1
    @test shd(DAG("A --> B"), DAG("B --> A")) == 1
end

@testitem "shd counts a reversal once, not twice" tags = [:unit, :metrics] begin
    @test shd(DAG("A --> B"), DAG("B --> A")) == 1
end

@testitem "shd counts skeleton and orientation mismatches" tags = [:unit, :metrics] begin
    g1 = DAG(directed(:A, :B), node(:C))
    g2 = DAG("A --> B --> C")
    @test shd(g1, g2) == 1
    @test shd(g1, g2; normalized = true) == 1 / 3
end

@testitem "shd identical graphs is zero" tags = [:unit, :metrics] begin
    g = DAG("A --> B --> C")
    @test shd(g, g) == 0
    @test shd(g, g; normalized = true) == 0.0
end

@testitem "shd distinguishes edge kinds across graph classes" tags = [:unit, :metrics] begin
    @test shd(DAG("A --> B"), ADMG("A <-> B")) == 1
    @test shd(PDAG("A --- B"), ADMG("A <-> B")) == 1
    @test shd(DAG("A --> B"), PDAG("A --- B")) == 1
end

@testitem "shd distinguishes circle marks" tags = [:unit, :metrics] begin
    @test shd(UNKNOWN("A o-> B"), UNKNOWN("A <-> B")) == 1
    @test shd(UNKNOWN("A o-> B"), UNKNOWN("A o-> B")) == 0
    @test shd(UNKNOWN("A o-o B"), UNKNOWN("A o-> B")) == 1
end

@testitem "shd normalized is zero for graphs with < 2 nodes" tags = [:unit, :metrics] begin
    g = DAG(node(:A))
    @test shd(g, g; normalized = true) == 0.0
end
