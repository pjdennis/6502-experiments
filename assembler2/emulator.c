// From: http://rubbermallet.org/fake6502.c

/* Fake6502 CPU emulator core v1.1 *******************
 * (c)2011 Mike Chambers (miker00lz@gmail.com)       *
 *****************************************************
 * v1.1 - Small bugfix in BIT opcode, but it was the *
 *        difference between a few games in my NES   *
 *        emulator working and being broken!         *
 *        I went through the rest carefully again    *
 *        after fixing it just to make sure I didn't *
 *        have any other typos! (Dec. 17, 2011)      *
 *                                                   *
 * v1.0 - First release (Nov. 24, 2011)              *
 *****************************************************
 * LICENSE: This source code is released into the    *
 * public domain, but if you use it please do give   *
 * credit. I put a lot of effort into writing this!  *
 *                                                   *
 *****************************************************
 * Fake6502 is a MOS Technology 6502 CPU emulation   *
 * engine in C. It was written as part of a Nintendo *
 * Entertainment System emulator I've been writing.  *
 *                                                   *
 * A couple important things to know about are two   *
 * defines in the code. One is "UNDOCUMENTED" which, *
 * when defined, allows Fake6502 to compile with     *
 * full support for the more predictable             *
 * undocumented instructions of the 6502. If it is   *
 * undefined, undocumented opcodes just act as NOPs. *
 *                                                   *
 * The other define is "NES_CPU", which causes the   *
 * code to compile without support for binary-coded  *
 * decimal (BCD) support for the ADC and SBC         *
 * opcodes. The Ricoh 2A03 CPU in the NES does not   *
 * support BCD, but is otherwise identical to the    *
 * standard MOS 6502. (Note that this define is      *
 * enabled in this file if you haven't changed it    *
 * yourself. If you're not emulating a NES, you      *
 * should comment it out.)                           *
 *                                                   *
 * If you do discover an error in timing accuracy,   *
 * or operation in general please e-mail me at the   *
 * address above so that I can fix it. Thank you!    *
 *                                                   *
 *****************************************************
 * Usage:                                            *
 *                                                   *
 * Fake6502 requires you to provide two external     *
 * functions:                                        *
 *                                                   *
 * uint8_t read6502(uint16_t address)                *
 * void write6502(uint16_t address, uint8_t value)   *
 *                                                   *
 * You may optionally pass Fake6502 the pointer to a *
 * function which you want to be called after every  *
 * emulated instruction. This function should be a   *
 * void with no parameters expected to be passed to  *
 * it.                                               *
 *                                                   *
 * This can be very useful. For example, in a NES    *
 * emulator, you check the number of clock ticks     *
 * that have passed so you can know when to handle   *
 * APU events.                                       *
 *                                                   *
 * To pass Fake6502 this pointer, use the            *
 * hookexternal(void *funcptr) function provided.    *
 *                                                   *
 * To disable the hook later, pass NULL to it.       *
 *****************************************************
 * Useful functions in this emulator:                *
 *                                                   *
 * void reset6502()                                  *
 *   - Call this once before you begin execution.    *
 *                                                   *
 * void exec6502(uint32_t tickcount)                 *
 *   - Execute 6502 code up to the next specified    *
 *     count of clock ticks.                         *
 *                                                   *
 * void step6502()                                   *
 *   - Execute a single instrution.                  *
 *                                                   *
 * void irq6502()                                    *
 *   - Trigger a hardware IRQ in the 6502 core.      *
 *                                                   *
 * void nmi6502()                                    *
 *   - Trigger an NMI in the 6502 core.              *
 *                                                   *
 * void hookexternal(void *funcptr)                  *
 *   - Pass a pointer to a void function taking no   *
 *     parameters. This will cause Fake6502 to call  *
 *     that function once after each emulated        *
 *     instruction.                                  *
 *                                                   *
 *****************************************************
 * Useful variables in this emulator:                *
 *                                                   *
 * uint64_t clockticks6502                           *
 *   - A running total of the emulated cycle count.  *
 *                                                   *
 * uint32_t instructions                             *
 *   - A running total of the total emulated         *
 *     instruction count. This is not related to     *
 *     clock cycle timing.                           *
 *                                                   *
 *****************************************************/

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <limits.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <time.h>

#define STDIN_FILENO  0
#define STDOUT_FILENO 1

//6502 defines
#define UNDOCUMENTED //when this is defined, undocumented opcodes are handled.
                     //otherwise, they're simply treated as NOPs.

#define NES_CPU      //when this is defined, the binary-coded decimal (BCD)
                     //status flag is not honored by ADC and SBC. the 2A03
                     //CPU in the Nintendo Entertainment System does not
                     //support BCD operation.

#define FLAG_CARRY     0x01
#define FLAG_ZERO      0x02
#define FLAG_INTERRUPT 0x04
#define FLAG_DECIMAL   0x08
#define FLAG_BREAK     0x10
#define FLAG_CONSTANT  0x20
#define FLAG_OVERFLOW  0x40
#define FLAG_SIGN      0x80

#define BASE_STACK     0x100

#define saveaccum(n) a = (uint8_t)((n) & 0x00FF)


//flag modifier macros
#define setcarry() status |= FLAG_CARRY
#define clearcarry() status &= (~FLAG_CARRY)
#define setzero() status |= FLAG_ZERO
#define clearzero() status &= (~FLAG_ZERO)
#define setinterrupt() status |= FLAG_INTERRUPT
#define clearinterrupt() status &= (~FLAG_INTERRUPT)
#define setdecimal() status |= FLAG_DECIMAL
#define cleardecimal() status &= (~FLAG_DECIMAL)
#define setoverflow() status |= FLAG_OVERFLOW
#define clearoverflow() status &= (~FLAG_OVERFLOW)
#define setsign() status |= FLAG_SIGN
#define clearsign() status &= (~FLAG_SIGN)


//flag calculation macros
#define zerocalc(n) {\
    if ((n) & 0x00FF) clearzero();\
        else setzero();\
}

#define signcalc(n) {\
    if ((n) & 0x0080) setsign();\
        else clearsign();\
}

#define carrycalc(n) {\
    if ((n) & 0xFF00) setcarry();\
        else clearcarry();\
}

#define overflowcalc(n, m, o) { /* n = result, m = accumulator, o = memory */ \
    if (((n) ^ (uint16_t)(m)) & ((n) ^ (o)) & 0x0080) setoverflow();\
        else clearoverflow();\
}


//6502 CPU registers
uint16_t pc;
uint8_t sp, a, x, y, status;


//helper variables
uint32_t instructions = 0; //keep track of total instructions executed
uint64_t clockticks6502 = 0, clockgoal6502 = 0;
uint16_t oldpc, ea, reladdr, value, result;
uint8_t opcode, oldstatus;

//externally supplied functions
extern uint8_t read6502(uint16_t address);
extern void write6502(uint16_t address, uint8_t value);

//a few general functions used by various other functions
void push16(uint16_t pushval) {
    write6502(BASE_STACK + sp, (pushval >> 8) & 0xFF);
    write6502(BASE_STACK + ((sp - 1) & 0xFF), pushval & 0xFF);
    sp -= 2;
}

void push8(uint8_t pushval) {
    write6502(BASE_STACK + sp--, pushval);
}

uint16_t pull16() {
    uint16_t temp16;
    temp16 = read6502(BASE_STACK + ((sp + 1) & 0xFF)) | ((uint16_t)read6502(BASE_STACK + ((sp + 2) & 0xFF)) << 8);
    sp += 2;
    return(temp16);
}

uint8_t pull8() {
    return (read6502(BASE_STACK + ++sp));
}

void reset6502() {
    pc = (uint16_t)read6502(0xFFFC) | ((uint16_t)read6502(0xFFFD) << 8);
    a = 0;
    x = 0;
    y = 0;
    sp = 0xFD;
    status |= FLAG_CONSTANT;
}


static void (*addrtable[256])();
static void (*optable[256])();
uint8_t penaltyop, penaltyaddr;

//addressing mode functions, calculates effective addresses
static void imp() { //implied
}

static void acc() { //accumulator
}

static void imm() { //immediate
    ea = pc++;
}

static void zp() { //zero-page
    ea = (uint16_t)read6502((uint16_t)pc++);
}

static void zpx() { //zero-page,X
    ea = ((uint16_t)read6502((uint16_t)pc++) + (uint16_t)x) & 0xFF; //zero-page wraparound
}

static void zpy() { //zero-page,Y
    ea = ((uint16_t)read6502((uint16_t)pc++) + (uint16_t)y) & 0xFF; //zero-page wraparound
}

static void rel() { //relative for branch ops (8-bit immediate value, sign-extended)
    reladdr = (uint16_t)read6502(pc++);
    if (reladdr & 0x80) reladdr |= 0xFF00;
}

static void abso() { //absolute
    ea = (uint16_t)read6502(pc) | ((uint16_t)read6502(pc+1) << 8);
    pc += 2;
}

static void absx() { //absolute,X
    uint16_t startpage;
    ea = ((uint16_t)read6502(pc) | ((uint16_t)read6502(pc+1) << 8));
    startpage = ea & 0xFF00;
    ea += (uint16_t)x;

    if (startpage != (ea & 0xFF00)) { //one cycle penlty for page-crossing on some opcodes
        penaltyaddr = 1;
    }

    pc += 2;
}

static void absy() { //absolute,Y
    uint16_t startpage;
    ea = ((uint16_t)read6502(pc) | ((uint16_t)read6502(pc+1) << 8));
    startpage = ea & 0xFF00;
    ea += (uint16_t)y;

    if (startpage != (ea & 0xFF00)) { //one cycle penlty for page-crossing on some opcodes
        penaltyaddr = 1;
    }

    pc += 2;
}

static void ind() { //indirect
    uint16_t eahelp, eahelp2;
    eahelp = (uint16_t)read6502(pc) | (uint16_t)((uint16_t)read6502(pc+1) << 8);
    eahelp2 = (eahelp & 0xFF00) | ((eahelp + 1) & 0x00FF); //replicate 6502 page-boundary wraparound bug
    ea = (uint16_t)read6502(eahelp) | ((uint16_t)read6502(eahelp2) << 8);
    pc += 2;
}

static void indx() { // (indirect,X)
    uint16_t eahelp;
    eahelp = (uint16_t)(((uint16_t)read6502(pc++) + (uint16_t)x) & 0xFF); //zero-page wraparound for table pointer
    ea = (uint16_t)read6502(eahelp & 0x00FF) | ((uint16_t)read6502((eahelp+1) & 0x00FF) << 8);
}

static void indy() { // (indirect),Y
    uint16_t eahelp, eahelp2, startpage;
    eahelp = (uint16_t)read6502(pc++);
    eahelp2 = (eahelp & 0xFF00) | ((eahelp + 1) & 0x00FF); //zero-page wraparound
    ea = (uint16_t)read6502(eahelp) | ((uint16_t)read6502(eahelp2) << 8);
    startpage = ea & 0xFF00;
    ea += (uint16_t)y;

    if (startpage != (ea & 0xFF00)) { //one cycle penlty for page-crossing on some opcodes
        penaltyaddr = 1;
    }
}

static uint16_t getvalue() {
    if (addrtable[opcode] == acc) return((uint16_t)a);
        else return((uint16_t)read6502(ea));
}

static uint16_t getvalue16() {
    return((uint16_t)read6502(ea) | ((uint16_t)read6502(ea+1) << 8));
}

static void putvalue(uint16_t saveval) {
    if (addrtable[opcode] == acc) a = (uint8_t)(saveval & 0x00FF);
        else write6502(ea, (saveval & 0x00FF));
}


//instruction handler functions
static void adc() {
    penaltyop = 1;
    value = getvalue();
    result = (uint16_t)a + value + (uint16_t)(status & FLAG_CARRY);

    carrycalc(result);
    zerocalc(result);
    overflowcalc(result, a, value);
    signcalc(result);

    #ifndef NES_CPU
    if (status & FLAG_DECIMAL) {
        clearcarry();

        if ((a & 0x0F) > 0x09) {
            a += 0x06;
        }
        if ((a & 0xF0) > 0x90) {
            a += 0x60;
            setcarry();
        }

        clockticks6502++;
    }
    #endif

    saveaccum(result);
}

static void and() {
    penaltyop = 1;
    value = getvalue();
    result = (uint16_t)a & value;

    zerocalc(result);
    signcalc(result);

    saveaccum(result);
}

static void asl() {
    value = getvalue();
    result = value << 1;

    carrycalc(result);
    zerocalc(result);
    signcalc(result);

    putvalue(result);
}

