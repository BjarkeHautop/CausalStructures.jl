# String DSL for building graphs, e.g. `cgraph("A --> B + C, D o-> E"; class = UNKNOWN)`.
#
# Grammar:
#   graph_str := statement (',' statement)*
#   statement := node_group (edge_op node_group)*
#   node_group := IDENT ('+' IDENT)*
#   edge_op := mark? '-'+ mark?
#
# `mark` on the left is `<` or `o`; on the right it is `>` or `o`; absent means a
# `Tail` endpoint. A statement with a single node_group and no edge_op declares
# isolated node(s). Consecutive node_groups are connected pairwise (cartesian
# product) by the edge_op between them, so chains ("A --> B --> C") and fan-outs
# ("A --> B + C") both fall out of the same rule.
#
# A `!` prefix negates a directed marker ("A !--> B", "A !<-- B"), producing a
# ForbiddenEdge for BackgroundKnowledge; only directed markers may be negated.

const _GRAPH_STR_EDGE_TOKEN_RE = r"\A!?[<o]?-+[o>]?"
const _GRAPH_STR_EDGE_MARKS_RE = r"\A(!)?([<o])?-+([o>])?\z"

function _lex_graph_string(s::AbstractString)
    tokens = Tuple{Symbol,Any}[]
    i = firstindex(s)
    n = ncodeunits(s)
    while i <= n
        c = s[i]
        if c == ',' || c == '\n'
            push!(tokens, (:comma, ","))
            i = nextind(s, i)
        elseif isspace(c)
            i = nextind(s, i)
        elseif c == '+'
            push!(tokens, (:plus, "+"))
            i = nextind(s, i)
        elseif c == '!' ||
               c == '<' ||
               c == '-' ||
               (c == 'o' && i < n && s[nextind(s, i)] == '-')
            m = match(_GRAPH_STR_EDGE_TOKEN_RE, SubString(s, i))
            m === nothing && throw(
                ArgumentError(
                    "Unexpected character '$c' at position $i in graph string: $(repr(s))",
                ),
            )
            push!(tokens, (:edge, m.match))
            i += ncodeunits(m.match)
        elseif isletter(c) || c == '_'
            j = i
            while j <= n && (isletter(s[j]) || isdigit(s[j]) || s[j] == '_')
                j = nextind(s, j)
            end
            push!(tokens, (:ident, Symbol(s[i:prevind(s, j)])))
            i = j
        else
            throw(
                ArgumentError(
                    "Unexpected character '$c' at position $i in graph string: $(repr(s))",
                ),
            )
        end
    end
    return tokens
end

function _graph_str_edge_marks(tok::AbstractString)
    m = match(_GRAPH_STR_EDGE_MARKS_RE, tok)
    negated, left, right = m.captures
    left_mark = left === nothing ? Tail : (left == "<" ? Arrow : Circle)
    right_mark = right === nothing ? Tail : (right == ">" ? Arrow : Circle)
    return negated !== nothing, left_mark, right_mark
end

# `is_directed`/`is_bidirected`/etc. (edges.jl) only recognize the canonical mark
# order (e.g. directed is (Tail, Arrow), never (Arrow, Tail)), so a reversed marker
# like "<--" must swap src/dst rather than keep the literal left/right positions.
function _graph_str_edge(left::Symbol, right::Symbol, tok::AbstractString)
    negated, left_mark, right_mark = _graph_str_edge_marks(tok)
    if negated
        (left_mark, right_mark) == (Tail, Arrow) && return ForbiddenEdge(left, right)
        (left_mark, right_mark) == (Arrow, Tail) && return ForbiddenEdge(right, left)
        throw(
            ArgumentError(
                "Only directed markers can be negated ('!-->' or '!<--'), got '$tok'",
            ),
        )
    end
    if (left_mark, right_mark) in ((Arrow, Tail), (Arrow, Circle), (Tail, Circle))
        return CausalEdge(right, left, right_mark, left_mark)
    end
    return CausalEdge(left, right, left_mark, right_mark)
end

function _parse_graph_statement(tokens::Vector{Tuple{Symbol,Any}})
    groups = Vector{Symbol}[]
    ops = String[]

    i = 1
    n = length(tokens)
    while i <= n
        kind, val = tokens[i]
        kind == :ident ||
            throw(ArgumentError("Expected a node name, got '$val' in graph string"))
        group = Symbol[val]
        i += 1
        while i <= n && tokens[i][1] == :plus
            i += 1
            i <= n && tokens[i][1] == :ident ||
                throw(ArgumentError("Expected a node name after '+' in graph string"))
            push!(group, tokens[i][2])
            i += 1
        end
        push!(groups, group)

        if i <= n
            tokens[i][1] == :edge ||
                throw(ArgumentError("Expected an edge marker, got '$(tokens[i][2])'"))
            push!(ops, tokens[i][2])
            i += 1
            i <= n || throw(
                ArgumentError(
                    "Trailing edge marker '$(ops[end])' with no following node in graph string",
                ),
            )
        end
    end

    items = Any[]
    if isempty(ops)
        for name in groups[1]
            push!(items, node(name))
        end
    else
        for k in eachindex(ops)
            for src in groups[k], dst in groups[k+1]
                push!(items, _graph_str_edge(src, dst, ops[k]))
            end
        end
    end
    return items
end

function _parse_graph_string(s::AbstractString)
    tokens = _lex_graph_string(s)
    items = Any[]
    stmt = Tuple{Symbol,Any}[]
    for tok in tokens
        if tok[1] == :comma
            isempty(stmt) || append!(items, _parse_graph_statement(stmt))
            empty!(stmt)
        else
            push!(stmt, tok)
        end
    end
    isempty(stmt) || append!(items, _parse_graph_statement(stmt))
    return items
end

"""
    cgraph(s::AbstractString; class::Type{<:CausalGraph}=DAG) -> CausalGraph

Construct a causal graph from a compact string description, instead of composing
[`CausalEdge`](@ref) values by hand.

Statements are separated by commas (or newlines); each connects node names with an
edge marker built from `<`, `-`, `o`, `>`:

| Marker | Equivalent constructor              |
|:------:|:------------------------------------|
| `-->`  | `directed(src, dst)`                |
| `<--`  | `directed(dst, src)`                |
| `---`  | `undirected(src, dst)`              |
| `<->`  | `bidirected(src, dst)`              |
| `o->`  | `partially_directed(src, dst)`      |
| `<-o`  | `partially_directed(dst, src)`      |
| `o--`  | `partially_undirected(src, dst)`    |
| `--o`  | `partially_undirected(dst, src)`    |
| `o-o`  | `partial(src, dst)`                 |

`+` fans a marker out to (or in from) several nodes at once, and chaining markers
connects consecutive node groups pairwise, so `"A --> B --> C"` yields two edges
(`A-->B`, `B-->C`) while `"A --> B + C"` yields `A-->B` and `A-->C`. A statement
with no marker (e.g. `"F"`) declares isolated node(s).

# Examples

```jldoctest
julia> cg = cgraph("A --> B + C, D o-> E"; class = UNKNOWN)
UNKNOWN with 5 nodes and 3 edges:
  nodes: A, B, C, D, E
  edges:
    A --> B, A --> C, D o-> E
```
"""
function cgraph(s::AbstractString; class::Type{<:CausalGraph} = DAG)
    items = _parse_graph_string(s)
    return cgraph(items...; class = class)
end
