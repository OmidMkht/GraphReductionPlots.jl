#!/usr/bin/env julia

const EXAMPLES = Dict(
    "basic" => "basic.jl",
    "transmission" => "transmission_case118.jl",
    "case118" => "transmission_case118.jl",
    "optikron" => "optikron_case100.jl",
    "case100" => "optikron_case100.jl",
    "matrices" => "matrix_inputs.jl",
)

function usage(io=stdout)
    println(io, "GraphReductionPlots.jl example runner")
    println(io)
    println(io, "Usage:")
    println(io, "  julia --project=. examples/run_examples.jl <example>")
    println(io)
    println(io, "Examples:")
    println(io, "  basic         Synthetic barbell graph")
    println(io, "  transmission  IEEE 118-bus transmission contraction")
    println(io, "  optikron      Opti-KRON 100-node contraction")
    println(io, "  matrices      Adjacency and incidence matrix inputs")
    println(io, "  all           Run all examples")
    println(io)
    println(io, "Custom data: copy examples/custom_template.jl and replace its input section.")
    println(io, "Aliases: case118, case100")
end

function run_example(name)
    file = get(EXAMPLES, name, nothing)
    if file === nothing
        println(stderr, "Unknown example: $name")
        usage(stderr)
        return false
    end
    println("\n=== Running $name ($(file)) ===")
    include(joinpath(@__DIR__, file))
    return true
end

if isempty(ARGS) || ARGS[1] in ("help", "-h", "--help")
    usage()
elseif ARGS[1] == "all"
    for name in ("basic", "transmission", "optikron", "matrices")
        run_example(name) || exit(1)
    end
else
    run_example(lowercase(ARGS[1])) || exit(1)
end
