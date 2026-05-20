LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

USE STD.TEXTIO.ALL;

LIBRARY HARDWARE;
USE HARDWARE.VGA_TYPES.ALL;

ENTITY vga_tb IS
    PORT (
        -- finished: '0' while running, '1' when complete
        finished   : OUT STD_LOGIC := '0';
        -- error_code: 0 means success; nonzero encodes failure reason
        error_code : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00"
    );
END vga_tb;

ARCHITECTURE behaviour OF vga_tb IS

    SIGNAL finished_i   : STD_LOGIC := '0';
    SIGNAL error_code_i : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00";

    -- Component Declaration for the Unit Under Test (UUT)
    COMPONENT vga
        PORT(
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
    END COMPONENT;

    --Inputs
    SIGNAL clock_25MHz  : STD_LOGIC := '0';
    SIGNAL r_in         : STD_LOGIC := '0';
    SIGNAL g_in         : STD_LOGIC := '0';
    SIGNAL b_in         : STD_LOGIC := '0';

    --Outputs
    SIGNAL r_out        : STD_LOGIC;
    SIGNAL g_out        : STD_LOGIC;
    SIGNAL b_out        : STD_LOGIC;
    SIGNAL hsync        : STD_LOGIC;
    SIGNAL vsync        : STD_LOGIC;
    SIGNAL in_screen    : STD_LOGIC;
    SIGNAL screen       : SCREEN;

    -- Make key TB state visible (and loggable)
    SIGNAL tb_pixels_generated : INTEGER := 0;
    SIGNAL tb_last_x           : INTEGER := -1;
    SIGNAL tb_last_y           : INTEGER := -1;
    SIGNAL tb_cycle            : INTEGER := 0;

    -- Trace configuration
    CONSTANT TRACE_TO_FILE       : BOOLEAN := TRUE;
    CONSTANT TRACE_TO_TRANSCRIPT : BOOLEAN := FALSE;
    CONSTANT TRACE_EVERY_N       : POSITIVE := 1;      -- 1 = log every 25MHz tick
    CONSTANT TRANSCRIPT_EVERY_N  : POSITIVE := 2000;   -- reduce transcript spam

    -- Expected 640x480@60-ish timing, matching MiniprojectResources/vga_sync.vhd.
    CONSTANT H_VISIBLE_LAST : INTEGER := 639;
    CONSTANT H_SYNC_START   : INTEGER := 659;
    CONSTANT H_SYNC_END     : INTEGER := 755;
    CONSTANT H_LAST         : INTEGER := 799;
    CONSTANT V_VISIBLE_LAST : INTEGER := 479;
    CONSTANT V_COUNT_TICK   : INTEGER := 699;
    CONSTANT V_SYNC_START   : INTEGER := 493;
    CONSTANT V_SYNC_END     : INTEGER := 494;
    CONSTANT V_LAST         : INTEGER := 524;

    FILE trace_f : TEXT OPEN WRITE_MODE IS "log/vga_trace.csv";
BEGIN

    finished <= finished_i;
    error_code <= error_code_i;

    -- Instantiate the Unit Under Test (UUT)
    uut: vga PORT MAP (
        clock_25MHz => clock_25MHz,
        r_in => r_in,
        g_in => g_in,
        b_in => b_in,
        r_out => r_out,
        g_out => g_out,
        b_out => b_out,
        hsync => hsync,
        vsync => vsync,
        in_screen => in_screen,
        screen => screen
    );

    clk_gen: PROCESS
    BEGIN
        WHILE finished_i = '0' LOOP
            clock_25MHz <= '0';
            WAIT FOR 20 NS;  -- 25 MHz clock period
            clock_25MHz <= '1';
            WAIT FOR 20 NS;
        END LOOP;
        clock_25MHz <= '0';
        WAIT;
    END PROCESS clk_gen;

    -- Stimulus/check process:
    -- - Use `in_screen` to know whether the DUT is requesting a visible pixel.
    -- - Drive r/g/b based on the requested (x,y).
    -- - Check r/g/b outputs on the next clock against the previous driven values,
    --   expecting 0 during blanking.
    stim_proc: PROCESS
        VARIABLE pixels_generated : INTEGER := 0;
        VARIABLE last_x : INTEGER := -1;
        VARIABLE last_y : INTEGER := -1;

        VARIABLE have_prev : BOOLEAN := FALSE;
        VARIABLE prev_req_on : STD_LOGIC := '0';

        VARIABLE prev_r : STD_LOGIC := '0';
        VARIABLE prev_g : STD_LOGIC := '0';
        VARIABLE prev_b : STD_LOGIC := '0';

        VARIABLE cur_r : STD_LOGIC;
        VARIABLE cur_g : STD_LOGIC;
        VARIABLE cur_b : STD_LOGIC;

        VARIABLE expected_x      : INTEGER := 1;
        VARIABLE expected_y      : INTEGER := 0;
        VARIABLE current_x       : INTEGER := 0;
        VARIABLE expected_req_on : STD_LOGIC;
        VARIABLE expected_hsync  : STD_LOGIC;
        VARIABLE expected_vsync  : STD_LOGIC;
    BEGIN
        finished_i <= '0';
        error_code_i <= x"00";

        tb_pixels_generated <= 0;
        tb_last_x <= -1;
        tb_last_y <= -1;
        tb_cycle <= 0;

        -- Synchronize to the top-left visible pixel of a frame.
        LOOP
            WAIT UNTIL RISING_EDGE(clock_25MHz);
            WAIT FOR 0 NS;
            tb_cycle <= tb_cycle + 1;
            EXIT WHEN (screen.pixel_x = 0) AND (screen.pixel_y = 0) AND (in_screen = '1');
        END LOOP;

        -- Start a clean frame run.
        pixels_generated := 0;
        last_x := -1;
        last_y := -1;
        have_prev := FALSE;
        prev_req_on := '0';
        expected_x := 1;
        expected_y := 0;

        WHILE finished_i = '0' LOOP
            WAIT UNTIL RISING_EDGE(clock_25MHz);
            WAIT FOR 0 NS;

            tb_cycle <= tb_cycle + 1;

            -- Check outputs for the previous requested pixel.
            IF have_prev THEN
                IF prev_req_on = '1' THEN
                    IF (r_out /= prev_r) THEN
                        error_code_i <= "0001" & "00" & prev_r & r_out; -- visible, R, exp/act
                        finished_i <= '1';
                        WAIT;
                    ELSIF (g_out /= prev_g) THEN
                        error_code_i <= "0001" & "01" & prev_g & g_out; -- visible, G
                        finished_i <= '1';
                        WAIT;
                    ELSIF (b_out /= prev_b) THEN
                        error_code_i <= "0001" & "10" & prev_b & b_out; -- visible, B
                        finished_i <= '1';
                        WAIT;
                    END IF;
                ELSE
                    IF (r_out /= '0') THEN
                        error_code_i <= "0010" & "00" & '0' & r_out; -- blanking, R should be 0
                        finished_i <= '1';
                        WAIT;
                    ELSIF (g_out /= '0') THEN
                        error_code_i <= "0010" & "01" & '0' & g_out; -- blanking, G
                        finished_i <= '1';
                        WAIT;
                    ELSIF (b_out /= '0') THEN
                        error_code_i <= "0010" & "10" & '0' & b_out; -- blanking, B
                        finished_i <= '1';
                        WAIT;
                    END IF;
                END IF;
            END IF;

            IF (expected_x <= H_VISIBLE_LAST) AND (expected_y <= V_VISIBLE_LAST) THEN
                expected_req_on := '1';
            ELSE
                expected_req_on := '0';
            END IF;

            IF (expected_x >= H_SYNC_START) AND (expected_x <= H_SYNC_END) THEN
                expected_hsync := '0';
            ELSE
                expected_hsync := '1';
            END IF;

            IF (expected_y >= V_SYNC_START) AND (expected_y <= V_SYNC_END) THEN
                expected_vsync := '0';
            ELSE
                expected_vsync := '1';
            END IF;

            -- Check timing against the known-good VGA_SYNC counter behaviour.
            IF in_screen /= expected_req_on THEN
                error_code_i <= x"30";
                finished_i <= '1';
                WAIT;
            ELSIF hsync /= expected_hsync THEN
                error_code_i <= x"31";
                finished_i <= '1';
                WAIT;
            ELSIF vsync /= expected_vsync THEN
                error_code_i <= x"32";
                finished_i <= '1';
                WAIT;
            ELSIF expected_req_on = '1' THEN
                IF screen.pixel_x /= expected_x THEN
                    error_code_i <= x"33";
                    finished_i <= '1';
                    WAIT;
                ELSIF screen.pixel_y /= expected_y THEN
                    error_code_i <= x"34";
                    finished_i <= '1';
                    WAIT;
                END IF;
            END IF;

            -- Track last requested coordinates for trace/debug.
            IF in_screen = '1' THEN
                last_x := screen.pixel_x;
                last_y := screen.pixel_y;
            END IF;
            tb_last_x <= last_x;
            tb_last_y <= last_y;

            -- Drive inputs for the *current* request (these will be consumed on the next clock).
            IF in_screen = '1' THEN
                IF ((screen.pixel_x / 80) MOD 2) = 1 THEN cur_r := '1'; ELSE cur_r := '0'; END IF;
                IF ((screen.pixel_y / 60) MOD 2) = 1 THEN cur_g := '1'; ELSE cur_g := '0'; END IF;
                IF (((screen.pixel_x + screen.pixel_y) / 100) MOD 2) = 1 THEN cur_b := '1'; ELSE cur_b := '0'; END IF;
            ELSE
                cur_r := '0';
                cur_g := '0';
                cur_b := '0';
            END IF;

            r_in <= cur_r;
            g_in <= cur_g;
            b_in <= cur_b;

            prev_r := cur_r;
            prev_g := cur_g;
            prev_b := cur_b;
            prev_req_on := in_screen;
            have_prev := TRUE;

            current_x := expected_x;
            IF (expected_y >= V_LAST) AND (current_x >= V_COUNT_TICK) THEN
                expected_y := 0;
            ELSIF current_x = V_COUNT_TICK THEN
                expected_y := expected_y + 1;
            END IF;

            IF current_x = H_LAST THEN
                expected_x := 0;
            ELSE
                expected_x := expected_x + 1;
            END IF;

            IF in_screen = '1' THEN
                pixels_generated := pixels_generated + 1;
                tb_pixels_generated <= pixels_generated;
                IF pixels_generated = 640*480 THEN
                    -- One more tick is needed to check the final pixel's outputs.
                    WAIT UNTIL RISING_EDGE(clock_25MHz);
                    WAIT FOR 0 NS;
                    tb_cycle <= tb_cycle + 1;

                    IF (r_out /= prev_r) THEN
                        error_code_i <= "0001" & "00" & prev_r & r_out;
                        finished_i <= '1';
                        WAIT;
                    ELSIF (g_out /= prev_g) THEN
                        error_code_i <= "0001" & "01" & prev_g & g_out;
                        finished_i <= '1';
                        WAIT;
                    ELSIF (b_out /= prev_b) THEN
                        error_code_i <= "0001" & "10" & prev_b & b_out;
                        finished_i <= '1';
                        WAIT;
                    END IF;

                    error_code_i <= x"00";
                    finished_i <= '1';
                    WAIT;
                END IF;
            END IF;
        END LOOP;
    END PROCESS stim_proc;

    -- Trace all VGA ports + TB-visible counters into a CSV file (and optionally the transcript).
    -- CSV columns: cycle,time_ns,px_count,screen_x,screen_y,in_screen,r_in,g_in,b_in,r_out,g_out,b_out,hsync,vsync,last_x,last_y
    trace_proc: PROCESS
        VARIABLE L : LINE;
        VARIABLE sample : INTEGER := 0;
        VARIABLE time_ns : INTEGER;
    BEGIN
        IF TRACE_TO_FILE THEN
            WRITE(L, STRING'("cycle,time_ns,px_count,screen_x,screen_y,in_screen,r_in,g_in,b_in,r_out,g_out,b_out,hsync,vsync,last_x,last_y"));
            WRITELINE(trace_f, L);
        END IF;

        WHILE finished_i = '0' LOOP
            WAIT UNTIL RISING_EDGE(clock_25MHz);
            WAIT FOR 0 NS;

            sample := sample + 1;
            IF (sample MOD TRACE_EVERY_N) = 0 THEN
                time_ns := NOW / 1 NS;

                IF TRACE_TO_FILE THEN
                    L := NULL;
                    WRITE(L, INTEGER'IMAGE(tb_cycle));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(time_ns));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(tb_pixels_generated));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(screen.pixel_x));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(screen.pixel_y));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(in_screen));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(r_in));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(g_in));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(b_in));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(r_out));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(g_out));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(b_out));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(hsync));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(vsync));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(tb_last_x));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(tb_last_y));
                    WRITELINE(trace_f, L);
                END IF;

                IF TRACE_TO_TRANSCRIPT AND ((sample MOD TRANSCRIPT_EVERY_N) = 0) THEN
                    REPORT "vga_tb trace: t=" & INTEGER'IMAGE(time_ns) & "ns"
                        & " cyc=" & INTEGER'IMAGE(tb_cycle)
                        & " px=" & INTEGER'IMAGE(tb_pixels_generated)
                        & " screen_xy=(" & INTEGER'IMAGE(screen.pixel_x) & "," & INTEGER'IMAGE(screen.pixel_y) & ")"
                        & " rgb_in=" & STD_LOGIC'IMAGE(r_in) & STD_LOGIC'IMAGE(g_in) & STD_LOGIC'IMAGE(b_in)
                        & " rgb_out=" & STD_LOGIC'IMAGE(r_out) & STD_LOGIC'IMAGE(g_out) & STD_LOGIC'IMAGE(b_out)
                        & " hs=" & STD_LOGIC'IMAGE(hsync) & " vs=" & STD_LOGIC'IMAGE(vsync);
                END IF;
            END IF;
        END LOOP;

        IF TRACE_TO_FILE THEN
            FILE_CLOSE(trace_f);
        END IF;
        WAIT;
    END PROCESS trace_proc;
END ARCHITECTURE behaviour;
