# Transmission case118 fixture

Source: the `case118_edge/none` result from the Transmission Network
Reduction research project. The public fixture was extracted in August 2026.

`bus_mapping.csv` maps every bus to its retained representative.
`line_status.csv` contains the original branch endpoints and status fields;
the example uses only `from_bus_id` and `to_bus_id`.

The CSV contains 186 branch records (179 unique bus pairs; the rest are
parallel branches). The reduction merges buses without Kron reduction: a line
inside a cluster disappears and every other line stays unchanged. The example
therefore uses `merge_data` with all 186 records, so parallel lines survive in
the reduced network. It also checks that the `internal` column matches the bus
mapping.

The accompanying image is the source project's IEEE 118-bus reduction result.
The recorded run reduced 118 buses to 33 representatives and 186 lines to 71
reduced lines. It reported a 3.029x work-unit speedup and a 1.462x wall-clock
speedup for the tested operating point. These values document the source run;
GraphReductionPlots only visualizes its topology and membership mapping.
