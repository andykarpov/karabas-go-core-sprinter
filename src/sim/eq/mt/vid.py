import sys; sys.path.insert(0,'.')
from parse import load
from collections import Counter, defaultdict
L='/home/andy/Documents/Projects/Retrocomp/ZX-Spectrum/karabas-go/karabas-go-core-sprinter/src/sim/eq/build/mt/log%s.txt'
for sc in sys.argv[1:]:
    R=load(L%sc)
    # cycle position c: c=0 at the CE whose pre-edge phase is 5 (phase 6 starts after it)
    c=[None]*len(R); cur=None
    for i,r in enumerate(R):
        if r['e']=='C' and (int(r['ct'],8)&7)==5: cur=0
        elif cur is not None: cur+=1
        c[i]=cur
    for i in range(len(R)):
        if c[i] is not None and c[i]>11: c[i]=None
    # kind of VA during each period: VA seen at the N line after the CE (pre-edge at CE_N = value set at the CE)
    kinds=Counter(); vanx_ok=Counter(); vanx_bad=Counter()
    for i in range(1,len(R)-1):
        r=R[i]
        if r['e']=='N' and c[i] is not None:
            ph=int(r['ct'],8)&7
            kinds[(c[i]-1, ph, 'wcol0' if r['wrcolpin']=='0' else '', 'wpic' if r['wpic']=='0' else '', 'wcolint' if r['wcol']=='0' else '', 'wmode' if r['wmode']=='0' else '', 'vwr' if r['vwr']!='f' else '')]+=1
        # VA_NX check: vla_n at the CE_N before a CE equals vla_n at that CE (value loaded there)
        if r['e']=='C' and i>0 and R[i-1]['e']=='N' and c[i] is not None:
            if R[i-1]['vlan']==r['vlan']: vanx_ok[c[i]]+=1
            else: vanx_bad[c[i]]+=1
    print('scen',sc)
    print(' VA kinds per period start c (CE), phase:')
    for k,v in sorted(kinds.items(), key=lambda x:(x[0][0],x[0][1:])): print('  ',k,v)
    print(' VA_NX (vla_n) stable from the CE_N before: ok',dict(vanx_ok),'bad',dict(vanx_bad))
    ev=Counter()
    for i,r in enumerate(R):
        for f in ('dpic_ld','dcol_ld','mode_ld'):
            if r[f]=='1': ev[(f,c[i])]+=1
        if r['vwr']!='f': ev[('V_WR low during CLK before edge',c[i],r['e'],r['vwr'],r['vdoe'])]+=1
    for k,v in sorted(ev.items(), key=str): print('  ',k,v)
    # write data: vxd at the N edge before c=0 vs during the V_WR-low CLK
    same=diff=0; ewr_lead=Counter()
    for i,r in enumerate(R):
        if r['vwr']!='f' and r['e']=='N':
            # find c=-1 edge: i-2
            if R[i-2]['vxd']==r['vxd'] and R[i-2]['vxa']==r['vxa']: same+=1
            else: diff+=1
            # how many edges e_wr has been low before the write CE (i-1)
            k=i-1; n=0
            while k>0 and R[k]['ewr']=='0': k-=1; n+=1
            ewr_lead[n]+=1
    print(' write: vxa/vxd equal at CE_N before the slot CE and in the /WE CLK:',same,'differ:',diff,' e_wr low edges before write CE:',dict(ewr_lead))
