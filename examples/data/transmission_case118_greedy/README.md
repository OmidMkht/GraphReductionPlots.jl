# Transmission case118 fixture: strong reduction

Source: the `case118/greedy_noladder_cap1` result of the campaign in the
Transmission Network Reduction research project (greedy approach, cost cap
1%, no hop limit; status `kkt_verified` on its single design demand).

`line_internal.csv` gives one flag per branch of the IEEE 118-bus case, in the
same order as `../transmission_case118/line_status.csv`: 1 means the line is
merged (internal), 0 means it stays. The bus clusters are the connected
components of the internal lines.

Result: 118 buses become 10 super-nodes. Of the 186 lines, 148 are internal
and 38 stay. The 38 lines join 15 pairs of super-nodes, so they form 15
equivalent lines (up to 7 parallel lines in one pair).
