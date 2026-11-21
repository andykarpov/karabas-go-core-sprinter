import sys; sys.path.insert(0,'.')
from parse import load
from cpos import cpos
from collections import Counter
L='/home/andy/Documents/Projects/Retrocomp/ZX-Spectrum/karabas-go/karabas-go-core-sprinter/src/sim/eq/build/mt/log%s.txt'
res=Counter(); mcw=Counter(); dcpp=Counter(); col=Counter(); doc=Counter(); mdp=Counter(); wrd=Counter()
for sc in sys.argv[1:]:
    R=load(L%sc); c=cpos(R)
    for i in range(1,len(R)):
        r=R[i]; p=R[i-1]
        if r['e']=='C' and r['ddclr']=='0' and r['mced']=='0': dcpp[c[i]]+=1
        if r['do_ld']=='1': doc[c[i]]+=1
        if r['mdp_ev']=='1': mdp[c[i]]+=1
        if p['ras']=='1' and r['ras']=='0' and p['cas']=='f' and r['cas']=='f':
            f=i-1  # RAS fell at edge f (c4)
            # column at pins from c6: value at line f+3 (edge c7 pre-edge)
            cpin=int(R[f+3]['ma'],16)&0xfff
            io = R[f]['ior']=='0'
            for back in (1,0,-1):   # edges c3, c4, c5 (lines f-1, f, f+1)
                v=int(R[f-back]['colm' if not io else 'coli'],16)
                col[('IO' if io else 'MEM','c%d'%c[f-back], v==cpin)]+=1
            # mc_write / WE: when is the write decided
            j=f
            while j<f+8 and R[j]['we']=='1': j+=1
            if j<f+8:
                k=f
                while k>f-8 and R[k]['mcw']=='0': k-=1
                mcw[('mcw low since edge c%d'%c[k],'WE_N fell at c%d'%c[j-1])]+=1
                # write lanes on CAS_ at c9, data
                wrd[('CAS_ at c9 pre-edge', R[f+5]['cas'])]+=1
            # read data needed: hold until?
    print()
print('descriptor DCPP load edges (c):',dict(dcpp))
print('DO load edges (c):',dict(doc))
print('MDP (peripheral MD latch) edges (c):',dict(mdp))
print('early column == MA at c7:',sorted(col.items()))
print('write decision:',dict(mcw))
print('write lanes:',dict(wrd))
