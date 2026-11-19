"""
    KronData

A Kron-based reduction. Each community keeps one vertex (its
representative, the super-node); every other vertex is eliminated. Kron
reduction replaces all original edges by new ones: two super-nodes are joined
when a path links them through eliminated vertices only. On a radial network
this can create cycles.

Radialization (optional) brings back a minimal set of eliminated vertices
(`restored`) so the reduced network is radial again. `radial_edges` is the
Kron network on the super-nodes `1:k` and the restored vertices `k+1:k+r`.

Build it with [`kron_data`](@ref).
"""
struct KronData{L}
    vertex_count::Int
    sources::Vector{Int}
    destinations::Vector{Int}
    membership::Vector{Int}
    labels::Vector{L}
    representatives::Vector{Int}
    reduced_edges::Vector{Tuple{Int,Int}}
    restored::Vector{Int}
    radial_edges::Vector{Tuple{Int,Int}}
end

"""
    kron_data(graph, membership; representatives=nothing, radialize=false, restored=nothing)
    kron_data(sources, destinations, membership; ...)

Describe a Kron-based reduction. `representatives` gives the kept vertex of
each community, in first-seen label order (default: the first member). The
Kron network is computed from the topology: two kept vertices are joined when
a path links them through eliminated vertices only.

With `radialize=true`, the vertices to bring back are found as in
Structure-preserving Opti-KRON: for every clique of three or more super-nodes
in the Kron network, the vertices of degree three or more on the shortest
paths between its members are restored. Or pass the vertices to restore with
`restored`.
"""
kron_data(graph::AbstractGraph, membership::AbstractVector; kwargs...) =
    kron_data([src(edge) for edge in edges(graph)], [dst(edge) for edge in edges(graph)],
              membership; vertex_count=nv(graph), kwargs...)

function kron_data(sources::AbstractVector{<:Integer}, destinations::AbstractVector{<:Integer},
                   membership::AbstractVector; representatives=nothing, radialize=false,
                   restored=nothing, vertex_count=length(membership))
    merged = _merge_data(vertex_count, sources, destinations, membership, representatives, nothing)
    kept = merged.representatives
    reduced = _kron_edges(vertex_count, merged.sources, merged.destinations, kept)
    radialize && restored !== nothing && throw(ArgumentError(
        "pass either radialize=true or restored, not both"))
    brought_back = restored !== nothing ? unique(Int.(collect(restored))) :
        radialize ? _radialization_nodes(vertex_count, merged.sources, merged.destinations, kept, reduced) :
        Int[]
    all(1 .<= brought_back .<= vertex_count) || throw(ArgumentError(
        "restored vertices must be valid vertex indices"))
    isempty(intersect(brought_back, kept)) || throw(ArgumentError(
        "a restored vertex cannot be a representative"))
    radial = isempty(brought_back) ? reduced :
        _kron_edges(vertex_count, merged.sources, merged.destinations, vcat(kept, brought_back))
    return KronData(merged.vertex_count, merged.sources, merged.destinations, merged.membership,
                    merged.labels, kept, reduced, brought_back, radial)
end

kron_data(data::KronData; kwargs...) = data

function Base.show(io::IO, data::KronData)
    print(io, "KronData: ", data.vertex_count, " vertices, ", length(data.sources), " edges -> ",
          length(data.representatives), " super-nodes, ", length(data.reduced_edges), " Kron edges")
    isempty(data.restored) || print(io, "; radialized: ", length(data.restored),
        " vertices restored, ", length(data.radial_edges), " edges")
end

function _neighbors(vertex_count, sources, destinations)
    neighbors = [Int[] for _ in 1:vertex_count]
    for (a, b) in zip(sources, destinations)
        push!(neighbors[a], b)
        push!(neighbors[b], a)
    end
    return neighbors
end

# Edges of the Kron-reduced network on `kept` (indices into `kept`). Two kept
# vertices are joined by an original edge or by a path whose inner vertices are
# all eliminated: the kept neighbors of each eliminated component form a clique.
function _kron_edges(vertex_count, sources, destinations, kept)
    position = zeros(Int, vertex_count)
    position[kept] .= eachindex(kept)
    neighbors = _neighbors(vertex_count, sources, destinations)
    pairs = Set{Tuple{Int,Int}}()
    for (a, b) in zip(sources, destinations)
        position[a] > 0 && position[b] > 0 && push!(pairs, minmax(position[a], position[b]))
    end
    visited = falses(vertex_count)
    for start in 1:vertex_count
        (position[start] > 0 || visited[start]) && continue
        boundary = Set{Int}()
        stack = [start]
        visited[start] = true
        while !isempty(stack)
            vertex = pop!(stack)
            for neighbor in neighbors[vertex]
                if position[neighbor] > 0
                    push!(boundary, position[neighbor])
                elseif !visited[neighbor]
                    visited[neighbor] = true
                    push!(stack, neighbor)
                end
            end
        end
        members = sort(collect(boundary))
        for i in eachindex(members), j in (i + 1):length(members)
            push!(pairs, (members[i], members[j]))
        end
    end
    return sort(collect(pairs))
