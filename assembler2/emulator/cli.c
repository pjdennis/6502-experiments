#include "cli.h"
#include "cpu_core.h"  /* CPU_NMOS / CPU_65C02 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CPU_VARIANT_UNSET (-1)

void emu_opts_init(struct emu_opts *opts) {
    opts->code_filename = NULL;
    opts->load_address = -1;
    opts->input_filename = "/dev/null";
    opts->output_filename = "/dev/null";
    opts->error_output_filename = NULL;
    opts->dump_filename = NULL;
    opts->no_dump = 0;
    opts->input_specified = 0;
    opts->output_specified = 0;
    opts->console_mode = 0;
    opts->terminal_mode = 0;
    opts->show_repaints = 0;
    opts->server_mode = 0;
    opts->override_rows = 0;
    opts->override_cols = 0;
    opts->target_mhz = 0.0;
    opts->cpu_mhz = 0.0;
    opts->serial_baud = 0;
    opts->arg_base = 0;
    opts->server_main_dispatch = 0;
    opts->machine = MACHINE_NMOS_DEFAULT;
    opts->cpu_variant_opt = CPU_VARIANT_UNSET;
    opts->rom_filename = NULL;
    opts->serial_input_filename = NULL;
    opts->cycle_cap = 200000000ULL;
    opts->cycle_cap_set = 0;
    opts->live = 0;
}

void emu_opts_usage(FILE *fp) {
    fprintf(fp,
"usage: emulator <code file> [options] [<arguments>]\n"
"   or: emulator --server\n"
"\n"
"options:\n"
"  --load <hex addr>      load address for the code file (hexadecimal)\n"
"  --input <path>         file read from $F006 input port (default /dev/null)\n"
"  --output <path>        file written from $F009 output port (default /dev/null)\n"
"  --error-output <path>  file written from $F00C error port\n"
"  --dump <path>          memory dump path on exit\n"
"  --no-dump              skip the dump-on-exit\n"
"  --console              full-screen console UI\n"
"  --terminal             terminal-emulator UI (mutually exclusive with --console)\n"
"  --show-repaints        flash on console/terminal repaints (debug)\n"
"  --server               long-running server: as argv[1] dispatches into\n"
"                         server_main; after argv[1] enables one-shot reuse loop\n"
"  --mhz <speed>          wall-clock throttle target (emulated MHz)\n"
"  --cpu-mhz <speed>      assumed CPU MHz for --baud timing\n"
"  --baud <rate>          serial-port baud rate (requires --mhz or --cpu-mhz)\n"
"  --rows N               override terminal rows\n"
"  --cols N               override terminal cols\n"
"  --machine <name>       'nmos-default' (default) or 'wendy2c'\n"
"  --cpu <variant>        'nmos' or '65c02' (wendy2c forces '65c02')\n"
"  --rom <path>           wendy2c: ROM image (else falls back to <code file>)\n"
"  --serial-input <path>  wendy2c: bytes pre-queued into the SERIAL_USB chip\n"
"  --live                 wendy2c: live ANSI render of LCD, LED, button, VIA pin state\n"
"                         (saves the terminal; q/ESC/Ctrl-C to quit; space toggles button)\n"
"  --cycle-cap N          max cycles before forced exit (decimal; default 200000000;\n"
"                         no cap under --live unless this is given explicitly).\n"
"                         For wendy2c this is oscillator ticks (~2 per CPU cycle);\n"
"                         for nmos-default and --server it is CPU cycles.\n");
}

/* Helper: --FLAG VALUE. Returns 0 on success, sets *value_out and
 * advances *idx by 2; returns 1 on missing value. */
static int take_str_value(int argc, char **argv, int *idx, const char *flag, const char **value_out) {
    if (*idx + 1 >= argc) {
        fprintf(stderr, "error: %s requires a value\n", flag);
        return 1;
    }
    *value_out = argv[*idx + 1];
    *idx += 2;
    return 0;
}

