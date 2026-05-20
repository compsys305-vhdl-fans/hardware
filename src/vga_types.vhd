LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

PACKAGE vga_types IS
    TYPE screen IS RECORD
        pixel_x : INTEGER RANGE 0 TO 639;
        pixel_y : INTEGER RANGE 0 TO 479;
    END RECORD;

    TYPE vga_screen IS RECORD
        pixel_x     : INTEGER RANGE 0 TO 799;
        pixel_y     : INTEGER RANGE 0 TO 524;
        hsync       : STD_LOGIC;
        vsync       : STD_LOGIC;
        video_on    : STD_LOGIC;
        video_on_h  : STD_LOGIC;
        video_on_v  : STD_LOGIC;
    END RECORD;
END PACKAGE vga_types;
