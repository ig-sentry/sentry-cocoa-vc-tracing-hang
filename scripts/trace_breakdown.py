import sys, xml.etree.ElementTree as ET, collections
root=ET.parse(sys.argv[1]).getroot(); ids={}
def R(e):
    r=e.get('ref'); 
    if r: return ids[r]
    if e.get('id'): ids[e.get('id')]=e
    for c in e: R(c)
    return e
rows=[]
for row in root.iter('row'):
    d={}
    for c in row:
        c=R(c); d[c.tag]=c
    rows.append(d)
def tname(t): return t.get('fmt','')
samples=[]
for d in rows:
    th=d.get('thread'); bt=d.get('tagged-backtrace'); ts=d.get('sample-time')
    if th is None or bt is None: continue
    if 'Main Thread' not in tname(th) and 'main' not in tname(th).lower(): continue
    fr=[]
    for f in bt.iter('frame'):
        f=ids.get(f.get('ref'),f) if f.get('ref') else f
        fr.append(f.get('name','?'))
    w=d.get('weight'); wt=1
    samples.append((int(ts.text),fr,wt))
samples.sort(); 
if not samples: print("no main samples", collections.Counter(tname(d['thread']) for d in rows if 'thread' in d).most_common(5)); sys.exit()
# 1ms buckets: find longest window of continuous busy main thread (gap<5ms)
best=(0,0,0); s=0
for i in range(1,len(samples)):
    if samples[i][0]-samples[i-1][0]>5_000_000: 
        if samples[i-1][0]-samples[s][0]>best[0]: best=(samples[i-1][0]-samples[s][0],s,i)
        s=i
if samples[-1][0]-samples[s][0]>best[0]: best=(samples[-1][0]-samples[s][0],s,len(samples))
dur,a,b=best; win=samples[a:b]; tot=sum(x[2] for x in win)
print(f"main samples={len(samples)} longest busy window={dur/1e9:.2f}s samples={len(win)}")
top=collections.Counter(); incl=collections.Counter()
keys=['SentryWeakMap prune','hasUnfinishedChildSpansToWaitFor','SentryTracer','SentryWeakMap','limitOverride','viewWillLayoutSubViews','viewDidLayoutSubViews','objc_loadWeak','addChild','didMoveToParent','addSubview','layoutSubviews']
for t,fr,w in win:
    top[fr[0]]+=w
    seen=set()
    for f in fr:
        for k in keys:
            if k in f and k not in seen: seen.add(k); incl[k]+=w
    if any('Sentry' in f for f in fr): incl['ANY Sentry frame']+=w
print("TOP self:"); [print(f"  {100*v/tot:5.1f}% {k[:100]}") for k,v in top.most_common(12)]
print("INCLUSIVE:"); [print(f"  {100*v/tot:5.1f}% {k}") for k,v in incl.most_common()]
inner=collections.Counter(); outer=collections.Counter()
for t,fr,w in win:
    s=[f for f in fr if 'Sentry' in f]
    if s: inner[s[0][:110]]+=1
    phase='other'
    for f in fr:
        if 'viewDidLayoutSubViews' in f: phase='viewDidLayoutSubviews swizzle'; break
        if 'viewWillLayoutSubViews' in f: phase='viewWillLayoutSubviews swizzle'; break
        if 'viewWillAppear' in f or 'viewDidAppear' in f: phase='viewWill/DidAppear swizzle'; break
        if 'viewDidLoad' in f or 'loadView' in f: phase='loadView/viewDidLoad swizzle'; break
    outer[phase]+=1
print("INNERMOST Sentry frame:"); [print(f"  {100*v/tot:5.1f}% {k}") for k,v in inner.most_common(12)]
print("SWIZZLE ENTRY:"); [print(f"  {100*v/tot:5.1f}% {k}") for k,v in outer.most_common()]
