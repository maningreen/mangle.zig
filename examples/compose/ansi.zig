pub const reset = "\x1b[0m";

pub const text_attributes = struct {
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const italic = "\x1b[3m";
    const underline = "\x1b[4m";
    const reverse = "\x1b[7m";
};

pub const colors = struct {
    pub const regular = struct {
        pub const black = "\x1b[30m";
        pub const red = "\x1b[31m";
        pub const green = "\x1b[32m";
        pub const yellow = "\x1b[33m";
        pub const blue = "\x1b[34m";
        pub const magenta = "\x1b[35m";
        pub const cyan = "\x1b[36m";
        pub const white = "\x1b[37m";
    };
    pub const bright = struct {
        pub const black = "\x1b[90m";
        pub const red = "\x1b[91m";
        pub const green = "\x1b[92m";
        pub const yellow = "\x1b[93m";
        pub const blue = "\x1b[94m";
        pub const magenta = "\x1b[95m";
        pub const cyan = "\x1b[96m";
        pub const white = "\x1b[97m";
    };
};

pub const cursor_controls = struct {
    pub const up = "\x1b[{d}A"; // cursor up n
    pub const down = "\x1b[{d}B"; // cursor down n
    pub const right = "\x1b[{d}C"; // cursor right n
    pub const left = "\x1b[{d}D"; // cursor left n

    // \x1b[{d}E     // cursor down n lines, column 1
    // \x1b[{d}F     // cursor up n lines, column 1

    pub const set_col = "\x1b[{d}G"; // move to column n
    pub const set_pos = "\x1b[{d};{d}H"; // move to row n, column m
    // \x1b[{d};{d} f // same as H

    pub const home = "\x1b[H"; // home (1,1)
    pub const clear = "\x1b[2J"; // clear entire screen
    pub const clear_below = "\x1b[0J"; // clear from cursor down
    pub const clear_above = "\x1b[1J"; // clear from cursor up

    pub const clear_right = "\x1b[K"; // clear from cursor right
    pub const clear_left = "\x1b[1K"; // clear from cursor left
    pub const clear_line = "\x1b[2K"; // clear entire line

    pub const save = "\x1b[s"; // save cursor position
    pub const load = "\x1b[u"; // restore cursor position

    pub const hide = "\x1b[?25l"; // hide cursor
    pub const show = "\x1b[?25h"; // show cursor
};
