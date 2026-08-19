# Transmission case118 fixture

Source: `C:\Users\omokhtar\projects\Transmission Network Reduction\outputs\case118_edge\none`.

The fixture is a direct copy of two source result tables dated August 2026.
`bus_mapping.csv` maps every bus to its representative. `line_status.csv`
provides original branch endpoints plus research-specific status flags; the
example uses only `from_bus_id` and `to_bus_id`.

The accompanying result image comes from `outputs/reduction_case118.png`.
Source numerical summary: 118→33 buses, 186→71 lines, 3.029× work-unit speedup,
and 1.462× wall-clock speedup for the recorded run.
