import subprocess, re, sys
TITLE = "@testset \"the pins are swipl's (live, when swipl is on PATH)\" begin"
files = subprocess.run(["git","diff","--name-only","--diff-filter=A","origin/main..HEAD","--","test"],capture_output=True,text=True,check=True).stdout.split()
COMMENT = "    # the inert-testset guard: an assertion either way (main's convention, test_arg_body_swipl.jl:613)"
plans=[]; refused=[]
for f in files:
    if not f.endswith(".jl"): continue
    t=open(f).read()
    if TITLE not in t: continue
    if t.count(TITLE)!=1: refused.append((f,"title count")); continue
    ls=t.split("\n")
    i=ls.index(TITLE)
    j=i+1
    while ls[j]!="end": j+=1
    blk=ls[i+1:j]
    ifi=[k for k,b in enumerate(blk) if b=="    if swipl === nothing"]
    elsei=[k for k,b in enumerate(blk) if b=="    else"]
    if len(ifi)!=1 or len(elsei)!=1 or ifi[0]>elsei[0]:
        refused.append((f,"if/else shape")); continue
    if any("@test" in b for b in blk[:elsei[0]]):
        refused.append((f,"already asserts on the no-swipl side")); continue
    elseblk="\n".join(blk[elsei[0]:])
    consts=[]
    for c in re.findall(r"\b_[A-Z][A-Z0-9_]*PINNED[A-Z_0-9]*\b", elseblk):
        if c not in consts: consts.append(c)
    if consts:
        test="    @test "+" && ".join(f"!isempty({c})" for c in consts)
        what=",".join(consts)
    elif "_EF_GROUPS" in elseblk and "g.pins" in elseblk:
        test="    @test !isempty(_EF_GROUPS) && all(g -> !isempty(g.pins), _EF_GROUPS)"
        what="_EF_GROUPS (g.pins)"
    else:
        refused.append((f,"no pin constant")); continue
    k=i+1+ifi[0]
    plans.append((f,what,k,test))
print(f"selected {len(plans)}; refused {len(refused)}")
for r in refused: print("REFUSED",*r)
if "--apply" in sys.argv:
    if refused: sys.exit("refusing to apply with refusals")
for f,what,k,test in plans:
    if "--apply" in sys.argv:
        ls=open(f).read().split("\n")
        assert ls[k]=="    if swipl === nothing"
        ls[k:k]=[COMMENT,test]
        open(f,"w").write("\n".join(ls))
    print(f"{f.split('/')[-1]} | {what} | {'inserted' if '--apply' in sys.argv else 'planned'}")
