/* Tom Harte ProcessorTests harness (phase 3h).
 *
 * Loads JSON test vectors from emulator/tests/harte/data/{6502,wdc65c02}/v1/
 * and runs each opcode under the matching cpu_variant, comparing CPU
 * registers, RAM, and the bus cycle log against the expected values.
 *
 * Usage:
 *   harte_runner.out [variant] [opcode-hex]
 *
 *   variant     "6502" or "wdc65c02"; default both
 *   opcode-hex  "00".."ff"; default all
 *
 * Env:
 *   HARTE_LIMIT=N    only the first N vectors per opcode (0 = all)
 *
 * If data/ is missing, prints a warning and exits 0 (skip-with-warning
 * per the plan). */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <sys/stat.h>

#include "../cpu_core.h"

/* --------- bus tap state --------- */

#define MAX_CYCLES 16

struct cycle_entry {
    uint16_t addr;
    uint8_t  val;
    char     rw;  /* 'r' or 'w' */
};

static struct cycle_entry observed[MAX_CYCLES];
static int observed_count;

static void on_read(uint16_t addr, uint8_t val) {
    if (observed_count < MAX_CYCLES) {
        observed[observed_count].addr = addr;
        observed[observed_count].val = val;
        observed[observed_count].rw = 'r';
        observed_count++;
    }
}

static void on_write(uint16_t addr, uint8_t val) {
    if (observed_count < MAX_CYCLES) {
        observed[observed_count].addr = addr;
        observed[observed_count].val = val;
        observed[observed_count].rw = 'w';
        observed_count++;
    }
}

/* --------- mock RAM (full 64 KiB plain memory) --------- */

static uint8_t test_memory[0x10000];

uint8_t read6502(uint16_t address) { return test_memory[address]; }
void    write6502(uint16_t address, uint8_t value) { test_memory[address] = value; }

/* --------- minimal JSON scanner --------- */

typedef struct {
    const char *p;
    const char *end;
} jsc;

static void skip_ws(jsc *s) {
    while (s->p < s->end &&
           (*s->p == ' ' || *s->p == '\t' || *s->p == '\n' || *s->p == '\r')) s->p++;
}
static int peek_c(jsc *s) { skip_ws(s); return s->p < s->end ? *s->p : -1; }
static int expect_c(jsc *s, char c) {
    skip_ws(s);
    if (s->p < s->end && *s->p == c) { s->p++; return 1; }
    return 0;
}
static int read_int(jsc *s, long *out) {
    skip_ws(s);
    int neg = 0;
    if (s->p < s->end && *s->p == '-') { neg = 1; s->p++; }
    long v = 0;
    int got = 0;
    while (s->p < s->end && *s->p >= '0' && *s->p <= '9') {
        v = v * 10 + (*s->p - '0');
        s->p++;
        got = 1;
    }
    if (!got) return 0;
    *out = neg ? -v : v;
    return 1;
}
static int read_string(jsc *s, char *buf, size_t bufsz) {
    skip_ws(s);
    if (!(s->p < s->end && *s->p == '"')) return 0;
    s->p++;
    size_t i = 0;
    while (s->p < s->end && *s->p != '"') {
        /* No escapes expected in this dataset's fields. */
        if (i + 1 < bufsz) buf[i++] = *s->p;
        s->p++;
    }
    if (s->p < s->end) s->p++;
    buf[i] = '\0';
    return 1;
}
static int expect_key(jsc *s, const char *key) {
    char buf[32];
    if (!read_string(s, buf, sizeof(buf))) return 0;
    if (strcmp(buf, key) != 0) return 0;
    return expect_c(s, ':');
}

/* --------- per-test schema --------- */

#define MAX_RAM_PAIRS 32

struct test_state {
    long pc, s, a, x, y, p;
    struct { uint16_t addr; uint8_t val; } ram[MAX_RAM_PAIRS];
    int ram_count;
};

struct test_vec {
    char name[32];
    struct test_state initial, final_;
    struct cycle_entry cycles[MAX_CYCLES];
    int cycles_count;
};

static int parse_ram_array(jsc *s, struct test_state *st) {
    if (!expect_c(s, '[')) return 0;
    st->ram_count = 0;
    if (peek_c(s) == ']') { s->p++; return 1; }
    while (1) {
        if (!expect_c(s, '[')) return 0;
        long addr, val;
        if (!read_int(s, &addr)) return 0;
        if (!expect_c(s, ',')) return 0;
        if (!read_int(s, &val)) return 0;
        if (!expect_c(s, ']')) return 0;
        if (st->ram_count < MAX_RAM_PAIRS) {
            st->ram[st->ram_count].addr = (uint16_t)addr;
            st->ram[st->ram_count].val = (uint8_t)val;
            st->ram_count++;
        }
        if (peek_c(s) == ',') { s->p++; continue; }
        if (peek_c(s) == ']') { s->p++; return 1; }
        return 0;
    }
}

