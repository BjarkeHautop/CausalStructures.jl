@testitem "prob sorts and de-duplicates variables" tags = [:unit, :estimand] begin
    @test prob([:Y, :W]) == prob([:W, :Y])
    @test prob([:Y, :Y, :W]) == prob([:W, :Y])
    @test prob(:Y; given = [:X, :Z]) == prob(:Y; given = [:Z, :X])

    # A single Symbol and a one-element vector build the same term.
    @test prob(:Y) == prob([:Y])
end

@testitem "prob drops conditioned variables from the head" tags = [:unit, :estimand] begin
    # P(X, Y | X) == P(Y | X)
    @test prob([:X, :Y]; given = [:X]) == prob(:Y; given = [:X])
end

@testitem "prob prints with and without a conditioning set" tags = [:unit, :estimand] begin
    @test string(prob([:Y, :W]; given = [:X])) == "P(W, Y | X)"
    @test string(prob(:Y)) == "P(Y)"
end

@testitem "prob with an empty head is one" tags = [:unit, :estimand] begin
    @test isone(prob(Symbol[]))
    @test isone(prob(Symbol[]; given = [:X]))

    # The head is emptied by the conditioning set here.
    @test isone(prob([:X, :Y]; given = [:X, :Y]))
end

@testitem "marginal with an empty index is the identity" tags = [:unit, :estimand] begin
    p = prob(:Y; given = [:X])
    @test marginal(Symbol[], p) == p
end

@testitem "marginal flattens nested sums" tags = [:unit, :estimand] begin
    inner = marginal([:W], prob(:Y; given = [:W, :X]))
    outer = marginal([:Z], inner)

    @test outer isa Marginal
    @test outer.index == [:W, :Z]
    @test outer.term isa Prob
end

@testitem "marginal prints its index set" tags = [:unit, :estimand] begin
    e = marginal([:W], prob(:Y; given = [:W, :X]))
    @test string(e) == "Σ_{W} P(Y | W, X)"
end

@testitem "product flattens, drops ones, and collapses singletons" tags = [:unit, :estimand] begin
    a = prob(:W; given = [:X])
    b = prob(:Y; given = [:W, :X])

    @test product([a]) == a
    @test product([a, one(Estimand)]) == a
    @test product([product([a, b])]) == product([a, b])

    # Nested products are spliced into the parent rather than kept as a subtree.
    nested = product([product([a, b]), prob(:Z)])
    @test nested isa Product
    @test length(nested.terms) == 3
end

@testitem "empty product is the multiplicative identity" tags = [:unit, :estimand] begin
    e = product(Estimand[])

    @test isone(e)
    @test e == one(Estimand)
    @test string(e) == "1"
end

@testitem "product preserves factor order when printing" tags = [:unit, :estimand] begin
    e = product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])])
    @test string(e) == "P(W | X) P(Y | W, X)"
end

@testitem "quotient with a unit denominator collapses" tags = [:unit, :estimand] begin
    n = prob(:Y; given = [:X])
    @test quotient(n, one(Estimand)) == n
end

@testitem "quotient prints as a ratio" tags = [:unit, :estimand] begin
    # The conditioning sets differ, so this ratio is not a conditional and is
    # kept as one.
    e = quotient(prob([:Y, :Z]; given = [:X]), prob(:Z))

    @test e isa Quotient
    @test string(e) == "P(Y, Z | X) / P(Z)"
end

@testitem "quotient collapses a ratio of probabilities to a conditional" tags =
    [:unit, :estimand] begin
    # P(Y, Z | X) / P(Z | X) == P(Y | X, Z)
    @test quotient(prob([:Y, :Z]; given = [:X]), prob(:Z; given = [:X])) ==
          prob(:Y; given = [:X, :Z])

    # P(Y, Z) / P(Z) == P(Y | Z)
    @test quotient(prob([:Y, :Z]), prob(:Z)) == prob(:Y; given = [:Z])

    # No collapse when the two terms condition on different things.
    @test quotient(prob([:Y, :Z]; given = [:X]), prob(:Z)) isa Quotient

    # No collapse when the denominator's head is not part of the numerator's.
    @test quotient(prob(:Y; given = [:X]), prob(:Z; given = [:X])) isa Quotient
end

@testitem "marginal over part of the head marginalizes the term" tags = [:unit, :estimand] begin
    # Σ_W P(W, Y | X) == P(Y | X)
    @test marginal([:W], prob([:W, :Y]; given = [:X])) == prob(:Y; given = [:X])

    # A variable in the conditioning set is not marginalized, so the sum stands.
    @test marginal([:W], prob(:Y; given = [:W, :X])) isa Marginal

    # Nor is one the term does not mention at all.
    @test marginal([:Q], prob(:Y; given = [:X])) isa Marginal
end

@testitem "printing parenthesizes non-atomic subterms" tags = [:unit, :estimand] begin
    inner = marginal([:W], prob(:Y; given = [:W, :X]))

    # A sum inside a product must be bracketed: it would otherwise swallow the
    # factor to its right.
    @test string(product([prob(:X), inner])) == "P(X) (Σ_{W} P(Y | W, X))"

    # A quotient under a sum likewise, so the sum does not appear to range
    # over the numerator alone. The denominator has to mention W, or the sum
    # would move inside the ratio; the conditioning sets differ, which is what
    # keeps the ratio from collapsing into a plain conditional.
    num = prob([:Y, :Z]; given = [:X])
    den = prob(:Z; given = [:W])
    @test string(marginal([:W], quotient(num, den))) == "Σ_{W} (P(Y, Z | X) / P(Z | W))"

    # A product inside a sum needs no brackets.
    prod_term = product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])])
    @test string(marginal([:W], prod_term)) == "Σ_{W} P(W | X) P(Y | W, X)"
