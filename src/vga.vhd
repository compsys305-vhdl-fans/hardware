LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

LIBRARY PROJECT_CONFIG;
USE PROJECT_CONFIG.TYPES.ALL;

ENTITY vga IS
    PORT (
        clock_25MHz : IN STD_LOGIC;
        r_in        : IN STD_LOGIC;
        g_in        : IN STD_LOGIC;
        b_in        : IN STD_LOGIC;
        r_out       : OUT STD_LOGIC;
        g_out       : OUT STD_LOGIC;
        b_out       : OUT STD_LOGIC;
        hsync       : OUT STD_LOGIC;
        vsync       : OUT STD_LOGIC;
        in_screen   : OUT STD_LOGIC;
        screen      : OUT SCREEN
    );
END vga;

ARCHITECTURE display OF vga IS
    SIGNAL horiz_sync, vert_sync : STD_LOGIC;
    SIGNAL video_on, video_on_v, video_on_h : STD_LOGIC;
    SIGNAL h_count, v_count : STD_LOGIC_VECTOR(9 DOWNTO 0);
BEGIN
    -- video_on is high only when RGB data is displayed
    video_on <= video_on_h AND video_on_v;

    vga_controller: PROCESS
    BEGIN
        WAIT UNTIL (clock_25MHz'EVENT) AND (clock_25MHz = '1');

        -- Generate Horizontal and Vertical Timing Signals for Video Signal
        -- H_count counts pixels (640 + extra time for sync signals)
        --
        --  Horiz_sync  ------------------------------------__________--------
        --  H_count       0                640             659       755    799
        --
        IF (h_count = 799) THEN
            h_count <= "0000000000";
        ELSE
            h_count <= h_count + 1;
        END IF;

        -- Generate Horizontal Sync Signal using H_count
        IF (h_count <= 755) AND (h_count >= 659) THEN
            horiz_sync <= '0';
        ELSE
            horiz_sync <= '1';
        END IF;

        -- V_count counts rows of pixels (480 + extra time for sync signals)
        --
        --  Vert_sync      -----------------------------------------------_______------------
        --  V_count         0                                      480    493-494          524
        --
        IF (v_count >= 524) AND (h_count >= 699) THEN
            v_count <= "0000000000";
        ELSIF (h_count = 699) THEN
            v_count <= v_count + 1;
        END IF;

        -- Generate Vertical Sync Signal using V_count
        IF (v_count <= 494) AND (v_count >= 493) THEN
            vert_sync <= '0';
        ELSE
            vert_sync <= '1';
        END IF;

        -- Generate Video on Screen Signals for Pixel Data
        IF (h_count <= 639) THEN
            video_on_h <= '1';
            screen.pixel_x <= CONV_INTEGER(h_count);
        ELSE
            video_on_h <= '0';
        END IF;

        IF (v_count <= 479) THEN
            video_on_v <= '1';
            screen.pixel_y <= CONV_INTEGER(v_count);
        ELSE
            video_on_v <= '0';
        END IF;

        -- Generate in_screen signal for *requested* pixel position
        IF (h_count <= 639) AND (v_count <= 479) THEN
            in_screen <= '1';
        ELSE
            in_screen <= '0';
        END IF;

        -- Put all video signals through registers to improve timing
        r_out <= r_in AND video_on;
        g_out <= g_in AND video_on;
        b_out <= b_in AND video_on;
        hsync <= horiz_sync;
        vsync <= vert_sync;

    END PROCESS vga_controller;
END display;
