@testitem "Aqua" tags = [:aqua] begin
    using Aqua
    Aqua.test_all(CausalStructures)
end
