function _coordinates(graph, ::Nothing; iterations=500, layout=:stress)
    points = if layout === :stress
        NetworkLayout.stress(graph; iterations=iterations)
    elseif layout === :spring
        NetworkLayout.spring(graph; iterations=iterations)
    elseif layout === :spectral
        NetworkLayout.spectral(graph)
    elseif layout === :sfdp
        NetworkLayout.sfdp(graph)
    elseif layout isa Function
        layout(graph)
    else
        throw(ArgumentError("layout must be :stress, :spring, :spectral, :sfdp, or a function"))
    end
    return Float64[first(point) for point in points], Float64[last(point) for point in points]
end

_coordinates(graph, coordinates::Union{Tuple,AbstractVector}; iterations=500, layout=:stress) =
    _given_coordinates(coordinates, nv(graph))

function _given_coordinates(coordinates::Tuple, n)
    length(coordinates) == 2 || throw(ArgumentError("coordinates must be (x, y)"))
    x, y = Float64.(coordinates[1]), Float64.(coordinates[2])
    length(x) == n == length(y) || throw(DimensionMismatch("coordinates must match graph size"))
    return x, y
end

function _given_coordinates(coordinates::AbstractVector, n)
    length(coordinates) == n || throw(DimensionMismatch("coordinates must match graph size"))
    return Float64[p[1] for p in coordinates], Float64[p[2] for p in coordinates]
end

# Position of each reduced vertex: given coordinates, the representative
# vertex's own position, or (default) the centroid of its community.
function _reduced_coordinates(data, x, y, coordinates; layout=:stress)
    k = length(data.representatives)
    coordinates === :representatives && return x[data.representatives], y[data.representatives]
    coordinates isa Symbol && throw(ArgumentError(
        "reduced_coordinates must be nothing, :representatives, or coordinates"))
    coordinates !== nothing && return _given_coordinates(coordinates, k)
    return ([sum(x[data.membership .== i]) / count(==(i), data.membership) for i in 1:k],
            [sum(y[data.membership .== i]) / count(==(i), data.membership) for i in 1:k])
end

function _is_white(color)
    color isa Symbol && lowercase(String(color)) in ("white", "snow", "ivory") && return true
    try
        rgb = RGB(color)
        return minimum((rgb.r, rgb.g, rgb.b)) > 0.98
    catch
        return false
    end
end

# A palette entry as a color without alpha. Palettes may hold names such as :red.
_as_color(color::Colorant) = color
_as_color(color) = RGB(Makie.to_color(color))

# The color as RGBA, with its alpha multiplied by `factor`.
function _with_alpha(color, factor)
    rgba = Makie.to_color(color)
    return RGBAf(rgba.r, rgba.g, rgba.b, rgba.alpha * factor)
end

function _assert_nonwhite(color, name)
    base_color = color isa Tuple && !isempty(color) ? first(color) : color
    _is_white(base_color) && throw(ArgumentError("$name cannot be white"))
    return color
end

function _palette(k, background, palette)
    if palette !== nothing
        length(palette) >= k || throw(ArgumentError("palette needs at least $k colors"))
        colors = palette[1:k]
        foreach(color -> _assert_nonwhite(color, "palette color"), colors)
        return colors
    end
    colors = distinguishable_colors(k + 1, [RGB(1, 1, 1), RGB(0, 0, 0)])
    colors = filter(color -> !_is_white(color), colors)
    length(colors) >= k || throw(ArgumentError("could not generate $k non-white colors"))
    return colors[1:k]
end

function _automatic_view(spanx, spany)
    aspect = max(spanx, spany) / max(min(spanx, spany), eps())
    azimuth = atan(spany, spanx) + 0.5pi
    elevation = clamp(0.18pi - 0.035pi * log(aspect), 0.08pi, 0.22pi)
    return azimuth, elevation
end

_automatic_connectors(data::ContractionData) =
    _automatic_connectors(nv(data.original), nv(data.reduced), ne(data.original))

# Connectors help on small, lightly reduced graphs and clutter large ones.
function _automatic_connectors(original_vertices, reduced_vertices, original_edges)
    reduction_ratio = original_vertices / reduced_vertices
    return original_vertices <= 80 && original_vertices * reduced_vertices <= 300 &&
           reduction_ratio <= 5 && original_edges <= 5 * original_vertices
end

