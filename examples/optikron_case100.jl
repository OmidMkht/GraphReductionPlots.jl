using CairoMakie
using GraphReductionPlots
using Graphs

CairoMakie.activate!()

data_dir = joinpath(@__DIR__, "data", "optikron_case100")

function integer_rows(path)
    lines = readlines(path)
    return [parse.(Int, split(line, ',')) for line in lines[2:end] if !isempty(strip(line))]
end

edge_rows = integer_rows(joinpath(data_dir, "edges.csv"))
mapping_rows = integer_rows(joinpath(data_dir, "membership.csv"))
n = maximum(maximum(row) for row in edge_rows)

graph = SimpleGraph(n)
for (source, destination) in edge_rows
    add_edge!(graph, source, destination)
end
membership = [row[2] for row in sort(mapping_rows; by=first)]
data = contraction_data(graph, membership)

println("Opti-KRON fixture: $(nv(graph)) nodes / $(ne(graph)) edges")
println("Reduced: $(nv(data.reduced)) communities / $(ne(data.reduced)) edges")

figure = layeredplot(data; labels=("Full distribution graph", "Opti-KRON clusters"))
save(joinpath(@__DIR__, "optikron_case100_layered.png"), figure)

animation = animate_contraction(data; title="Opti-KRON graph contraction")
record_animation(animation, joinpath(@__DIR__, "optikron_case100.mp4"))
record_animation(animation, joinpath(@__DIR__, "optikron_case100.gif");
                 duration=4, framerate=20)
