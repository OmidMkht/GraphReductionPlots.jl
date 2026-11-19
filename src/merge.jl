"""
    MergeData

A reduction that merges vertices without Kron reduction. Each community
becomes one super-node.

- An *internal* edge has both ends in the same community. It disappears.
- An *external* edge has its ends in two communities. It stays as it is and
  joins the super-nodes of its two ends. No new edges are created.

Parallel edges are kept, so the reduced network can have several edges
between the same two super-nodes. Build it with [`merge_data`](@ref).

Fields: `vertex_count`, `sources` and `destinations` (the two ends of every
original edge), `membership` (dense community of each vertex), `labels`
(community labels in first-seen order), `representatives` (one vertex per
community), and `edge_weights` (one per original edge).
"""
struct MergeData{L}
    vertex_count::Int
    sources::Vector{Int}
    destinations::Vector{Int}
    membership::Vector{Int}
    labels::Vector{L}
    representatives::Vector{Int}
    edge_weights::Vector{Float64}
end

"""
    merge_data(graph, membership; representatives=nothing, edge_weights=nothing)
    merge_data(sources, destinations, membership; ...)
    merge_data(edge_list, membership; ...)
    merge_data(matrix, membership; representation=:adjacency, ...)

Describe a node-merging reduction (no Kron reduction): edges inside a
community disappear and every other edge is kept unchanged.

The original network can be:

- a `Graphs.jl` graph;
- two vectors `sources` and `destinations` (edge `e` joins `sources[e]` and
  `destinations[e]`);
- a vector of `(source, destination)` pairs;
- an adjacency or incidence matrix (`representation=:adjacency` or
  `:incidence`).

A simple graph and an adjacency matrix cannot hold parallel edges. Use edge
vectors, pairs, or an incidence matrix (one column per edge) to keep them.
For vectors and pairs, the number of vertices is `length(membership)`.

`representatives` gives one vertex per community, in first-seen label order.
The default is the first member. Plot with
`reduced_coordinates=:representatives` to draw each super-node at its
representative vertex.
"""
merge_data(graph::AbstractGraph, membership::AbstractVector; representatives=nothing,
           edge_weights=nothing) =
    _merge_data(nv(graph), [src(edge) for edge in edges(graph)],
                [dst(edge) for edge in edges(graph)], membership, representatives, edge_weights)

merge_data(sources::AbstractVector{<:Integer}, destinations::AbstractVector{<:Integer},
           membership::AbstractVector; representatives=nothing, edge_weights=nothing) =
    _merge_data(length(membership), sources, destinations, membership, representatives,
                edge_weights)

function merge_data(edge_list::AbstractVector, membership::AbstractVector;
                    representatives=nothing, edge_weights=nothing)
    all(edge -> length(edge) == 2, edge_list) || throw(ArgumentError(
        "every edge must be a (source, destination) pair"))
    return _merge_data(length(membership), [Int(edge[1]) for edge in edge_list],
                       [Int(edge[2]) for edge in edge_list], membership,
                       representatives, edge_weights)
end

function merge_data(matrix::AbstractMatrix, membership::AbstractVector;
                    representation=:adjacency, representatives=nothing, edge_weights=nothing)
    if representation === :adjacency
        size(matrix, 1) == size(matrix, 2) || throw(DimensionMismatch(
            "adjacency matrix must be square"))
        matrix == matrix' || throw(ArgumentError("the adjacency matrix must be symmetric"))
        pairs = [(i, j) for j in axes(matrix, 2) for i in axes(matrix, 1)
                 if i < j && !iszero(matrix[i, j])]
        weights = edge_weights === nothing ? [Float64(matrix[i, j]) for (i, j) in pairs] :
            edge_weights
    elseif representation === :incidence
        pairs = map(axes(matrix, 2)) do column
            ends = findall(!iszero, view(matrix, :, column))
            length(ends) == 2 || throw(ArgumentError(
                "incidence column $column must contain exactly two nonzero entries"))
            (ends[1], ends[2])
        end
        weights = edge_weights
    else
        throw(ArgumentError("representation must be :adjacency or :incidence"))
    end
    return _merge_data(size(matrix, 1), first.(pairs), last.(pairs), membership,
                       representatives, weights)
end