# Figure, camera and layer planes shared by the layered plots.
# Returns the figure, its axis, and the height of each layer, top first.
function _layer_axis(x, y, layer_count; layer_gap, azimuth, elevation, backgroundcolor,
                     figure_size, show_planes, plane_color)
    spanx = max(maximum(x) - minimum(x), eps())
    spany = max(maximum(y) - minimum(y), eps())
    span = max(spanx, spany)
    automatic_azimuth, automatic_elevation = _automatic_view(spanx, spany)
    resolved_gap = layer_gap === :auto ? clamp(0.65 + 0.08 * log(max(spanx, spany) / min(spanx, spany)), 0.55, 0.9) : layer_gap
    resolved_azimuth = azimuth === :auto ? automatic_azimuth : azimuth
    resolved_elevation = elevation === :auto ? automatic_elevation : elevation
    z_levels = [(layer_count - index) * resolved_gap * span for index in 1:layer_count]

    fig = Figure(size=figure_size, backgroundcolor=backgroundcolor)
    ax = Axis3(fig[1, 1]; aspect=:data, azimuth=resolved_azimuth, elevation=resolved_elevation,
               perspectiveness=0.0)
    hidedecorations!(ax); hidespines!(ax)

    if show_planes
        padx, pady = 0.06span, 0.06span
        xs = range(minimum(x)-padx, maximum(x)+padx; length=2)
        ys = range(minimum(y)-pady, maximum(y)+pady; length=2)
        for z in z_levels
            surface!(ax, xs, ys, fill(z - 0.01span, 2, 2);
                     color=fill(plane_color, 2, 2), shading=NoShading, transparency=true)
        end
    end
    return fig, ax, z_levels
end

# One line from each vertex down to its community's reduced vertex.
function _draw_connectors!(ax, vertex_list, membership, x, y, cx, cy, ztop, zbottom,
                           colors, alpha, width)
    connectors = Point3f[]
    connector_colors = Any[]
    for vertex in vertex_list
        community = membership[vertex]
        push!(connectors, Point3f(x[vertex], y[vertex], ztop))
        push!(connectors, Point3f(cx[community], cy[community], zbottom))
        color = RGBA(_as_color(colors[community]), alpha)
        append!(connector_colors, [color, color])
    end
    linesegments!(ax, connectors; color=connector_colors, linewidth=width)
end

function _draw_layer_labels!(ax, x, y, z_levels, labels)
    for (z, label) in zip(z_levels, labels)
        text!(ax, minimum(x), maximum(y), z; text=label, align=(:left, :bottom))
    end
end

function _edge_segments(graph, x, y, z=0.0; max_edges=:auto)
    segments = Point3f[]
    for edge in _limited_edges(graph, max_edges)
        push!(segments, Point3f(x[src(edge)], y[src(edge)], z))
        push!(segments, Point3f(x[dst(edge)], y[dst(edge)], z))
    end
    return segments
end

function _scaled_widths(weights, base_width, scale)
    scale in (:linear, :sqrt, :log) || throw(ArgumentError(
        "weight_scale must be :linear, :sqrt, or :log"))
    values = abs.(Float64.(weights))
    isempty(values) && return Float64[]
    transformed = scale === :sqrt ? sqrt.(values) : scale === :log ? log1p.(values) : values
    minimum_value, maximum_value = extrema(transformed)
    normalized = maximum_value == minimum_value ? ones(length(values)) :
        (transformed .- minimum_value) ./ (maximum_value - minimum_value)
    return base_width .* (0.5 .+ 1.5 .* normalized)
end

function _draw_weighted_edges!(ax, graph, x, y, z, color, weights, base_width, scale, max_edges)
    selected_edges = _limited_edges(graph, max_edges)
    selected_weights = weights[1:length(selected_edges)]
    widths = _scaled_widths(selected_weights, base_width, scale)
    for (index, edge) in enumerate(selected_edges)
        segment = Point3f[Point3f(x[src(edge)], y[src(edge)], z),
                          Point3f(x[dst(edge)], y[dst(edge)], z)]
        linesegments!(ax, segment; color=color, linewidth=widths[index])
    end
end

function _limited_edges(graph, max_edges)
    graph_edges = collect(edges(graph))
    limit = max_edges === :auto ? 4000 : Int(max_edges)
    limit > 0 || throw(ArgumentError("max_edges must be positive"))
    return length(graph_edges) <= limit ? graph_edges : graph_edges[1:limit]
end

_limited_vertices(graph::AbstractGraph, max_vertices) = _limited_vertices(nv(graph), max_vertices)

function _limited_vertices(vertex_count::Integer, max_vertices)
    graph_vertices = collect(1:vertex_count)
    limit = max_vertices === :auto ? 1000 : Int(max_vertices)
    limit > 0 || throw(ArgumentError("max_connectors must be positive"))
    return length(graph_vertices) <= limit ? graph_vertices :
        graph_vertices[round.(Int, range(1, length(graph_vertices); length=limit))]
