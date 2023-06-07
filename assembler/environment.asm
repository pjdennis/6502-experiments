; Provided by environment:
read_b    = $F006 ; Returns next char in A; C set when at end
write_b   = $F009 ; Writes char to stdout
write_d   = $F00C ; Writes char to stderr
exit      = $F00F ; Exits the program; exit code in A
open      = $F012 ; Opens file with name at A;X. Returns handle in A
close     = $F015 ; Closes file with handle in A
read      = $F018 ; Reads from file with handle in A
argc      = $F01B ; Returns argument count in A
argv      = $F01E ; Returns argument A in A;X
openout   = $F021
write     = $F024