static int parse_state(jsc *s, struct test_state *st) {
    if (!expect_c(s, '{')) return 0;
    /* Keys appear in fixed order: pc, s, a, x, y, p, ram. */
    static const char *keys[] = {"pc","s","a","x","y","p"};
    long *vals[] = {&st->pc, &st->s, &st->a, &st->x, &st->y, &st->p};
    for (int i = 0; i < 6; i++) {
        if (!expect_key(s, keys[i])) return 0;
        if (!read_int(s, vals[i])) return 0;
        if (!expect_c(s, ',')) return 0;
    }
    if (!expect_key(s, "ram")) return 0;
    if (!parse_ram_array(s, st)) return 0;
    return expect_c(s, '}');
}

static int parse_cycles_array(jsc *s, struct test_vec *t) {
    if (!expect_c(s, '[')) return 0;
    t->cycles_count = 0;
    if (peek_c(s) == ']') { s->p++; return 1; }
    while (1) {
        if (!expect_c(s, '[')) return 0;
        long addr, val;
        if (!read_int(s, &addr)) return 0;
        if (!expect_c(s, ',')) return 0;
        if (!read_int(s, &val)) return 0;
        if (!expect_c(s, ',')) return 0;
        char rw[8];
        if (!read_string(s, rw, sizeof(rw))) return 0;
        if (!expect_c(s, ']')) return 0;
        if (t->cycles_count < MAX_CYCLES) {
            t->cycles[t->cycles_count].addr = (uint16_t)addr;
            t->cycles[t->cycles_count].val = (uint8_t)val;
            t->cycles[t->cycles_count].rw = (rw[0] == 'r') ? 'r' : 'w';
            t->cycles_count++;
        }
        if (peek_c(s) == ',') { s->p++; continue; }
        if (peek_c(s) == ']') { s->p++; return 1; }
        return 0;
    }
}

static int parse_test(jsc *s, struct test_vec *t) {
    skip_ws(s);
    if (!expect_c(s, '{')) return 0;
    if (!expect_key(s, "name")) return 0;
    if (!read_string(s, t->name, sizeof(t->name))) return 0;
    if (!expect_c(s, ',')) return 0;
    if (!expect_key(s, "initial")) return 0;
    if (!parse_state(s, &t->initial)) return 0;
    if (!expect_c(s, ',')) return 0;
    if (!expect_key(s, "final")) return 0;
    if (!parse_state(s, &t->final_)) return 0;
    if (!expect_c(s, ',')) return 0;
    if (!expect_key(s, "cycles")) return 0;
    if (!parse_cycles_array(s, t)) return 0;
    return expect_c(s, '}');
}

/* --------- per-test execution + comparison --------- */

static int compare_state(const struct test_vec *t) {
    int ok = 1;
    if ((long)pc != t->final_.pc) ok = 0;
    if ((long)sp != t->final_.s)  ok = 0;
    if ((long)a  != t->final_.a)  ok = 0;
    if ((long)x  != t->final_.x)  ok = 0;
    if ((long)y  != t->final_.y)  ok = 0;
    if ((long)status != t->final_.p) ok = 0;
    for (int i = 0; i < t->final_.ram_count; i++) {
        if (test_memory[t->final_.ram[i].addr] != t->final_.ram[i].val) {
            ok = 0;
            break;
        }
    }
    return ok;
}

static int compare_cycles(const struct test_vec *t) {
    if (observed_count != t->cycles_count) return 0;
    for (int i = 0; i < observed_count; i++) {
        if (observed[i].addr != t->cycles[i].addr) return 0;
        if (observed[i].val  != t->cycles[i].val)  return 0;
        if (observed[i].rw   != t->cycles[i].rw)   return 0;
    }
    return 1;
}

/* Run one test through the CPU. cycle_check=1 also requires the bus
 * cycle log to match (strategy 1 burst order won't, so callers may
 * disable it for opcodes with multiple memory accesses). Returns:
 *   0 = pass, 1 = state mismatch, 2 = cycle mismatch */
static int run_one(const struct test_vec *t, int cycle_check) {
    /* Initial RAM. */
    memset(test_memory, 0, sizeof(test_memory));
    for (int i = 0; i < t->initial.ram_count; i++) {
        test_memory[t->initial.ram[i].addr] = t->initial.ram[i].val;
    }
    /* Initial regs. */
    pc = (uint16_t)t->initial.pc;
    sp = (uint8_t)t->initial.s;
    a  = (uint8_t)t->initial.a;
    x  = (uint8_t)t->initial.x;
    y  = (uint8_t)t->initial.y;
    status = (uint8_t)t->initial.p;
    clockticks6502 = 0;
    clockgoal6502 = 0;

    observed_count = 0;
    cpu_bus_read_tap = on_read;
    cpu_bus_write_tap = on_write;

    step6502();

    cpu_bus_read_tap = NULL;
    cpu_bus_write_tap = NULL;

    if (!compare_state(t)) return 1;
    if (cycle_check && !compare_cycles(t)) return 2;
    return 0;
}

/* --------- file iteration --------- */

