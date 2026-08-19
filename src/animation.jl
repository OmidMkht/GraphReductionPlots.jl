"""A built animation that can be displayed or recorded as MP4/GIF."""
struct ContractionAnimation
    figure::Any
    time::Observable{Float64}
    default_duration::Float64
end

struct ReductionSequenceAnimation
    figure::Any
    time::Observable{Float64}
    default_duration::Float64
end

Base.display(animation::ContractionAnimation) = display(animation.figure)
Base.display(animation::ReductionSequenceAnimation) = display(animation.figure)

function _smoothstep(t)
    u = clamp(t, 0.0, 1.0)
    return u * u * (3 - 2u)
end

"""
    animate_contraction(graph, membership; kwargs...) -> ContractionAnimation

Animate vertices moving to their community centroids while internal edges fade
and the quotient-graph edges appear. This is algorithm-independent: membership
can come from clustering, community detection, coarsening, or manual grouping.
"""
animate_contraction(graph::AbstractGraph, membership::AbstractVector; data_kwargs=NamedTuple(), kwargs...) =
    animate_contraction(contraction_data(graph, membership; data_kwargs...); kwargs...)

animate_contraction(matrix::AbstractMatrix, membership::AbstractVector; data_kwargs=NamedTuple(), kwargs...) =
    animate_contraction(contraction_data(matrix, membership; data_kwargs...); kwargs...)

function animate_contraction(data::ContractionData;
                             coordinates=nothing, reduced_coordinates=nothing,
                             layout=:stress, layout_iterations=500,
                             marker_scale=1.0, backgroundcolor=:white,
                             palette=nothing, edge_color=:gray,
                             title="Graph contraction", figure_size=(900, 700),
                             default_duration=8.0, node_size=8.0,
                             cluster_node_size=15.0, edge_width=1.0,
                             contracted_edge_width=2.0, max_edges=:auto,
                             edge_width_by=nothing, weight_scale=:sqrt)
    x, y = _coordinates(data.original, coordinates; iterations=layout_iterations, layout=layout)
    k = nv(data.reduced)
    colors = _palette(k, backgroundcolor, palette)
    cx, cy = _reduced_coordinates(data, x, y, reduced_coordinates; layout=layout)
    target_x = cx[data.membership]
    target_y = cy[data.membership]

    time = Observable(0.0)
    progress = lift(_smoothstep, time)
    animated_x = lift(p -> (1-p) .* x .+ p .* target_x, progress)
    animated_y = lift(p -> (1-p) .* y .+ p .* target_y, progress)

    fig = Figure(size=figure_size, backgroundcolor=backgroundcolor)
    ax = Axis(fig[1, 1]; title=title, aspect=DataAspect())
    hidedecorations!(ax); hidespines!(ax)

    _assert_nonwhite(edge_color, "edge_color")
    edge_width_by in (nothing, :weight) || throw(ArgumentError(
        "edge_width_by must be nothing or :weight"))
    original_edges = _limited_edges(data.original, max_edges)
    original_widths = edge_width_by === :weight ?
        _scaled_widths(data.edge_weights[1:length(original_edges)], edge_width, weight_scale) :
        fill(edge_width, length(original_edges))
    for (edge_index, edge) in enumerate(original_edges)
        internal = data.membership[src(edge)] == data.membership[dst(edge)]
        lines!(ax,
            lift(xs -> [xs[src(edge)], xs[dst(edge)]], animated_x),
            lift(ys -> [ys[src(edge)], ys[dst(edge)]], animated_y);
            color=lift(p -> (edge_color, internal ? 0.65 * (1-p) : 0.65), progress),
                    linewidth=original_widths[edge_index])
    end
                contracted_edges = _limited_edges(data.reduced, max_edges)
                contracted_widths = edge_width_by === :weight ?
                _scaled_widths(data.reduced_edge_weights[1:length(contracted_edges)],
                           contracted_edge_width, weight_scale) :
                fill(contracted_edge_width, length(contracted_edges))
                for (edge_index, edge) in enumerate(contracted_edges)
        lines!(ax, [cx[src(edge)], cx[dst(edge)]], [cy[src(edge)], cy[dst(edge)]];
               color=lift(p -> (edge_color, 0.9p), progress),
               linewidth=lift(p -> contracted_widths[edge_index] * (0.5 + 0.5p), progress))
    end
    scatter!(ax, animated_x, animated_y; color=colors[data.membership],
             markersize=lift(p -> (node_size - 3p) * marker_scale, progress))
    scatter!(ax, cx, cy; color=lift(p -> [RGBA(color, p) for color in colors], progress),
             markersize=lift(p -> cluster_node_size * p * marker_scale, progress))
    xpadding = max((maximum(x) - minimum(x)) * 0.05, 1.0e-6)
    ypadding = max((maximum(y) - minimum(y)) * 0.05, 1.0e-6)
    limits!(ax, minimum(x) - xpadding, maximum(x) + xpadding,
            minimum(y) - ypadding, maximum(y) + ypadding)
    return ContractionAnimation(fig, time, Float64(default_duration))