static void bcc() {
    if ((status & FLAG_CARRY) == 0) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void bcs() {
    if ((status & FLAG_CARRY) == FLAG_CARRY) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void beq() {
    if ((status & FLAG_ZERO) == FLAG_ZERO) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void bit() {
    value = getvalue();
    result = (uint16_t)a & value;

    zerocalc(result);
    status = (status & 0x3F) | (uint8_t)(value & 0xC0);
}

static void bmi() {
    if ((status & FLAG_SIGN) == FLAG_SIGN) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void bne() {
    if ((status & FLAG_ZERO) == 0) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void bpl() {
    if ((status & FLAG_SIGN) == 0) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void brk_insn() {
    pc++;
    push16(pc); //push next instruction address onto stack
    push8(status | FLAG_BREAK); //push CPU status to stack
    setinterrupt(); //set interrupt flag
    pc = (uint16_t)read6502(0xFFFE) | ((uint16_t)read6502(0xFFFF) << 8);
}

static void bvc() {
    if ((status & FLAG_OVERFLOW) == 0) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void bvs() {
    if ((status & FLAG_OVERFLOW) == FLAG_OVERFLOW) {
        oldpc = pc;
        pc += reladdr;
        if ((oldpc & 0xFF00) != (pc & 0xFF00)) clockticks6502 += 2; //check if jump crossed a page boundary
            else clockticks6502++;
    }
}

static void clc() {
    clearcarry();
}

static void cld() {
    cleardecimal();
}

static void cli() {
    clearinterrupt();
}

static void clv() {
    clearoverflow();
}

static void cmp() {
    penaltyop = 1;
    value = getvalue();
    result = (uint16_t)a - value;

    if (a >= (uint8_t)(value & 0x00FF)) setcarry();
        else clearcarry();
    if (a == (uint8_t)(value & 0x00FF)) setzero();
        else clearzero();
    signcalc(result);
}

static void cpx() {
    value = getvalue();
    result = (uint16_t)x - value;

    if (x >= (uint8_t)(value & 0x00FF)) setcarry();
        else clearcarry();
    if (x == (uint8_t)(value & 0x00FF)) setzero();
        else clearzero();
    signcalc(result);
}

static void cpy() {
    value = getvalue();
    result = (uint16_t)y - value;

    if (y >= (uint8_t)(value & 0x00FF)) setcarry();
        else clearcarry();
    if (y == (uint8_t)(value & 0x00FF)) setzero();
        else clearzero();
    signcalc(result);
}

static void dec() {
    value = getvalue();
    result = value - 1;

    zerocalc(result);
    signcalc(result);

    putvalue(result);
}

static void dex() {
    x--;

    zerocalc(x);
    signcalc(x);
}

static void dey() {
    y--;

    zerocalc(y);
    signcalc(y);
}

static void eor() {
    penaltyop = 1;
    value = getvalue();
    result = (uint16_t)a ^ value;

    zerocalc(result);
    signcalc(result);

    saveaccum(result);
}

static void inc() {
    value = getvalue();
    result = value + 1;

    zerocalc(result);
    signcalc(result);

    putvalue(result);
}

static void inx() {
    x++;

    zerocalc(x);
    signcalc(x);
}

static void iny() {
    y++;

    zerocalc(y);
    signcalc(y);
}

static void jmp() {
    pc = ea;
}

static void jsr() {
    push16(pc - 1);
    pc = ea;
}

static void lda() {
    penaltyop = 1;
    value = getvalue();
    a = (uint8_t)(value & 0x00FF);

    zerocalc(a);
    signcalc(a);
}

static void ldx() {
    penaltyop = 1;
    value = getvalue();
    x = (uint8_t)(value & 0x00FF);

    zerocalc(x);
    signcalc(x);
}

static void ldy() {
    penaltyop = 1;
    value = getvalue();
    y = (uint8_t)(value & 0x00FF);

    zerocalc(y);
    signcalc(y);
}

static void lsr() {
    value = getvalue();
    result = value >> 1;

    if (value & 1) setcarry();
        else clearcarry();
    zerocalc(result);
    signcalc(result);

    putvalue(result);
}

static void nop() {
    switch (opcode) {
        case 0x1C:
        case 0x3C:
        case 0x5C:
        case 0x7C:
        case 0xDC:
        case 0xFC:
            penaltyop = 1;
            break;
    }
}

static void ora() {
    penaltyop = 1;
    value = getvalue();
    result = (uint16_t)a | value;

    zerocalc(result);
    signcalc(result);

    saveaccum(result);
}

static void pha() {
    push8(a);
}

static void php() {
    push8(status | FLAG_BREAK);
}

static void pla() {
    a = pull8();

    zerocalc(a);
    signcalc(a);
}

static void plp() {
    status = pull8() | FLAG_CONSTANT;
}

static void rol() {
    value = getvalue();
    result = (value << 1) | (status & FLAG_CARRY);

    carrycalc(result);
    zerocalc(result);
    signcalc(result);

    putvalue(result);
}

static void ror() {
    value = getvalue();
    result = (value >> 1) | ((status & FLAG_CARRY) << 7);

    if (value & 1) setcarry();
        else clearcarry();
    zerocalc(result);
    signcalc(result);

    putvalue(result);
}

static void rti() {
    status = pull8();
    value = pull16();
    pc = value;
}

static void rts() {
    value = pull16();
    pc = value + 1;
}

static void sbc() {
    penaltyop = 1;
    value = getvalue() ^ 0x00FF;
    result = (uint16_t)a + value + (uint16_t)(status & FLAG_CARRY);

    carrycalc(result);
    zerocalc(result);
    overflowcalc(result, a, value);
    signcalc(result);

    #ifndef NES_CPU
    if (status & FLAG_DECIMAL) {
        clearcarry();

        a -= 0x66;
        if ((a & 0x0F) > 0x09) {
            a += 0x06;
        }
        if ((a & 0xF0) > 0x90) {
            a += 0x60;
            setcarry();
        }

        clockticks6502++;
    }
    #endif

    saveaccum(result);
}

static void sec() {
    setcarry();
}

static void sed() {
    setdecimal();
}

static void sei() {
    setinterrupt();
}

static void sta() {
    putvalue(a);
}

static void stx() {
    putvalue(x);
}

static void sty() {
    putvalue(y);
}

static void tax() {
    x = a;

    zerocalc(x);
    signcalc(x);
}

static void tay() {
    y = a;

    zerocalc(y);
    signcalc(y);
}

static void tsx() {
    x = sp;

    zerocalc(x);
    signcalc(x);
}

static void txa() {
    a = x;

    zerocalc(a);
    signcalc(a);
}

static void txs() {
    sp = x;
}

static void tya() {
    a = y;

    zerocalc(a);
    signcalc(a);
}

//undocumented instructions
#ifdef UNDOCUMENTED
    static void lax() {
        lda();
        ldx();
    }

    static void sax() {
        sta();
        stx();
        putvalue(a & x);
        if (penaltyop && penaltyaddr) clockticks6502--;
    }

    static void dcp() {
        dec();
        cmp();
        if (penaltyop && penaltyaddr) clockticks6502--;
    }

    static void isb() {
        inc();
        sbc();
        if (penaltyop && penaltyaddr) clockticks6502--;
    }

    static void slo() {
        asl();
        ora();
        if (penaltyop && penaltyaddr) clockticks6502--;
    }

    static void rla() {
        rol();
        and();
        if (penaltyop && penaltyaddr) clockticks6502--;
    }

    static void sre() {
        lsr();
        eor();
        if (penaltyop && penaltyaddr) clockticks6502--;
    }

    static void rra() {
        ror();
        adc();
        if (penaltyop && penaltyaddr) clockticks6502--;
    }
#else
    #define lax nop
    #define sax nop
    #define dcp nop
    #define isb nop
    #define slo nop
    #define rla nop
    #define sre nop
    #define rra nop
#endif


static void (*addrtable[256])() = {
/*         |  0  |  1  |  2  |  3  |  4  |  5  |  6  |  7  |  8  |  9  |  A  |  B  |  C  |  D  |  E  |  F  |     */
/* 0 */      imp, indx,  imp, indx,   zp,   zp,   zp,   zp,  imp,  imm,  acc,  imm, abso, abso, abso, abso, /* 0 */
/* 1 */      rel, indy,  imp, indy,  zpx,  zpx,  zpx,  zpx,  imp, absy,  imp, absy, absx, absx, absx, absx, /* 1 */
/* 2 */     abso, indx,  imp, indx,   zp,   zp,   zp,   zp,  imp,  imm,  acc,  imm, abso, abso, abso, abso, /* 2 */
/* 3 */      rel, indy,  imp, indy,  zpx,  zpx,  zpx,  zpx,  imp, absy,  imp, absy, absx, absx, absx, absx, /* 3 */
/* 4 */      imp, indx,  imp, indx,   zp,   zp,   zp,   zp,  imp,  imm,  acc,  imm, abso, abso, abso, abso, /* 4 */
/* 5 */      rel, indy,  imp, indy,  zpx,  zpx,  zpx,  zpx,  imp, absy,  imp, absy, absx, absx, absx, absx, /* 5 */
/* 6 */      imp, indx,  imp, indx,   zp,   zp,   zp,   zp,  imp,  imm,  acc,  imm,  ind, abso, abso, abso, /* 6 */
/* 7 */      rel, indy,  imp, indy,  zpx,  zpx,  zpx,  zpx,  imp, absy,  imp, absy, absx, absx, absx, absx, /* 7 */
/* 8 */      imm, indx,  imm, indx,   zp,   zp,   zp,   zp,  imp,  imm,  imp,  imm, abso, abso, abso, abso, /* 8 */
/* 9 */      rel, indy,  imp, indy,  zpx,  zpx,  zpy,  zpy,  imp, absy,  imp, absy, absx, absx, absy, absy, /* 9 */
/* A */      imm, indx,  imm, indx,   zp,   zp,   zp,   zp,  imp,  imm,  imp,  imm, abso, abso, abso, abso, /* A */
/* B */      rel, indy,  imp, indy,  zpx,  zpx,  zpy,  zpy,  imp, absy,  imp, absy, absx, absx, absy, absy, /* B */
/* C */      imm, indx,  imm, indx,   zp,   zp,   zp,   zp,  imp,  imm,  imp,  imm, abso, abso, abso, abso, /* C */
/* D */      rel, indy,  imp, indy,  zpx,  zpx,  zpx,  zpx,  imp, absy,  imp, absy, absx, absx, absx, absx, /* D */
/* E */      imm, indx,  imm, indx,   zp,   zp,   zp,   zp,  imp,  imm,  imp,  imm, abso, abso, abso, abso, /* E */
/* F */      rel, indy,  imp, indy,  zpx,  zpx,  zpx,  zpx,  imp, absy,  imp, absy, absx, absx, absx, absx  /* F */
};

static void (*optable[256])() = {
/*        |  0  |  1  |  2  |  3  |  4  |  5  |  6  |  7  |  8  |  9  |  A  |  B  |  C  |  D  |  E  |  F  |      */
/* 0 */ brk_insn,  ora,  nop,  slo,  nop,  ora,  asl,  slo,  php,  ora,  asl,  nop,  nop,  ora,  asl,  slo, /* 0 */
/* 1 */      bpl,  ora,  nop,  slo,  nop,  ora,  asl,  slo,  clc,  ora,  nop,  slo,  nop,  ora,  asl,  slo, /* 1 */
/* 2 */      jsr,  and,  nop,  rla,  bit,  and,  rol,  rla,  plp,  and,  rol,  nop,  bit,  and,  rol,  rla, /* 2 */
/* 3 */      bmi,  and,  nop,  rla,  nop,  and,  rol,  rla,  sec,  and,  nop,  rla,  nop,  and,  rol,  rla, /* 3 */
/* 4 */      rti,  eor,  nop,  sre,  nop,  eor,  lsr,  sre,  pha,  eor,  lsr,  nop,  jmp,  eor,  lsr,  sre, /* 4 */
/* 5 */      bvc,  eor,  nop,  sre,  nop,  eor,  lsr,  sre,  cli,  eor,  nop,  sre,  nop,  eor,  lsr,  sre, /* 5 */
/* 6 */      rts,  adc,  nop,  rra,  nop,  adc,  ror,  rra,  pla,  adc,  ror,  nop,  jmp,  adc,  ror,  rra, /* 6 */
/* 7 */      bvs,  adc,  nop,  rra,  nop,  adc,  ror,  rra,  sei,  adc,  nop,  rra,  nop,  adc,  ror,  rra, /* 7 */
/* 8 */      nop,  sta,  nop,  sax,  sty,  sta,  stx,  sax,  dey,  nop,  txa,  nop,  sty,  sta,  stx,  sax, /* 8 */
/* 9 */      bcc,  sta,  nop,  nop,  sty,  sta,  stx,  sax,  tya,  sta,  txs,  nop,  nop,  sta,  nop,  nop, /* 9 */
/* A */      ldy,  lda,  ldx,  lax,  ldy,  lda,  ldx,  lax,  tay,  lda,  tax,  nop,  ldy,  lda,  ldx,  lax, /* A */
/* B */      bcs,  lda,  nop,  lax,  ldy,  lda,  ldx,  lax,  clv,  lda,  tsx,  lax,  ldy,  lda,  ldx,  lax, /* B */
/* C */      cpy,  cmp,  nop,  dcp,  cpy,  cmp,  dec,  dcp,  iny,  cmp,  dex,  nop,  cpy,  cmp,  dec,  dcp, /* C */
/* D */      bne,  cmp,  nop,  dcp,  nop,  cmp,  dec,  dcp,  cld,  cmp,  nop,  dcp,  nop,  cmp,  dec,  dcp, /* D */
/* E */      cpx,  sbc,  nop,  isb,  cpx,  sbc,  inc,  isb,  inx,  sbc,  nop,  sbc,  cpx,  sbc,  inc,  isb, /* E */
/* F */      beq,  sbc,  nop,  isb,  nop,  sbc,  inc,  isb,  sed,  sbc,  nop,  isb,  nop,  sbc,  inc,  isb  /* F */
};

static const uint32_t ticktable[256] = {
/*         |  0  |  1  |  2  |  3  |  4  |  5  |  6  |  7  |  8  |  9  |  A  |  B  |  C  |  D  |  E  |  F  |     */
/* 0 */       7,    6,    2,    8,    3,    3,    5,    5,    3,    2,    2,    2,    4,    4,    6,    6,  /* 0 */
/* 1 */       2,    5,    2,    8,    4,    4,    6,    6,    2,    4,    2,    7,    4,    4,    7,    7,  /* 1 */
/* 2 */       6,    6,    2,    8,    3,    3,    5,    5,    4,    2,    2,    2,    4,    4,    6,    6,  /* 2 */
/* 3 */       2,    5,    2,    8,    4,    4,    6,    6,    2,    4,    2,    7,    4,    4,    7,    7,  /* 3 */
/* 4 */       6,    6,    2,    8,    3,    3,    5,    5,    3,    2,    2,    2,    3,    4,    6,    6,  /* 4 */
/* 5 */       2,    5,    2,    8,    4,    4,    6,    6,    2,    4,    2,    7,    4,    4,    7,    7,  /* 5 */
/* 6 */       6,    6,    2,    8,    3,    3,    5,    5,    4,    2,    2,    2,    5,    4,    6,    6,  /* 6 */
/* 7 */       2,    5,    2,    8,    4,    4,    6,    6,    2,    4,    2,    7,    4,    4,    7,    7,  /* 7 */
/* 8 */       2,    6,    2,    6,    3,    3,    3,    3,    2,    2,    2,    2,    4,    4,    4,    4,  /* 8 */
/* 9 */       2,    6,    2,    6,    4,    4,    4,    4,    2,    5,    2,    5,    5,    5,    5,    5,  /* 9 */
/* A */       2,    6,    2,    6,    3,    3,    3,    3,    2,    2,    2,    2,    4,    4,    4,    4,  /* A */
/* B */       2,    5,    2,    5,    4,    4,    4,    4,    2,    4,    2,    4,    4,    4,    4,    4,  /* B */
/* C */       2,    6,    2,    8,    3,    3,    5,    5,    2,    2,    2,    2,    4,    4,    6,    6,  /* C */
/* D */       2,    5,    2,    8,    4,    4,    6,    6,    2,    4,    2,    7,    4,    4,    7,    7,  /* D */
/* E */       2,    6,    2,    8,    3,    3,    5,    5,    2,    2,    2,    2,    4,    4,    6,    6,  /* E */
/* F */       2,    5,    2,    8,    4,    4,    6,    6,    2,    4,    2,    7,    4,    4,    7,    7   /* F */
};


void nmi6502() {
    push16(pc);
    push8(status);
    status |= FLAG_INTERRUPT;
    pc = (uint16_t)read6502(0xFFFA) | ((uint16_t)read6502(0xFFFB) << 8);
}

void irq6502() {
    push16(pc);
    push8(status);
    status |= FLAG_INTERRUPT;
    pc = (uint16_t)read6502(0xFFFE) | ((uint16_t)read6502(0xFFFF) << 8);
}

uint8_t callexternal = 0;
void (*loopexternal)();

void exec6502(uint64_t tickcount) {
    clockgoal6502 += tickcount;

    while (clockticks6502 < clockgoal6502) {
        opcode = read6502(pc++);
        status |= FLAG_CONSTANT;

        penaltyop = 0;
        penaltyaddr = 0;

        (*addrtable[opcode])();
        (*optable[opcode])();
        clockticks6502 += ticktable[opcode];
        if (penaltyop && penaltyaddr) clockticks6502++;

        instructions++;

        if (callexternal) (*loopexternal)();
    }

}

void step6502() {
    opcode = read6502(pc++);
    status |= FLAG_CONSTANT;

    penaltyop = 0;
    penaltyaddr = 0;

    (*addrtable[opcode])();
    (*optable[opcode])();
    clockticks6502 += ticktable[opcode];
    if (penaltyop && penaltyaddr) clockticks6502++;
    clockgoal6502 = clockticks6502;

    instructions++;

    if (callexternal) (*loopexternal)();
}

void hookexternal(void *funcptr) {
    if (funcptr != (void *)NULL) {
        loopexternal = funcptr;
        callexternal = 1;
    } else callexternal = 0;
}

////////////////////////////////////////


#define port_read_b  0xf004
#define port_write_b 0xf001
#define port_write_d 0xf002
#define port_exit    0xf003
#define port_open    0xf005
#define port_close   0xf000
#define port_read    0xfe85
#define port_argc    0xfe80
#define port_argv_l  0xfe81
#define port_argv_h  0xfe82
#define port_openout 0xfe83
#define port_write   0xfe84
#define port_con_read  0xfe90
#define port_con_flush 0xfe91
#define port_term_rows 0xfe92
#define port_term_cols 0xfe93
#define port_con_ready 0xfe94
#define port_serial_ready       0xfe95
#define port_serial_data        0xfe96
#define port_serial_write       0xfe97
#define port_serial_write_ready 0xfe98
#define port_eof_b   0xfe99
#define port_eof     0xfe9a
#define port_opendir 0xfe9b

uint8_t memory[0x10001];

FILE* files[255];

typedef struct {
    char *buffer;
    size_t buf_size;
    size_t buf_pos;
} DirState;

DirState *dir_state[255];

FILE* input_file_ptr;
FILE* output_file_ptr;
int con_eof_flag = 0;

int arg_count;
uint16_t* arg_addresses;

int done = 0;
int exitcode_set = -1;
int error_output_started = 0;  // Track if emulated program wrote to stderr
int console_mode = 0;
int terminal_mode = 0;
int terminal_interactive = 0;
FILE* serial_input_file = NULL;
FILE* serial_output_file = NULL;
double target_mhz = 0.0;
double cpu_mhz = 0.0;
int serial_baud = 0;
uint64_t serial_cycles_per_byte = 0;

// Serial buffering - simulates hardware FIFOs
// RX: characters fill from source at baud rate, CPU reads instantly from buffer
// TX: CPU writes instantly to buffer, bytes drain to output at baud rate
#define SERIAL_BUF_SIZE 256
static uint8_t serial_rx_buf[SERIAL_BUF_SIZE];
static int serial_rx_head = 0;  // next write position
static int serial_rx_tail = 0;  // next read position
static uint64_t serial_rx_next_fill_at = 0;

static uint8_t serial_tx_buf[SERIAL_BUF_SIZE];
static int serial_tx_head = 0;
static int serial_tx_tail = 0;
static uint64_t serial_tx_next_drain_at = 0;
int override_rows = 0;
int override_cols = 0;
struct termios orig_termios;
struct timespec start_time;
static volatile sig_atomic_t sigint_requested = 0;
static volatile sig_atomic_t sigtstp_requested = 0;
static volatile sig_atomic_t sigcont_requested = 0;
static int termios_saved = 0;
static int screen_rows = 0;
static int screen_cols = 0;
static char *screen_cells = NULL;
static unsigned char *screen_attr = NULL;
static int cursor_row = 0;
static int cursor_col = 0;
static int parser_state = 0;
static int csi_params[8];
static int csi_param_count = 0;
static int csi_param_value = -1;
static int csi_private = 0;
static unsigned char current_attr = 0;
static int scroll_top = 0;       // 0-based top row of scroll region
static int scroll_bot = -1;      // 0-based bottom row (-1 = use screen_rows-1)
static char serial_inject_buf[32];
static int serial_inject_pos = 0;
static int serial_inject_len = 0;
int show_repaints = 0;
int server_mode = 0;
static struct timespec *repaint_time = NULL;
static unsigned char *repaint_count = NULL;
static unsigned char *repaint_displayed = NULL;  // currently displayed background color (0=none, 1-7=rainbow index+1)
static struct timespec last_repaint_check;

void get_terminal_size(int *rows, int *cols);
void console_resize(int rows, int cols);
void console_redraw();

int terminal_restored = 0;

void restore_terminal() {
    if (terminal_restored) return;
    terminal_restored = 1;
    if (console_mode || terminal_mode) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
        const char seq[] = "\x1b[?1049l\x1b[?25h\x1b[0m";
        if (write(STDOUT_FILENO, seq, sizeof(seq) - 1) < 0) {
        }
    }
}

void setup_raw_terminal() {
    if (!termios_saved) {
        tcgetattr(STDIN_FILENO, &orig_termios);
        termios_saved = 1;
    }
    const char enter_seq[] = "\x1b[?1049h";
    if (write(STDOUT_FILENO, enter_seq, sizeof(enter_seq) - 1) < 0) {
    }
    struct termios raw = orig_termios;
    cfmakeraw(&raw);
    raw.c_lflag |= ISIG;  // Keep Ctrl+C working for safety
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    terminal_restored = 0;
}

void enter_console() {
    int rows, cols;
    get_terminal_size(&rows, &cols);
    console_resize(rows, cols);
    setup_raw_terminal();
}

void handle_sigint(int sig) {
    (void)sig;
    sigint_requested = 1;
}

void handle_sigtstp(int sig) {
    (void)sig;
    sigtstp_requested = 1;
}

void handle_sigcont(int sig) {
    (void)sig;
    sigcont_requested = 1;
}

void console_resize(int rows, int cols) {
    if (rows <= 0 || cols <= 0) return;
    if (rows == screen_rows && cols == screen_cols && screen_cells != NULL) return;
    size_t sz = (size_t)rows * (size_t)cols;
    char *new_cells = malloc(sz);
    unsigned char *new_attr = malloc(sz);
    if (!new_cells) return;
    if (!new_attr) {
        free(new_cells);
        return;
    }
    memset(new_cells, ' ', sz);
    memset(new_attr, 0, sz);

    struct timespec *new_rtime = NULL;
    unsigned char *new_rcount = NULL;
    unsigned char *new_rdisp = NULL;
    if (show_repaints) {
        new_rtime = calloc(sz, sizeof(struct timespec));
        new_rcount = calloc(sz, 1);
        new_rdisp = calloc(sz, 1);
    }

    if (screen_cells) {
        int copy_rows = rows < screen_rows ? rows : screen_rows;
        int copy_cols = cols < screen_cols ? cols : screen_cols;
        for (int r = 0; r < copy_rows; r++) {
            memcpy(new_cells + r * cols, screen_cells + r * screen_cols, (size_t)copy_cols);
            memcpy(new_attr + r * cols, screen_attr + r * screen_cols, (size_t)copy_cols);
            if (show_repaints && repaint_time && new_rtime) {
                memcpy(new_rtime + r * cols, repaint_time + r * screen_cols, (size_t)copy_cols * sizeof(struct timespec));
                memcpy(new_rcount + r * cols, repaint_count + r * screen_cols, (size_t)copy_cols);
            }
        }
        free(screen_cells);
        free(screen_attr);
        free(repaint_time);
        free(repaint_count);
        free(repaint_displayed);
    }
    screen_cells = new_cells;
    screen_attr = new_attr;
    repaint_time = new_rtime;
    repaint_count = new_rcount;
    repaint_displayed = new_rdisp;
    screen_rows = rows;
    screen_cols = cols;
    scroll_top = 0;
    scroll_bot = screen_rows - 1;
    if (cursor_row >= screen_rows) cursor_row = screen_rows - 1;
    if (cursor_row < 0) cursor_row = 0;
    if (cursor_col >= screen_cols) cursor_col = screen_cols - 1;
    if (cursor_col < 0) cursor_col = 0;
}

void console_clear_line(int mode) {
    if (!screen_cells || screen_rows <= 0 || screen_cols <= 0) return;
    if (mode == 1) {
        int end = cursor_col + 1;
        if (end > screen_cols) end = screen_cols;
        memset(screen_cells + cursor_row * screen_cols, ' ', (size_t)end);
        memset(screen_attr + cursor_row * screen_cols, 0, (size_t)end);
        if (repaint_time) {
            memset(repaint_time + cursor_row * screen_cols, 0, (size_t)end * sizeof(struct timespec));
            memset(repaint_count + cursor_row * screen_cols, 0, (size_t)end);
        }
    } else if (mode == 2) {
        memset(screen_cells + cursor_row * screen_cols, ' ', (size_t)screen_cols);
        memset(screen_attr + cursor_row * screen_cols, 0, (size_t)screen_cols);
        if (repaint_time) {
            memset(repaint_time + cursor_row * screen_cols, 0, (size_t)screen_cols * sizeof(struct timespec));
            memset(repaint_count + cursor_row * screen_cols, 0, (size_t)screen_cols);
        }
    } else {
        int start = cursor_col;
        if (start < 0) start = 0;
        if (start < screen_cols) {
            memset(screen_cells + cursor_row * screen_cols + start, ' ', (size_t)(screen_cols - start));
            memset(screen_attr + cursor_row * screen_cols + start, 0, (size_t)(screen_cols - start));
            if (repaint_time) {
                memset(repaint_time + cursor_row * screen_cols + start, 0, (size_t)(screen_cols - start) * sizeof(struct timespec));
                memset(repaint_count + cursor_row * screen_cols + start, 0, (size_t)(screen_cols - start));
            }
        }
    }
}

void console_clear_screen(int mode) {
    if (!screen_cells || screen_rows <= 0 || screen_cols <= 0) return;
    size_t full = (size_t)screen_rows * (size_t)screen_cols;
    if (mode == 1) {
        for (int r = 0; r < cursor_row; r++) {
            memset(screen_cells + r * screen_cols, ' ', (size_t)screen_cols);
            memset(screen_attr + r * screen_cols, 0, (size_t)screen_cols);
            if (repaint_time) {
                memset(repaint_time + r * screen_cols, 0, (size_t)screen_cols * sizeof(struct timespec));
                memset(repaint_count + r * screen_cols, 0, (size_t)screen_cols);
            }
        }
        int end = cursor_col + 1;
        if (end > screen_cols) end = screen_cols;
        memset(screen_cells + cursor_row * screen_cols, ' ', (size_t)end);
        memset(screen_attr + cursor_row * screen_cols, 0, (size_t)end);
        if (repaint_time) {
            memset(repaint_time + cursor_row * screen_cols, 0, (size_t)end * sizeof(struct timespec));
            memset(repaint_count + cursor_row * screen_cols, 0, (size_t)end);
        }
    } else if (mode == 2 || mode == 3) {
        memset(screen_cells, ' ', full);
        memset(screen_attr, 0, full);
        if (repaint_time) {
            memset(repaint_time, 0, full * sizeof(struct timespec));
            memset(repaint_count, 0, full);
        }
    } else {
        int start = cursor_col;
        if (start < 0) start = 0;
        if (start < screen_cols) {
            memset(screen_cells + cursor_row * screen_cols + start, ' ', (size_t)(screen_cols - start));
            memset(screen_attr + cursor_row * screen_cols + start, 0, (size_t)(screen_cols - start));
            if (repaint_time) {
                memset(repaint_time + cursor_row * screen_cols + start, 0, (size_t)(screen_cols - start) * sizeof(struct timespec));
                memset(repaint_count + cursor_row * screen_cols + start, 0, (size_t)(screen_cols - start));
            }
        }
        for (int r = cursor_row + 1; r < screen_rows; r++) {
            memset(screen_cells + r * screen_cols, ' ', (size_t)screen_cols);
            memset(screen_attr + r * screen_cols, 0, (size_t)screen_cols);
            if (repaint_time) {
                memset(repaint_time + r * screen_cols, 0, (size_t)screen_cols * sizeof(struct timespec));
                memset(repaint_count + r * screen_cols, 0, (size_t)screen_cols);
            }
        }
    }
}

void console_scroll_region_up(int top, int bot, int lines) {
    if (!screen_cells || screen_rows <= 0 || screen_cols <= 0) return;
    if (lines <= 0 || top > bot) return;
    int region_rows = bot - top + 1;
    size_t row_bytes = (size_t)screen_cols;
    if (lines >= region_rows) {
        for (int r = top; r <= bot; r++) {
            memset(screen_cells + r * row_bytes, ' ', row_bytes);
            memset(screen_attr + r * row_bytes, 0, row_bytes);
        }
        if (repaint_time) {
            for (int r = top; r <= bot; r++) {
                memset(repaint_time + r * screen_cols, 0, row_bytes * sizeof(struct timespec));
                memset(repaint_count + r * screen_cols, 0, row_bytes);
                memset(repaint_displayed + r * screen_cols, 0, row_bytes);
            }
        }
        return;
    }
    size_t keep = (size_t)(region_rows - lines) * row_bytes;
    size_t clear = (size_t)lines * row_bytes;
    memmove(screen_cells + top * row_bytes, screen_cells + (top + lines) * row_bytes, keep);
    memmove(screen_attr + top * row_bytes, screen_attr + (top + lines) * row_bytes, keep);
    memset(screen_cells + (bot - lines + 1) * row_bytes, ' ', clear);
    memset(screen_attr + (bot - lines + 1) * row_bytes, 0, clear);
    if (repaint_time) {
        memmove(repaint_time + top * screen_cols, repaint_time + (top + lines) * screen_cols, keep * sizeof(struct timespec));
        memmove(repaint_count + top * screen_cols, repaint_count + (top + lines) * screen_cols, keep);
        memmove(repaint_displayed + top * screen_cols, repaint_displayed + (top + lines) * screen_cols, keep);
        memset(repaint_time + (bot - lines + 1) * screen_cols, 0, clear * sizeof(struct timespec));
        memset(repaint_count + (bot - lines + 1) * screen_cols, 0, clear);
        memset(repaint_displayed + (bot - lines + 1) * screen_cols, 0, clear);
    }
}

void console_scroll_region_down(int top, int bot, int lines) {
    if (!screen_cells || screen_rows <= 0 || screen_cols <= 0) return;
    if (lines <= 0 || top > bot) return;
    int region_rows = bot - top + 1;
    size_t row_bytes = (size_t)screen_cols;
    if (lines >= region_rows) {
        for (int r = top; r <= bot; r++) {
            memset(screen_cells + r * row_bytes, ' ', row_bytes);
            memset(screen_attr + r * row_bytes, 0, row_bytes);
        }
        if (repaint_time) {
            for (int r = top; r <= bot; r++) {
                memset(repaint_time + r * screen_cols, 0, row_bytes * sizeof(struct timespec));
                memset(repaint_count + r * screen_cols, 0, row_bytes);
                memset(repaint_displayed + r * screen_cols, 0, row_bytes);
            }
        }
        return;
    }
    size_t keep = (size_t)(region_rows - lines) * row_bytes;
    size_t clear = (size_t)lines * row_bytes;
    memmove(screen_cells + (top + lines) * row_bytes, screen_cells + top * row_bytes, keep);
    memmove(screen_attr + (top + lines) * row_bytes, screen_attr + top * row_bytes, keep);
    memset(screen_cells + top * row_bytes, ' ', clear);
    memset(screen_attr + top * row_bytes, 0, clear);
    if (repaint_time) {
        memmove(repaint_time + (top + lines) * screen_cols, repaint_time + top * screen_cols, keep * sizeof(struct timespec));
        memmove(repaint_count + (top + lines) * screen_cols, repaint_count + top * screen_cols, keep);
        memmove(repaint_displayed + (top + lines) * screen_cols, repaint_displayed + top * screen_cols, keep);
        memset(repaint_time + top * screen_cols, 0, clear * sizeof(struct timespec));
        memset(repaint_count + top * screen_cols, 0, clear);
        memset(repaint_displayed + top * screen_cols, 0, clear);
    }
}

void console_scroll_up(int lines) {
    console_scroll_region_up(0, screen_rows - 1, lines);
}

void console_put_char(unsigned char ch) {
    if (!screen_cells || screen_rows <= 0 || screen_cols <= 0) return;
    int ebot = (scroll_bot >= 0 && scroll_bot < screen_rows) ? scroll_bot : screen_rows - 1;
    if (cursor_row < 0) cursor_row = 0;
    if (cursor_row >= screen_rows) {
        console_scroll_region_up(scroll_top, ebot, 1);
        cursor_row = screen_rows - 1;
    }
    if (cursor_col < 0) cursor_col = 0;
    if (cursor_col >= screen_cols) {
        cursor_col = 0;
        cursor_row++;
        if (cursor_row > ebot) {
            console_scroll_region_up(scroll_top, ebot, 1);
            cursor_row = ebot;
        } else if (cursor_row >= screen_rows) {
            cursor_row = screen_rows - 1;
        }
    }
    int idx = cursor_row * screen_cols + cursor_col;
    screen_cells[idx] = (char)ch;
    screen_attr[idx] = current_attr;
    if (repaint_time) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double age = (now.tv_sec - repaint_time[idx].tv_sec)
                   + (now.tv_nsec - repaint_time[idx].tv_nsec) / 1e9;
        if (repaint_time[idx].tv_sec != 0 && age < 2.0) {
            if (repaint_count[idx] < 6)
                repaint_count[idx]++;
        } else
            repaint_count[idx] = 0;
        repaint_time[idx] = now;
        repaint_displayed[idx] = 0;
    }
    cursor_col++;
    if (cursor_col >= screen_cols) {
        cursor_col = 0;
        cursor_row++;
        if (cursor_row > ebot) {
            console_scroll_region_up(scroll_top, ebot, 1);
            cursor_row = ebot;
        } else if (cursor_row >= screen_rows) {
            cursor_row = screen_rows - 1;
        }
    }
}

// Forward declarations for buffer functions
int con_byte_ready();
void console_handle_byte(unsigned char ch);

static int serial_rx_count() {
    return (serial_rx_head - serial_rx_tail + SERIAL_BUF_SIZE) % SERIAL_BUF_SIZE;
}

static int serial_tx_count() {
    return (serial_tx_head - serial_tx_tail + SERIAL_BUF_SIZE) % SERIAL_BUF_SIZE;
}

// Fill RX buffer from input source at baud rate.
// Characters arrive from the "wire" at baud rate intervals and queue in the
// hardware FIFO. The CPU can then read them out as fast as it wants.
void serial_rx_fill() {
    int filled = 0;
    while (clockticks6502 >= serial_rx_next_fill_at &&
           serial_rx_count() < SERIAL_BUF_SIZE - 1) {
        int ch = -1;
        if (terminal_interactive) {
            if (!con_byte_ready()) break;
            uint8_t b;
            int got = read(STDIN_FILENO, &b, 1);
            if (got != 1) break;
            ch = b;
        } else if (serial_input_file) {
            ch = fgetc(serial_input_file);
            if (ch == EOF) break;
        } else {
            break;
        }
        serial_rx_buf[serial_rx_head] = (uint8_t)ch;
        serial_rx_head = (serial_rx_head + 1) % SERIAL_BUF_SIZE;
        serial_rx_next_fill_at += serial_cycles_per_byte;
        filled = 1;
    }
    // Prevent credit accumulation: when no input was available and the CPU
    // has been running (e.g. idle-polling), advance the fill timestamp so
    // future RX bytes arrive at baud rate from "now".
    if (!filled && serial_rx_next_fill_at < clockticks6502) {
        serial_rx_next_fill_at = clockticks6502;
    }
}

// Drain TX buffer to output at baud rate.
// Bytes leave the FIFO onto the "wire" at baud rate intervals.
// The CPU can fill the buffer as fast as it wants.
void serial_tx_drain() {
    while (clockticks6502 >= serial_tx_next_drain_at &&
           serial_tx_head != serial_tx_tail) {
        uint8_t b = serial_tx_buf[serial_tx_tail];
        serial_tx_tail = (serial_tx_tail + 1) % SERIAL_BUF_SIZE;
        if (terminal_interactive) {
            if (write(STDOUT_FILENO, &b, 1) < 0) {}
        } else if (serial_output_file) {
            fputc(b, serial_output_file);
        }
        if (terminal_mode) {
            console_handle_byte(b);
        }
        serial_tx_next_drain_at += serial_cycles_per_byte;
    }
    // Prevent credit accumulation: when the TX buffer is empty and the CPU
    // has been running (e.g. idle-polling for input), advance the drain
    // timestamp so future TX bytes drain at baud rate from "now", not from
    // the distant past.
    if (serial_tx_head == serial_tx_tail && serial_tx_next_drain_at < clockticks6502) {
        serial_tx_next_drain_at = clockticks6502;
    }
}

// Flush any remaining bytes in TX buffer (called at exit)
void serial_tx_flush() {
    while (serial_tx_head != serial_tx_tail) {
        uint8_t b = serial_tx_buf[serial_tx_tail];
        serial_tx_tail = (serial_tx_tail + 1) % SERIAL_BUF_SIZE;
        if (terminal_interactive) {
            if (write(STDOUT_FILENO, &b, 1) < 0) {}
        } else if (serial_output_file) {
            fputc(b, serial_output_file);
        }
        if (terminal_mode) {
            console_handle_byte(b);
        }
    }
}

void serial_inject_response(const char *str) {
    int len = (int)strlen(str);
    if (len > (int)sizeof(serial_inject_buf) - serial_inject_len) {
        len = (int)sizeof(serial_inject_buf) - serial_inject_len;
    }
    memcpy(serial_inject_buf + serial_inject_len, str, (size_t)len);
    serial_inject_len += len;
}

void console_handle_csi(unsigned char final) {
    if (csi_private) {
        csi_private = 0;
        return;
    }
    int params[8];
    int count = 0;
    for (int i = 0; i < csi_param_count && i < 8; i++) params[i] = csi_params[i];
    count = csi_param_count;
    if (count == 0) {
        params[0] = 0;
        count = 1;
    }
    switch (final) {
        case 'A': { // CUU
            int n = params[0] ? params[0] : 1;
            cursor_row -= n;
            if (cursor_row < 0) cursor_row = 0;
            break;
        }
        case 'B': { // CUD
            int n = params[0] ? params[0] : 1;
            cursor_row += n;
            if (cursor_row >= screen_rows) cursor_row = screen_rows - 1;
            break;
        }
        case 'C': { // CUF
            int n = params[0] ? params[0] : 1;
            cursor_col += n;
            if (cursor_col >= screen_cols) cursor_col = screen_cols - 1;
            break;
        }
        case 'D': { // CUB
            int n = params[0] ? params[0] : 1;
            cursor_col -= n;
            if (cursor_col < 0) cursor_col = 0;
            break;
        }
        case 'E': { // CNL
            int n = params[0] ? params[0] : 1;
            cursor_row += n;
            if (cursor_row >= screen_rows) cursor_row = screen_rows - 1;
            cursor_col = 0;
            break;
        }
        case 'F': { // CPL
            int n = params[0] ? params[0] : 1;
            cursor_row -= n;
            if (cursor_row < 0) cursor_row = 0;
            cursor_col = 0;
            break;
        }
        case 'G': { // CHA
            int n = params[0] ? params[0] : 1;
            cursor_col = n - 1;
            if (cursor_col < 0) cursor_col = 0;
            if (cursor_col >= screen_cols) cursor_col = screen_cols - 1;
            break;
        }
        case 'H':
        case 'f': { // CUP
            int r = (count > 0 && params[0] ? params[0] : 1) - 1;
            int c = (count > 1 && params[1] ? params[1] : 1) - 1;
            if (r < 0) r = 0;
            if (c < 0) c = 0;
            if (r >= screen_rows) r = screen_rows - 1;
            if (c >= screen_cols) c = screen_cols - 1;
            cursor_row = r;
            cursor_col = c;
            break;
        }
        case 'J': { // ED
            console_clear_screen(params[0]);
            break;
        }
        case 'K': { // EL
            console_clear_line(params[0]);
            break;
        }
        case 'n': { // DSR
            if (params[0] == 6) {
                char buf[32];
                snprintf(buf, sizeof(buf), "\x1b[%d;%dR", cursor_row + 1, cursor_col + 1);
                serial_inject_response(buf);
            }
            break;
        }
        case 'r': { // DECSTBM - Set Top and Bottom Margins
            if (count >= 2 && params[0] > 0 && params[1] > 0) {
                scroll_top = params[0] - 1;
                scroll_bot = params[1] - 1;
                if (scroll_top < 0) scroll_top = 0;
                if (scroll_bot >= screen_rows) scroll_bot = screen_rows - 1;
                if (scroll_top > scroll_bot) {
                    scroll_top = 0;
                    scroll_bot = screen_rows - 1;
                }
            } else {
                scroll_top = 0;
                scroll_bot = screen_rows - 1;
            }
            break;
        }
        case 'S': { // SU - Scroll Up
            int n = params[0] ? params[0] : 1;
            int ebot = (scroll_bot >= 0 && scroll_bot < screen_rows) ? scroll_bot : screen_rows - 1;
            console_scroll_region_up(scroll_top, ebot, n);
            break;
        }
        case 'T': { // SD - Scroll Down
            int n = params[0] ? params[0] : 1;
            int ebot = (scroll_bot >= 0 && scroll_bot < screen_rows) ? scroll_bot : screen_rows - 1;
            console_scroll_region_down(scroll_top, ebot, n);
            break;
        }
        case 'm': { // SGR
            for (int i = 0; i < count; i++) {
                int p = params[i];
                if (p == 0) {
                    current_attr = 0;
                } else if (p == 7) {
                    current_attr = 1;
                } else if (p == 27) {
                    current_attr = 0;
                }
            }
            break;
        }
        default:
            break;
    }
}

void console_handle_byte(unsigned char ch) {
    if (parser_state == 0) {
        if (ch == 0x1b) {
            parser_state = 1;
            return;
        }
        if (ch == '\r') {
            cursor_col = 0;
            return;
        }
        if (ch == '\n') {
            int ebot = (scroll_bot >= 0 && scroll_bot < screen_rows) ? scroll_bot : screen_rows - 1;
            cursor_row++;
            if (cursor_row > ebot) {
                console_scroll_region_up(scroll_top, ebot, 1);
                cursor_row = ebot;
            } else if (cursor_row >= screen_rows) {
                cursor_row = screen_rows - 1;
            }
            return;
        }
        if (ch == '\b') {
            cursor_col--;
            if (cursor_col < 0) cursor_col = 0;
            return;
        }
        if (ch == '\t') {
            int next_tab = (cursor_col + 8) & ~7;
            if (next_tab >= screen_cols) next_tab = screen_cols - 1;
            cursor_col = next_tab;
            return;
        }
        if (ch >= 0x20) {
            console_put_char(ch);
        }
        return;
    }
    if (parser_state == 1) {
        if (ch == '[') {
            parser_state = 2;
            csi_param_count = 0;
            csi_param_value = -1;
            return;
        }
        parser_state = 0;
        return;
    }
    if (parser_state == 2) {
        if (ch == '?' && csi_param_count == 0 && csi_param_value < 0) {
            csi_private = 1;
            return;
        }
        if (ch >= '0' && ch <= '9') {
            if (csi_param_value < 0) csi_param_value = 0;
            csi_param_value = csi_param_value * 10 + (ch - '0');
            return;
        }
        if (ch == ';') {
            if (csi_param_count < 8) {
                csi_params[csi_param_count++] = (csi_param_value < 0) ? 0 : csi_param_value;
            }
            csi_param_value = -1;
            return;
        }
        if (csi_param_count < 8) {
            csi_params[csi_param_count++] = (csi_param_value < 0) ? 0 : csi_param_value;
        }
        console_handle_csi(ch);
        parser_state = 0;
        return;
    }
}

static const unsigned char rainbow_colors[7] = {196, 208, 226, 46, 51, 21, 201};

void repaint_overlay_update(struct timespec *now) {
    if (!repaint_time || !screen_cells) return;
    // Don't inject overlay if the 6502 is mid-ANSI-sequence
    if (parser_state != 0) return;

    // Buffer all output to emit atomically
    // Worst case per cell: cursor pos (12) + bg color (16) + reverse (4) + char (1) + unreverse (5) + bg reset (5) = ~43
    // Plus trailer: reset (4) + restore attr (4) + cursor pos (12) = ~20
    size_t buf_size = (size_t)screen_rows * (size_t)screen_cols * 48 + 64;
    char *buf = malloc(buf_size);
    if (!buf) return;
    size_t pos = 0;
    int any_changed = 0;

    for (int r = 0; r < screen_rows; r++) {
        int run_color = -1;   // current run's desired color (-1 = no active run)
        int run_attr = -1;    // current run's attr
        int last_col = -2;    // last column written (-2 = none)
        for (int c = 0; c < screen_cols; c++) {
            int idx = r * screen_cols + c;
            unsigned char desired = 0;  // 0 = no background
            if (repaint_time[idx].tv_sec != 0) {
                double age = (now->tv_sec - repaint_time[idx].tv_sec)
                           + (now->tv_nsec - repaint_time[idx].tv_nsec) / 1e9;
                if (age < 2.0) {
                    desired = repaint_count[idx] + 1;  // 1-7
                }
            }
            if (desired != repaint_displayed[idx]) {
                any_changed = 1;
                unsigned char attr = screen_attr[idx];
                // Continue current run if consecutive column with same color and attr
                if (c == last_col + 1 && (int)desired == run_color && (int)attr == run_attr) {
                    buf[pos++] = screen_cells[idx];
                } else {
                    // Start a new run: cursor pos + attributes + color
                    pos += (size_t)snprintf(buf + pos, buf_size - pos, "\x1b[%d;%dH", r + 1, c + 1);
                    memcpy(buf + pos, "\x1b[0m", 4); pos += 4;
                    if (attr) {
                        memcpy(buf + pos, "\x1b[7m", 4); pos += 4;
                    }
                    if (desired) {
                        if (attr) {
                            pos += (size_t)snprintf(buf + pos, buf_size - pos, "\x1b[38;5;%dm", rainbow_colors[desired - 1]);
                        } else {
                            pos += (size_t)snprintf(buf + pos, buf_size - pos, "\x1b[48;5;%dm", rainbow_colors[desired - 1]);
                        }
                    }
                    buf[pos++] = screen_cells[idx];
                    run_color = (int)desired;
                    run_attr = (int)attr;
                }
                last_col = c;
                repaint_displayed[idx] = desired;
            } else {
                // Cell doesn't need updating - break the run
                run_color = -1;
                last_col = -2;
            }
        }
    }

    if (any_changed) {
        // Reset all attributes to clean state, then restore 6502's current state
        memcpy(buf + pos, "\x1b[0m", 4); pos += 4;
        if (current_attr) {
            memcpy(buf + pos, "\x1b[7m", 4); pos += 4;
        }
        // Restore cursor to where the 6502 expects it
        pos += (size_t)snprintf(buf + pos, buf_size - pos, "\x1b[%d;%dH", cursor_row + 1, cursor_col + 1);
        if (write(STDOUT_FILENO, buf, pos) < 0) {}
    }
    free(buf);
}

void console_redraw() {
    if (!screen_cells || screen_rows <= 0 || screen_cols <= 0) return;
    unsigned char last_attr = 0;
    const char reset[] = "\x1b[0m";
    if (write(STDOUT_FILENO, reset, sizeof(reset) - 1) < 0) {
    }
    for (int r = 0; r < screen_rows; r++) {
        char pos[32];
        int pos_len = snprintf(pos, sizeof(pos), "\x1b[%d;1H", r + 1);
        if (pos_len > 0) {
            if (write(STDOUT_FILENO, pos, (size_t)pos_len) < 0) {
            }
        }
        for (int c = 0; c < screen_cols; c++) {
            unsigned char attr = screen_attr[r * screen_cols + c];
            if (attr != last_attr) {
                if (attr) {
                    const char rev[] = "\x1b[7m";
                    if (write(STDOUT_FILENO, rev, sizeof(rev) - 1) < 0) {
                    }
                } else {
                    const char norm[] = "\x1b[0m";
                    if (write(STDOUT_FILENO, norm, sizeof(norm) - 1) < 0) {
                    }
                }
                last_attr = attr;
            }
            if (write(STDOUT_FILENO, screen_cells + r * screen_cols + c, 1) < 0) {
            }
        }
    }
    if (current_attr) {
        const char rev[] = "\x1b[7m";
        if (write(STDOUT_FILENO, rev, sizeof(rev) - 1) < 0) {
        }
    } else {
        if (write(STDOUT_FILENO, reset, sizeof(reset) - 1) < 0) {
        }
    }
    char cur[32];
    int len = snprintf(cur, sizeof(cur), "\x1b[%d;%dH", cursor_row + 1, cursor_col + 1);
    if (len > 0) {
        if (write(STDOUT_FILENO, cur, (size_t)len) < 0) {
        }
    }
    if (repaint_displayed) {
        memset(repaint_displayed, 0, (size_t)screen_rows * (size_t)screen_cols);
    }
}

void setup_console() {
    atexit(restore_terminal);
    enter_console();
}

int con_byte_ready() {
    fd_set fds;
    struct timeval tv = {0, 0};
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);
    return select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv) > 0;
}

void get_terminal_size(int *rows, int *cols) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0) {
        *rows = ws.ws_row;
        *cols = ws.ws_col;
    } else {
        *rows = 24;
        *cols = 80;
    }
    if (override_rows > 0) *rows = override_rows;
    if (override_cols > 0) *cols = override_cols;
}

void files_init(FILE* input_file) {
    files[0] = input_file;
    for (size_t x = 1; x != 255; x++) {
        files[x] = NULL;
    }
    for (size_t x = 0; x != 255; x++) {
        dir_state[x] = NULL;
    }
}

uint8_t file_open_with_mode(const char* name, const char* mode) {
    uint8_t x;
    for (x = 1; x != 255; x++) {
        if (files[x] == NULL && dir_state[x] == NULL) {
            FILE* file = fopen(name, mode);
            if (!file) {
                return 0;
            }
	    files[x] = file;
	    return x + 1;
        }
    }
    restore_terminal();
    fprintf(stderr, "could not open file: %s: too many files open\n", name);
    exit(1);
}

uint8_t file_open(const char* name) {
    return file_open_with_mode(name, "rb");
}

uint8_t file_open_for_write(const char* name) {
    return file_open_with_mode(name, "wb");
}

static int dir_filter(const struct dirent *entry) {
    return entry->d_name[0] != '.';
}

uint8_t dir_open(const char* name) {
    uint8_t slot = 0;
    for (uint8_t x = 1; x != 255; x++) {
        if (files[x] == NULL && dir_state[x] == NULL) {
            slot = x; break;
        }
    }
    if (slot == 0) {
        restore_terminal();
        fprintf(stderr, "could not open directory: %s: too many handles open\n", name);
        exit(1);
    }

    struct dirent **namelist;
    int n = scandir(name, &namelist, dir_filter, alphasort);
    if (n < 0) return 0;

    size_t total = 0;
    for (int i = 0; i < n; i++)
        total += 1 + strlen(namelist[i]->d_name) + 1;

    char *buf = malloc(total ? total : 1);
    size_t pos = 0;
    for (int i = 0; i < n; i++) {
        uint8_t meta = 0;
        int is_dir = 0;
        if (namelist[i]->d_type == DT_DIR) {
            is_dir = 1;
        } else if (namelist[i]->d_type == DT_UNKNOWN) {
            char fullpath[PATH_MAX];
            snprintf(fullpath, sizeof(fullpath), "%s/%s", name, namelist[i]->d_name);
            struct stat st;
            if (stat(fullpath, &st) == 0 && S_ISDIR(st.st_mode))
                is_dir = 1;
        }
        if (is_dir) meta |= 0x01;

        if (!is_dir) {
            char fullpath[PATH_MAX];
            snprintf(fullpath, sizeof(fullpath), "%s/%s", name, namelist[i]->d_name);
            if (access(fullpath, W_OK) != 0)
                meta |= 0x02;
        }

        buf[pos++] = meta;
        size_t namelen = strlen(namelist[i]->d_name);
        memcpy(buf + pos, namelist[i]->d_name, namelen + 1);
        pos += namelen + 1;
        free(namelist[i]);
    }
    free(namelist);

    DirState *ds = malloc(sizeof(DirState));
    ds->buffer = buf;
    ds->buf_size = pos;
    ds->buf_pos = 0;
    dir_state[slot] = ds;
    return slot + 1;
}

FILE* file_handle(uint8_t file) {
    if (file == 0 || files[file - 1] == NULL) {
        restore_terminal();
        fprintf(stderr, "file %i is not open\n", (int) file);
	exit(1);
    }
    return files[file - 1];
}

void file_close(uint8_t file) {
    if (file <= 1) {
        restore_terminal();
        fprintf(stderr, "Cannot close standard file %i\n", (int) file);
        exit(1);
    }
    if (dir_state[file - 1] != NULL) {
        DirState *ds = dir_state[file - 1];
        free(ds->buffer);
        free(ds);
        dir_state[file - 1] = NULL;
        return;
    }
    fclose(file_handle(file));
    files[file - 1] = NULL;
}

int file_read(uint8_t file) {
    return fgetc(file_handle(file));
}

int file_write(uint8_t file, uint8_t value) {
    return fputc(value, file_handle(file));
}

int files_destroy() {
    int unclosed_count = 0;
    for (size_t x = 1; x != 255; x++) {
        if (files[x] != NULL) {
	    fprintf(stderr, "File %i was not closed\n", (int) (x + 1));
            fclose(files[x]);
	    files[x] = NULL;
            unclosed_count++;
        }
        if (dir_state[x] != NULL) {
            fprintf(stderr, "File %i was not closed\n", (int) (x + 1));
            free(dir_state[x]->buffer);
            free(dir_state[x]);
            dir_state[x] = NULL;
            unclosed_count++;
        }
    }
    return unclosed_count;
}

uint8_t read6502(uint16_t address) {
    if (address == port_read_b) {                    // read_b
        if (terminal_mode) {
            restore_terminal();
            fprintf(stderr, "Error: read_b not available in terminal mode, use serial_read\n");
            exit(1);
        }
        int b = fgetc(input_file_ptr);
        if (b == EOF) {
            b = 4;
            fseek(input_file_ptr, 0, SEEK_SET);
        }
        return b;
    } else if (address == port_open) {               // open
        uint16_t address = a | (x << 8);
        return file_open((const char*) (memory + address));
    } else if (address == port_openout) {            // openout
        uint16_t address = a | (x << 8);
        return file_open_for_write((const char*) (memory + address));
    } else if (address == port_read) {               // read
        if (a > 0 && dir_state[a - 1] != NULL) {
            DirState *ds = dir_state[a - 1];
            if (ds->buf_pos >= ds->buf_size) return 4;
            return (uint8_t)ds->buffer[ds->buf_pos++];
        }
        int b = file_read(a);
        if (b == EOF) {
            b = 4;
            fseek(file_handle(a), 0, SEEK_SET);
        }
        return b;
    } else if (address == port_eof_b) {              // eof_b
        if (terminal_mode) {
            restore_terminal();
            fprintf(stderr, "Error: eof_b not available in terminal mode, use serial_read\n");
            exit(1);
        }
        int b = fgetc(input_file_ptr);
        if (b == EOF) {
            fseek(input_file_ptr, 0, SEEK_SET);
            return 0x80;
        }
        ungetc(b, input_file_ptr);
        return 0;
    } else if (address == port_eof) {                // eof
        if (a > 0 && dir_state[a - 1] != NULL) {
            DirState *ds = dir_state[a - 1];
            return (ds->buf_pos >= ds->buf_size) ? 0x80 : 0x00;
        }
        FILE *f = file_handle(a);
        int b = fgetc(f);
        if (b == EOF) {
            fseek(f, 0, SEEK_SET);
            return 0x80;
        }
        ungetc(b, f);
        return 0;
    } else if (address == port_opendir) {            // opendir
        uint16_t addr = a | (x << 8);
        return dir_open((const char*)(memory + addr));
    } else if (address == port_argc) {               // argc
        return arg_count;
    } else if (address == port_argv_l) {             // argvl
        if (a >= arg_count) {
            restore_terminal();
            fprintf(stderr, "Argument %i does not exist\n", (int) a);
            exit(1);
        }
        return arg_addresses[a] & 0xff;
    } else if (address == port_argv_h) {             // argvh
        if (a >= arg_count) {
            restore_terminal();
            fprintf(stderr, "Argument %i does not exist\n", (int) a);
            exit(1);
        }
        return arg_addresses[a] >> 8;
    } else if (address == port_con_read) {             // con_read
        if (terminal_mode) {
            restore_terminal();
            fprintf(stderr, "Error: con_read not available in terminal mode, use serial_read\n");
            exit(1);
        }
        if (console_mode) {
            struct timespec before, after;
            clock_gettime(CLOCK_MONOTONIC, &before);
            uint8_t ch;
            int got = read(STDIN_FILENO, &ch, 1);
            if (got < 0 && errno == EINTR && sigint_requested) {
                if (exitcode_set == -1) exitcode_set = 130;
                done = 1;
                return 0;
            }
            clock_gettime(CLOCK_MONOTONIC, &after);
            long sec_diff = after.tv_sec - before.tv_sec;
            long nsec_diff = after.tv_nsec - before.tv_nsec;
            start_time.tv_sec += sec_diff;
            start_time.tv_nsec += nsec_diff;
            if (start_time.tv_nsec >= 1000000000L) {
                start_time.tv_sec++;
                start_time.tv_nsec -= 1000000000L;
            }
            if (start_time.tv_nsec < 0) {
                start_time.tv_sec--;
                start_time.tv_nsec += 1000000000L;
            }
            if (got == 1) return ch;
            return 0;
        } else {
            int b = fgetc(input_file_ptr);
            if (b == EOF) { con_eof_flag = 1; return 0; }
            return b;
        }
    } else if (address == port_term_rows) {           // term_rows
        int rows, cols;
        get_terminal_size(&rows, &cols);
        return (uint8_t)rows;
    } else if (address == port_term_cols) {           // term_cols
        int rows, cols;
        get_terminal_size(&rows, &cols);
        return (uint8_t)cols;
    } else if (address == port_con_ready) {           // con_ready
        if (terminal_mode) {
            restore_terminal();
            fprintf(stderr, "Error: con_ready not available in terminal mode, use serial_read\n");
            exit(1);
        }
        if (console_mode) {
            return con_byte_ready() ? 0xFF : 0x00;
        } else {
            return con_eof_flag ? 0x00 : 0xFF;
        }
    } else if (address == port_serial_ready) {        // serial_ready
        if (serial_baud > 0)
            serial_tx_drain();  // drain TX so DSR responses can be injected
        if (serial_inject_pos < serial_inject_len)
            return 0xFF;
        if (serial_baud > 0) {
            serial_rx_fill();
            return serial_rx_head != serial_rx_tail ? 0xFF : 0x00;
        }
        // No baud rate - direct polling
        if (terminal_interactive) {
            return con_byte_ready() ? 0xFF : 0x00;
        } else if (terminal_mode && serial_input_file) {
            int ch = fgetc(serial_input_file);
            if (ch == EOF) return 0x00;
            ungetc(ch, serial_input_file);
            return 0xFF;
        }
        return 0x00;
    } else if (address == port_serial_data) {         // serial_data
        if (serial_inject_pos < serial_inject_len) {
            uint8_t ch = (uint8_t)serial_inject_buf[serial_inject_pos++];
            if (serial_inject_pos >= serial_inject_len) {
                serial_inject_pos = 0;
                serial_inject_len = 0;
            }
            return ch;
        }
        if (serial_baud > 0) {
            serial_rx_fill();
            if (serial_rx_head != serial_rx_tail) {
                uint8_t ch = serial_rx_buf[serial_rx_tail];
                serial_rx_tail = (serial_rx_tail + 1) % SERIAL_BUF_SIZE;
                return ch;
            }
            return 0;
        }
        // No baud rate - direct read
        if (terminal_interactive) {
            struct timespec before, after;
            clock_gettime(CLOCK_MONOTONIC, &before);
            uint8_t ch;
            int got = read(STDIN_FILENO, &ch, 1);
            if (got < 0 && errno == EINTR && sigint_requested) {
                if (exitcode_set == -1) exitcode_set = 130;
                done = 1;
                return 0;
            }
            clock_gettime(CLOCK_MONOTONIC, &after);
            long sec_diff = after.tv_sec - before.tv_sec;
            long nsec_diff = after.tv_nsec - before.tv_nsec;
            start_time.tv_sec += sec_diff;
            start_time.tv_nsec += nsec_diff;
            if (start_time.tv_nsec >= 1000000000L) {
                start_time.tv_sec++;
                start_time.tv_nsec -= 1000000000L;
            }
            if (start_time.tv_nsec < 0) {
                start_time.tv_sec--;
                start_time.tv_nsec += 1000000000L;
            }
            if (got == 1) return ch;
            return 0;
        } else if (terminal_mode && serial_input_file) {
            int b = fgetc(serial_input_file);
            if (b == EOF) return 0;
            return (uint8_t)b;
        }
        return 0x00;
    } else if (address == port_serial_write_ready) {  // serial_write_ready
        if (serial_baud > 0) {
            serial_tx_drain();
            return serial_tx_count() < SERIAL_BUF_SIZE - 1 ? 0xFF : 0x00;
        }
        return 0xFF;
    } else if (address == 0xfffe && memory[0xfffe] == 0 && memory[0xffff] == 0) {
        done = 1;
    }/* else if (address == 0xfe) {
        fprintf(stderr, "Accessed address %04x with PC=%04x\n", (int) address, (int) pc);

        FILE* dump_file_ptr = fopen("dump.out", "wb");
        if (!dump_file_ptr) {
            fprintf(stderr, "could not open output file: dump.out\n");
            return 1;
        }

        fwrite(memory, 1, 0x10000, dump_file_ptr);
        fclose(dump_file_ptr);

        exit(1);
    }*/
    return memory[address];
}

void write6502(uint16_t address, uint8_t value) {
    if (address == port_write_b) {                   // write_b
        if (terminal_mode) {
            restore_terminal();
            fprintf(stderr, "Error: write_b not available in terminal mode, use serial_write\n");
            exit(1);
        }
        if (console_mode) {
            unsigned char ch = value;
            console_handle_byte(ch);
            if (write(STDOUT_FILENO, &ch, 1) < 0) {
            }
        } else {
            fputc(value, output_file_ptr);
        }
        return;
    } else if (address == port_write_d) {            // write_d
        if (!error_output_started) {
            fputc('\n', stderr);  // End command line before first error output
            error_output_started = 1;
        }
        fputc(value, stderr);
        return;
    } else if (address == port_close) {              // close
        file_close(value);
	return;
    } else if (address == port_exit) {               // exit
        exitcode_set = value;
        done = 1;
	return;
    } else if (address == port_write) {              // write
        file_write(x, value);
        return;
    } else if (address == port_con_flush) {          // con_flush
        if (terminal_mode) {
            restore_terminal();
            fprintf(stderr, "Error: con_flush not available in terminal mode, use serial_write\n");
            exit(1);
        }
        fflush(stdout);
        return;
    } else if (address == port_serial_write) {      // serial_write
        if (serial_baud > 0) {
            serial_tx_drain();
            serial_tx_buf[serial_tx_head] = value;
            serial_tx_head = (serial_tx_head + 1) % SERIAL_BUF_SIZE;
            return;
        }
        // No baud rate - direct write
        if (terminal_interactive) {
            unsigned char ch = value;
            if (write(STDOUT_FILENO, &ch, 1) < 0) {
            }
        } else if (terminal_mode && serial_output_file) {
            fputc(value, serial_output_file);
        }
        if (terminal_mode) {
            console_handle_byte(value);
        }
        return;
    }

    memory[address] = value;
}

void show_commandline(int argc, char**argv) {
    for (int i = 1; i < argc; i++) {
        fprintf(stderr, "%s ", argv[i]);
    }
}

#define save_address(v) uint16_t v = p; p += 2
#define fill_address(v) memory[v] = p & 0xff; memory[v+1] = p >> 8;
#define emit_byte(b) memory[p++] = b;
#define emit_address(v) emit_byte(v & 0xff); emit_byte(v >> 8);
#define inst_jmp 0x4c
#define inst_lda 0xad
#define inst_beq 0xf0
#define inst_clc 0x18
#define inst_rts 0x60
#define inst_sec 0x38
#define inst_sta 0x8d
#define inst_ldx 0xae
#define inst_pha 0x48
#define inst_pla 0x68
#define inst_bit 0x2c
#define inst_bmi 0x30

static int server_main(void);

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: emulator <code file> [--load <hex load address>] [--input <input file>] [--output <output file>] [--dump <dump file>] [--no-dump] [--console] [--terminal] [--server] [--mhz <speed>] [--cpu-mhz <speed>] [--baud <rate>] [--rows N] [--cols N] [<arguments>]\n");
        return 1;
    }

    // Check for --server as first argument (before code file)
    if (argc >= 2 && strcmp(argv[1], "--server") == 0) {
        return server_main();
    }

    char* code_filename = argv[1];
    long load_address = -1;
    char* input_filename = "/dev/null";
    char* output_filename = "/dev/null";
    char* dump_filename = NULL;
    int no_dump = 0;
    int input_specified = 0;
    int output_specified = 0;

    int i = 2;
    while (i < argc && strncmp(argv[i], "--", 2) == 0) {
        if (strcmp(argv[i], "--console") == 0) {
            console_mode = 1;
            i++;
        } else if (strcmp(argv[i], "--terminal") == 0) {
            terminal_mode = 1;
            i++;
        } else if (strcmp(argv[i], "--load") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --load requires a value\n");
                return 1;
            }
            load_address = strtol(argv[i + 1], NULL, 16);
            if (load_address < 0 || load_address > 0xffff) {
                fprintf(stderr, "error: --load value must be between 0 and ffff\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--input") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --input requires a value\n");
                return 1;
            }
            input_filename = argv[i + 1];
            input_specified = 1;
            i += 2;
        } else if (strcmp(argv[i], "--output") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --output requires a value\n");
                return 1;
            }
            output_filename = argv[i + 1];
            output_specified = 1;
            i += 2;
        } else if (strcmp(argv[i], "--dump") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --dump requires a value\n");
                return 1;
            }
            dump_filename = argv[i + 1];
            i += 2;
        } else if (strcmp(argv[i], "--no-dump") == 0) {
            no_dump = 1;
            i++;
        } else if (strcmp(argv[i], "--rows") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --rows requires a value\n");
                return 1;
            }
            override_rows = (int)strtol(argv[i + 1], NULL, 10);
            if (override_rows <= 0) {
                fprintf(stderr, "error: --rows value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--cols") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --cols requires a value\n");
                return 1;
            }
            override_cols = (int)strtol(argv[i + 1], NULL, 10);
            if (override_cols <= 0) {
                fprintf(stderr, "error: --cols value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--mhz") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --mhz requires a value\n");
                return 1;
            }
            target_mhz = strtod(argv[i + 1], NULL);
            if (target_mhz <= 0.0) {
                fprintf(stderr, "error: --mhz value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--cpu-mhz") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --cpu-mhz requires a value\n");
                return 1;
            }
            cpu_mhz = strtod(argv[i + 1], NULL);
            if (cpu_mhz <= 0.0) {
                fprintf(stderr, "error: --cpu-mhz value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--baud") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --baud requires a value\n");
                return 1;
            }
            serial_baud = (int)strtol(argv[i + 1], NULL, 10);
            if (serial_baud <= 0) {
                fprintf(stderr, "error: --baud value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--show-repaints") == 0) {
            show_repaints = 1;
            i++;
        } else if (strcmp(argv[i], "--server") == 0) {
            server_mode = 1;
            i++;
        } else {
            fprintf(stderr, "error: unknown option %s\n", argv[i]);
            return 1;
        }
    }

    if (console_mode && terminal_mode) {
        fprintf(stderr, "error: --console and --terminal are mutually exclusive\n");
        return 1;
    }

    if (serial_baud > 0 && cpu_mhz <= 0.0 && target_mhz <= 0.0) {
        fprintf(stderr, "error: --baud requires --cpu-mhz or --mhz\n");
        return 1;
    }

    if (serial_baud > 0) {
        double effective_cpu_mhz = cpu_mhz > 0.0 ? cpu_mhz : target_mhz;
        serial_cycles_per_byte = (uint64_t)(effective_cpu_mhz * 10000000.0 / serial_baud);
    }

    if (terminal_mode && !input_specified && !output_specified) {
        terminal_interactive = 1;
    }

    int arg_base = i;

    for (size_t x = 0; x != 0x10001; x++) {
        memory[x] = 0;
    }

    FILE* code_file_ptr = fopen(code_filename, "rb");
    if (!code_file_ptr) {
        fprintf(stderr, "could not open code file: %s\n", code_filename);
        return 1;
    }

    if (load_address < 0) {
        if (fseek(code_file_ptr, 0, SEEK_END) != 0) {
            fprintf(stderr, "could not determine code file size: %s\n", code_filename);
            fclose(code_file_ptr);
            return 1;
        }
        long code_size = ftell(code_file_ptr);
        if (code_size < 0) {
            fprintf(stderr, "could not determine code file size: %s\n", code_filename);
            fclose(code_file_ptr);
            return 1;
        }
        if (code_size > 0x10000) {
            fprintf(stderr, "Code file %s is too large to fit in memory\n", code_filename);
            fclose(code_file_ptr);
            return 1;
        }
        load_address = 0x10000 - code_size;
        if (fseek(code_file_ptr, 0, SEEK_SET) != 0) {
            fprintf(stderr, "could not rewind code file: %s\n", code_filename);
            fclose(code_file_ptr);
            return 1;
        }
    }

    long index = load_address;
    int b;
    while ((b = fgetc(code_file_ptr)) != EOF) {
        if (index > 0xffff) {
            fprintf(stderr,
                    "Code file %s will not fit in memory at the specified load address\n",
		    code_filename);
            fclose(code_file_ptr);
            return 1;
        }
        memory[index++] = b;
    }
    fclose(code_file_ptr);

    if (index < 0xfffe) {
      memory[0xfffd] = memory[index - 1];
      memory[0xfffc] = memory[index - 2];
    }

    size_t p = 0xf006;
    emit_byte(inst_jmp);        // f006     jmp read_b
    save_address(addr_read_b);
    emit_byte(inst_jmp);        // f009     jmp write_b
    save_address(addr_write_b);
    emit_byte(inst_jmp);        // f00c     jmp write_d
    save_address(addr_write_d);
    emit_byte(inst_jmp);        // f00f     jmp exit
    save_address(addr_exit);
    emit_byte(inst_jmp);        // f012     jmp open
    save_address(addr_open);
    emit_byte(inst_jmp);        // f015     jmp close
    save_address(addr_close);
    emit_byte(inst_jmp);        // f018     jmp read
    save_address(addr_read);
    emit_byte(inst_jmp);        // f01b     jmp argc
    save_address(addr_argc);
    emit_byte(inst_jmp);        // f01e     jmp argv
    save_address(addr_argv);
    emit_byte(inst_jmp);        // f021     jmp openout
    save_address(addr_openout);
    emit_byte(inst_jmp);        // f024     jmp write
    save_address(addr_write);
    emit_byte(inst_jmp);        // f027     jmp con_read
    save_address(addr_con_read);
    emit_byte(inst_jmp);        // f02a     jmp con_flush
    save_address(addr_con_flush);
    emit_byte(inst_jmp);        // f02d     jmp con_ready
    save_address(addr_con_ready);
    emit_byte(inst_jmp);        // f030     jmp term_rows
    save_address(addr_term_rows);
    emit_byte(inst_jmp);        // f033     jmp term_cols
    save_address(addr_term_cols);
    emit_byte(inst_jmp);        // f036     jmp serial_read
    save_address(addr_serial_read);
    emit_byte(inst_jmp);        // f039     jmp serial_write
    save_address(addr_serial_write);
    emit_byte(inst_jmp);        // f03c     jmp opendir
    save_address(addr_opendir);
    fill_address(addr_read_b);
    emit_byte(inst_bit);        // read_b:  bit port_eof_b
    emit_address(port_eof_b);
    emit_byte(inst_bmi);        //          bmi .at_end (+5)
    emit_byte(0x05);
    emit_byte(inst_lda);        //          lda port_read_b
    emit_address(port_read_b);
    emit_byte(inst_clc);        //          clc
    emit_byte(inst_rts);        //          rts
    emit_byte(inst_sec);        // .at_end: sec
    emit_byte(inst_rts);        //          rts
    fill_address(addr_write_b);
    emit_byte(inst_sta);        // write_b: sta $f001
    emit_address(port_write_b);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_write_d);
    emit_byte(inst_sta);        // write_d: sta $f002
    emit_address(port_write_d);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_exit);
    emit_byte(inst_sta);        // exit:    sta $f003
    emit_address(port_exit);
    fill_address(addr_open);
    emit_byte(inst_lda);        // open:    lda $f005
    emit_address(port_open);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_close);
    emit_byte(inst_sta);        // close:   sta $f000
    emit_address(port_close);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_read);
    emit_byte(inst_bit);        // read:    bit port_eof
    emit_address(port_eof);
    emit_byte(inst_bmi);        //          bmi .at_end (+5)
    emit_byte(0x05);
    emit_byte(inst_lda);        //          lda port_read
    emit_address(port_read);
    emit_byte(inst_clc);        //          clc
    emit_byte(inst_rts);        //          rts
    emit_byte(inst_sec);        // .at_end: sec
    emit_byte(inst_rts);        //          rts
    fill_address(addr_argc);
    emit_byte(inst_lda);        // argc:    lda $fe80
    emit_address(port_argc);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_argv);
    emit_byte(inst_ldx);        // argv:    ldx $fe82
    emit_address(port_argv_h);
    emit_byte(inst_lda);        //          lda $fe81
    emit_address(port_argv_l);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_openout);
    emit_byte(inst_lda);        // openout: lda $fe83
    emit_address(port_openout);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_write);
    emit_byte(inst_sta);        // write:   sta $fe84
    emit_address(port_write);
    emit_byte(inst_rts);        //          rts
    fill_address(addr_con_read);
    emit_byte(inst_lda);        // con_read: lda $fe90
    emit_address(port_con_read);
    emit_byte(inst_rts);        //           rts
    fill_address(addr_con_flush);
    emit_byte(inst_sta);        // con_flush: sta $fe91
    emit_address(port_con_flush);
    emit_byte(inst_rts);        //            rts
    fill_address(addr_con_ready);
    emit_byte(inst_lda);        // con_ready: lda $fe94
    emit_address(port_con_ready);
    emit_byte(inst_rts);        //            rts
    fill_address(addr_term_rows);
    emit_byte(inst_lda);        // term_rows: lda $fe92
    emit_address(port_term_rows);
    emit_byte(inst_rts);        //            rts
    fill_address(addr_term_cols);
    emit_byte(inst_lda);        // term_cols: lda $fe93
    emit_address(port_term_cols);
    emit_byte(inst_rts);        //            rts
    fill_address(addr_serial_read);
    emit_byte(inst_lda);        // serial_read: lda $fe95
    emit_address(port_serial_ready);
    emit_byte(inst_beq);        //              beq .no_data (+5)
    emit_byte(0x05);
    emit_byte(inst_lda);        //              lda $fe96
    emit_address(port_serial_data);
    emit_byte(inst_clc);        //              clc
    emit_byte(inst_rts);        //              rts
    emit_byte(inst_sec);        // .no_data:    sec
    emit_byte(inst_rts);        //              rts
    fill_address(addr_serial_write);
    if (terminal_mode) {
        emit_byte(inst_pha);    // serial_write: pha
        emit_byte(inst_lda);    //               lda $fe98
        emit_address(port_serial_write_ready);
        emit_byte(inst_beq);    //               beq .not_ready (+6)
        emit_byte(0x06);
        emit_byte(inst_pla);    //               pla
        emit_byte(inst_sta);    //               sta $fe97
        emit_address(port_serial_write);
        emit_byte(inst_clc);    //               clc (accepted)
        emit_byte(inst_rts);    //               rts
        emit_byte(inst_pla);    // .not_ready:   pla
        emit_byte(inst_sec);    //               sec (not accepted)
        emit_byte(inst_rts);    //               rts
    } else {
        emit_byte(inst_sec);    // serial_write: sec (not accepted, no terminal mode)
        emit_byte(inst_rts);    //               rts
    }
    fill_address(addr_opendir);
    emit_byte(inst_lda);        // opendir: lda port_opendir
    emit_address(port_opendir);
    emit_byte(inst_rts);        //          rts

    if (console_mode) {
        input_file_ptr = stdin;
        setup_console();
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = handle_sigint;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGINT, &sa, NULL);
        sa.sa_handler = handle_sigtstp;
        sigaction(SIGTSTP, &sa, NULL);
        sa.sa_handler = handle_sigcont;
        sigaction(SIGCONT, &sa, NULL);
    } else if (terminal_interactive) {
        input_file_ptr = fopen("/dev/null", "rb");
        atexit(restore_terminal);
        setup_raw_terminal();
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = handle_sigint;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGINT, &sa, NULL);
        sa.sa_handler = handle_sigtstp;
        sigaction(SIGTSTP, &sa, NULL);
        sa.sa_handler = handle_sigcont;
        sigaction(SIGCONT, &sa, NULL);
    } else if (terminal_mode) {
        // Terminal mode with file I/O
        input_file_ptr = fopen("/dev/null", "rb");
        if (input_specified) {
            serial_input_file = fopen(input_filename, "rb");
            if (!serial_input_file) {
                fprintf(stderr, "could not open input file: %s\n", input_filename);
                return 1;
            }
        }
        if (output_specified) {
            serial_output_file = fopen(output_filename, "wb");
            if (!serial_output_file) {
                fprintf(stderr, "could not open output file: %s\n", output_filename);
                if (serial_input_file) fclose(serial_input_file);
                return 1;
            }
        }
    } else {
        input_file_ptr = fopen(input_filename, "rb");
        if (!input_file_ptr) {
            fprintf(stderr, "could not open input file: %s\n", input_filename);
            return 1;
        }
    }

    if (terminal_mode) {
        int rows, cols;
        get_terminal_size(&rows, &cols);
        console_resize(rows, cols);
    }

    if (console_mode) {
        output_file_ptr = stdout;
    } else if (terminal_mode) {
        output_file_ptr = fopen("/dev/null", "wb");
    } else if (strcmp(output_filename, "-") == 0) {
        output_file_ptr = stdout;
    } else {
        output_file_ptr = fopen(output_filename, "wb");
        if (!output_file_ptr) {
            fprintf(stderr, "could not open output file: %s\n", output_filename);
            if (!console_mode) fclose(input_file_ptr);
            return 1;
        }
    }

    files_init(input_file_ptr);

    arg_count = argc - arg_base;
    arg_addresses = malloc(arg_count * sizeof(uint16_t));
    for (int arg = 0; arg != arg_count; arg++) {
        arg_addresses[arg] = p;
        const char* s = argv[arg_base + arg];
        while (memory[p++] = *s++)
            ;
    }

    if (!console_mode && !terminal_mode) {
        show_commandline(argc, argv);  // Print command line before emulation (no newline yet)
    }
    reset6502();

    uint64_t next_throttle_check = 10000;
    uint64_t next_repaint_check = 10000;
    clock_gettime(CLOCK_MONOTONIC, &start_time);
    last_repaint_check = start_time;

    const int max_cycles = 200000000;
    while (!done) {
        if (sigtstp_requested) {
            sigtstp_requested = 0;
            if (console_mode || terminal_mode) restore_terminal();
            struct sigaction sa;
            memset(&sa, 0, sizeof(sa));
            sa.sa_handler = SIG_DFL;
            sigemptyset(&sa.sa_mask);
            sigaction(SIGTSTP, &sa, NULL);
            raise(SIGTSTP);
            sa.sa_handler = handle_sigtstp;
            sigaction(SIGTSTP, &sa, NULL);
        }
        if (sigcont_requested) {
            sigcont_requested = 0;
            if (console_mode) enter_console();
            if (console_mode) console_redraw();
            if (terminal_mode) enter_console();
            if (terminal_mode) console_redraw();
        }
        if (sigint_requested) {
            if (exitcode_set == -1) exitcode_set = 130;
            if (console_mode || terminal_mode) restore_terminal();
            done = 1;
            break;
        }
        step6502();

        if (target_mhz > 0 && clockticks6502 >= next_throttle_check) {
            next_throttle_check = clockticks6502 + 10000;
            double emulated_us = (double)clockticks6502 / target_mhz;
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            double wall_us = (now.tv_sec - start_time.tv_sec) * 1e6
                           + (now.tv_nsec - start_time.tv_nsec) / 1e3;
            double ahead_us = emulated_us - wall_us;
            if (ahead_us > 100.0) {
                struct timespec delay;
                delay.tv_sec = 0;
                delay.tv_nsec = (long)(ahead_us * 1000.0);
                nanosleep(&delay, NULL);
            }
        }

        if (show_repaints && (console_mode || terminal_mode)
            && clockticks6502 >= next_repaint_check) {
            next_repaint_check = clockticks6502 + 10000;
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            double ms = (now.tv_sec - last_repaint_check.tv_sec) * 1e3
                      + (now.tv_nsec - last_repaint_check.tv_nsec) / 1e6;
            if (ms >= 16.0) {
                last_repaint_check = now;
                repaint_overlay_update(&now);
            }
        }

        if (!console_mode && !terminal_mode && clockticks6502 > max_cycles) {
            fprintf(stderr, "\ndid not terminate within %i cycles\n", max_cycles);
            free(arg_addresses);
            fclose(output_file_ptr);
            fclose(input_file_ptr);
            return 1;
        }
    }

    free(arg_addresses);

    int unclosed_files = files_destroy();

    if (serial_baud > 0) serial_tx_flush();
    if (serial_input_file) fclose(serial_input_file);
    if (serial_output_file) fclose(serial_output_file);

    if (!console_mode && !terminal_mode && strcmp(output_filename, "-") != 0) {
        fclose(output_file_ptr);
    }
    if (terminal_mode) {
        fclose(output_file_ptr);
    }

    if (!console_mode) {
        fclose(input_file_ptr);
    }

    uint8_t exitcode;
    if (exitcode_set != -1) {
        exitcode = exitcode_set;
    } else {
        uint16_t location = memory[0x100 + sp + 2] + (memory[0x100 + sp + 3] << 8) - 1;
        exitcode = memory[location];
        if (exitcode != 0) {
            if (!error_output_started) {
                fputc('\n', stderr);
                error_output_started = 1;
            }
            fprintf(stderr, "Error: ");
            for (int i = 0; i != 40; i++) {
                uint8_t c = memory[location + 1 + i];
                if (c == 0) break;
                fputc(c, stderr);
            }
            fputc('\n', stderr);
        }
    }

    // If files were left unclosed and no other error occurred, set error exit code
    if (unclosed_files > 0 && exitcode == 0) {
        exitcode = 1;
    }

    // Compute MHz for display
    double display_mhz = 0.0;
    if (target_mhz > 0) {
        display_mhz = target_mhz;
    } else {
        struct timespec end_time;
        clock_gettime(CLOCK_MONOTONIC, &end_time);
        double elapsed_us = (end_time.tv_sec - start_time.tv_sec) * 1e6
                          + (end_time.tv_nsec - start_time.tv_nsec) / 1e3;
        if (elapsed_us > 0) {
            display_mhz = (double)clockticks6502 / elapsed_us;
        }
    }

    // Print final status line (skip in console/terminal mode)
    if (!console_mode && !terminal_mode) {
        if (error_output_started || exitcode != 0) {
            fprintf(stderr, "Exit code %d; Executed %llu cycles at %.1f MHz\n", exitcode, (unsigned long long)clockticks6502, display_mhz);
        } else {
            fprintf(stderr, "executed %llu cycles at %.1f MHz\n", (unsigned long long)clockticks6502, display_mhz);
        }
    }

    if (dump_filename || (exitcode != 0 && !no_dump)) {
        char* auto_dump = NULL;
        if (!dump_filename) {
            // Auto-dump on error: derive filename from code file basename
            const char* base = strrchr(code_filename, '/');
            base = base ? base + 1 : code_filename;
            const char* suffix = ".dump.bin";
            auto_dump = malloc(strlen(base) + strlen(suffix) + 1);
            strcpy(auto_dump, base);
            strcat(auto_dump, suffix);
            dump_filename = auto_dump;
            fprintf(stderr, "Dumping memory to %s\n", dump_filename);
        }
        FILE* dump_file_ptr = fopen(dump_filename, "wb");
        if (!dump_file_ptr) {
            fprintf(stderr, "could not open dump file: %s\n", dump_filename);
            free(auto_dump);
            return 1;
        }
        fwrite(memory, 1, 0x10000, dump_file_ptr);
        fclose(dump_file_ptr);
        free(auto_dump);
    }

    return exitcode;
}

