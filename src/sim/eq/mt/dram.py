import sys; sys.path.insert(0,'.')
from parse import load
from cpos import cpos
from collections import Counter
L='/home/andy/Documents/Projects/Retrocomp/ZX-Spectrum/karabas-go/karabas-go-core-sprinter/src/sim/eq/build/mt/log%s.txt'
res=Counter(); rf_gaps=Counter(); ewr=Counter(); mdoe=Counter(); misc=Counter()
def edge_of_change(R,i,f): return i-1   # value at line i differs from i-1 -> changed at edge i-1
for sc in sys.argv[1:]:
    R=load(L%sc); c=cpos(R)
    last_rf=None; cyc_idx=0
    for i in range(1,len(R)):
        r=R[i]; p=R[i-1]
        if c[i-1]==0: cyc_idx+=1
        # e_wr fall position
        if p['ewr']=='1' and r['ewr']=='0': ewr[c[i-1]]+=1
        # RAS fall
        if p['ras']=='1' and r['ras']=='0':
            f=i-1
            refresh = p['cas']!='f' or r['cas']!='f'
            j=i
            while j<len(R) and R[j]['ras']=='0': j+=1
            ras_rise=j-1
            if refresh:
                k=i-1
                while k>0 and R[k]['cas']!='f': k-=1
                cas_fall=k
                if last_rf is not None: rf_gaps[(f-last_rf)//12]+=1
                last_rf=f
                res[(sc,'CBR','cCASfall=%s'%c[cas_fall],'cRASfall=%s'%c[f],'RASlen=%d'%(ras_rise-f),'cas=%s'%r['cas'])]+=1
                continue
            cf=next((x-1 for x in range(i,j+2) if R[x]['cas']!='f' and R[x-1]['cas']=='f'),None)
            if cf is None:
                res[(sc,'RAS-only','io=%s'%R[f]['io'],'cRAS=%s'%c[f],'RASlen=%d'%(ras_rise-f))]+=1; continue
            cr=next((x-1 for x in range(cf+1,j+6) if R[x]['cas']=='f' and R[x-1]['cas']!='f'),None) if cf else None
            wf=next((x-1 for x in range(i,j+1) if R[x]['we']=='0' and R[x-1]['we']=='1'),None)
            # decision: mc_type fell (CPU cycle) at which edge before RAS
            k=f
            while k>0 and R[k]['mct']=='0': k-=1
            mct_fall=k  # mct became 0 after edge k
            k2=f
            while k2>0 and R[k2]['mcw']==R[f]['mcw'] and k2>f-12: k2-=1
            # row MA valid: MA value at RAS fall (pre-edge at the line after the edge?)
            # MA seen in the CLK before the RAS fall edge = R[f]['ma']; when did it get that value?
            k3=f
            while k3>0 and R[k3]['ma']==R[f]['ma']: k3-=1
            row_since=f-k3
            # column: MA at the CAS fall edge (pre-edge) and since
            colv=R[cf]['ma']; k4=cf
            while k4>0 and R[k4]['ma']==colv: k4-=1
            col_since=cf-k4
            k5=cf
            while k5<len(R) and R[k5]['ma']==colv: k5+=1
            col_until=(k5-1)-cf
            do=[x for x in range(f,cr+6) if R[x]['do_ld']=='1']
            dc=[x for x in range(f,cr+6) if R[x]['dcpp_ld']=='1' and R[x]['e']=='C']
            mdp=[x for x in range(f,cr+12) if R[x]['mdp_ev']=='1']
            write = wf is not None
            io = R[f]['io']=='0'
            # write data: MD_OE and MD_O stable from? to?
            wd=''
            if write:
                k6=wf
                while k6>0 and R[k6]['mdoe']=='1' and R[k6]['mdo']==R[wf]['mdo']: k6-=1
                wd='MDO_stable_since_WEfall=-%d'%(wf-k6)
                k7=wf
                while k7<len(R) and R[k7]['mdoe']=='1' and R[k7]['mdo']==R[wf]['mdo']: k7+=1
                wd+=' until=+%d'%((k7-1)-wf)
            res[(sc,'IO' if io else 'MEM','WR' if write else 'RD','cMCT0=%s'%c[mct_fall],'cRAS=%s'%c[f],'cCAS=%s'%c[cf],'cCASrise=%s'%c[cr],'cWE=%s'%(c[wf] if wf else '-'),'cRASrise=%s'%c[ras_rise],'row_since=%d'%row_since,'col_since=%d col_until=+%d'%(col_since,col_until),'DO@%s'%[c[x] for x in do] if not write else '','DCPP@%s'%[c[x] for x in dc] if io else '',wd)]+=1
for k,v in sorted(res.items(), key=str): print(v,*k)
print('CBR gaps (in 12-CLK cycles):',sorted(rf_gaps.items()))
print('e_wr fall at c:',dict(ewr))
