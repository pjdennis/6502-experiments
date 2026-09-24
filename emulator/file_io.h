#ifndef FILE_IO_H
#define FILE_IO_H

#include <stdio.h>
#include <stdint.h>

typedef struct {
    char *buffer;
    size_t buf_size;
    size_t buf_pos;
} DirState;

#define FILE_IO_MAX_HANDLES 255

extern FILE* files[FILE_IO_MAX_HANDLES];
extern DirState *dir_state[FILE_IO_MAX_HANDLES];

void files_init(FILE* input_file);
uint8_t file_open_with_mode(const char* name, const char* mode);
uint8_t file_open(const char* name);
uint8_t file_open_for_write(const char* name);
uint8_t dir_open(const char* name);
FILE* file_handle(uint8_t file);
void file_close(uint8_t file);
int file_read(uint8_t file);
int file_write(uint8_t file, uint8_t value);
int files_destroy(void);

#endif
