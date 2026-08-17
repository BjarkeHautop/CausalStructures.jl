@testitem "possible_joint_parent_sets rejects duplicate or empty xs" tags = [:unit] begin
    cpdag = cgraph("X1 --- X2"; class = CPDAG)
    @test_throws ArgumentError possible_joint_parent_sets(cpdag, Symbol[])
    @test_throws ArgumentError possible_joint_parent_sets(cpdag, [:X1, :X1])
end

@testitem "possible_joint_parent_sets reduces to possible_parent_sets for a singleton" tags =
    [:unit] begin
    cpdag = cgraph("X1 --- X2, X1 --- A, X2 --- B, A --> Y, B --> Y"; class = CPDAG)
    for x in [:X1, :X2, :A, :B]
        single = Set(Set.(possible_parent_sets(cpdag, x)))
        joint = Set(Set(r[1]) for r in possible_joint_parent_sets(cpdag, [x]))
        @test single == joint
    end
end

@testitem "possible_joint_parent_sets: worked example with two intervention nodes" tags =
    [:unit] begin
    cpdag = cgraph("X1 --- X2, X1 --- A, X2 --- B, A --> Y, B --> Y"; class = CPDAG)
    result = Set(Tuple(r) for r in possible_joint_parent_sets(cpdag, [:X1, :X2]))
    expected = Set([([:X2], [:B]), ([:A], [:X1]), (Symbol[], [:X1]), ([:X2], Symbol[])])
    @test result == expected
end

@testitem "possible_joint_parent_sets rejects a new v-structure away from xs" tags = [:unit] begin
    # A --> X1 --> X2 <-- B would create a new v-structure at X2 (X1, B not
    # adjacent), even though X2's collision is not itself the intervention node A.
    cpdag = cgraph("X1 --- X2, X1 --- A, X2 --- B, A --> Y, B --> Y"; class = CPDAG)
    for r in possible_joint_parent_sets(cpdag, [:X1, :X2])
        @test Set(r[2]) != Set([:X1, :B])
    end
end

@testitem "possible_joint_parent_sets rejects orientations that would create a cycle" tags =
    [:unit] begin
    # complete undirected triangle: 8 mask combinations, 6 acyclic total orders survive
    tri = cgraph("X1 --- X2, X2 --- X3, X3 --- X1"; class = CPDAG)
    result = possible_joint_parent_sets(tri, [:X1, :X2, :X3])
    @test length(result) == 6
    for r in result
        pa1, pa2, pa3 = r
        # no orientation may make each node an ancestor of the next in a 3-cycle
        @test !(:X2 in pa1 && :X3 in pa2 && :X1 in pa3)
        @test !(:X3 in pa1 && :X1 in pa2 && :X2 in pa3)
    end
end

@testitem "possible_joint_parent_sets: entries are ordered like xs and pairwise consistent" tags =
    [:unit] begin
    cpdag = cgraph("X1 --- X2, X1 --- A, X2 --- B, A --> Y, B --> Y"; class = CPDAG)
    for r in possible_joint_parent_sets(cpdag, [:X2, :X1])
        pa_x2, pa_x1 = r
        # exactly one of X1, X2 is a parent of the other (they're adjacent)
        @test (:X1 in pa_x2) != (:X2 in pa_x1)
    end
end
