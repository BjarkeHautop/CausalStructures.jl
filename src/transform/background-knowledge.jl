# Background knowledge in the sense of Meek (1995): required and forbidden directed
# edges, and the maximally oriented PDAGs (MPDAGs) they induce.

"""
    BackgroundKnowledge(items...) -> BackgroundKnowledge
    BackgroundKnowledge(s::AbstractString) -> BackgroundKnowledge

Causal background knowledge: a set of *required* direct causes (`A --> B` must be
present) and *forbidden* direct causes (`C --> D` must be absent).

`items` may be any combination of [`RequiredEdge`](@ref) values from
[`required_directed`](@ref) and [`ForbiddenEdge`](@ref) values from
[`forbidden_directed`](@ref).
The string form uses the [`cgraph`](@ref) string syntax restricted to the markers
`-->`, `<--`, `!-->`, and `!<--`.

Locally contradictory knowledge (the same edge both required and forbidden, or both
directions required) raises an error at construction.

Apply to a graph with [`apply_background_knowledge`](@ref) or [`dag_to_mpdag`](@ref).

# Examples

```jldoctest
julia> BackgroundKnowledge(required_directed(:A, :B), forbidden_directed(:C, :D))
BackgroundKnowledge with 1 required and 1 forbidden:
  required: A --> B
  forbidden: C !--> D

julia> BackgroundKnowledge("A --> B, C !--> D")
BackgroundKnowledge with 1 required and 1 forbidden:
  required: A --> B
  forbidden: C !--> D
```

# References

- [meek1995causal](@cite)
"""
struct BackgroundKnowledge
    required::Vector{RequiredEdge}
    forbidden::Vector{ForbiddenEdge}

    function BackgroundKnowledge(
        required::Vector{RequiredEdge},
        forbidden::Vector{ForbiddenEdge},
    )
        req = Set{Tuple{Symbol,Symbol}}((e.src, e.dst) for e in required)
        for (a, b) in req
            (b, a) in req && throw(
                ArgumentError(
                    "Contradictory background knowledge: both $a --> $b and $b --> $a required",
                ),
            )
        end
        for f in forbidden
            (f.src, f.dst) in req && throw(
                ArgumentError(
                    "Contradictory background knowledge: $(f.src) --> $(f.dst) is both required and forbidden",
                ),
            )
        end
        return new(required, forbidden)
    end
end

function BackgroundKnowledge(items...)
    required = RequiredEdge[]
    forbidden = ForbiddenEdge[]
    for item in items
        if item isa RequiredEdge
            push!(required, item)
        elseif item isa ForbiddenEdge
            push!(forbidden, item)
        elseif item isa CausalEdge
            throw(
                ArgumentError(
                    "Graph edges are not background-knowledge items; use " *
                    "required_directed($(repr(item.src)), $(repr(item.dst))) " *
                    "for a required edge",
                ),
            )
        else
            throw(ArgumentError("Unsupported background-knowledge item: $(typeof(item))"))
        end
    end
    return BackgroundKnowledge(required, forbidden)
end

function BackgroundKnowledge(s::AbstractString)
    required = RequiredEdge[]
    forbidden = ForbiddenEdge[]
    for item in _parse_graph_string(s)
        if item isa CausalEdge && is_directed(item)
            push!(required, RequiredEdge(item.src, item.dst))
        elseif item isa ForbiddenEdge
            push!(forbidden, item)
        else
            throw(
                ArgumentError(
                    "Background-knowledge strings only support the markers " *
                    "'-->', '<--', '!-->', and '!<--'; got: $(repr(s))",
                ),
            )
        end
    end
    return BackgroundKnowledge(required, forbidden)
end

