#include "greatest.h"
#include "../console.h"

#include <stdlib.h>
#include <string.h>

// Stubs for external dependencies used by console.c
uint64_t clockticks6502 = 0;
int terminal_interactive = 0;
int terminal_mode = 0;
FILE *serial_input_file = NULL;
FILE *serial_output_file = NULL;

int con_byte_ready(void) { return 0; }

// Helper: reset console to fresh state with given dimensions
static void console_init_test(int rows, int cols) {
    if (screen_cells) { free(screen_cells); screen_cells = NULL; }
    if (screen_attr) { free(screen_attr); screen_attr = NULL; }
    screen_rows = 0;
    screen_cols = 0;
    cursor_row = 0;
    cursor_col = 0;
    current_attr = 0;
    scroll_top = 0;
    scroll_bot = -1;
    show_repaints = 0;
    serial_reset();
    console_resize(rows, cols);
}

// Helper: get character at (row, col)
static char cell_at(int r, int c) {
    return screen_cells[r * screen_cols + c];
}

// Helper: get attribute at (row, col)
static unsigned char attr_at(int r, int c) {
    return screen_attr[r * screen_cols + c];
}

// Helper: feed a string byte-by-byte through console_handle_byte
static void feed_string(const char *s) {
    while (*s) console_handle_byte((unsigned char)*s++);
}

// Helper: fill screen cells directly (no wrapping/scrolling), cursor unchanged
static void fill_cells(const char *s) {
    for (int i = 0; s[i] && i < screen_rows * screen_cols; i++)
        screen_cells[i] = s[i];
}

TEST resize_allocates_correct_size(void) {
    console_init_test(5, 10);
    ASSERT_EQ(screen_rows, 5);
    ASSERT_EQ(screen_cols, 10);
    ASSERT(screen_cells != NULL);
    ASSERT(screen_attr != NULL);
    // All cells should be spaces
    for (int i = 0; i < 50; i++) {
        ASSERT_EQ(screen_cells[i], ' ');
        ASSERT_EQ(screen_attr[i], 0);
    }
    PASS();
}

TEST resize_rejects_invalid(void) {
    console_init_test(5, 10);
    console_resize(0, 10);   // should be ignored
    ASSERT_EQ(screen_rows, 5);
    console_resize(5, -1);   // should be ignored
    ASSERT_EQ(screen_cols, 10);
    PASS();
}

TEST resize_preserves_content(void) {
    console_init_test(3, 4);
    screen_cells[0] = 'A';
    screen_cells[1] = 'B';
    // Resize larger - old content preserved
    console_resize(5, 6);
    ASSERT_EQ(screen_rows, 5);
    ASSERT_EQ(screen_cols, 6);
    ASSERT_EQ(screen_cells[0], 'A');
    ASSERT_EQ(screen_cells[1], 'B');
    PASS();
}

TEST put_char_at_origin(void) {
    console_init_test(5, 10);
    console_put_char('X');
    ASSERT_EQ(cell_at(0, 0), 'X');
    ASSERT_EQ(cursor_row, 0);
    ASSERT_EQ(cursor_col, 1);
    PASS();
}

TEST put_char_with_attribute(void) {
    console_init_test(5, 10);
    current_attr = 1;  // reverse video
    console_put_char('R');
    ASSERT_EQ(cell_at(0, 0), 'R');
    ASSERT_EQ(attr_at(0, 0), 1);
    current_attr = 0;
    PASS();
}

TEST put_char_wraps_at_end_of_line(void) {
    console_init_test(5, 3);
    console_put_char('A');
    console_put_char('B');
    console_put_char('C');  // fills col 2, cursor wraps
    ASSERT_EQ(cursor_row, 1);
    ASSERT_EQ(cursor_col, 0);
    console_put_char('D');
    ASSERT_EQ(cell_at(1, 0), 'D');
    PASS();
}

TEST put_char_scrolls_at_bottom(void) {
    console_init_test(2, 3);
    // Fill both rows
    feed_string("ABCDEF");
    // Now cursor is at row 1, col 0 (wrapped from row 1 col 3)
    // Writing more should scroll
    console_put_char('G');
    // Row 0 should now have what was row 1 (DEF)
    ASSERT_EQ(cell_at(0, 0), 'D');
    ASSERT_EQ(cell_at(0, 1), 'E');
    ASSERT_EQ(cell_at(0, 2), 'F');
    PASS();
}

TEST clear_line_mode0_right(void) {
    console_init_test(3, 5);
    feed_string("HELLO");
    cursor_row = 0;
    cursor_col = 2;
    console_clear_line(0);  // clear from cursor to end
    ASSERT_EQ(cell_at(0, 0), 'H');
    ASSERT_EQ(cell_at(0, 1), 'E');
    ASSERT_EQ(cell_at(0, 2), ' ');
    ASSERT_EQ(cell_at(0, 3), ' ');
    ASSERT_EQ(cell_at(0, 4), ' ');
    PASS();
}

