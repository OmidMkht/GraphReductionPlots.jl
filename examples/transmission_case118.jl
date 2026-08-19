using CairoMakie
using GraphReductionPlots
using Graphs

CairoMakie.activate!()

data_dir = joinpath(@__DIR__, "data", "transmission_case118")

function integer_rows(path)
    lines = readlines(path)
    return [parse.(Int, split(line, ',')) for line in lines[2:end] if !isempty(strip(line))]
end

mapping_rows = integer_rows(joinpath(data_dir, "bus_mapping.csv"))
line_rows = integer_rows(joinpath(data_dir, "line_status.csv"))

n = maximum(row[1] for row in mapping_rows)
graph = SimpleGraph(n)
for row in line_rows
    add_edge!(graph, row[2], row[3])
end

# The representative bus ID is a valid, non-contiguous community label.
membership = [row[2] for row in sort(mapping_rows; by=first)]
data = contraction_data(graph, membership)

println("IEEE 118 case: $(nv(graph)) buses / $(ne(graph)) lines")
println("Reduced: $(nv(data.reduced)) communities / $(ne(data.reduced)) lines")

figure = layeredplot(data; labels=("IEEE 118 network", "Reduced communities"))
save(joinpath(@__DIR__, "transmission_case118_layered.png"), figure)

animation = animate_contraction(data; title="IEEE 118 transmission-network contraction")
record_animation(animation, joinpath(@__DIR__, "transmission_case118.mp4"))
record_animation(animation, joinpath(@__DIR__, "transmission_case118.gif");
                 duration=4, framerate=20)
