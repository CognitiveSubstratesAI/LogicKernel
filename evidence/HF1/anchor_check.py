import os,sys
os.chdir('/home/shivaji1012/code/lk-halt1')
ns={}
exec(open('tools/mutants/HF1.py').read(),ns)
M=ns['MUTANTS']; bad=0
ids=[m['id'].split(' ')[0] for m in M]
assert len(ids)==len(set(ids)),'dup ids'
cache={}
for m in M:
    f=m['file']; s=cache.setdefault(f,open(f).read())
    c=s.count(m['old'])
    if c!=1: print('ANCHOR',m['id'][:30],f,c); bad+=1
    if m['old']==m['new']: print('SAME',m['id'][:30]); bad+=1
    for t in m['targets']:
        if not os.path.exists(t): print('NOTARGET',t); bad+=1
for t in ns['TARGETS']:
    if not os.path.exists(t): print('NOTARGET',t); bad+=1
print(len(M),'mutants',len(ids),'ids',sum(1 for m in M if m.get('equivalent')),'equivalent; bad =',bad)
