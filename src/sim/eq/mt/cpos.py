def cpos(R):
    c=[None]*len(R); cur=None
    for i,r in enumerate(R):
        if r['e']=='C' and (int(r['ct'],8)&7)==5: cur=0
        elif cur is not None: cur+=1
        c[i]=cur
    return c
