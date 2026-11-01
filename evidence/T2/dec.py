import sys,re
# decode enc lines into readable form (slices of the output only)
def dec(s):
    def codes(m): return "".join(chr(int(x)) for x in m.split(",") if x)
    s=re.sub(r"a\[([0-9,]*)\]", lambda m: "'"+codes(m.group(1))+"'", s)
    s=re.sub(r"s\[([0-9,]*)\]", lambda m: '"'+codes(m.group(1))+'"', s)
    s=re.sub(r"c\[([0-9,]*)\]/(\d+)\(", lambda m: codes(m.group(1))+"/"+m.group(2)+"(", s)
    return s
for l in open(sys.argv[1]).read().split("\n")[int(sys.argv[2]):int(sys.argv[3])]:
    print(dec(l).encode("unicode_escape").decode())
