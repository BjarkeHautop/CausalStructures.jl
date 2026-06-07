using CausalGraphInterface
using CairoMakie
using Documenter

DocMeta.setdocmeta!(
    CausalGraphInterface,
    :DocTestSetup,
    :(using CausalGraphInterface);
    recursive = true,
)

# Add titles of sections and overrides page titles
const titles = Dict(
    "05-quick-guide.md" => "Getting Started",
    "20-causal-identification.md" => "Causal Identification",
    "40-plotting.md" => "Plotting",
    "50-benchmark.md" => "Performance",
    "80-preferences.md" => "Preferences",
    "91-developer.md" => "Developer docs",
)

function recursively_list_pages(folder; path_prefix = "")
    pages_list = Any[]
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
    modules = [CausalGraphInterface],
    authors = "Bjarke Hautop Kristensen <bjarke.hautop@gmail.com>",
    repo = "https://github.com/BjarkeHautop/CausalGraphInterface.jl/blob/{commit}{path}#{line}",
    sitename = "CausalGraphInterface.jl",
    format = Documenter.HTML(;
        canonical = "https://BjarkeHautop.github.io/CausalGraphInterface.jl",
        example_size_threshold = nothing,
        size_threshold_ignore = ["40-plotting.md", "95-reference.md"],
    ),
    pages = list_pages(),
)

deploydocs(; repo = "github.com/BjarkeHautop/CausalGraphInterface.jl")