int parse_args(int argc, char **argv, struct emu_opts *opts) {
    emu_opts_init(opts);

    if (argc < 2) {
        emu_opts_usage(stderr);
        return 1;
    }

    /* --server as first argument: special path. Caller dispatches into
     * server_main and ignores the rest of the struct. */
    if (strcmp(argv[1], "--server") == 0) {
        opts->server_main_dispatch = 1;
        return 0;
    }

    opts->code_filename = argv[1];

    int i = 2;
    while (i < argc && strncmp(argv[i], "--", 2) == 0) {
        if (strcmp(argv[i], "--console") == 0) {
            opts->console_mode = 1;
            i++;
        } else if (strcmp(argv[i], "--terminal") == 0) {
            opts->terminal_mode = 1;
            i++;
        } else if (strcmp(argv[i], "--load") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --load requires a value\n");
                return 1;
            }
            opts->load_address = strtol(argv[i + 1], NULL, 16);
            if (opts->load_address < 0 || opts->load_address > 0xffff) {
                fprintf(stderr, "error: --load value must be between 0 and ffff\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--input") == 0) {
            if (take_str_value(argc, argv, &i, "--input", &opts->input_filename)) return 1;
            opts->input_specified = 1;
        } else if (strcmp(argv[i], "--output") == 0) {
            if (take_str_value(argc, argv, &i, "--output", &opts->output_filename)) return 1;
            opts->output_specified = 1;
        } else if (strcmp(argv[i], "--error-output") == 0) {
            if (take_str_value(argc, argv, &i, "--error-output", &opts->error_output_filename)) return 1;
        } else if (strcmp(argv[i], "--dump") == 0) {
            if (take_str_value(argc, argv, &i, "--dump", &opts->dump_filename)) return 1;
        } else if (strcmp(argv[i], "--no-dump") == 0) {
            opts->no_dump = 1;
            i++;
        } else if (strcmp(argv[i], "--rows") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --rows requires a value\n");
                return 1;
            }
            opts->override_rows = (int)strtol(argv[i + 1], NULL, 10);
            if (opts->override_rows <= 0) {
                fprintf(stderr, "error: --rows value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--cols") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --cols requires a value\n");
                return 1;
            }
            opts->override_cols = (int)strtol(argv[i + 1], NULL, 10);
            if (opts->override_cols <= 0) {
                fprintf(stderr, "error: --cols value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--mhz") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --mhz requires a value\n");
                return 1;
            }
            opts->target_mhz = strtod(argv[i + 1], NULL);
            if (opts->target_mhz <= 0.0) {
                fprintf(stderr, "error: --mhz value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--cpu-mhz") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --cpu-mhz requires a value\n");
                return 1;
            }
            opts->cpu_mhz = strtod(argv[i + 1], NULL);
            if (opts->cpu_mhz <= 0.0) {
                fprintf(stderr, "error: --cpu-mhz value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--baud") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --baud requires a value\n");
                return 1;
            }
            opts->serial_baud = (int)strtol(argv[i + 1], NULL, 10);
            if (opts->serial_baud <= 0) {
                fprintf(stderr, "error: --baud value must be positive\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--show-repaints") == 0) {
            opts->show_repaints = 1;
            i++;
        } else if (strcmp(argv[i], "--server") == 0) {
            opts->server_mode = 1;
            i++;
        } else if (strcmp(argv[i], "--machine") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --machine requires a value\n");
                return 1;
            }
            const char *m = argv[i + 1];
            if (strcmp(m, "nmos-default") == 0) opts->machine = MACHINE_NMOS_DEFAULT;
            else if (strcmp(m, "wendy2c") == 0) opts->machine = MACHINE_WENDY2C;
            else {
                fprintf(stderr, "error: --machine value must be 'nmos-default' or 'wendy2c'\n");
                return 1;
            }
            i += 2;
        } else if (strcmp(argv[i], "--rom") == 0) {
            if (take_str_value(argc, argv, &i, "--rom", &opts->rom_filename)) return 1;
        } else if (strcmp(argv[i], "--serial-input") == 0) {
            if (take_str_value(argc, argv, &i, "--serial-input", &opts->serial_input_filename)) return 1;
        } else if (strcmp(argv[i], "--live") == 0) {
            opts->live = 1;
            i++;
        } else if (strcmp(argv[i], "--cycle-cap") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --cycle-cap requires a value\n");
                return 1;
            }
            char *end;
            unsigned long long v = strtoull(argv[i + 1], &end, 10);
            if (*end != '\0' || v == 0) {
                fprintf(stderr, "error: --cycle-cap value must be a positive decimal integer\n");
                return 1;
            }
            opts->cycle_cap = (uint64_t)v;
            opts->cycle_cap_set = 1;
            i += 2;
        } else if (strcmp(argv[i], "--cpu") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --cpu requires a value\n");
                return 1;
            }
            const char *c = argv[i + 1];
            if (strcmp(c, "nmos") == 0) opts->cpu_variant_opt = CPU_NMOS;
            else if (strcmp(c, "65c02") == 0) opts->cpu_variant_opt = CPU_65C02;
            else {
                fprintf(stderr, "error: --cpu value must be 'nmos' or '65c02'\n");
                return 1;
            }
            i += 2;
        } else {
            fprintf(stderr, "error: unknown option %s\n", argv[i]);
            return 1;
        }
    }

    if (opts->console_mode && opts->terminal_mode) {
        fprintf(stderr, "error: --console and --terminal are mutually exclusive\n");
        return 1;
    }

    if (opts->serial_baud > 0 && opts->cpu_mhz <= 0.0 && opts->target_mhz <= 0.0) {
        fprintf(stderr, "error: --baud requires --cpu-mhz or --mhz\n");
        return 1;
    }

    if (opts->live && opts->machine != MACHINE_WENDY2C) {
        fprintf(stderr, "error: --live currently requires --machine wendy2c\n");
        return 1;
    }

    /* --machine wendy2c defaults --cpu to 65c02. */
    if (opts->machine == MACHINE_WENDY2C && opts->cpu_variant_opt == CPU_VARIANT_UNSET) {
        opts->cpu_variant_opt = CPU_65C02;
    }
    /* --machine wendy2c + --cpu nmos is invalid (wendy2c is a W65C02S board). */
    if (opts->machine == MACHINE_WENDY2C && opts->cpu_variant_opt == CPU_NMOS) {
        fprintf(stderr, "error: --machine wendy2c requires --cpu 65c02\n");
        return 1;
    }
    /* For nmos-default, default --cpu to nmos. */
    if (opts->cpu_variant_opt == CPU_VARIANT_UNSET) {
        opts->cpu_variant_opt = CPU_NMOS;
    }

    opts->arg_base = i;
    return 0;
}
