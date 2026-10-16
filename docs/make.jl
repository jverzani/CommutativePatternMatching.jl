using CommutativePatternMatching
using Documenter

DocMeta.setdocmeta!(CommutativePatternMatching, :DocTestSetup, :(using CommutativePatternMatching); recursive=true)

makedocs(;
    modules=[CommutativePatternMatching],
    authors="jverzani <jverzani@gmail.com> and contributors",
    sitename="CommutativePatternMatching.jl",
    format=Documenter.HTML(;
        canonical="https://jverzani.github.io/CommutativePatternMatching.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/jverzani/CommutativePatternMatching.jl",
    devbranch="main",
)
