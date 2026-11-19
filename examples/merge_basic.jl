using CairoMakie
using GraphReductionPlots

CairoMakie.activate!()

# A 3 x 5 grid. Vertex (row, column) has number (column - 1) * 3 + row.
grid_rows, grid_columns = 3, 5
grid_vertex(row, column) = (column - 1) * grid_rows + row
sources, destinations = Int[], Int[]
for column in 1:grid_columns, row in 1:grid_rows
    row < grid_rows && (push!(sources, grid_vertex(row, column)); push!(destinations, grid_vertex(row + 1, column)))
    column < grid_columns && (push!(sources, grid_vertex(row, column)); push!(destinations, grid_vertex(row, column + 1)))
end
# A second, parallel edge between two vertices (like a double-circuit line).
push!(sources, grid_vertex(1, 3)); push!(destinations, grid_vertex(1, 4))

# Merge columns 1-2 into A, keep column 3 as B, merge columns 4-5 into C.
column_group = [:A, :A, :B, :C, :C]
membership = [column_group[column] for column in 1:grid_columns for row in 1:grid_rows]
x = Float64[column for column in 1:grid_columns for row in 1:grid_rows]
y = Float64[-row for column in 1:grid_columns for row in 1:grid_rows]

# Node merging without Kron reduction: the edges inside A, B and C disappear,
# every other edge stays. A quotient graph would keep only 2 edges here.
data = merge_data(sources, destinations, membership)
println(data)
println("Edges that disappear: ", length(internal_edges(data)))
println("Edges that stay: ", reduced_edges(data))
# The parallel edges between two super-nodes form one equivalent edge.
println("Equivalent edges: ", [(group.ends, length(group.edges)) for group in equivalent_edges(data)])

figure = layeredplot(data; coordinates=(x, y), labels=("Original", "Merged nodes"))
save(joinpath(@__DIR__, "merge_layered.png"), figure)

# The animation starts uncolored, colors the clusters, then merges.
# Option 1 (default): parallel edges join while the nodes merge.
animation = animate_contraction(data; coordinates=(x, y), title="Node merging")
record_animation(animation, joinpath(@__DIR__, "merge.mp4"))
record_animation(animation, joinpath(@__DIR__, "merge.gif"); duration=6, framerate=20)

# Option 2: parallel edges join after the nodes have merged.
animation_after = animate_contraction(data; coordinates=(x, y), title="Node merging",
                                      parallel_timing=:after_nodes)
record_animation(animation_after, joinpath(@__DIR__, "merge_after.gif"); duration=6, framerate=20)