merge_data(data::MergeData; kwargs...) = data

function _merge_data(vertex_count, sources, destinations, membership, representatives,
                     edge_weights)
    length(membership) == vertex_count || throw(DimensionMismatch(
        "membership has $(length(membership)) entries for a $vertex_count-vertex graph"))
    isempty(membership) && throw(ArgumentError("membership cannot be empty"))
    length(sources) == length(destinations) || throw(DimensionMismatch(
        "sources and destinations must have the same length"))
    for (edge, (a, b)) in enumerate(zip(sources, destinations))
        1 <= a <= vertex_count && 1 <= b <= vertex_count || throw(ArgumentError(
            "edge $edge joins a vertex outside 1:$vertex_count"))
        a == b && throw(ArgumentError("edge $edge is a self-loop"))
    end
    labels, dense = _dense_membership(membership)
    reps = _representatives(dense, length(labels), representatives)
    weights = _edge_weights(length(sources), edge_weights)
    return MergeData(Int(vertex_count), Int.(sources), Int.(destinations), dense, labels,
                     reps, weights)
end

_is_internal(data::MergeData, edge) =
    data.membership[data.sources[edge]] == data.membership[data.destinations[edge]]

"""
    internal_edges(data::MergeData) -> Vector{Int}

Indices of the edges that disappear: both ends are in the same community.
"""
internal_edges(data::MergeData) = [edge for edge in eachindex(data.sources) if _is_internal(data, edge)]

"""
    external_edges(data::MergeData) -> Vector{Int}

Indices of the edges that stay in the reduced network.
"""
external_edges(data::MergeData) = [edge for edge in eachindex(data.sources) if !_is_internal(data, edge)]

"""
    reduced_edges(data::MergeData) -> Vector{Tuple{Int,Int}}

The two super-nodes of every external edge, in the order of
`external_edges(data)`. Parallel edges appear more than once.
"""
reduced_edges(data::MergeData) =
    [(data.membership[data.sources[edge]], data.membership[data.destinations[edge]])
     for edge in external_edges(data)]

"""
    equivalent_edges(data::MergeData; combine=:sum)

The reduced network after parallel edges are combined: one equivalent edge
for each pair of super-nodes joined by at least one external edge. Each entry
is a named tuple `(ends, edges, weight)`: the two super-nodes (smaller first),
the original edges it replaces, and their combined weight.

`combine` sets how the weights of parallel edges are combined:

- `:sum` (default): for admittance, susceptance, or rating;
- `:reciprocal`: `1 / sum(1 ./ weights)`, for reactance or impedance;
- `:max`, `:mean`, `:count`, or a function that takes the weight vector.
"""
equivalent_edges(data::MergeData; combine=:sum) =
    _equivalent_groups(data, external_edges(data), combine)

function _equivalent_groups(data, external, combine)
    _check_combine(combine)
    position = Dict{Tuple{Int,Int},Int}()
    ends = Tuple{Int,Int}[]
    members = Vector{Int}[]
    for edge in external
        key = minmax(data.membership[data.sources[edge]], data.membership[data.destinations[edge]])
        index = get(position, key, 0)
        if index == 0
            push!(ends, key)
            push!(members, Int[])
            index = position[key] = length(ends)
        end
        push!(members[index], edge)
    end
    return [(ends=ends[i], edges=members[i],
             weight=_combine_weights(data.edge_weights[members[i]], combine))
            for i in eachindex(ends)]
end

_check_combine(combine) =
    combine isa Function || combine in (:sum, :reciprocal, :max, :mean, :count) ||
    throw(ArgumentError("combine must be :sum, :reciprocal, :max, :mean, :count, or a function"))

function _combine_weights(values, combine)
    combine isa Function && return Float64(combine(values))
    combine === :sum && return sum(values)
    combine === :reciprocal && return 1 / sum(1 ./ values)
    combine === :max && return maximum(values)
    combine === :mean && return sum(values) / length(values)
    return Float64(length(values))
end

function Base.show(io::IO, data::MergeData)
    external = external_edges(data)
    pairs = length(Set(minmax(data.membership[data.sources[edge]],
                              data.membership[data.destinations[edge]]) for edge in external))
    print(io, "MergeData: ", data.vertex_count, " vertices, ", length(data.sources),
          " edges -> ", length(data.labels), " super-nodes, ", length(external),
          " edges (", pairs, " after combining parallel edges); ",
          length(data.sources) - length(external), " internal edges removed")
