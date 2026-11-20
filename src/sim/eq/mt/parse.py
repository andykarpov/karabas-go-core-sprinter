import re,sys
def load(fn):
    rows=[]
    for line in open(fn):
        p=line.split()
        r={'n':int(p[0]),'e':p[1]}
        for t in p[2:]:
            if '=' in t:
                k,v=t.split('=',1); r[k]=v
        rows.append(r)
    return rows
