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
    # into our own underscore-prefixed extension points (e.g. `_layout_impl`,
    # `_PLOT_*_DEFAULT`).
    ignore_names = (
        :Arrow,
        :Automatic,
        :Circle,
        :FigureAxisPlot,
        :Tail,
        :_PLOT_CURVATURE_DEFAULT,
        :_PLOT_EDGE_ARROW_FILL_DEFAULT,
        :_PLOT_EDGE_COLOR_DEFAULT,
        :_PLOT_EDGE_LINESTYLE_DEFAULT,
        :_PLOT_FIG_SIZE_DEFAULT,
        :_PLOT_LABEL_COLOR_DEFAULT,
        :_PLOT_LABEL_FONTSIZE_DEFAULT,
        :_PLOT_LABEL_FONT_DEFAULT,
        :_PLOT_LINEWIDTH_DEFAULT,
        :_PLOT_NODE_COLOR_DEFAULT,
        :_PLOT_NODE_LINESTYLE_DEFAULT,
        :_PLOT_NODE_PADDING_DEFAULT,
        :_PLOT_NODE_SHAPE_DEFAULT,
        :_PLOT_NODE_STROKECOLOR_DEFAULT,
        :_PLOT_NODE_STROKEWIDTH_DEFAULT,
        :_PLOT_OUTER_MARGIN_DEFAULT,
        :_PLOT_STRETCH_TO_FIG_SIZE_DEFAULT,
        :_PLOT_TITLE_COLOR_DEFAULT,
        :_PLOT_TITLE_FONTSIZE_DEFAULT,
        :_default_layout_method,
        :_layout_edge_paths_impl,
        :_layout_impl,
        :automatic,
        :layout,
        :plottype,
        :text_bb,
        :validate,
    )
    @test check_all_qualified_accesses_are_public(
        CausalStructures;
        ignore = ignore_names,
    ) === nothing
end
