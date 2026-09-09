//* This file contains ansi escape sequences
//* Do note, most of this was created by AI (and with that case is the exception)
//* It has been manually edited.

pub const clear = struct {
    pub const screen = "\x1b[2J";
    pub const screenToEnd = "\x1b[0J";
    pub const screenToStart = "\x1b[1J";

    pub const line = "\x1b[2K";
};

pub const cursor = struct {
    pub const home = "\x1b[H";

    pub const up = "\x1b[1A";
    pub const down = "\x1b[1B";
    pub const right = "\x1b[1C";
    pub const left = "\x1b[1D";

    pub const save = "\x1b[s";
    pub const restore = "\x1b[u";

    pub const set = "\x1b[{d};{d}H";

    pub const hide = "\x1b[?25l";
    pub const show = "\x1b[?25h";
};

pub const colors = struct {
    pub const reset = "\x1b[0m";

    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";

    pub const default = "\x1b[39m";
};

pub const styles = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";
    pub const blink = "\x1b[5m";
    pub const reverse = "\x1b[7m";
    pub const strikethrough = "\x1b[9m";
};

pub const screen = struct {
    pub const double_buffer = "\x1b[?47h";
};
