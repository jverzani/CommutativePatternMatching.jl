using CommutativePatternMatching
using Documenter
using MaterialDocs

DocMeta.setdocmeta!(CommutativePatternMatching, :DocTestSetup, :(using CommutativePatternMatching); recursive=true)

makedocs(;
    modules=[CommutativePatternMatching],
    authors="jverzani <jverzani@gmail.com> and contributors",
    sitename="CommutativePatternMatching.jl",
    format=Material3(;
        theme=:ocean_depth,
        dark_mode=:toggle,
        canonical="https://jverzani.github.io/CommutativePatternMatching.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Patterns" => "patterns.md",
        "Reference" => "reference.md",
    ],
)

deploydocs(;
    repo="github.com/jverzani/CommutativePatternMatching.jl",
    devbranch="main",
)
