using CairoMakie
using GraphReductionPlots

CairoMakie.activate!()

# Kron-based reduction of the Opti-KRON 100-node feeder, then radialization.
# Writes case100_kron_radial.mp4 and .gif without a header.
# Length in seconds: VIDEO_SECONDS (default 30), including a 2-second hold at the end.

data_dir = joinpath(@__DIR__, "data", "optikron_case100")

function csv_rows(path)
    lines = readlines(path)
    return [split(line, ',') for line in lines[2:end] if !isempty(strip(line))]
end

edge_rows = csv_rows(joinpath(data_dir, "edges.csv"))
sources = [parse(Int, row[1]) for row in edge_rows]
destinations = [parse(Int, row[2]) for row in edge_rows]
membership = [parse(Int, row[2]) for row in sort(csv_rows(joinpath(data_dir, "membership.csv"));
                                                 by=row -> parse(Int, row[1]))]
stage_rows = csv_rows(joinpath(data_dir, "supernodes.csv"))
kept = [parse(Int, row[1]) for row in stage_rows if row[2] == "reduction"]
expected_restored = [parse(Int, row[1]) for row in stage_rows if row[2] == "radialization"]

# The kept bus of each community, in the package's community order (first-seen labels).
representatives = [only(filter(bus -> membership[bus] == label, kept)) for label in unique(membership)]

data = kron_data(sources, destinations, membership; representatives=representatives, radialize=true)
println(data)
sort(data.restored) == sort(expected_restored) ||
    error("radialization restored $(data.restored), the source run restored $(expected_restored)")

seconds = parse(Float64, get(ENV, "VIDEO_SECONDS", "30"))
final_hold = 2.0
animation = animate_contraction(data; title="")
name = joinpath(@__DIR__, "case100_kron_radial")
record_animation(animation, name * ".mp4"; duration=seconds - final_hold, final_hold=final_hold)
record_animation(animation, name * ".gif"; duration=seconds - final_hold,
                 final_hold=final_hold, framerate=15, px_per_unit=1)
println("wrote ", name, ".mp4 and .gif")
