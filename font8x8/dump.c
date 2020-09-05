#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

#include "font8x8_basic.h"

void usage(char *exec) {
    printf("Usage: %s <char_code>\n", exec);
    printf("       <char_code> Decimal character code between 0 and 127\n");
}

void render(char c) {
    char *bitmap = font8x8_basic[c];

    printf("  .byte ");

    for (int x = 0; x < 7; x++) {
        printf("$%02x, ", (unsigned char) bitmap[x]);
    }
    printf("$%02x ; %3i $%02x", (unsigned char) bitmap[7], c, c);
    if (isprint(c)) {
        printf(" '%c'", c);
    }
    printf("\n");
}

void render_all() {
    printf("character_patterns:\n");
    for (int c = 32; c < 127; c++) {
        render(c);
    }
}

int main(int argc, char **argv) {
    render_all();
/*
    int ord;
    if (argc != 2) {
        usage(argv[0]);
        return 1;
    }
    ord = atoi(argv[1]);
    if (ord > 127 || ord < 0) {
        usage(argv[0]);
        return 2;
    }
    
    render(ord);
*/
    return 0;
}
