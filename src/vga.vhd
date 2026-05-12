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
    SIGNAL h_count, v_count : STD_LOGIC_VECTOR(9 DOWNTO 0) := "0000000000";
BEGIN
    -- TEST: Drive sync signals with a simple pattern to verify pin connectivity
    hsync <= h_count(0);  -- Toggle at half the counter rate
    vsync <= v_count(0);
    r_out <= '0';
    g_out <= '0';
    b_out <= '0';
    in_screen <= '0';
    screen.pixel_x <= 0;
    screen.pixel_y <= 0;

    vga_controller: PROCESS
    BEGIN
        WAIT UNTIL (clock_25MHz'EVENT) AND (clock_25MHz = '1');
        IF (h_count = 799) THEN
            h_count <= "0000000000";
        ELSE
            h_count <= h_count + 1;
        END IF;
        
        IF (v_count >= 524) AND (h_count >= 699) THEN
            v_count <= "0000000000";
        ELSIF (h_count = 699) THEN
            v_count <= v_count + 1;
        END IF;
    END PROCESS vga_controller;
END display;
