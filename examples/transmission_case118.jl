using CairoMakie
using GraphReductionPlots

CairoMakie.activate!()

data_dir = joinpath(@__DIR__, "data", "transmission_case118")

function integer_rows(path)
    lines = readlines(path)
    return [parse.(Int, split(line, ',')) for line in lines[2:end] if !isempty(strip(line))]
end

mapping_rows = integer_rows(joinpath(data_dir, "bus_mapping.csv"))
line_rows = integer_rows(joinpath(data_dir, "line_status.csv"))

# The representative bus ID is a valid, non-contiguous community label.
membership = [row[2] for row in sort(mapping_rows; by=first)]

# This reduction merges buses without Kron reduction: a line inside a cluster
# disappears and every other line stays as it is. All 186 lines are kept,
# including parallel lines, so the reduced network keeps them too.
data = merge_data([row[2] for row in line_rows], [row[3] for row in line_rows], membership;
                  representatives=unique(membership))

# The `internal` column of the source run must match the membership.
Set(internal_edges(data)) == Set(findall(row -> row[4] == 1, line_rows)) ||
    error("internal lines in line_status.csv do not match bus_mapping.csv")

println("IEEE 118 case: $(data.vertex_count) buses / $(length(data.sources)) lines")
println("Reduced: $(length(data.labels)) super-nodes / $(length(external_edges(data))) lines " *
        "($(length(internal_edges(data))) internal lines removed)")
println("Equivalent lines after combining parallel lines: $(length(equivalent_edges(data)))")

figure = layeredplot(data; labels=("IEEE 118 network", "Merged buses"))
save(joinpath(@__DIR__, "transmission_case118_layered.png"), figure)

# Uncolored -> clusters colored -> buses merge. Parallel lines join into their
# equivalent line while the buses merge (default) or afterwards (:after_nodes).
animation = animate_contraction(data; title="IEEE 118 bus merging")
record_animation(animation, joinpath(@__DIR__, "transmission_case118.mp4"))
record_animation(animation, joinpath(@__DIR__, "transmission_case118.gif");
                 duration=6, framerate=20)
animation_after = animate_contraction(data; title="IEEE 118 bus merging",
                                      parallel_timing=:after_nodes)
record_animation(animation_after, joinpath(@__DIR__, "transmission_case118_after.gif");
                 duration=6, framerate=20)