end

# The original network (MergeData or KronData) as a simple graph. Used only for automatic layouts.
function _layout_graph(data)
    graph = SimpleGraph(data.vertex_count)
    for (a, b) in zip(data.sources, data.destinations)
        add_edge!(graph, a, b)
    end
    return graph
end

_automatic_connectors(data::MergeData) =
    _automatic_connectors(data.vertex_count, length(data.labels), length(data.sources))

function _limited_indices(count, max_edges)
    limit = max_edges === :auto ? 4000 : Int(max_edges)
    limit > 0 || throw(ArgumentError("max_edges must be positive"))
    return collect(1:min(count, limit))
end

# Curvature of each selected edge. Edges that join the same two points fan out
# as arcs, so parallel edges do not lie on top of each other. A single edge
# stays straight. The sign is for drawing the edge from ends_a[e] to ends_b[e].
function _fan_curvatures(ends_a, ends_b, selected, spread)
    groups = Dict{Tuple{Int,Int},Vector{Int}}()
    for edge in selected
        push!(get!(groups, minmax(ends_a[edge], ends_b[edge]), Int[]), edge)
    end
    curvature = zeros(Float64, length(ends_a))
    for ((low, _), members) in groups
        length(members) == 1 && continue
        half = min(spread * (length(members) - 1) / 2, 0.5)
        for (value, edge) in zip(range(-half, half; length=length(members)), members)
            curvature[edge] = ends_a[edge] == low ? value : -value
        end
    end
    return curvature
end

# Append one edge as a quadratic Bezier arc, as pairs of points for
# `linesegments!`. Curvature 0 gives the straight edge. `point` builds a 2D or
# 3D point from (x, y).
function _push_arc!(points, x1, y1, x2, y2, curvature, samples, point)
    control_x = (x1 + x2) / 2 - curvature * (y2 - y1)
    control_y = (y1 + y2) / 2 + curvature * (x2 - x1)
    previous = point(x1, y1)
    for step in 1:(samples - 1)
        t = step / (samples - 1)
        s = 1 - t
        current = point(s^2 * x1 + 2s * t * control_x + t^2 * x2,
                        s^2 * y1 + 2s * t * control_y + t^2 * y2)
        push!(points, previous, current)
        previous = current
    end
    return points
end

_arc_samples(curvatures, arc_samples) = [iszero(c) ? 2 : arc_samples for c in curvatures]

# Color (with alpha) of each edge that disappears: its community color, or one color.
function _internal_colors(data, edges, colors, internal_edge_color)
    if internal_edge_color === :community
        return [_with_alpha(colors[data.membership[data.sources[edge]]], 0.85) for edge in edges]
    end
    _assert_nonwhite(internal_edge_color, "internal_edge_color")
    return fill(_with_alpha(internal_edge_color, 1.0), length(edges))
end

# Mix of two RGBA colors: `a` at q = 0, `b` at q = 1.
_blend(a, b, q) = RGBAf(a.r + q * (b.r - a.r), a.g + q * (b.g - a.g),
                        a.b + q * (b.b - a.b), a.alpha + q * (b.alpha - a.alpha))

# Repeat a per-edge value for each point that `_push_arc!` adds for that edge.
_per_point(values, edges, samples) =
    reduce(vcat, [fill(values[index], 2 * (samples[edge] - 1)) for (index, edge) in enumerate(edges)];
           init=eltype(values)[])

_check_parallel_edges(parallel_edges) = parallel_edges in (:merge, :keep) ||
    throw(ArgumentError("parallel_edges must be :merge or :keep"))

