using CairoMakie
using GraphReductionPlots
using Graphs

CairoMakie.activate!()

# A strong bus-merging reduction of the IEEE 118-bus case (118 -> 10 buses).
# Writes an MP4 and a GIF for each way of joining parallel lines:
#   case118_greedy_with_nodes.*   option 1: lines join while buses merge
#   case118_greedy_after_nodes.*  option 2: lines join after buses merge
# Length in seconds: VIDEO_SECONDS (default 30), including a 2-second hold at the end.

base_dir = joinpath(@__DIR__, "data", "transmission_case118")
greedy_dir = joinpath(@__DIR__, "data", "transmission_case118_greedy")

function csv_rows(path)
    lines = readlines(path)
    return [parse.(Int, split(line, ',')) for line in lines[2:end] if !isempty(strip(line))]
end

line_rows = csv_rows(joinpath(base_dir, "line_status.csv"))
sources = [row[2] for row in line_rows]
destinations = [row[3] for row in line_rows]
internal = [row[2] == 1 for row in csv_rows(joinpath(greedy_dir, "line_internal.csv"))]

# The clusters are the connected components of the internal lines.
# Each cluster is labeled by its smallest bus number.
bus_count = 118
internal_graph = SimpleGraph(bus_count)
for (a, b, inside) in zip(sources, destinations, internal)
    inside && add_edge!(internal_graph, a, b)
end
membership = zeros(Int, bus_count)
for component in connected_components(internal_graph)
    membership[component] .= minimum(component)
end

data = merge_data(sources, destinations, membership)
Set(internal_edges(data)) == Set(findall(internal)) ||
    error("the internal lines do not match the clusters")
println(data)

seconds = parse(Float64, get(ENV, "VIDEO_SECONDS", "30"))
final_hold = 2.0
for timing in (:with_nodes, :after_nodes)
    # An empty title gives a video without a header.
    animation = animate_contraction(data; title="", parallel_timing=timing)
    name = joinpath(@__DIR__, "case118_greedy_$(timing)")
    record_animation(animation, name * ".mp4";
                     duration=seconds - final_hold, final_hold=final_hold)
    # Half-size frames and 15 frames per second keep the GIF small.
    record_animation(animation, name * ".gif"; duration=seconds - final_hold,
                     final_hold=final_hold, framerate=15, px_per_unit=1)
    println("wrote ", name, ".mp4 and .gif")
end
