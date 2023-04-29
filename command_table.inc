; Requires:
;   CT_ZERO_PAGE_BASE    - zero page location for variables
;   CT_COMMANDS          - table of commands - zero terminated name followed by function address
;                          table is zero-terminated

CT_TABLE_PTR            = CT_ZERO_PAGE_BASE + $00 ; 2 bytes
CT_COMMAND_PTR          = CT_ZERO_PAGE_BASE + $02 ; 2 bytes
CT_COMMAND_FUNCTION_PTR = CT_ZERO_PAGE_BASE + $04 ; 2 bytes

CT_ZERO_PAGE_STOP       = CT_ZERO_PAGE_BASE + $06
