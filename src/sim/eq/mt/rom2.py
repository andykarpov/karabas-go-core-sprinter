import sys; sys.path.insert(0,'.')
from parse import load
from cpos import cpos
from collections import Counter
L='/home/andy/Documents/Projects/Retrocomp/ZX-Spectrum/karabas-go/karabas-go-core-sprinter/src/sim/eq/build/mt/log%s.txt'
res=Counter()
for sc in sys.argv[1:]:
    R=load(L%sc); c=cpos(R)
    for cs in ('csr','csc'):
        i=1
        while i<len(R):
            if R[i][cs]=='0' and R[i-1][cs]=='1':
                j=i
                while j<len(R) and R[j][cs]=='0': j+=1
                f=i-1   # edge at which CS fell (CE)
                k=f
                while k>0 and R[k]['a']==R[i]['a'] and R[k]['ra']==R[i]['ra']: k-=1
                a_edge=k  # A/RA changed at this edge
                isrd = any(R[x]['rd']=='0' for x in range(i,j))
                iswr = any(R[x]['wr']=='0' for x in range(i,j))
                m1 = R[i]['m1']=='0'
                end=j-1   # last edge CS seen low -> CS rises at edge j-1
                # Z80 sample edge: M1 = clkz rise in T3 (last rise before end); read = last clkz fall before end
                rises=[x for x in range(i,j) if R[x]['clkz']=='1' and R[x-1]['clkz']=='0']  # clkz changed at edge x-1
                falls=[x for x in range(i,j) if R[x]['clkz']=='0' and R[x-1]['clkz']=='1']
                if m1: smp = rises[-1]-1
                else: smp = falls[-1]-1
                wt=sum(1 for x in range(i,j) if R[x]['wait']=='1')
                # write: data on D valid from? WR fall edge
                wf = next((x-1 for x in range(i,j) if R[x]['wr']=='0'),None)
                key=(sc,cs,'M1' if m1 else ('RD' if isrd else ('WR' if iswr else '?')), 'turbo' if (len(rises)>=1 and (rises[0]-falls[0] if falls else 0)!=0) else '', 'cCSfall=%s'%c[f], 'A->CS=%d'%(f-a_edge), 'CS->sample=%s'%((smp-f) if isrd else '-'), 'A->sample=%s'%((smp-a_edge) if isrd else '-'), 'CS->WRfall=%s'%((wf-f) if wf is not None else '-'), 'CSlen=%d'%(j-i), 'wait=%d'%wt, 'zper=%s'%((rises[1]-rises[0]) if len(rises)>1 else '-'))
                res[key]+=1
                i=j
            else: i+=1
for k,v in sorted(res.items(), key=str): print(v,*k)
