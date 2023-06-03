* = $1000
  DATA "H\nel\"lo"
  DATA "Blah\""
my_label_1

  DATA $0G

* = $100F
my_label_2
  JMP my_label_1
  JMP my_label_2