static uint8_t pristine_memory[0x10000];
static uint8_t *keys_buffer = NULL;
static size_t keys_buffer_len = 0;
static char *output_buffer = NULL;
static size_t output_buffer_len = 0;
static size_t stubs_end;  // address after stubs (where args go)

static int server_load_binary(const char *filename, long load_address) {
    memset(memory, 0, 0x10000);

    FILE *f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "server: could not open binary: %s\n", filename);
        return -1;
    }

    if (load_address < 0) {
        if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -1; }
        long code_size = ftell(f);
        if (code_size < 0 || code_size > 0x10000) { fclose(f); return -1; }
        load_address = 0x10000 - code_size;
        if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -1; }
    }

    long index = load_address;
    int b;
    while ((b = fgetc(f)) != EOF) {
        if (index > 0xffff) { fclose(f); return -1; }
        memory[index++] = b;
    }
    fclose(f);

    if (index < 0xfffe) {
        memory[0xfffd] = memory[index - 1];
        memory[0xfffc] = memory[index - 2];
    }

    // Generate I/O stubs (same as main)
    size_t p = 0xf006;
    emit_byte(inst_jmp);        // f006     jmp read_b
    save_address(addr_read_b);
    emit_byte(inst_jmp);        // f009     jmp write_b
    save_address(addr_write_b);
    emit_byte(inst_jmp);        // f00c     jmp write_d
    save_address(addr_write_d);
    emit_byte(inst_jmp);        // f00f     jmp exit
    save_address(addr_exit);
    emit_byte(inst_jmp);        // f012     jmp open
    save_address(addr_open);
    emit_byte(inst_jmp);        // f015     jmp close
    save_address(addr_close);
    emit_byte(inst_jmp);        // f018     jmp read
    save_address(addr_read);
    emit_byte(inst_jmp);        // f01b     jmp argc
    save_address(addr_argc);
    emit_byte(inst_jmp);        // f01e     jmp argv
    save_address(addr_argv);
    emit_byte(inst_jmp);        // f021     jmp openout
    save_address(addr_openout);
    emit_byte(inst_jmp);        // f024     jmp write
    save_address(addr_write);
    emit_byte(inst_jmp);        // f027     jmp con_read
    save_address(addr_con_read);
    emit_byte(inst_jmp);        // f02a     jmp con_flush
    save_address(addr_con_flush);
    emit_byte(inst_jmp);        // f02d     jmp con_ready
    save_address(addr_con_ready);
    emit_byte(inst_jmp);        // f030     jmp term_rows
    save_address(addr_term_rows);
    emit_byte(inst_jmp);        // f033     jmp term_cols
    save_address(addr_term_cols);
    emit_byte(inst_jmp);        // f036     jmp serial_read
    save_address(addr_serial_read);
    emit_byte(inst_jmp);        // f039     jmp serial_write
    save_address(addr_serial_write);
    emit_byte(inst_jmp);        // f03c     jmp opendir
    save_address(addr_opendir);
    fill_address(addr_read_b);
    emit_byte(inst_bit);
    emit_address(port_eof_b);
    emit_byte(inst_bmi);
    emit_byte(0x05);
    emit_byte(inst_lda);
    emit_address(port_read_b);
    emit_byte(inst_clc);
    emit_byte(inst_rts);
    emit_byte(inst_sec);
    emit_byte(inst_rts);
    fill_address(addr_write_b);
    emit_byte(inst_sta);
    emit_address(port_write_b);
    emit_byte(inst_rts);
    fill_address(addr_write_d);
    emit_byte(inst_sta);
    emit_address(port_write_d);
    emit_byte(inst_rts);
    fill_address(addr_exit);
    emit_byte(inst_sta);
    emit_address(port_exit);
    fill_address(addr_open);
    emit_byte(inst_lda);
    emit_address(port_open);
    emit_byte(inst_rts);
    fill_address(addr_close);
    emit_byte(inst_sta);
    emit_address(port_close);
    emit_byte(inst_rts);
    fill_address(addr_read);
    emit_byte(inst_bit);
    emit_address(port_eof);
    emit_byte(inst_bmi);
    emit_byte(0x05);
    emit_byte(inst_lda);
    emit_address(port_read);
    emit_byte(inst_clc);
    emit_byte(inst_rts);
    emit_byte(inst_sec);
    emit_byte(inst_rts);
    fill_address(addr_argc);
    emit_byte(inst_lda);
    emit_address(port_argc);
    emit_byte(inst_rts);
    fill_address(addr_argv);
    emit_byte(inst_ldx);
    emit_address(port_argv_h);
    emit_byte(inst_lda);
    emit_address(port_argv_l);
    emit_byte(inst_rts);
    fill_address(addr_openout);
    emit_byte(inst_lda);
    emit_address(port_openout);
    emit_byte(inst_rts);
    fill_address(addr_write);
    emit_byte(inst_sta);
    emit_address(port_write);
    emit_byte(inst_rts);
    fill_address(addr_con_read);
    emit_byte(inst_lda);
    emit_address(port_con_read);
    emit_byte(inst_rts);
    fill_address(addr_con_flush);
    emit_byte(inst_sta);
    emit_address(port_con_flush);
    emit_byte(inst_rts);
    fill_address(addr_con_ready);
    emit_byte(inst_lda);
    emit_address(port_con_ready);
    emit_byte(inst_rts);
    fill_address(addr_term_rows);
    emit_byte(inst_lda);
    emit_address(port_term_rows);
    emit_byte(inst_rts);
    fill_address(addr_term_cols);
    emit_byte(inst_lda);
    emit_address(port_term_cols);
    emit_byte(inst_rts);
    fill_address(addr_serial_read);
    emit_byte(inst_lda);
    emit_address(port_serial_ready);
    emit_byte(inst_beq);
    emit_byte(0x05);
    emit_byte(inst_lda);
    emit_address(port_serial_data);
    emit_byte(inst_clc);
    emit_byte(inst_rts);
    emit_byte(inst_sec);
    emit_byte(inst_rts);
    fill_address(addr_serial_write);
    if (terminal_mode) {
        emit_byte(inst_pha);
        emit_byte(inst_lda);
        emit_address(port_serial_write_ready);
        emit_byte(inst_beq);
        emit_byte(0x06);
        emit_byte(inst_pla);
        emit_byte(inst_sta);
        emit_address(port_serial_write);
        emit_byte(inst_clc);
        emit_byte(inst_rts);
        emit_byte(inst_pla);
        emit_byte(inst_sec);
        emit_byte(inst_rts);
    } else {
        emit_byte(inst_sec);
        emit_byte(inst_rts);
    }
    fill_address(addr_opendir);
    emit_byte(inst_lda);
    emit_address(port_opendir);
    emit_byte(inst_rts);

    stubs_end = p;
    memcpy(pristine_memory, memory, 0x10000);
    return 0;
}

