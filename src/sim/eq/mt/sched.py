# Online slot arbiter check: 6 SRAM slots of 2 CLKs per 7 MHz cycle, decided at their start edge s with what is known then.
# Slots start at s = -1 (=11 of the previous cycle), 1, 3, 5, 7, 9. Item = (name, earliest s, latest s, revealed at edge).
import itertools
SL=[-1,1,3,5,7,9]
def items(kind, w, cf, wslots):
    it=[]
    if w: it.append(('W',-1,-1 if wslots==1 else -1,-1))
    if kind in ('ZXld','ZXldM','GRtr'): it.append(('P',3,3,1))          # pixels: VA_NX at c3, data by c7
    if kind.startswith('ZX'): it.append(('A',1 if ATR else 5,5,1))        # ZX attribute: VA_ATR from c1, else VA_NX at c5
    if kind.startswith('GR'): it.append(('A',5,5,1))                     # graphics colour: VA_NX at c5 only
    if kind in ('ZXm','GRm'): it += [('M1',1,9,1),('M2',1,9,1)]          # mode table halves, VA_MOD all cycle, data by c12
    if kind=='ZXldM': it.append(('M1',3,9,1))                            # transitional lane 0 (cycle 0: VA_MOD from c3), data by c13
    if cf is not None: it.append(('C',cf-1,cf+2,cf-1))                   # CPU: A visible at cf-1, T80 latch at cf+5
    return it
def run(kind,w,cf,wslots=1):
    it=items(kind,w,cf,wslots); busy={}
    for s in SL:
        if wslots==2 and s==1 and busy.get(-1)=='W': busy[s]='W2'; continue   # 3-CLK write: [11,3]
        cand=[x for x in it if x[0] not in busy.values() and x[3]<=s and x[1]<=s<=x[2]]
        if not cand: continue
        fixed=[x for x in cand if x[1]==x[2]]
        pick = fixed[0] if fixed else None
        if pick is None:
            cpu=[x for x in cand if x[0]=='C']
            pick = cpu[0] if cpu else min(cand,key=lambda x:x[2])
        busy[s]=pick[0]
    miss=[x[0] for x in it if x[0] not in busy.values()]
    return busy,miss
for ATR in (True,False):
  for PIX in (True,False):
    for wslots in (1,2):
      bad=[]
      for kind in ('ZXld','ZXm','ZXplain','ZXldM','GRm','GRplain','GRtr') + (() if PIX else ('GRld',)):
        k2 = kind
        for w,cf in itertools.product((0,1),(None,0,4,8)):
          if kind=='GRld':   # without PIX_RQ the pixel slot is always taken in graphics too
              it_kind='GRtr'
          else: it_kind=kind
          b,m=run(it_kind,w,cf,wslots)
          if m: bad.append((kind,'W' if w else '-','cf=%s'%cf,m,dict(sorted(b.items()))))
      print('VA_ATR=%s PIX_RQ=%s write=%d CLK:'%(ATR,PIX,2 if wslots==1 else 3), 'all fit' if not bad else '')
      for x in bad: print('   miss',*x)