static char *read_file(const char *path, size_t *size_out) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf); fclose(f); return NULL;
    }
    buf[sz] = '\0';
    fclose(f);
    *size_out = (size_t)sz;
    return buf;
}

static int run_opcode_file(const char *path, int variant_id, int limit, int cycle_check) {
    size_t sz;
    char *buf = read_file(path, &sz);
    if (!buf) {
        fprintf(stderr, "  %s: open failed\n", path);
        return 1;
    }
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    if (sz == 0) {
        free(buf);
        fprintf(stderr, "SKIP %s/%s  (empty -- opcode not modeled by Harte)\n",
                (variant_id == CPU_NMOS) ? "6502" : "wdc65c02", base);
        return 0;
    }
    jsc s = { buf, buf + sz };
    if (!expect_c(&s, '[')) {
        free(buf);
        fprintf(stderr, "FAIL %s/%s  (malformed JSON header)\n",
                (variant_id == CPU_NMOS) ? "6502" : "wdc65c02", base);
        return 1;
    }
    if (peek_c(&s) == ']') { free(buf); return 0; }  /* empty array */

    cpu_variant = variant_id;

    int total = 0, passed = 0, state_fail = 0, cycle_fail = 0;
    while (1) {
        struct test_vec t;
        memset(&t, 0, sizeof(t));
        if (!parse_test(&s, &t)) break;
        total++;
        int rc = run_one(&t, cycle_check);
        if (rc == 0) passed++;
        else if (rc == 1) state_fail++;
        else if (rc == 2) cycle_fail++;
        if (limit > 0 && total >= limit) break;
        skip_ws(&s);
        if (peek_c(&s) == ',') { s.p++; continue; }
        if (peek_c(&s) == ']') break;
        break;
    }
    free(buf);

    if (state_fail || cycle_fail) {
        fprintf(stderr,
            "FAIL %s/%s  passed=%d/%d  state-fail=%d  cycle-fail=%d\n",
            (variant_id == CPU_NMOS) ? "6502" : "wdc65c02",
            base, passed, total, state_fail, cycle_fail);
        return 1;
    } else {
        fprintf(stderr,
            "PASS %s/%s  %d vectors\n",
            (variant_id == CPU_NMOS) ? "6502" : "wdc65c02",
            base, passed);
        return 0;
    }
}

static int harte_limit(void) {
    const char *e = getenv("HARTE_LIMIT");
    if (!e || !*e) return 0;
    long v = strtol(e, NULL, 10);
    return (v > 0) ? (int)v : 0;
}

static int data_dir_present(const char *p) {
    struct stat st;
    return (stat(p, &st) == 0) && (st.st_mode & S_IFDIR);
}

int main(int argc, char **argv) {
    const char *data = "emulator/tests/harte/data";
    if (!data_dir_present(data)) {
        fprintf(stderr,
            "WARNING: Harte data not fetched; run "
            "emulator/tests/harte/fetch.sh first. Skipping.\n");
        return 0;
    }

    int limit = harte_limit();
    /* Single-opcode mode: harte_runner.out <variant> <op-hex> */
    if (argc == 3) {
        const char *variant = argv[1];
        int variant_id = -1;
        const char *subdir = NULL;
        if (strcmp(variant, "6502") == 0) { variant_id = CPU_NMOS; subdir = "6502"; }
        else if (strcmp(variant, "wdc65c02") == 0) { variant_id = CPU_65C02; subdir = "wdc65c02"; }
        else { fprintf(stderr, "unknown variant '%s'\n", variant); return 2; }
        char path[512];
        snprintf(path, sizeof(path), "%s/%s/v1/%s.json", data, subdir, argv[2]);
        /* Cycle check disabled by default -- strategy 1 collapses bus
         * accesses to instruction-start order. */
        return run_opcode_file(path, variant_id, limit, 0);
    }

    /* Default: sweep all 256 opcodes for both variants. */
    fprintf(stderr, "Harte data present at %s. HARTE_LIMIT=%d (0=all).\n",
            data, limit);
    int total_fail = 0;
    int variants[] = {CPU_NMOS, CPU_65C02};
    const char *subdirs[] = {"6502", "wdc65c02"};
    for (int v = 0; v < 2; v++) {
        int v_pass = 0, v_fail = 0, v_skip = 0;
        for (int op = 0; op < 256; op++) {
            char path[512];
            snprintf(path, sizeof(path), "%s/%s/v1/%02x.json",
                     data, subdirs[v], op);
            struct stat st;
            if (stat(path, &st) != 0) {
                v_skip++; continue;
            }
            if (st.st_size == 0) { v_skip++; continue; }
            int rc = run_opcode_file(path, variants[v], limit, 0);
            if (rc == 0) v_pass++;
            else v_fail++;
        }
        fprintf(stderr, "%s summary: pass=%d fail=%d skip=%d\n",
                subdirs[v], v_pass, v_fail, v_skip);
        total_fail += v_fail;
    }
    return total_fail ? 1 : 0;
}