end

animate_contraction(sequence::ReductionSequence; kwargs...) =
    animate_contraction(sequence, nothing; kwargs...)

function animate_contraction(sequence::ReductionSequence, coordinates;
                             layout=:stress, layout_iterations=500, palette=nothing,
                             edge_color=:gray, title="Graph reduction sequence",
                             figure_size=(900, 700), default_duration=10.0,
                             node_size=8.0, edge_width=1.0,
                             max_edges=:auto)
    positions = _stage_positions(sequence, coordinates; iterations=layout_iterations, layout=layout)
    original_graph = sequence[1].original
    original_x, original_y = positions[1]
    stage_count = length(positions)
    _assert_nonwhite(edge_color, "edge_color")
    trajectories_x = [original_x]
    trajectories_y = [original_y]
    cumulative_membership = collect(vertices(original_graph))
    for stage_index in 1:length(sequence.stages)
        stage = sequence[stage_index]
        cumulative_membership = stage.membership[cumulative_membership]
        stage_x, stage_y = positions[stage_index + 1]
        push!(trajectories_x, stage_x[cumulative_membership])
        push!(trajectories_y, stage_y[cumulative_membership])
    end

    colors = _palette(nv(sequence[1].contracted), :white, palette)
    time = Observable(0.0)
    progress = lift(_smoothstep, time)
    function trajectory_value(trajectories, p)
        scaled = clamp(p, 0.0, 1.0) * (stage_count - 1)
        lower = min(floor(Int, scaled) + 1, stage_count)
        upper = min(lower + 1, stage_count)
        fraction = scaled - (lower - 1)
        return (1 - fraction) .* trajectories[lower] .+ fraction .* trajectories[upper]
    end
    animated_x = lift(p -> trajectory_value(trajectories_x, p), progress)
    animated_y = lift(p -> trajectory_value(trajectories_y, p), progress)

    fig = Figure(size=figure_size, backgroundcolor=:white)
    ax = Axis(fig[1, 1]; title=title, aspect=DataAspect())
    hidedecorations!(ax); hidespines!(ax)
    for edge in _limited_edges(original_graph, max_edges)
        lines!(ax,
               lift(xs -> [xs[src(edge)], xs[dst(edge)]], animated_x),
               lift(ys -> [ys[src(edge)], ys[dst(edge)]], animated_y);
               color=edge_color, linewidth=edge_width)
    end
    scatter!(ax, animated_x, animated_y; color=colors[sequence[1].membership],
             markersize=node_size)
    xpadding = max((maximum(original_x) - minimum(original_x)) * 0.05, 1.0e-6)
    ypadding = max((maximum(original_y) - minimum(original_y)) * 0.05, 1.0e-6)
    limits!(ax, minimum(original_x) - xpadding, maximum(original_x) + xpadding,
            minimum(original_y) - ypadding, maximum(original_y) + ypadding)
    return ReductionSequenceAnimation(fig, time, Float64(default_duration))
end

"""
    record_animation(animation, filename; duration, framerate=30, final_hold=0.5)

Record to `.mp4`, `.gif`, or another format supported by the active Makie
backend. Load and activate `CairoMakie` or `GLMakie` before calling this method.
"""
function record_animation(animation::ContractionAnimation, filename::AbstractString;
                          duration=animation.default_duration, framerate=30,
                          final_hold=0.5)
    duration > 0 || throw(ArgumentError("duration must be positive"))
    framerate > 0 || throw(ArgumentError("framerate must be positive"))
    frames = max(2, round(Int, duration * framerate))
    hold = max(0, round(Int, final_hold * framerate))
    record(animation.figure, filename, 1:(frames + hold); framerate=framerate) do frame
        animation.time[] = min(frame - 1, frames - 1) / (frames - 1)
    end
    return filename
end

function record_animation(animation::ReductionSequenceAnimation, filename::AbstractString;
                          duration=animation.default_duration, framerate=30,
                          final_hold=0.5)
    duration > 0 || throw(ArgumentError("duration must be positive"))
    framerate > 0 || throw(ArgumentError("framerate must be positive"))
    frames = max(2, round(Int, duration * framerate))
    hold = max(0, round(Int, final_hold * framerate))
    record(animation.figure, filename, 1:(frames + hold); framerate=framerate) do frame
        animation.time[] = min(frame - 1, frames - 1) / (frames - 1)
    end
    return filename
end
