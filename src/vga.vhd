LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

LIBRARY PROJECT_CONFIG;
USE PROJECT_CONFIG.TYPES.ALL;

ENTITY vga IS
    PORT (
        clock_25MHz : IN STD_LOGIC;
        r_in        : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        g_in        : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        b_in        : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        r_out       : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        g_out       : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        b_out       : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        hsync       : OUT STD_LOGIC;
        vsync       : OUT STD_LOGIC;
        in_screen   : OUT STD_LOGIC;
        screen      : OUT SCREEN
    );
END vga;

ARCHITECTURE display OF vga IS
    SIGNAL vga_s        : VGA_SCREEN;
BEGIN
    -- video only when we are within the visible area
    vga_s.video_on <= vga_s.video_on_h AND vga_s.video_on_v;

    vga_controller: PROCESS (clock_25MHz)
        VARIABLE req_on : STD_LOGIC;
    BEGIN
        IF RISING_EDGE(clock_25MHz) THEN
            -- horizontal sync
            IF (vga_s.pixel_x = 799) THEN
                vga_s.pixel_x <= 0;
            ELSE
                vga_s.pixel_x <= vga_s.pixel_x + 1;
            END IF;

            IF (vga_s.pixel_x <= 755) AND (vga_s.pixel_x >= 659) THEN
                vga_s.hsync <= '0';
            ELSE
                vga_s.hsync <= '1';
            END IF;

            -- Match the known-good DE0-CV VGA_SYNC timing.
            IF (vga_s.pixel_y >= 524) AND (vga_s.pixel_x >= 699) THEN
                vga_s.pixel_y <= 0;
            ELSIF (vga_s.pixel_x = 699) THEN
                vga_s.pixel_y <= vga_s.pixel_y + 1;
            END IF;

            IF (vga_s.pixel_y <= 494) AND (vga_s.pixel_y >= 493) THEN
                vga_s.vsync <= '0';
            ELSE
                vga_s.vsync <= '1';
            END IF;

            -- generate video on/off signals
            IF (vga_s.pixel_x <= 639) THEN
                vga_s.video_on_h <= '1';
                screen.pixel_x <= vga_s.pixel_x;
            ELSE
                vga_s.video_on_h <= '0';
            END IF;

            IF (vga_s.pixel_y <= 479) THEN
                vga_s.video_on_v <= '1';
                screen.pixel_y <= vga_s.pixel_y;
            ELSE
                vga_s.video_on_v <= '0';
            END IF;

            -- Whether the *requested* pixel position is within the visible screen.
            IF (vga_s.pixel_x <= 639) AND (vga_s.pixel_y <= 479) THEN
                req_on := '1';
            ELSE
                req_on := '0';
            END IF;
            in_screen <= req_on;

            -- drive display outputs
            IF vga_s.video_on = '1' THEN
                r_out <= r_in;
                g_out <= g_in;
                b_out <= b_in;
            ELSE
                r_out <= (OTHERS => '0');
                g_out <= (OTHERS => '0');
                b_out <= (OTHERS => '0');
            END IF;
            hsync <= vga_s.hsync;
            vsync <= vga_s.vsync;
        END IF;
    END PROCESS vga_controller;
END display;