# Width of every original edge and of every equivalent edge. With weights, one
# scale covers both, so widths can be compared. Without weights, an
# equivalent edge grows with the square root of the number of edges it replaces.
function _line_widths(data, groups, edge_width, edge_width_by, weight_scale)
    edge_width_by in (nothing, :weight) || throw(ArgumentError(
        "edge_width_by must be nothing or :weight"))
    edge_count = length(data.sources)
    if edge_width_by === :weight
        equivalent_weights = groups === nothing ? Float64[] : [group.weight for group in groups]
        scaled = _scaled_widths(vcat(data.edge_weights, equivalent_weights), edge_width, weight_scale)
        return scaled[1:edge_count], scaled[(edge_count + 1):end]
    end
    equivalent = groups === nothing ? Float64[] :
        [edge_width * min(sqrt(length(group.edges)), 3.0) for group in groups]
    return fill(Float64(edge_width), edge_count), equivalent
end

"""
    layeredplot(data::MergeData; kwargs...)

Two-layer figure of a node-merging reduction. The top layer is the original
network. Its internal edges (the ones that disappear) are drawn in their
community color. The bottom layer has one super-node per community.

With `parallel_edges=:merge` (default), the bottom layer shows the equivalent
edges: parallel edges between two super-nodes are combined into one thicker,
darker line (`equivalent_edge_color`). With `parallel_edges=:keep`, every
external edge is drawn and parallel edges fan out as arcs.

Keywords as for the other `layeredplot` methods, plus `internal_edge_color`
(`:community` or one color), `internal_edge_width`, `parallel_weight` (how
weights combine, see [`equivalent_edges`](@ref)), `parallel_spread` (bend
between neighboring parallel edges, as a fraction of their length), and
`arc_samples` (points per curved edge). `reduced_coordinates=:representatives`
puts each super-node on its representative vertex.
"""
function layeredplot(data::MergeData;
                     coordinates=nothing, reduced_coordinates=nothing,
                     layout=:stress, layout_iterations=500,
                     layer_gap=:auto, marker_scale=1.0,
                     backgroundcolor=:white, palette=nothing,
                     edge_color=(:gray, 0.7), internal_edge_color=:community,
                     parallel_edges=:merge, parallel_weight=:sum,
                     equivalent_edge_color=(:gray20, 0.9),
                     connector_alpha=0.5,
                     labels=("Original", "Merged"), show_labels=true,
                     show_connectors=:auto, show_planes=true,
                     plane_color=(:gray, 0.07), figure_size=(1000, 700),
                     azimuth=:auto, elevation=:auto,
                     node_size=7.0, cluster_node_size=14.0,
                     edge_width=1.2, internal_edge_width=1.6,
                     connector_width=0.7, max_edges=:auto,
                     max_connectors=:auto, edge_width_by=nothing,
                     weight_scale=:sqrt, parallel_spread=0.25, arc_samples=24)
    _check_parallel_edges(parallel_edges)
    x, y = coordinates === nothing ?
        _coordinates(_layout_graph(data), nothing; iterations=layout_iterations, layout=layout) :
        _given_coordinates(coordinates, data.vertex_count)
    k = length(data.labels)
    colors = _palette(k, backgroundcolor, palette)
    cx, cy = _reduced_coordinates(data, x, y, reduced_coordinates; layout=layout)
    resolved_connectors = show_connectors === :auto ? _automatic_connectors(data) : show_connectors

    _assert_nonwhite(edge_color, "edge_color")
    _assert_nonwhite(equivalent_edge_color, "equivalent_edge_color")
    _assert_nonwhite(plane_color, "plane_color")

    fig, ax, z_levels = _layer_axis(x, y, 2; layer_gap=layer_gap, azimuth=azimuth,
        elevation=elevation, backgroundcolor=backgroundcolor, figure_size=figure_size,
        show_planes=show_planes, plane_color=plane_color)
    ztop, zbottom = z_levels

    selected = _limited_indices(length(data.sources), max_edges)
    internal = filter(edge -> _is_internal(data, edge), selected)
    external = filter(edge -> !_is_internal(data, edge), selected)
    groups = parallel_edges === :merge ? _equivalent_groups(data, external, parallel_weight) : nothing
    widths, equivalent_widths = _line_widths(data, groups, edge_width, edge_width_by, weight_scale)
    internal_widths = edge_width_by === :weight ?
        widths .* (internal_edge_width / edge_width) : fill(Float64(internal_edge_width), length(widths))
    edge_rgba = _with_alpha(edge_color, 1.0)

    # Top layer: the original network, with every parallel edge fanned out.
    top_curvature = _fan_curvatures(data.sources, data.destinations, selected, parallel_spread)
    top_samples = _arc_samples(top_curvature, arc_samples)
    top_point = (px, py) -> Point3f(px, py, ztop)
    for (group, color_of_edge, width_of_edge) in (
            (internal, _internal_colors(data, internal, colors, internal_edge_color), internal_widths[internal]),
            (external, fill(edge_rgba, length(external)), widths[external]))
        isempty(group) && continue
        points = Point3f[]
        for edge in group
            a, b = data.sources[edge], data.destinations[edge]
            _push_arc!(points, x[a], y[a], x[b], y[b], top_curvature[edge], top_samples[edge], top_point)
        end
        linesegments!(ax, points; color=_per_point(color_of_edge, group, top_samples),
                      linewidth=_per_point(width_of_edge, group, top_samples))
    end
    scatter!(ax, x, y, fill(ztop, data.vertex_count);
             color=colors[data.membership], markersize=node_size * marker_scale)

    # Bottom layer: the external edges between super-nodes.
    if groups === nothing
        reduced_a = data.membership[data.sources]
        reduced_b = data.membership[data.destinations]
        bottom_curvature = _fan_curvatures(reduced_a, reduced_b, external, parallel_spread)
        bottom_samples = _arc_samples(bottom_curvature, arc_samples)
        bottom_point = (px, py) -> Point3f(px, py, zbottom)
        if !isempty(external)
            points = Point3f[]
            for edge in external
                a, b = reduced_a[edge], reduced_b[edge]
                _push_arc!(points, cx[a], cy[a], cx[b], cy[b], bottom_curvature[edge],
                           bottom_samples[edge], bottom_point)
            end
            linesegments!(ax, points; color=edge_rgba,
                          linewidth=_per_point(widths[external], external, bottom_samples))
        end
    else
        # A single edge is drawn as it is; parallel edges as their equivalent edge.
        single = findall(group -> length(group.edges) == 1, groups)
        combined = findall(group -> length(group.edges) > 1, groups)
        for (indices, color) in ((single, edge_rgba), (combined, _with_alpha(equivalent_edge_color, 1.0)))
            isempty(indices) && continue
            points = Point3f[]
            for (a, b) in (groups[index].ends for index in indices)
                push!(points, Point3f(cx[a], cy[a], zbottom), Point3f(cx[b], cy[b], zbottom))
            end
            linesegments!(ax, points; color=color, linewidth=repeat(equivalent_widths[indices], inner=2))
        end
    end
    scatter!(ax, cx, cy, fill(zbottom, k); color=colors, markersize=cluster_node_size * marker_scale)

    if resolved_connectors
        _draw_connectors!(ax, _limited_vertices(data.vertex_count, max_connectors), data.membership,
                          x, y, cx, cy, ztop, zbottom, colors, connector_alpha, connector_width)
    end
    show_labels && _draw_layer_labels!(ax, x, y, z_levels, labels)
    return fig
