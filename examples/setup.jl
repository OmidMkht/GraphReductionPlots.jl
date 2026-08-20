using Pkg

const EXAMPLES_DIR = @__DIR__
const REPOSITORY_ROOT = normpath(joinpath(EXAMPLES_DIR, ".."))

Pkg.activate(EXAMPLES_DIR)
Pkg.develop(path=REPOSITORY_ROOT)
Pkg.instantiate()

println("Example environment is ready.")
println("Run: julia --project=examples examples/run_examples.jl --help")
