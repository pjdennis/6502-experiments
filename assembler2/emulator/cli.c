#include "cli.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
}

void emu_opts_usage(FILE *fp) {
    fprintf(fp, "usage: emulator <code file> [--load <hex load address>] [--input <input file>] [--output <output file>] [--error-output <file>] [--dump <dump file>] [--no-dump] [--console] [--terminal] [--server] [--mhz <speed>] [--cpu-mhz <speed>] [--baud <rate>] [--rows N] [--cols N] [<arguments>]\n");
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

    opts->arg_base = i;
    return 0;
}