static int server_main(void) {
    char line[4096];
    long srv_load_address = -1;
    char srv_input[4096] = "";
    char srv_output[4096] = "";
    char srv_binary[4096] = "";
    int use_inline_keys = 0;
    int use_inline_output = 0;
    char loaded_binary[4096] = "";
    int loaded_terminal_mode = -1;
    long loaded_address = -1;
    char *srv_args[256];
    int srv_arg_count = 0;
    int binary_loaded = 0;

    while (fgets(line, sizeof(line), stdin)) {
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') line[--len] = '\0';

        if (strcmp(line, "QUIT") == 0) {
            break;
        } else if (strncmp(line, "BINARY ", 7) == 0) {
            strncpy(srv_binary, line + 7, sizeof(srv_binary) - 1);
            srv_binary[sizeof(srv_binary) - 1] = '\0';
            // Skip reload if same binary, mode, and load address
            if (binary_loaded &&
                strcmp(srv_binary, loaded_binary) == 0 &&
                terminal_mode == loaded_terminal_mode &&
                srv_load_address == loaded_address) {
                // Already loaded - skip file I/O
            } else if (server_load_binary(srv_binary, srv_load_address) != 0) {
                fprintf(stderr, "server: failed to load binary\n");
                binary_loaded = 0;
                loaded_binary[0] = '\0';
            } else {
                binary_loaded = 1;
                strncpy(loaded_binary, srv_binary, sizeof(loaded_binary) - 1);
                loaded_binary[sizeof(loaded_binary) - 1] = '\0';
                loaded_terminal_mode = terminal_mode;
                loaded_address = srv_load_address;
            }
        } else if (strncmp(line, "LOAD ", 5) == 0) {
            srv_load_address = strtol(line + 5, NULL, 16);
        } else if (strncmp(line, "ROWS ", 5) == 0) {
            override_rows = (int)strtol(line + 5, NULL, 10);
        } else if (strncmp(line, "COLS ", 5) == 0) {
            override_cols = (int)strtol(line + 5, NULL, 10);
        } else if (strncmp(line, "MODE ", 5) == 0) {
            terminal_mode = strcmp(line + 5, "terminal") == 0 ? 1 : 0;
        } else if (strncmp(line, "INPUT ", 6) == 0) {
            strncpy(srv_input, line + 6, sizeof(srv_input) - 1);
            srv_input[sizeof(srv_input) - 1] = '\0';
        } else if (strncmp(line, "OUTPUT ", 7) == 0) {
            strncpy(srv_output, line + 7, sizeof(srv_output) - 1);
            srv_output[sizeof(srv_output) - 1] = '\0';
        } else if (strncmp(line, "KEYS ", 5) == 0) {
            size_t klen = (size_t)strtol(line + 5, NULL, 10);
            free(keys_buffer);
            keys_buffer = malloc(klen);
            keys_buffer_len = klen;
            // Read exactly klen raw bytes from stdin
            size_t read_so_far = 0;
            while (read_so_far < klen) {
                size_t n = fread(keys_buffer + read_so_far, 1,
                                 klen - read_so_far, stdin);
                if (n == 0) break;
                read_so_far += n;
            }
            use_inline_keys = 1;
            srv_input[0] = '\0';
        } else if (strcmp(line, "INLINE_OUTPUT") == 0) {
            use_inline_output = 1;
            srv_output[0] = '\0';
        } else if (strncmp(line, "ARG ", 4) == 0) {
            if (srv_arg_count < 256) {
                srv_args[srv_arg_count++] = strdup(line + 4);
            }
        } else if (strcmp(line, "RUN") == 0) {
            if (!binary_loaded) {
                fprintf(stdout, "EXIT 1\n");
                fflush(stdout);
                goto run_cleanup;
            }

            // Restore pristine memory
            memcpy(memory, pristine_memory, 0x10000);

            // Write program arguments into memory after stubs
            size_t p = stubs_end;
            arg_count = srv_arg_count;
            free(arg_addresses);
            arg_addresses = malloc(arg_count * sizeof(uint16_t));
            for (int arg = 0; arg < arg_count; arg++) {
                arg_addresses[arg] = p;
                const char *s = srv_args[arg];
                while ((memory[p++] = *s++))
                    ;
            }

            // Open I/O
            if (terminal_mode) {
                input_file_ptr = fopen("/dev/null", "rb");
                output_file_ptr = fopen("/dev/null", "wb");
                if (use_inline_keys) {
                    serial_input_file = fmemopen(
                        keys_buffer, keys_buffer_len, "rb");
                } else if (srv_input[0]) {
                    serial_input_file = fopen(srv_input, "rb");
                }
                if (use_inline_output) {
                    free(output_buffer);
                    output_buffer = NULL;
                    output_buffer_len = 0;
                    serial_output_file = open_memstream(
                        &output_buffer, &output_buffer_len);
                } else if (srv_output[0]) {
                    serial_output_file = fopen(srv_output, "wb");
                }
                int rows, cols;
                get_terminal_size(&rows, &cols);
                console_resize(rows, cols);
            } else {
                if (use_inline_keys) {
                    input_file_ptr = fmemopen(
                        keys_buffer, keys_buffer_len, "rb");
                } else {
                    input_file_ptr = fopen(
                        srv_input[0] ? srv_input : "/dev/null", "rb");
                }
                if (use_inline_output) {
                    free(output_buffer);
                    output_buffer = NULL;
                    output_buffer_len = 0;
                    output_file_ptr = open_memstream(
                        &output_buffer, &output_buffer_len);
                } else if (srv_output[0]) {
                    output_file_ptr = fopen(srv_output, "wb");
                } else {
                    output_file_ptr = fopen("/dev/null", "wb");
                }
            }

            files_init(input_file_ptr);

            // Reset CPU and emulation state
            done = 0;
            exitcode_set = -1;
            error_output_started = 0;
            clockticks6502 = 0;
            clockgoal6502 = 0;
            instructions = 0;
            con_eof_flag = 0;
            serial_rx_head = 0;
            serial_rx_tail = 0;
            serial_rx_next_fill_at = 0;
            serial_tx_head = 0;
            serial_tx_tail = 0;
            serial_tx_next_drain_at = 0;
            reset6502();

            // Run emulation
            const int max_cycles = 200000000;
            while (!done) {
                step6502();
                if (clockticks6502 > max_cycles) {
                    fprintf(stderr, "\nserver: did not terminate within %d cycles\n", max_cycles);
                    done = 1;
                    if (exitcode_set == -1) exitcode_set = 1;
                }
            }

            // Clean up
            files_destroy();
            if (serial_baud > 0) serial_tx_flush();
            if (serial_input_file) { fclose(serial_input_file); serial_input_file = NULL; }
            if (serial_output_file) { fclose(serial_output_file); serial_output_file = NULL; }

            if (terminal_mode) {
                fclose(output_file_ptr);
                output_file_ptr = NULL;
            } else {
                if (output_file_ptr && output_file_ptr != stdout) {
                    fclose(output_file_ptr);
                    output_file_ptr = NULL;
                }
            }
            fclose(input_file_ptr);
            input_file_ptr = NULL;

            // Determine exit code
            uint8_t exitcode;
            if (exitcode_set != -1) {
                exitcode = exitcode_set;
            } else {
                uint16_t location = memory[0x100 + sp + 2]
                    + (memory[0x100 + sp + 3] << 8) - 1;
                exitcode = memory[location];
            }

            fprintf(stdout, "EXIT %d\n", exitcode);
            if (use_inline_output && output_buffer) {
                fprintf(stdout, "OUTPUT %zu\n", output_buffer_len);
                fwrite(output_buffer, 1, output_buffer_len, stdout);
            }
            fflush(stdout);

run_cleanup:
            // Free args for next run
            for (int j = 0; j < srv_arg_count; j++) {
                free(srv_args[j]);
            }
            srv_arg_count = 0;
            srv_input[0] = '\0';
            srv_output[0] = '\0';
            use_inline_keys = 0;
            use_inline_output = 0;
        } else {
            fprintf(stderr, "server: unknown command: %s\n", line);
        }
    }

    // Final cleanup
    for (int j = 0; j < srv_arg_count; j++) {
        free(srv_args[j]);
    }
    free(arg_addresses);
    arg_addresses = NULL;
    free(keys_buffer);
    keys_buffer = NULL;
    free(output_buffer);
    output_buffer = NULL;

    return 0;
}