TEST clear_line_mode1_left(void) {
    console_init_test(3, 5);
    feed_string("HELLO");
    cursor_row = 0;
    cursor_col = 2;
    console_clear_line(1);  // clear from start to cursor (inclusive)
    ASSERT_EQ(cell_at(0, 0), ' ');
    ASSERT_EQ(cell_at(0, 1), ' ');
    ASSERT_EQ(cell_at(0, 2), ' ');
    ASSERT_EQ(cell_at(0, 3), 'L');
    ASSERT_EQ(cell_at(0, 4), 'O');
    PASS();
}

TEST clear_line_mode2_whole(void) {
    console_init_test(3, 5);
    feed_string("HELLO");
    cursor_row = 0;
    cursor_col = 2;
    console_clear_line(2);
    for (int c = 0; c < 5; c++)
        ASSERT_EQ(cell_at(0, c), ' ');
    PASS();
}

TEST clear_screen_mode2_all(void) {
    console_init_test(3, 5);
    fill_cells("ABCDEFGHIJKLMNO");
    console_clear_screen(2);
    for (int i = 0; i < 15; i++)
        ASSERT_EQ(screen_cells[i], ' ');
    PASS();
}

TEST clear_screen_mode0_below(void) {
    console_init_test(3, 3);
    fill_cells("ABCDEFGHI");
    cursor_row = 1;
    cursor_col = 1;
    console_clear_screen(0);  // clear from cursor to end
    // Row 0 should be untouched
    ASSERT_EQ(cell_at(0, 0), 'A');
    ASSERT_EQ(cell_at(0, 1), 'B');
    ASSERT_EQ(cell_at(0, 2), 'C');
    // Row 1: cols 0 untouched, cols 1-2 cleared
    ASSERT_EQ(cell_at(1, 0), 'D');
    ASSERT_EQ(cell_at(1, 1), ' ');
    ASSERT_EQ(cell_at(1, 2), ' ');
    // Row 2: all cleared
    ASSERT_EQ(cell_at(2, 0), ' ');
    PASS();
}

TEST scroll_region_up_moves_data(void) {
    console_init_test(4, 3);
    fill_cells("ABCDEFGHIJKL");
    console_scroll_region_up(0, 3, 1);
    // row0 should now have DEF (was row1)
    ASSERT_EQ(cell_at(0, 0), 'D');
    ASSERT_EQ(cell_at(0, 1), 'E');
    ASSERT_EQ(cell_at(0, 2), 'F');
    // row3 should be blank (new row)
    ASSERT_EQ(cell_at(3, 0), ' ');
    ASSERT_EQ(cell_at(3, 1), ' ');
    PASS();
}

TEST scroll_region_down_moves_data(void) {
    console_init_test(4, 3);
    fill_cells("ABCDEFGHIJKL");
    console_scroll_region_down(0, 3, 1);
    // row0 should be blank (new row)
    ASSERT_EQ(cell_at(0, 0), ' ');
    // row1 should have ABC (was row0)
    ASSERT_EQ(cell_at(1, 0), 'A');
    ASSERT_EQ(cell_at(1, 1), 'B');
    ASSERT_EQ(cell_at(1, 2), 'C');
    PASS();
}

TEST scroll_region_partial(void) {
    console_init_test(5, 3);
    fill_cells("ABCDEFGHIJKLMNO");
    // Scroll rows 1-3 up by 1
    console_scroll_region_up(1, 3, 1);
    // row0 unchanged
    ASSERT_EQ(cell_at(0, 0), 'A');
    // row1 = was row2 (GHI)
    ASSERT_EQ(cell_at(1, 0), 'G');
    // row2 = was row3 (JKL)
    ASSERT_EQ(cell_at(2, 0), 'J');
    // row3 = blank
    ASSERT_EQ(cell_at(3, 0), ' ');
    // row4 unchanged
    ASSERT_EQ(cell_at(4, 0), 'M');
    PASS();
}

TEST handle_byte_printable(void) {
    console_init_test(5, 10);
    console_handle_byte('A');
    ASSERT_EQ(cell_at(0, 0), 'A');
    ASSERT_EQ(cursor_col, 1);
    PASS();
}

TEST handle_byte_cr(void) {
    console_init_test(5, 10);
    cursor_col = 5;
    console_handle_byte('\r');
    ASSERT_EQ(cursor_col, 0);
    ASSERT_EQ(cursor_row, 0);
    PASS();
}