end

# Vertices to restore so the Kron network becomes radial. For each clique of
# three or more super-nodes, collect the shortest paths between its members
# (in order) and keep the vertices of degree three or more on those paths.
function _radialization_nodes(vertex_count, sources, destinations, kept, reduced)
    graph = SimpleGraph(vertex_count)
    for (a, b) in zip(sources, destinations)
        add_edge!(graph, a, b)
    end
    kron_graph = SimpleGraph(length(kept))
    for (a, b) in reduced
        add_edge!(kron_graph, a, b)
    end
    critical = Int[]
    for clique in maximal_cliques(kron_graph)
        length(clique) >= 3 || continue
        members = kept[clique]
        path_vertices = Int[]
        for index in 1:(length(members) - 1)
            for edge in a_star(graph, members[index], members[index + 1])
                push!(path_vertices, src(edge), dst(edge))
            end
        end
        path_vertices = sort(unique(path_vertices))
        inside = falses(vertex_count)
        inside[path_vertices] .= true
        for vertex in path_vertices
            count(neighbor -> inside[neighbor], neighbors(graph, vertex)) >= 3 && push!(critical, vertex)
        end
    end
    return setdiff(sort(unique(critical)), kept)
end

"""
    animate_contraction(data::KronData; kwargs...) -> ContractionAnimation

Animate a Kron-based reduction in steps:

1. **Clusters.** The network starts uncolored, then the clusters take their
   colors (`color_share` of the time; `color_share=0` skips this step).
2. **Kron reduction.** Vertices move to their super-node. All original edges
   fade out and the Kron edges (`reduced_edge_color`) fade in.
3. **Radialization** (only when vertices are restored). The restored vertices
   move back out of their super-node. Kron edges that are not in the radial
   network fade out and the new radial edges fade in. This step uses the last
   `radial_share` of the time.

Super-nodes are drawn at their representative vertex by default
(`reduced_coordinates=:representatives`). An empty `title` hides the title.
"""
function animate_contraction(data::KronData;
                             coordinates=nothing, reduced_coordinates=:representatives,
                             layout=:stress, layout_iterations=500,
                             marker_scale=1.0, backgroundcolor=:white,
                             palette=nothing, edge_color=(:gray, 0.7),
                             internal_edge_color=:community, uncolored_color=:gray55,
                             reduced_edge_color=(:gray20, 0.9),
                             color_share=0.2, radial_share=0.3,
                             title="Kron reduction", figure_size=(900, 700),
                             default_duration=8.0, node_size=8.0,
                             cluster_node_size=15.0, restored_node_size=12.0,
                             edge_width=1.2, internal_edge_width=1.6,
                             reduced_edge_width=2.2)
    radialized = !isempty(data.restored)
    0 <= color_share < 1 || throw(ArgumentError("color_share must be in [0, 1)"))
    radialized && !(0 < radial_share < 1 - color_share) && throw(ArgumentError(
        "radial_share must be positive, and color_share + radial_share must be below 1"))
    _assert_nonwhite(edge_color, "edge_color")
    _assert_nonwhite(reduced_edge_color, "reduced_edge_color")

    x, y = coordinates === nothing ?
        _coordinates(_layout_graph(data), nothing; iterations=layout_iterations, layout=layout) :
        _given_coordinates(coordinates, data.vertex_count)
    k = length(data.labels)
    colors = _palette(k, backgroundcolor, palette)
    cx, cy = _reduced_coordinates(data, x, y, reduced_coordinates; layout=layout)
    target_x, target_y = cx[data.membership], cy[data.membership]
    restored = data.restored

    # Progress of each step at animation time t in [0, 1]. Kron edges fade in
    # during the last 60% of the reduction step.
    node_end = radialized ? 1 - radial_share : 1.0
    node_fraction(t) = (t - color_share) / (node_end - color_share)
    color_at(t) = color_share > 0 ? _smoothstep(t / color_share) : 1.0
    node_at(t) = _smoothstep(node_fraction(t))
    kron_at(t) = _smoothstep((node_fraction(t) - 0.4) / 0.6)
    radial_at(t) = radialized ? _smoothstep((t - node_end) / radial_share) : 0.0
    function positions_at(t)
        q, r = node_at(t), radial_at(t)
        xs = (1 - q) .* x .+ q .* target_x
        ys = (1 - q) .* y .+ q .* target_y
        xs[restored] .+= r .* (x[restored] .- target_x[restored])
        ys[restored] .+= r .* (y[restored] .- target_y[restored])
        return xs, ys
    end
    # Super-nodes, then restored vertices: the vertices of the radial network.
    function radial_positions(t)
        xs, ys = positions_at(t)
        return vcat(cx, xs[restored]), vcat(cy, ys[restored])
    end
    segment_points(pairs, xs, ys) =
        [point for (a, b) in pairs for point in (Point2f(xs[a], ys[a]), Point2f(xs[b], ys[b]))]

    time = Observable(0.0)
    fig = Figure(size=figure_size, backgroundcolor=backgroundcolor)
    ax = Axis(fig[1, 1]; title=title, titlevisible=!isempty(title), aspect=DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    edge_rgba = _with_alpha(edge_color, 1.0)

    # Original edges: internal ones take their community color first; all fade out.
    original = collect(zip(data.sources, data.destinations))
    internal = [data.membership[a] == data.membership[b] for (a, b) in original]
    colored = [inside ? (internal_edge_color === :community ?
                         _with_alpha(colors[data.membership[a]], 0.85) :
                         _with_alpha(internal_edge_color, 1.0)) : edge_rgba
               for ((a, _), inside) in zip(original, internal)]
    widths = [inside ? internal_edge_width : edge_width for inside in internal]
    if !isempty(original)
        linesegments!(ax, lift(t -> segment_points(original, positions_at(t)...), time);
                      color=lift(t -> repeat(_with_alpha.(_blend.(Ref(edge_rgba), colored, color_at(t)),
                                                          1 - node_at(t)), inner=2), time),
                      linewidth=lift(t -> repeat(edge_width .+ color_at(t) .* (widths .- edge_width),
                                                 inner=2), time))
    end

    # Kron edges. Those that are also radial edges stay; the others fade out
    # during radialization, when the new radial edges fade in.
    radial_set = Set(data.radial_edges)
    staying = filter(edge -> edge in radial_set, data.reduced_edges)
    leaving = filter(edge -> !(edge in radial_set), data.reduced_edges)
    arriving = filter(edge -> !(edge in Set(data.reduced_edges)), data.radial_edges)
    for (pairs, alpha_at) in ((staying, kron_at), (leaving, t -> kron_at(t) * (1 - radial_at(t))))
        isempty(pairs) && continue
        linesegments!(ax, segment_points(pairs, cx, cy);
                      color=lift(t -> _with_alpha(reduced_edge_color, alpha_at(t)), time),
                      linewidth=reduced_edge_width)
    end
    if !isempty(arriving)
        linesegments!(ax, lift(t -> segment_points(arriving, radial_positions(t)...), time);
                      color=lift(t -> _with_alpha(reduced_edge_color, radial_at(t)), time),
                      linewidth=reduced_edge_width)
    end

    node_colors = [_with_alpha(colors[community], 1.0) for community in data.membership]
    neutral = _with_alpha(uncolored_color, 1.0)
    scatter!(ax, lift(t -> Point2f.(positions_at(t)...), time);
             color=lift(t -> _blend.(Ref(neutral), node_colors, color_at(t)), time),
             markersize=lift(t -> (node_size - 3node_at(t)) * marker_scale, time))
    scatter!(ax, cx, cy; color=lift(t -> [_with_alpha(color, node_at(t)) for color in colors], time),
             markersize=lift(t -> cluster_node_size * node_at(t) * marker_scale, time))
    if radialized
        restored_colors = colors[data.membership[restored]]
        scatter!(ax, lift(t -> Point2f.(positions_at(t)[1][restored], positions_at(t)[2][restored]), time);
                 color=lift(t -> [_with_alpha(color, radial_at(t)) for color in restored_colors], time),
                 markersize=lift(t -> restored_node_size * radial_at(t) * marker_scale, time))
    end
    xpadding = max((maximum(x) - minimum(x)) * 0.05, 1.0e-6)
    ypadding = max((maximum(y) - minimum(y)) * 0.05, 1.0e-6)
    limits!(ax, minimum(x) - xpadding, maximum(x) + xpadding,
            minimum(y) - ypadding, maximum(y) + ypadding)
    return ContractionAnimation(fig, time, Float64(default_duration))
end
