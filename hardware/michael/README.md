# Michael

The second board (v2, 2021). Its firmware is in `firmware/boards/michael/` and `firmware/programs/michael/`.

- [`arduino/`](arduino/): the Arduino sketches used as a monitor and programmer for Michael (from 2021-01-22, `6b02ccc`). Also the Python host scripts and small 6502 programs run through them. `compile_and_upload.sh` / `compile_and_program.sh` assemble with `firmware/vasm`.
- `michael-2023-12-04.rom`: a ROM image from 2023-12-04 (committed on michael_keyboard_wip).