end

function _stage_positions(sequence, coordinates; iterations=500, layout=:stress)
    positions = Tuple{Vector{Float64},Vector{Float64}}[]
    x, y = _coordinates(sequence[1].original, coordinates; iterations=iterations, layout=layout)
    push!(positions, (x, y))
    for stage in sequence.stages
        k = nv(stage.reduced)
        current_x, current_y = positions[end]
        cx = [sum(current_x[stage.membership .== i]) / count(==(i), stage.membership) for i in 1:k]
        cy = [sum(current_y[stage.membership .== i]) / count(==(i), stage.membership) for i in 1:k]
        push!(positions, (cx, cy))
    end
    return positions
end

"""
    layeredplot(graph, membership; kwargs...)
    layeredplot(data::ContractionData; kwargs...)

Create a publication-ready 3D figure with the original graph above its
contracted graph. Returns a Makie `Figure`; save it with `save("plot.pdf", fig)`.
"""
layeredplot(graph::AbstractGraph, membership::AbstractVector; data_kwargs=NamedTuple(), kwargs...) =
    layeredplot(contraction_data(graph, membership; data_kwargs...); kwargs...)

layeredplot(matrix::AbstractMatrix, membership::AbstractVector; data_kwargs=NamedTuple(), kwargs...) =
    layeredplot(contraction_data(matrix, membership; data_kwargs...); kwargs...)

function layeredplot(data::ContractionData;
                     coordinates=nothing, reduced_coordinates=nothing,
                     layout=:stress, layout_iterations=500,
                     layer_gap=:auto, marker_scale=1.0,
                     backgroundcolor=:white, palette=nothing,
                     edge_color=(:gray, 0.55), connector_alpha=0.5,
                     labels=("Original", "Contracted"), show_labels=true,
                     show_connectors=:auto, show_planes=true,
                     plane_color=(:gray, 0.07), figure_size=(1000, 700),
                     azimuth=:auto, elevation=:auto,
                     node_size=7.0, cluster_node_size=14.0,
                     edge_width=1.0, contracted_edge_width=2.0,
                     connector_width=0.7, max_edges=:auto,
                     max_connectors=:auto, edge_width_by=nothing,
                     weight_scale=:sqrt)
    x, y = _coordinates(data.original, coordinates; iterations=layout_iterations, layout=layout)
    k = nv(data.reduced)
    colors = _palette(k, backgroundcolor, palette)
    cx, cy = _reduced_coordinates(data, x, y, reduced_coordinates; layout=layout)
    resolved_connectors = show_connectors === :auto ? _automatic_connectors(data) : show_connectors

    _assert_nonwhite(edge_color, "edge_color")
    _assert_nonwhite(plane_color, "plane_color")

    fig, ax, z_levels = _layer_axis(x, y, 2; layer_gap=layer_gap, azimuth=azimuth,
        elevation=elevation, backgroundcolor=backgroundcolor, figure_size=figure_size,
        show_planes=show_planes, plane_color=plane_color)
    ztop, zbottom = z_levels

    if edge_width_by === :weight
        _draw_weighted_edges!(ax, data.original, x, y, ztop, edge_color,
                              data.edge_weights, edge_width, weight_scale, max_edges)
    else
        edge_width_by === nothing || throw(ArgumentError("edge_width_by must be nothing or :weight"))
        full_segments = _edge_segments(data.original, x, y, ztop; max_edges=max_edges)
        isempty(full_segments) || linesegments!(ax, full_segments; color=edge_color, linewidth=edge_width)
    end
    scatter!(ax, x, y, fill(ztop, nv(data.original));
             color=colors[data.membership], markersize=node_size * marker_scale)

    if edge_width_by === :weight
        _draw_weighted_edges!(ax, data.reduced, cx, cy, zbottom, edge_color,
                      data.reduced_edge_weights, contracted_edge_width,
                              weight_scale, max_edges)
    else
        reduced_segments = _edge_segments(data.reduced, cx, cy, zbottom; max_edges=max_edges)
        isempty(reduced_segments) || linesegments!(ax, reduced_segments; color=edge_color, linewidth=contracted_edge_width)
    end
    scatter!(ax, cx, cy, fill(zbottom, k); color=colors, markersize=cluster_node_size * marker_scale)

    if resolved_connectors
        _draw_connectors!(ax, _limited_vertices(data.original, max_connectors), data.membership,
                          x, y, cx, cy, ztop, zbottom, colors, connector_alpha, connector_width)
    end

    show_labels && _draw_layer_labels!(ax, x, y, z_levels, labels)
    return fig
