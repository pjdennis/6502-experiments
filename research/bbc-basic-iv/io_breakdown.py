import re,bisect
# the io sub-regions (start,end inclusive by line) with labels
io_regions=[
(2009,2057,"PRINT# (write to file)"),
(2058,2230,"PRINT + print-field formatting (TAB/SPC/comma/~/';)"),
(2775,2922,"Graphics/screen verbs: GCOL COLOUR MODE MOVE DRAW PLOT CLG CLS VDU REPORT"),
(5429,5464,"Functions: NOT POS USR VPOS"),
(5465,5514,"File functions: PTR BGET OPENIN OPENOUT OPENUP (+PI)"),
(6604,6660,"SOUND ENVELOPE WIDTH"),
(7254,7404,"INPUT / INPUT#"),
(7544,7605,"Line input (OSWORD 0) + newline helper"),
(7856,7978,"Output helpers: print char, detokenise, hex out, spaces, LISTO"),
(8053,8112,"SAVE OSCLI EXT= PTR= CLOSE BPUT"),
(8113,8154,"PRINT inline ROM text + OSWORD-5 byte read + NEW-prog"),
]
# numeric labels -> addr
labels=[]
for i,line in enumerate(open("Basic4.src"),1):
    m=re.match(r'^\.L([0-9A-F]{4})\b',line)
    if m: labels.append((i,int(m.group(1),16)))
def bytes_in(s,e):
    # sum size of every label whose line in [s,e]; size=next label addr-this
    tot=0
    for k,(ln,addr) in enumerate(labels):
        if s<=ln<=e:
            nxt=labels[k+1][1] if k+1<len(labels) else 0xBFF6
            tot+=max(0,nxt-addr)
    return tot
rows=[(bytes_in(s,e),d) for s,e,d in io_regions]
T=sum(r[0] for r in rows)
print(f"I/O bucket total: {T} bytes  ({100*T/16384:.1f}% of ROM)\n")
print(f"{'bytes':>6}{'%ROM':>7}{'%ofIO':>7}  routine group")
print("-"*80)
for b,d in sorted(rows,key=lambda x:-x[0]):
    print(f"{b:>6}{100*b/16384:>6.1f}%{100*b/T:>6.1f}%  {d}")