TEST handle_byte_lf(void) {
    console_init_test(5, 10);
    cursor_row = 1;
    console_handle_byte('\n');
    ASSERT_EQ(cursor_row, 2);
    PASS();
}

TEST handle_byte_lf_scrolls_at_bottom(void) {
    console_init_test(3, 3);
    fill_cells("ABCDEFGHI");
    cursor_row = 2;
    cursor_col = 0;
    console_handle_byte('\n');
    // Should have scrolled: row0 = DEF (was row1)
    ASSERT_EQ(cell_at(0, 0), 'D');
    ASSERT_EQ(cursor_row, 2);
    PASS();
}

TEST handle_byte_backspace(void) {
    console_init_test(5, 10);
    cursor_col = 3;
    console_handle_byte('\b');
    ASSERT_EQ(cursor_col, 2);
    // Should not go below 0
    cursor_col = 0;
    console_handle_byte('\b');
    ASSERT_EQ(cursor_col, 0);
    PASS();
}

TEST handle_byte_tab(void) {
    console_init_test(5, 20);
    cursor_col = 0;
    console_handle_byte('\t');
    ASSERT_EQ(cursor_col, 8);
    console_handle_byte('\t');
    ASSERT_EQ(cursor_col, 16);
    PASS();
}

TEST csi_cursor_up(void) {
    console_init_test(10, 10);
    cursor_row = 5;
    feed_string("\x1b[2A");  // CUU 2
    ASSERT_EQ(cursor_row, 3);
    PASS();
}

TEST csi_cursor_down(void) {
    console_init_test(10, 10);
    cursor_row = 3;
    feed_string("\x1b[2B");  // CUD 2
    ASSERT_EQ(cursor_row, 5);
    PASS();
}

TEST csi_cursor_forward(void) {
    console_init_test(10, 10);
    cursor_col = 2;
    feed_string("\x1b[3C");  // CUF 3
    ASSERT_EQ(cursor_col, 5);
    PASS();
}

TEST csi_cursor_back(void) {
    console_init_test(10, 10);
    cursor_col = 5;
    feed_string("\x1b[2D");  // CUB 2
    ASSERT_EQ(cursor_col, 3);
    PASS();
}

TEST csi_cup_position(void) {
    console_init_test(10, 10);
    feed_string("\x1b[3;7H");  // CUP row=3, col=7
    ASSERT_EQ(cursor_row, 2);  // 0-based
    ASSERT_EQ(cursor_col, 6);  // 0-based
    PASS();
}

TEST csi_cup_default(void) {
    console_init_test(10, 10);
    cursor_row = 5;
    cursor_col = 5;
    feed_string("\x1b[H");  // CUP with no params = home
    ASSERT_EQ(cursor_row, 0);
    ASSERT_EQ(cursor_col, 0);
    PASS();
}

TEST csi_erase_display(void) {
    console_init_test(3, 3);
    fill_cells("ABCDEFGHI");
    feed_string("\x1b[2J");  // clear entire screen
    for (int i = 0; i < 9; i++)
        ASSERT_EQ(screen_cells[i], ' ');
    PASS();
}

TEST csi_erase_line(void) {
    console_init_test(3, 5);
    feed_string("HELLO");
    cursor_row = 0;
    cursor_col = 2;
    feed_string("\x1b[K");  // clear from cursor to end of line (mode 0)
    ASSERT_EQ(cell_at(0, 0), 'H');
    ASSERT_EQ(cell_at(0, 1), 'E');
    ASSERT_EQ(cell_at(0, 2), ' ');
    ASSERT_EQ(cell_at(0, 3), ' ');
    PASS();
}

TEST csi_sgr_reverse(void) {
    console_init_test(5, 10);
    feed_string("\x1b[7m");  // reverse video
    ASSERT_EQ(current_attr, 1);
    feed_string("\x1b[0m");  // reset
    ASSERT_EQ(current_attr, 0);
    PASS();
}

TEST csi_scroll_region(void) {
    console_init_test(10, 10);
    feed_string("\x1b[2;8r");  // set scroll region rows 2-8
    ASSERT_EQ(scroll_top, 1);  // 0-based
    ASSERT_EQ(scroll_bot, 7);  // 0-based
    PASS();
}

TEST csi_scroll_up(void) {
    console_init_test(4, 3);
    fill_cells("ABCDEFGHIJKL");
    feed_string("\x1b[1S");  // scroll up 1
    ASSERT_EQ(cell_at(0, 0), 'D');
    ASSERT_EQ(cell_at(3, 0), ' ');
    PASS();
}

TEST csi_scroll_down(void) {
    console_init_test(4, 3);
    fill_cells("ABCDEFGHIJKL");
    feed_string("\x1b[1T");  // scroll down 1
    ASSERT_EQ(cell_at(0, 0), ' ');
    ASSERT_EQ(cell_at(1, 0), 'A');
    PASS();
}

