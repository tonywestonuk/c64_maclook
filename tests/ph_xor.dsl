# POLYHEDRON: after XOR frames, the screen must equal a fresh redraw
dclick 292 30
wait 60
dclick 55 142
wait 300
cmd 6
wait 300
cmd .
wait 150
shot phx_frames
cmd H
wait 100
cmd H
wait 150
shot phx_redraw