end

"""
    animate_contraction(data::MergeData; kwargs...) -> ContractionAnimation

Animate a node-merging reduction in steps:

1. **Clusters.** The network starts uncolored (`uncolored_color` nodes, all
   edges in `edge_color`). Then the clusters take their colors. This step
   uses the first `color_share` of the animation; `color_share=0` skips it.
2. **Merging nodes.** Vertices move to their super-node. Internal edges
   shrink with their community and fade out. External edges stay visible and
   follow their two ends. No new edge appears.
3. **Equivalent edges.** Parallel edges between two super-nodes are replaced
   by one equivalent edge (thicker, `equivalent_edge_color`).

`parallel_timing` sets when step 3 happens:

- `:with_nodes` (default): during step 2. The parallel edges come together
  as their ends merge and turn into the equivalent edge.
- `:after_nodes`: after step 2. The parallel edges first fan out between the
  merged super-nodes, then join into the equivalent edge. This step uses the
  last `line_share` of the animation.

`parallel_edges=:keep` skips step 3: parallel edges stay as separate arcs.
Other keywords as for `layeredplot(data::MergeData)`, plus `title`,
`default_duration`, and `figure_size`.
"""
function animate_contraction(data::MergeData;
                             coordinates=nothing, reduced_coordinates=nothing,
                             layout=:stress, layout_iterations=500,
                             marker_scale=1.0, backgroundcolor=:white,
                             palette=nothing, edge_color=(:gray, 0.7),
                             internal_edge_color=:community,
                             uncolored_color=:gray55, color_share=0.2,
                             parallel_edges=:merge, parallel_timing=:with_nodes,
                             line_share=0.3, parallel_weight=:sum,
                             equivalent_edge_color=(:gray20, 0.9),
                             title="Node merging", figure_size=(900, 700),
                             default_duration=8.0, node_size=8.0,
                             cluster_node_size=15.0, edge_width=1.2,
                             internal_edge_width=1.6, max_edges=:auto,
                             edge_width_by=nothing, weight_scale=:sqrt,
                             parallel_spread=0.25, arc_samples=24)
    _check_parallel_edges(parallel_edges)
    parallel_timing in (:with_nodes, :after_nodes) || throw(ArgumentError(
        "parallel_timing must be :with_nodes or :after_nodes"))
    0 <= color_share < 1 || throw(ArgumentError("color_share must be in [0, 1)"))
    merge_lines = parallel_edges === :merge
    lines_after = merge_lines && parallel_timing === :after_nodes
    lines_after && !(0 < line_share < 1 - color_share) && throw(ArgumentError(
        "line_share must be positive, and color_share + line_share must be below 1"))

    x, y = coordinates === nothing ?
        _coordinates(_layout_graph(data), nothing; iterations=layout_iterations, layout=layout) :
        _given_coordinates(coordinates, data.vertex_count)
    k = length(data.labels)
    colors = _palette(k, backgroundcolor, palette)
    cx, cy = _reduced_coordinates(data, x, y, reduced_coordinates; layout=layout)
    target_x, target_y = cx[data.membership], cy[data.membership]
    _assert_nonwhite(edge_color, "edge_color")
    _assert_nonwhite(equivalent_edge_color, "equivalent_edge_color")

    selected = _limited_indices(length(data.sources), max_edges)
    internal = filter(edge -> _is_internal(data, edge), selected)
    external = filter(edge -> !_is_internal(data, edge), selected)
    groups = merge_lines ? _equivalent_groups(data, external, parallel_weight) : nothing
    widths, equivalent_widths = _line_widths(data, groups, edge_width, edge_width_by, weight_scale)
    internal_widths = edge_width_by === :weight ?
        widths .* (internal_edge_width / edge_width) : fill(Float64(internal_edge_width), length(widths))
    combined = groups === nothing ? Int[] : findall(group -> length(group.edges) > 1, groups)
    replaced = Set(edge for index in combined for edge in groups[index].edges)
    steady = filter(edge -> !(edge in replaced), external)  # visible to the end
    fading = filter(edge -> edge in replaced, external)     # replaced by an equivalent edge

    # Bend of each edge: its fan in the original network at the start, then its
    # fan between the super-nodes once the nodes have merged. Parallel edges
    # that are combined during the node step straighten instead. Internal
    # edges keep their original bend while they vanish.
    start_curvature = _fan_curvatures(data.sources, data.destinations, selected, parallel_spread)
    fan_curvature = _fan_curvatures(data.membership[data.sources],
                                    data.membership[data.destinations], external, parallel_spread)
    middle_curvature = copy(start_curvature)
    middle_curvature[external] .= merge_lines && !lines_after ? 0.0 : fan_curvature[external]
    samples = [iszero(start_curvature[edge]) && iszero(middle_curvature[edge]) ? 2 : arc_samples
               for edge in eachindex(data.sources)]

    # Progress of each step at animation time t in [0, 1]. With :with_nodes,
    # a bundle first closes up as its ends move together; it turns into the
    # equivalent edge during the last 60% of the node step.
    node_end = lines_after ? 1 - line_share : 1.0
    node_fraction(t) = (t - color_share) / (node_end - color_share)
    color_at(t) = color_share > 0 ? _smoothstep(t / color_share) : 1.0
    node_at(t) = _smoothstep(node_fraction(t))
    line_at(t) = !merge_lines ? 0.0 : lines_after ? _smoothstep((t - node_end) / line_share) :
        _smoothstep((node_fraction(t) - 0.4) / 0.6)
    positions_at(q) = ((1 - q) .* x .+ q .* target_x, (1 - q) .* y .+ q .* target_y)

    function frame_points(group, t; line_progress=line_at(t))
        q = node_at(t)
        xs, ys = positions_at(q)
        points = Point2f[]
        for edge in group
            a, b = data.sources[edge], data.destinations[edge]
            curvature = (1 - line_progress) * ((1 - q) * start_curvature[edge] + q * middle_curvature[edge])
            _push_arc!(points, xs[a], ys[a], xs[b], ys[b], curvature, samples[edge], Point2f)
        end
        return points
    end

    time = Observable(0.0)
    fig = Figure(size=figure_size, backgroundcolor=backgroundcolor)
    ax = Axis(fig[1, 1]; title=title, titlevisible=!isempty(title), aspect=DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    edge_rgba = _with_alpha(edge_color, 1.0)

    if !isempty(internal)
        # Gray like the other edges at first, then in their community color, then gone.
        colored = _per_point(_internal_colors(data, internal, colors, internal_edge_color), internal, samples)
        start_widths = _per_point(widths[internal], internal, samples)
        end_widths = _per_point(internal_widths[internal], internal, samples)
        linesegments!(ax, lift(t -> frame_points(internal, t; line_progress=0.0), time);
                      color=lift(t -> _with_alpha.(_blend.(Ref(edge_rgba), colored, color_at(t)),
                                                   1 - node_at(t)), time),
                      linewidth=lift(t -> start_widths .+ color_at(t) .* (end_widths .- start_widths), time))
    end
    if !isempty(steady)
        linesegments!(ax, lift(t -> frame_points(steady, t), time); color=edge_rgba,
                      linewidth=_per_point(widths[steady], steady, samples))
    end
    if !isempty(fading)
        linesegments!(ax, lift(t -> frame_points(fading, t), time);
                      color=lift(t -> _with_alpha(edge_color, 1 - line_at(t)), time),
                      linewidth=_per_point(widths[fading], fading, samples))
    end
    if !isempty(combined)
        # Each equivalent edge joins the mean positions of its parallel edges'
        # ends, so it grows out of the bundle and ends between the super-nodes.
        near_ends = [[data.membership[data.sources[edge]] == groups[index].ends[1] ?
                      data.sources[edge] : data.destinations[edge] for edge in groups[index].edges]
                     for index in combined]
        far_ends = [[data.membership[data.sources[edge]] == groups[index].ends[1] ?
                     data.destinations[edge] : data.sources[edge] for edge in groups[index].edges]
                    for index in combined]
        mean_point(xs, ys, vertices) = Point2f(sum(xs[vertices]) / length(vertices),
                                               sum(ys[vertices]) / length(vertices))
        function equivalent_points(t)
            xs, ys = positions_at(node_at(t))
            points = Point2f[]
            for (near, far) in zip(near_ends, far_ends)
                push!(points, mean_point(xs, ys, near), mean_point(xs, ys, far))
            end
            return points
        end
        linesegments!(ax, lift(equivalent_points, time);
                      color=lift(t -> _with_alpha(equivalent_edge_color, line_at(t)), time),
                      linewidth=repeat(equivalent_widths[combined], inner=2))
    end

    node_colors = [_with_alpha(colors[community], 1.0) for community in data.membership]
    neutral = _with_alpha(uncolored_color, 1.0)
    scatter!(ax, lift(t -> Point2f.(positions_at(node_at(t))...), time);
             color=lift(t -> _blend.(Ref(neutral), node_colors, color_at(t)), time),
             markersize=lift(t -> (node_size - 3node_at(t)) * marker_scale, time))
    scatter!(ax, cx, cy; color=lift(t -> [_with_alpha(color, node_at(t)) for color in colors], time),
             markersize=lift(t -> cluster_node_size * node_at(t) * marker_scale, time))
    xpadding = max((maximum(x) - minimum(x)) * 0.05, 1.0e-6)
    ypadding = max((maximum(y) - minimum(y)) * 0.05, 1.0e-6)
    limits!(ax, minimum(x) - xpadding, maximum(x) + xpadding,
            minimum(y) - ypadding, maximum(y) + ypadding)
    return ContractionAnimation(fig, time, Float64(default_duration))
end
