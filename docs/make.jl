using CausalStructures
using CairoMakie
using Documenter
using DocumenterCitations

bib = CitationBibliography(joinpath(@__DIR__, "src", "references.bib"); style = :authoryear)

DocMeta.setdocmeta!(
    CausalStructures,
    :DocTestSetup,
    :(using CausalStructures);
    recursive = true,
)

# Add titles of sections and overrides page titles
const titles = Dict(
    "05-quick-guide.md" => "Getting Started",
    "15-equivalence-classes.md" => "Equivalence Classes",
    "20-causal-identification.md" => "Causal Identification",
    "40-plotting.md" => "Plotting",
    "80-preferences.md" => "Preferences",
    "90-bibliography.md" => "Bibliography",
    "91-developer.md" => "Developer docs",
    "95-reference" => "Reference",
)

function recursively_list_pages(folder; path_prefix = "")
    pages_list = Any[]

    # A subfolder's own index.md (if any) becomes its overview page, listed
    # first within that subfolder. The root index.md is handled separately by
    # `list_pages`, so skip this for the top-level call (empty path_prefix).
    if path_prefix != "" && isfile(joinpath(folder, "index.md"))
        folder_title = get(titles, path_prefix, path_prefix)
        push!(pages_list, "$folder_title overview" => joinpath(path_prefix, "index.md"))
    end

    for file in readdir(folder)
        if file == "index.md"
            # We add index.md separately to make sure it is the first in the list
            continue
        end
        # this is the relative path according to our prefix, not @__DIR__, i.e., relative to `src`
        relpath = joinpath(path_prefix, file)
        # full path of the file
        fullpath = joinpath(folder, relpath)

        if isdir(fullpath)
            # If this is a folder, enter the recursion case
            subsection = recursively_list_pages(fullpath; path_prefix = relpath)

            # Ignore empty folders
            if length(subsection) > 0
                title = if haskey(titles, relpath)
                    titles[relpath]
                else
                    @error "Bad usage: '$relpath' does not have a title set. Fix in 'docs/make.jl'"
                    relpath
                end
                push!(pages_list, title => subsection)
            end

            continue
        end

        if splitext(file)[2] != ".md" # non .md files are ignored
            continue
        elseif haskey(titles, relpath) # case 'title => path'
            push!(pages_list, titles[relpath] => relpath)
        else # case 'title'
            push!(pages_list, relpath)
        end
    end

    return pages_list
end

function list_pages()
    root_dir = joinpath(@__DIR__, "src")
    pages_list = recursively_list_pages(root_dir)

    return ["index.md"; pages_list]
end

makedocs(;
    modules = [CausalStructures],
    authors = "Bjarke Hautop Kristensen <bjarke.hautop@gmail.com>",
    repo = "https://github.com/BjarkeHautop/CausalStructures.jl/blob/{commit}{path}#{line}",
    sitename = "CausalStructures.jl",
    format = Documenter.HTML(;
        canonical = "https://BjarkeHautop.github.io/CausalStructures.jl",
        repolink = "https://github.com/BjarkeHautop/CausalStructures.jl",
        example_size_threshold = nothing,
        size_threshold_ignore = [
            "15-equivalence-classes.md",
            "20-causal-identification.md",
            "40-plotting.md",
        ],
    ),
    pages = list_pages(),
    plugins = [bib],
)

deploydocs(; repo = "github.com/BjarkeHautop/CausalStructures.jl")
