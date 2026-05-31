import re
# category boundaries by start line (same map as line analysis)
segs = [
(1,"harness"),(8,"harness"),(26,"harness"),(30,"startup"),(47,"startup"),
(65,"variables"),(122,"progmgmt"),(149,"fpmath"),(197,"fpmath"),(531,"tokeniser"),
(676,"interp"),(795,"assembler"),(1515,"tokeniser"),(1684,"tokeniser"),(1716,"progmgmt"),
(1750,"startup"),(1783,"interp"),(1807,"interp"),(1854,"interp"),(1949,"strings"),
(2009,"io"),(2058,"io"),(2231,"interp"),(2279,"progmgmt"),(2302,"progmgmt"),
(2434,"progmgmt"),(2456,"variables"),(2596,"interp"),(2676,"evaluator"),(2727,"control"),
(2775,"io"),(2923,"variables"),(3324,"evaluator"),(4002,"harness"),(4005,"evaluator"),
(4065,"numstr"),(4137,"numstr"),(4394,"numstr"),(4523,"fpmath"),(5429,"io"),
(5465,"io"),(5515,"evaluator"),(5549,"numstr"),(5607,"functions"),(5691,"strings"),
(5762,"evaluator"),(5844,"evaluator"),(5943,"functions"),(6092,"strings"),(6199,"control"),
(6270,"harness"),(6273,"control"),(6444,"variables"),(6536,"error"),(6568,"error"),
(6604,"io"),(6661,"variables"),(6705,"progmgmt"),(6877,"control"),(6992,"control"),
(7083,"control"),(7144,"control"),(7254,"io"),(7405,"control"),(7503,"control"),
(7544,"io"),(7606,"tokeniser"),(7686,"interp"),(7710,"evaluator"),(7856,"io"),
(7979,"progmgmt"),(8053,"io"),(8113,"io"),(8155,"fpmath"),(8171,"fpmath"),
(8224,"harness"),(99999,"END"),
]
starts=[s[0] for s in segs]
def cat_for_line(ln):
    import bisect
    i=bisect.bisect_right(starts,ln)-1
    return segs[i][1]

# parse numeric labels: .L#### (4 hex) including .LBFxx constants
labels=[]
for i,line in enumerate(open("Basic4.src"),1):
    m=re.match(r'^\.L([0-9A-F]{4})\b',line)
    if m:
        labels.append((i,int(m.group(1),16)))

# verify monotonic addresses
nonmono=[(labels[k],labels[k+1]) for k in range(len(labels)-1) if labels[k+1][1]<labels[k][1]]
print("labels:",len(labels),"  non-monotonic pairs:",len(nonmono))
for a,b in nonmono[:10]: print("  ",a,"->",b)

END_OF_CONSTS=0xBFF6   # after 8 EXP series *5 bytes past LBFCE
ROM_END=0xC000
from collections import defaultdict
catb=defaultdict(int)
for k,(ln,addr) in enumerate(labels):
    nextaddr = labels[k+1][1] if k+1<len(labels) else END_OF_CONSTS
    size=nextaddr-addr
    if size<0: size=0
    catb[cat_for_line(ln)]+=size
# tail: "Roger" + zero pad
catb["padding"]= ROM_END-END_OF_CONSTS

total=sum(catb.values())
print("\nTotal bytes accounted:",total,"(ROM=16384)")
print(f"\n{'CATEGORY':<12}{'bytes':>7}{'%ROM':>8}")
print("-"*28)
for c,b in sorted(catb.items(),key=lambda x:-x[1]):
    print(f"{c:<12}{b:>7}{100*b/16384:>7.1f}%")
