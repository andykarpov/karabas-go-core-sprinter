import sys; sys.path.insert(0,'.')
from parse import load
from cpos import cpos
from collections import Counter
L='/home/andy/Documents/Projects/Retrocomp/ZX-Spectrum/karabas-go/karabas-go-core-sprinter/src/sim/eq/build/mt/log%s.txt'
res=Counter()
for sc in sys.argv[1:]:
    R=load(L%sc); c=cpos(R)
    for i,r in enumerate(R):
        for f in ('dpic_ld','dcol_ld','mode_ld'):
            if r[f]!='1' or c[i] is None: continue
            # dp_ value used here was captured at edge i-1 (CE_N); VA on the bus then = R[i-1]['va'] (set at CE i-2)
            # the VA set 2 edges earlier (CE i-4) = R[i-3]['va']
            if f=='mode_ld':
                res[(f,'c%d'%c[i],'VA at this CE pre-edge set at c%d'%c[i-2], 'wr_mode low with that VA' if R[i-1]['wmode']=='0' else '?')]+=1
                continue
            lane=r['vla_d']
            near=(R[i-1]['b']==lane); far=(R[i-3]['b']==lane)
            # which flag accompanied which VA: wr_pic/wr_col low in the period of the VA set at CE i-4 ?
            flag='wpic' if f=='dpic_ld' else 'wcol'
            res[(f,'c%d'%c[i],'lane==VA@CE-1period' ,near,'lane==VA@CE-2periods',far, '%s low with VA@CE-2periods'%flag, R[i-3][flag]=='0', 'with VA@CE-1period', R[i-1][flag]=='0')]+=1
for k,v in sorted(res.items(),key=str): print(v,*k)