"""
    apply_background_knowledge(cg::AbstractPDAG, bk) -> MPDAG

Orient the edges of `cg` according to the background knowledge `bk`, then close under
Meek's rules R1-R4 (see [`meek_closure`](@ref)), returning the [`MPDAG`](@ref) that
represents the DAGs consistent with both `cg` and `bk`.

`bk` may be a [`BackgroundKnowledge`](@ref) or a string accepted by its constructor.

Per constraint, against the current state of the edge in `cg`:

| Constraint         | `A --- B`         | `A --> B` | `B --> A` | not adjacent |
|:-------------------|:------------------|:----------|:----------|:-------------|
| required `A --> B` | orient `A --> B`  | no-op     | error     | error        |
| forbidden `A --> B`| orient `B --> A`  | error     | no-op     | no-op        |

Errors are raised because background knowledge cannot add or remove adjacencies, only
orient existing edges.

# Examples

```jldoctest
julia> cpdag = cgraph("A --- B --- C"; class = CPDAG);

julia> apply_background_knowledge(cpdag, "C --> B")
MPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    B --> A, C --> B

julia> apply_background_knowledge(cpdag, "C !--> B")
MPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --- B, B --> C
```

# References

- [meek1995causal](@cite)
"""
function apply_background_knowledge(cg::AbstractPDAG, bk::BackgroundKnowledge)
    node_set = Set(cg.backend.nodes)

    dir = Set{Tuple{Symbol,Symbol}}()
    und = Set{Tuple{Symbol,Symbol}}()
    for e in cg.edges
        if is_directed(e)
            push!(dir, (e.src, e.dst))
        else
            push!(und, _ordered_pair(e.src, e.dst))
        end
    end

    function check_nodes(a, b)
        for v in (a, b)
            v in node_set ||
                throw(ArgumentError("Background-knowledge node $v is not in the graph"))
        end
    end

    for e in bk.required
        a, b = e.src, e.dst
        check_nodes(a, b)
        if (a, b) in dir
            continue
        elseif (b, a) in dir
            error("Background knowledge requires $a --> $b, but the graph has $b --> $a")
        elseif _ordered_pair(a, b) in und
            delete!(und, _ordered_pair(a, b))
            push!(dir, (a, b))
        else
            error("Background knowledge requires $a --> $b, but $a and $b are not adjacent")
        end
    end

    for f in bk.forbidden
        a, b = f.src, f.dst
        check_nodes(a, b)
        if (a, b) in dir
            error("Background knowledge forbids $a --> $b, but the graph has $a --> $b")
        elseif _ordered_pair(a, b) in und
            delete!(und, _ordered_pair(a, b))
            push!(dir, (b, a))
        end
    end

    new_edges = CausalEdge[]
    for (a, b) in sort!(collect(dir))
        push!(new_edges, directed(a, b))
    end
    for (a, b) in sort!(collect(und))
        push!(new_edges, undirected(a, b))
    end

    return meek_closure(PDAG(node_set, new_edges))
end

apply_background_knowledge(cg::AbstractPDAG, s::AbstractString) =
    apply_background_knowledge(cg, BackgroundKnowledge(s))

"""
    dag_to_mpdag(cg::DAG, bk = BackgroundKnowledge()) -> MPDAG

Return the [`MPDAG`](@ref) representing the DAGs that are Markov equivalent to `cg`
and consistent with the background knowledge `bk`. This is the CPDAG of `cg` with
the `bk` orientations applied and closed under Meek's rules R1-R4.

`bk` may be a [`BackgroundKnowledge`](@ref) or a string accepted by its constructor.
Raises an error if `cg` itself violates `bk`; this guarantees the restricted
equivalence class is non-empty, since it contains `cg`.

# Examples

```jldoctest
julia> dag = cgraph("A --> B --> C");

julia> dag_to_cpdag(dag)
CPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --- B, B --- C

julia> dag_to_mpdag(dag, "A --> B")
MPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```

# References

- [meek1995causal](@cite)
"""
function dag_to_mpdag(cg::DAG, bk::BackgroundKnowledge = BackgroundKnowledge())
    dir = Set{Tuple{Symbol,Symbol}}((e.src, e.dst) for e in cg.edges)
    for e in bk.required
        (e.src, e.dst) in dir || error(
            "Background knowledge is inconsistent with the DAG: " *
            "required $(e.src) --> $(e.dst) is not an edge of the DAG",
        )
    end
    for f in bk.forbidden
        (f.src, f.dst) in dir && error(
            "Background knowledge is inconsistent with the DAG: " *
            "forbidden $(f.src) --> $(f.dst) is an edge of the DAG",
        )
    end
    return apply_background_knowledge(dag_to_cpdag(cg), bk)
end

dag_to_mpdag(cg::DAG, s::AbstractString) = dag_to_mpdag(cg, BackgroundKnowledge(s))
