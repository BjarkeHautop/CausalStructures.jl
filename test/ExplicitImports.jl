@testitem "ExplicitImports" tags = [:explicit_imports] begin
    using ExplicitImports
    using Makie, NetworkLayout, Sugiyama

    @test check_no_implicit_imports(CausalStructures) === nothing
    @test check_all_explicit_imports_via_owners(CausalStructures) === nothing
    @test check_all_explicit_imports_are_public(CausalStructures) === nothing
    @test check_no_stale_explicit_imports(CausalStructures) === nothing
    @test check_all_qualified_accesses_via_owners(CausalStructures) === nothing

    # `validate` is self-qualified in `_build_graph` (core/defs.jl) to disambiguate
    # from the local `validate::Bool` keyword argument that shadows it.
    @test check_no_self_qualified_accesses(CausalStructures; ignore = (:validate,)) ===
          nothing

    # The plotting extensions necessarily reach into non-public recipe/theming
    # internals of Makie (e.g. `current_default_theme`, `text_bb`, `plottype`) and
    # into our own underscore-prefixed extension points (e.g. `_layout_impl`).
    #
    # `default_rng`, `get_extension`, and `Iterators.reverse` were only declared
    # `public` (rather than merely exported) starting in Julia 1.11, so they must
    # stay ignored to keep this check passing on the LTS (1.10) release too.
    # `Binding` and `meta` are used to introspect docstrings (e.g. to check
    # whether a method has one) and are not declared `public` in `Base.Docs`.
    ignore_names = (
        :Arrow,
        :Automatic,
        :Binding,
        :Circle,
        :FigureAxisPlot,
        :Tail,
        :_default_layout_method,
        :_layout_edge_paths_impl,
        :_layout_impl,
        :automatic,
        :default_rng,
        :get_extension,
        :layout,
        :meta,
        :plottype,
        :reverse,
        :text_bb,
        :validate,
    )
    @test check_all_qualified_accesses_are_public(
        CausalStructures;
        ignore = ignore_names,
    ) === nothing
end
