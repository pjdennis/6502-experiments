#include "greatest.h"
#include "../file_io.h"

#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <setjmp.h>

// Stubs for emulator functions that file_io.c calls
static int emulation_exit_called = 0;
static int emulation_exit_code = 0;
static jmp_buf test_abort_jmp;

void restore_terminal(void) {}

void emulation_exit(int code) {
    emulation_exit_called = 1;
    emulation_exit_code = code;
    longjmp(test_abort_jmp, 1);
}

static void reset_stubs(void) {
    emulation_exit_called = 0;
    emulation_exit_code = 0;
}

// Helper: create a temp file with content, return path (caller frees)
static char* make_temp_file(const char* content) {
    char *path = strdup("/tmp/test_file_io_XXXXXX");
    int fd = mkstemp(path);
    if (content && *content) {
        write(fd, content, strlen(content));
    }
    close(fd);
    return path;
}

TEST files_init_clears_handles(void) {
    files[5] = (FILE*)0xDEAD;
    dir_state[5] = (DirState*)0xBEEF;
    files_init(NULL);
    ASSERT_EQ(files[0], NULL);
    ASSERT_EQ(files[5], NULL);
    ASSERT_EQ(dir_state[5], NULL);
    PASS();
}

TEST files_init_sets_stdin(void) {
    FILE* fake_stdin = (FILE*)0x1234;
    files_init(fake_stdin);
    ASSERT_EQ(files[0], fake_stdin);
    PASS();
}

TEST file_open_read_close_roundtrip(void) {
    char *path = make_temp_file("hello");
    files_init(NULL);
    reset_stubs();

    uint8_t handle = file_open(path);
    ASSERT(handle >= 2);  // handle 1 is stdin

    int ch = file_read(handle);
    ASSERT_EQ(ch, 'h');
    ch = file_read(handle);
    ASSERT_EQ(ch, 'e');

    file_close(handle);
    unlink(path);
    free(path);
    PASS();
}

TEST file_open_nonexistent_returns_zero(void) {
    files_init(NULL);
    reset_stubs();

    uint8_t handle = file_open("/tmp/nonexistent_test_file_io_xyz");
    ASSERT_EQ(handle, 0);
    PASS();
}

TEST file_write_roundtrip(void) {
    char *path = make_temp_file("");
    files_init(NULL);
    reset_stubs();

    uint8_t handle = file_open_for_write(path);
    ASSERT(handle >= 2);

    file_write(handle, 'A');
    file_write(handle, 'B');
    file_close(handle);

    // Read back and verify
    FILE* f = fopen(path, "rb");
    char buf[16] = {0};
    fread(buf, 1, 16, f);
    fclose(f);
    ASSERT_STR_EQ(buf, "AB");

    unlink(path);
    free(path);
    PASS();
}

TEST files_destroy_reports_unclosed(void) {
    char *path = make_temp_file("data");
    files_init(NULL);
    reset_stubs();

    file_open(path);  // open but don't close

    int count = files_destroy();
    ASSERT_EQ(count, 1);

    unlink(path);
    free(path);
    PASS();
}

TEST files_destroy_zero_when_all_closed(void) {
    char *path = make_temp_file("data");
    files_init(NULL);
    reset_stubs();

    uint8_t handle = file_open(path);
    file_close(handle);

    int count = files_destroy();
    ASSERT_EQ(count, 0);

    unlink(path);
    free(path);
    PASS();
}

TEST file_close_standard_file_errors(void) {
    files_init(NULL);
    reset_stubs();

    if (setjmp(test_abort_jmp) == 0) {
        file_close(1);  // try to close stdin handle
        FAIL();  // should not reach here
    }
    ASSERT(emulation_exit_called);
    ASSERT_EQ(emulation_exit_code, 1);
    PASS();
}

TEST dir_open_reads_entries(void) {
    // Create temp directory with known files
    char tmpdir[] = "/tmp/test_dir_io_XXXXXX";
    mkdtemp(tmpdir);

    char path1[256], path2[256];
    snprintf(path1, sizeof(path1), "%s/alpha.txt", tmpdir);
    snprintf(path2, sizeof(path2), "%s/beta.txt", tmpdir);
    FILE *f1 = fopen(path1, "w"); fclose(f1);
    FILE *f2 = fopen(path2, "w"); fclose(f2);

    files_init(NULL);
    reset_stubs();

    uint8_t handle = dir_open(tmpdir);
    ASSERT(handle >= 2);

    // Read metadata byte + "alpha.txt\0" + metadata byte + "beta.txt\0"
    int meta1 = file_read(handle);
    ASSERT_EQ(meta1, 0x00);  // regular file

    char name[64];
    int i = 0;
    int ch;
    while ((ch = file_read(handle)) != 0 && ch != EOF)
        name[i++] = ch;
    name[i] = '\0';
    ASSERT_STR_EQ(name, "alpha.txt");

    file_close(handle);
    unlink(path1);
    unlink(path2);
    rmdir(tmpdir);
    PASS();
}

SUITE(file_io_suite) {
    RUN_TEST(files_init_clears_handles);
    RUN_TEST(files_init_sets_stdin);
    RUN_TEST(file_open_read_close_roundtrip);
    RUN_TEST(file_open_nonexistent_returns_zero);
    RUN_TEST(file_write_roundtrip);
    RUN_TEST(files_destroy_reports_unclosed);
    RUN_TEST(files_destroy_zero_when_all_closed);
    RUN_TEST(file_close_standard_file_errors);
    RUN_TEST(dir_open_reads_entries);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(file_io_suite);
    GREATEST_MAIN_END();
}
