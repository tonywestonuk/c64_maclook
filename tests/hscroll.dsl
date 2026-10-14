# disk window made narrow: the horizontal scroll bar works
dclick 292 30
wait 60
drag 269 173 169 173
wait 60
shot hs_a
hold 159 173 30
shot hs_b
click 145 173
shot hs_c
hold 39 173 60
shot hs_d
dump hs_d