end

layeredplot(sequence::ReductionSequence; kwargs...) = layeredplot(sequence, nothing; kwargs...)

function layeredplot(sequence::ReductionSequence, coordinates;
                      layout=:stress, layout_iterations=500, layer_gap=:auto, marker_scale=1.0,
                      backgroundcolor=:white, palette=nothing,
                      edge_color=(:gray, 0.55), connector_alpha=0.5,
                      show_connectors=:auto, show_planes=true,
                      plane_color=(:gray, 0.07), figure_size=(1000, 700),
                      azimuth=:auto, elevation=:auto,
                      node_size=7.0, cluster_node_size=14.0,
                      edge_width=1.0, contracted_edge_width=2.0,
                      connector_width=0.7, max_edges=:auto,
                      max_connectors=:auto, labels=nothing)
    positions = _stage_positions(sequence, coordinates; iterations=layout_iterations, layout=layout)
    initial_x, initial_y = positions[1]
    spanx = max(maximum(initial_x) - minimum(initial_x), eps())
    spany = max(maximum(initial_y) - minimum(initial_y), eps())
    span = max(spanx, spany)
    automatic_azimuth, automatic_elevation = _automatic_view(spanx, spany)
    resolved_gap = layer_gap === :auto ? 0.65 : layer_gap
    resolved_azimuth = azimuth === :auto ? automatic_azimuth : azimuth
    resolved_elevation = elevation === :auto ? automatic_elevation : elevation
    stage_count = length(positions)
    z_levels = [(stage_count - index) * resolved_gap * span for index in 1:stage_count]
    stage_labels = labels === nothing ? [index == 1 ? "Original" : "Stage $(index - 1)" for index in 1:stage_count] : labels
    length(stage_labels) == stage_count || throw(DimensionMismatch("one label is required per layer"))
    _assert_nonwhite(edge_color, "edge_color")
    _assert_nonwhite(plane_color, "plane_color")

    fig = Figure(size=figure_size, backgroundcolor=backgroundcolor)
    ax = Axis3(fig[1, 1]; aspect=:data, azimuth=resolved_azimuth,
               elevation=resolved_elevation, perspectiveness=0.0)
    hidedecorations!(ax); hidespines!(ax)
    all_nodes = [nv(sequence[1].original); [nv(stage.reduced) for stage in sequence.stages]...]
    stage_palettes = [_palette(count, backgroundcolor, palette) for count in all_nodes]
    for index in 1:stage_count
        graph = index == 1 ? sequence[1].original : sequence[index - 1].reduced
        x, y = positions[index]
        z = z_levels[index]
        segments = _edge_segments(graph, x, y, z; max_edges=max_edges)
        isempty(segments) || linesegments!(ax, segments; color=edge_color,
                                           linewidth=index == stage_count ? contracted_edge_width : edge_width)
        scatter!(ax, x, y, fill(z, nv(graph)); color=stage_palettes[index],
                 markersize=(index == stage_count ? cluster_node_size : node_size) * marker_scale)
        if show_planes
            padx, pady = 0.06span, 0.06span
            xs = range(minimum(initial_x)-padx, maximum(initial_x)+padx; length=2)
            ys = range(minimum(initial_y)-pady, maximum(initial_y)+pady; length=2)
            surface!(ax, xs, ys, fill(z - 0.01span, 2, 2);
                     color=fill(plane_color, 2, 2), shading=NoShading, transparency=true)
        end
        if labels !== false
            text!(ax, minimum(initial_x), maximum(initial_y), z; text=stage_labels[index],
                  align=(:left, :bottom))
        end
    end
    if show_connectors !== false
        for index in 1:length(sequence.stages)
            stage = sequence[index]
            show_stage_connectors = show_connectors === :auto ?
                _automatic_connectors(stage) : true
            show_stage_connectors || continue
            current_x, current_y = positions[index]
            next_x, next_y = positions[index + 1]
            connectors = Point3f[]
            connector_colors = Any[]
            for vertex in _limited_vertices(stage.graph, max_connectors)
                community = stage.membership[vertex]
                push!(connectors, Point3f(current_x[vertex], current_y[vertex], z_levels[index]))
                push!(connectors, Point3f(next_x[community], next_y[community], z_levels[index + 1]))
                color = stage_palettes[index + 1][community]
                append!(connector_colors, [RGBA(color, connector_alpha), RGBA(color, connector_alpha)])
            end
            linesegments!(ax, connectors; color=connector_colors, linewidth=connector_width)
        end
    end
    return fig
end