end

@testitem "marginal pulls constant factors out of the sum" tags = [:unit, :estimand] begin
    # P(Y | X) does not mention W, so it is a constant of the sum, and what is
    # left of the sum stays where that factor's neighbour stood.
    e = marginal([:W], product([prob(:Y; given = [:X]), prob(:V; given = [:X, :W])]))

    @test string(e) == "P(Y | X) (Σ_{W} P(V | W, X))"
end

@testitem "marginal drops a factor that sums to one" tags = [:unit, :estimand] begin
    # Σ_W P(W | X, Z) == 1, leaving P(Z | X) behind.
    e = marginal([:W], product([prob(:Z; given = [:X]), prob(:W; given = [:X, :Z])]))
    @test e == prob(:Z; given = [:X])

    # Dropping P(W | X, Z) frees Z, so P(Z | X) then sums to one as well and
    # the whole summand collapses.
    whole =
        marginal([:W, :Z], product([prob(:Z; given = [:X]), prob(:W; given = [:X, :Z])]))
    @test isone(whole)
end

@testitem "marginal keeps a factor another factor still depends on" tags =
    [:unit, :estimand] begin
    # Σ_W P(W | X) P(Y | W, X) is not P(Y | X) times anything: the second factor
    # depends on W, so neither factor may leave and neither sums away.
    e = marginal([:W], product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])]))

    @test e isa Marginal
    @test string(e) == "Σ_{W} P(W | X) P(Y | W, X)"
end

@testitem "marginal pulls a constant denominator out of the sum" tags = [:unit, :estimand] begin
    # Σ_W (P(Y, W | X) / P(Z)) == (Σ_W P(Y, W | X)) / P(Z), and the numerator
    # then marginalizes directly.
    e = marginal([:W], quotient(prob([:Y, :W]; given = [:X]), prob(:Z)))
    @test e == quotient(prob(:Y; given = [:X]), prob(:Z))

    # The denominator mentions W here, so the sum has to stay outside the ratio.
    kept = marginal([:W], quotient(prob([:Y, :Z]; given = [:X]), prob(:Z; given = [:W])))
    @test kept isa Marginal
end

@testitem "quotient cancels a factor shared by both sides" tags = [:unit, :estimand] begin
    # P(Z | X) P(Y | X, Z) / P(Z | X) == P(Y | X, Z)
    num = product([prob(:Z; given = [:X]), prob(:Y; given = [:X, :Z])])
    @test quotient(num, prob(:Z; given = [:X])) == prob(:Y; given = [:X, :Z])

    # Cancelling everything leaves the multiplicative identity.
    @test isone(quotient(num, num))

    # A factor appearing only on one side is left alone.
    @test quotient(num, prob(:Z; given = [:W])) isa Quotient
end

@testitem "estimands hash consistently with equality" tags = [:unit, :estimand] begin
    a = marginal([:W], product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])]))
    b = marginal([:W], product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])]))

    @test a == b
    @test hash(a) == hash(b)
    @test length(Set([a, b])) == 1
end

@testitem "estimands of different shapes are not equal" tags = [:unit, :estimand] begin
    @test prob(:Y) != marginal([:W], prob(:Y))
    @test prob(:Y) != quotient(prob(:Y), prob(:X))
    @test prob(:Y; given = [:X]) != prob(:X; given = [:Y])
end

@testitem "_freshen renames a sum that shadows a free variable" tags = [:unit, :estimand] begin
    # A is free in the first factor, so the sum in the second must not bind it.
    e = product([prob(:B; given = [:A]), marginal([:A], prob(:C; given = [:A]))])

    @test string(CausalStructures._freshen(e)) == "P(B | A) (Σ_{A'} P(C | A'))"
end

@testitem "_freshen seeds the walk with free variables, not just reserved ones" tags =
    [:unit, :estimand] begin
    # Guards against the entry point being bypassed: passing a `reserved` set
    # must not lose the expression's own free variables.
    e = product([prob(:B; given = [:A]), marginal([:A], prob(:C; given = [:A]))])

    @test string(CausalStructures._freshen(e, Set([:B]))) == "P(B | A) (Σ_{A'} P(C | A'))"
end

@testitem "_freshen lets disjoint scopes reuse a name" tags = [:unit, :estimand] begin
    # Two sibling sums are separate scopes, so both may bind A' -- renaming one
    # does not touch the other, and no ambiguity arises.
    e = product([
        prob(:B; given = [:A]),
        marginal([:A], prob(:C; given = [:A])),
        marginal([:A], prob(:D; given = [:A])),
    ])

    @test string(CausalStructures._freshen(e)) ==
          "P(B | A) (Σ_{A'} P(C | A')) (Σ_{A'} P(D | A'))"
end

@testitem "_freshen leaves a non-shadowing sum alone" tags = [:unit, :estimand] begin
    e = marginal([:W], product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])]))
    @test CausalStructures._freshen(e) == e
end

@testitem "latex rendering" tags = [:unit, :estimand] begin
    e = marginal([:W], product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])]))
    latex = sprint(show, MIME("text/latex"), e)

    @test latex == "\$\\sum_{W} P(W \\mid X) P(Y \\mid W, X)\$"

    frac = sprint(show, MIME("text/latex"), quotient(prob(:Y), prob(:X)))
    @test frac == "\$\\frac{P(Y)}{P(X)}\$"
end