TEST csi_dsr_injects_response(void) {
    console_init_test(10, 10);
    cursor_row = 4;
    cursor_col = 7;
    feed_string("\x1b[6n");  // DSR - request cursor position
    // Should inject ESC[5;8R into serial_inject_buf
    ASSERT(serial_inject_len > 0);
    char expected[32];
    snprintf(expected, sizeof(expected), "\x1b[%d;%dR", 5, 8);
    ASSERT_EQ(serial_inject_len, (int)strlen(expected));
    ASSERT_MEM_EQ(serial_inject_buf, expected, (size_t)serial_inject_len);
    PASS();
}

TEST csi_private_sequence_ignored(void) {
    console_init_test(10, 10);
    cursor_row = 3;
    cursor_col = 5;
    feed_string("\x1b[?25h");  // show cursor - private sequence, should be ignored
    ASSERT_EQ(cursor_row, 3);
    ASSERT_EQ(cursor_col, 5);
    PASS();
}

TEST serial_reset_clears_state(void) {
    serial_rx_head = 5;
    serial_rx_tail = 3;
    serial_tx_head = 10;
    serial_tx_tail = 2;
    serial_reset();
    ASSERT_EQ(serial_rx_head, 0);
    ASSERT_EQ(serial_rx_tail, 0);
    ASSERT_EQ(serial_tx_head, 0);
    ASSERT_EQ(serial_tx_tail, 0);
    PASS();
}

TEST serial_inject_stores_bytes(void) {
    console_init_test(5, 5);
    serial_inject_response("AB");
    ASSERT_EQ(serial_inject_len, 2);
    ASSERT_EQ(serial_inject_buf[0], 'A');
    ASSERT_EQ(serial_inject_buf[1], 'B');
    // Append more
    serial_inject_response("CD");
    ASSERT_EQ(serial_inject_len, 4);
    ASSERT_EQ(serial_inject_buf[2], 'C');
    ASSERT_EQ(serial_inject_buf[3], 'D');
    PASS();
}

TEST serial_rx_tx_count(void) {
    serial_reset();
    ASSERT_EQ(serial_rx_count(), 0);
    ASSERT_EQ(serial_tx_count(), 0);
    serial_rx_buf[0] = 'X';
    serial_rx_head = 1;
    ASSERT_EQ(serial_rx_count(), 1);
    serial_tx_buf[0] = 'Y';
    serial_tx_head = 3;
    ASSERT_EQ(serial_tx_count(), 3);
    PASS();
}

SUITE(console_suite) {
    RUN_TEST(resize_allocates_correct_size);
    RUN_TEST(resize_rejects_invalid);
    RUN_TEST(resize_preserves_content);
    RUN_TEST(put_char_at_origin);
    RUN_TEST(put_char_with_attribute);
    RUN_TEST(put_char_wraps_at_end_of_line);
    RUN_TEST(put_char_scrolls_at_bottom);
    RUN_TEST(clear_line_mode0_right);
    RUN_TEST(clear_line_mode1_left);
    RUN_TEST(clear_line_mode2_whole);
    RUN_TEST(clear_screen_mode2_all);
    RUN_TEST(clear_screen_mode0_below);
    RUN_TEST(scroll_region_up_moves_data);
    RUN_TEST(scroll_region_down_moves_data);
    RUN_TEST(scroll_region_partial);
    RUN_TEST(handle_byte_printable);
    RUN_TEST(handle_byte_cr);
    RUN_TEST(handle_byte_lf);
    RUN_TEST(handle_byte_lf_scrolls_at_bottom);
    RUN_TEST(handle_byte_backspace);
    RUN_TEST(handle_byte_tab);
    RUN_TEST(csi_cursor_up);
    RUN_TEST(csi_cursor_down);
    RUN_TEST(csi_cursor_forward);
    RUN_TEST(csi_cursor_back);
    RUN_TEST(csi_cup_position);
    RUN_TEST(csi_cup_default);
    RUN_TEST(csi_erase_display);
    RUN_TEST(csi_erase_line);
    RUN_TEST(csi_sgr_reverse);
    RUN_TEST(csi_scroll_region);
    RUN_TEST(csi_scroll_up);
    RUN_TEST(csi_scroll_down);
    RUN_TEST(csi_dsr_injects_response);
    RUN_TEST(csi_private_sequence_ignored);
    RUN_TEST(serial_reset_clears_state);
    RUN_TEST(serial_inject_stores_bytes);
    RUN_TEST(serial_rx_tx_count);
}

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(console_suite);
    GREATEST_MAIN_END();
}
