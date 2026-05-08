LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

USE STD.TEXTIO.ALL;

ENTITY mouse_tb IS
    PORT (
        -- finished: '0' while running, '1' when complete
        finished   : OUT STD_LOGIC := '0';
        -- error_code: 0 means success; nonzero encodes failure reason
        error_code : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00"
    );
END mouse_tb;

ARCHITECTURE behaviour OF mouse_tb IS

    SIGNAL finished_i   : STD_LOGIC := '0';
    SIGNAL error_code_i : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00";

    -- Component Declaration for the Unit Under Test (UUT)
    COMPONENT mouse
        PORT(
            clock_25Mhz  : IN STD_LOGIC;
            reset        : IN STD_LOGIC;
            mouse_data   : INOUT STD_LOGIC;
            mouse_clk    : INOUT STD_LOGIC;
            left_button  : OUT STD_LOGIC;
            right_button : OUT STD_LOGIC;
            out_mouse_x  : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
            out_mouse_y  : OUT STD_LOGIC_VECTOR(9 DOWNTO 0)
        );
    END COMPONENT;

    -- Inputs
    SIGNAL clock_25MHz : STD_LOGIC := '0';
    SIGNAL reset       : STD_LOGIC := '1';

    -- PS/2 bus. The TB models the mouse side with explicit line drives.
    SIGNAL mouse_data          : STD_LOGIC := 'Z';
    SIGNAL mouse_clk           : STD_LOGIC := 'Z';
    SIGNAL tb_mouse_data_drive : STD_LOGIC := 'Z';
    SIGNAL tb_mouse_clk_drive  : STD_LOGIC := 'Z';

    -- Outputs
    SIGNAL left_button  : STD_LOGIC;
    SIGNAL right_button : STD_LOGIC;
    SIGNAL out_mouse_x  : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL out_mouse_y  : STD_LOGIC_VECTOR(9 DOWNTO 0);

    -- Make key TB state visible (and loggable)
    SIGNAL tb_cycle        : INTEGER := 0;
    SIGNAL tb_phase        : INTEGER := 0;
    SIGNAL tb_host_bit     : INTEGER := -1;
    SIGNAL tb_mouse_bit    : INTEGER := -1;
    SIGNAL tb_bytes_sent   : INTEGER := 0;
    SIGNAL tb_packets_sent : INTEGER := 0;

    -- Trace configuration
    CONSTANT TRACE_TO_FILE       : BOOLEAN := TRUE;
    CONSTANT TRACE_TO_TRANSCRIPT : BOOLEAN := FALSE;
    CONSTANT TRACE_EVERY_N       : POSITIVE := 1;
    CONSTANT TRANSCRIPT_EVERY_N  : POSITIVE := 2000;

    -- PS/2 clocks are commonly 10-16.7 kHz. This slow 25 kHz test clock leaves
    -- plenty of time for the DUT's 8-sample clock filter to settle.
    CONSTANT PS2_HALF_PERIOD : TIME := 20 US;
    CONSTANT PS2_SETUP_TIME  : TIME := 2 US;

    -- Error-code map:
    -- x"01": DUT did not release/increase mouse clock after inhibit
    -- x"02": DUT did not start driving the F4 command
    -- x"10"-x"1A": F4 command bit mismatch; low nibble is bit index
    -- x"20": PS/2 line contention while TB was sending to DUT
    -- x"21": X not centred at 320 after ACK
    -- x"22": Y not centred at 240 after ACK
    -- x"23": buttons not clear after ACK
    -- x"31": X movement result mismatch
    -- x"32": Y movement result mismatch
    -- x"33": button state mismatch after movement packet
    -- x"41": X right-edge clamp mismatch
    -- x"42": Y bottom-edge clamp mismatch

    FILE trace_f : TEXT OPEN WRITE_MODE IS "log/mouse_trace.csv";

    FUNCTION odd_parity(data_byte : STD_LOGIC_VECTOR(7 DOWNTO 0))
        RETURN STD_LOGIC IS
    BEGIN
        RETURN NOT (
            data_byte(7) XOR
            data_byte(6) XOR
            data_byte(5) XOR
            data_byte(4) XOR
            data_byte(3) XOR
            data_byte(2) XOR
            data_byte(1) XOR
            data_byte(0)
        );
    END FUNCTION odd_parity;

    FUNCTION slv_to_integer(slv : STD_LOGIC_VECTOR) RETURN INTEGER IS
        VARIABLE value : INTEGER := 0;
    BEGIN
        FOR i IN slv'RANGE LOOP
            value := value * 2;
            IF slv(i) = '1' THEN
                value := value + 1;
            END IF;
        END LOOP;
        RETURN value;
    END FUNCTION slv_to_integer;

BEGIN

    finished <= finished_i;
    error_code <= error_code_i;

    mouse_data <= tb_mouse_data_drive;
    mouse_clk <= tb_mouse_clk_drive;

    -- Instantiate the Unit Under Test (UUT)
    uut: mouse PORT MAP (
        clock_25Mhz => clock_25MHz,
        reset => reset,
        mouse_data => mouse_data,
        mouse_clk => mouse_clk,
        left_button => left_button,
        right_button => right_button,
        out_mouse_x => out_mouse_x,
        out_mouse_y => out_mouse_y
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

    cycle_counter: PROCESS
    BEGIN
        WHILE finished_i = '0' LOOP
            WAIT UNTIL RISING_EDGE(clock_25MHz);
            tb_cycle <= tb_cycle + 1;
        END LOOP;
        WAIT;
    END PROCESS cycle_counter;

    stim_proc: PROCESS
        PROCEDURE fail(CONSTANT code : STD_LOGIC_VECTOR(7 DOWNTO 0)) IS
        BEGIN
            error_code_i <= code;
            finished_i <= '1';
            WAIT;
        END PROCEDURE fail;

        PROCEDURE wait_25mhz_cycles(CONSTANT cycles : NATURAL) IS
        BEGIN
            FOR i IN 1 TO cycles LOOP
                WAIT UNTIL RISING_EDGE(clock_25MHz);
            END LOOP;
            WAIT FOR 0 NS;
        END PROCEDURE wait_25mhz_cycles;

        PROCEDURE wait_for_line(
            SIGNAL line_value : IN STD_LOGIC;
            CONSTANT expected : IN STD_LOGIC;
            CONSTANT timeout_cycles : IN NATURAL;
            CONSTANT timeout_code : IN STD_LOGIC_VECTOR(7 DOWNTO 0)
        ) IS
        BEGIN
            FOR i IN 0 TO timeout_cycles LOOP
                WAIT UNTIL RISING_EDGE(clock_25MHz);
                WAIT FOR 0 NS;
                IF line_value = expected THEN
                    RETURN;
                END IF;
            END LOOP;
            fail(timeout_code);
        END PROCEDURE wait_for_line;

        PROCEDURE clock_dut_command(
            CONSTANT expected_byte : IN STD_LOGIC_VECTOR(7 DOWNTO 0)
        ) IS
            VARIABLE expected_bits : STD_LOGIC_VECTOR(10 DOWNTO 0);
        BEGIN
            expected_bits(0) := '0';
            expected_bits(8 DOWNTO 1) := expected_byte;
            expected_bits(9) := odd_parity(expected_byte);
            expected_bits(10) := '1';

            tb_phase <= 2;
            FOR bit_index IN 0 TO 10 LOOP
                tb_host_bit <= bit_index;
                WAIT FOR PS2_SETUP_TIME;

                IF mouse_data /= expected_bits(bit_index) THEN
                    fail("0001" & CONV_STD_LOGIC_VECTOR(bit_index, 4));
                END IF;

                tb_mouse_clk_drive <= '0';
                WAIT FOR PS2_HALF_PERIOD;
                tb_mouse_clk_drive <= '1';
                WAIT FOR PS2_HALF_PERIOD;
            END LOOP;

            tb_host_bit <= -1;
        END PROCEDURE clock_dut_command;

        PROCEDURE drive_mouse_serial_bit(
            CONSTANT bit_value : IN STD_LOGIC;
            CONSTANT bit_index : IN INTEGER
        ) IS
        BEGIN
            tb_mouse_bit <= bit_index;
            tb_mouse_data_drive <= bit_value;
            WAIT FOR PS2_SETUP_TIME;

            IF mouse_data /= bit_value THEN
                fail(x"20");
            END IF;

            tb_mouse_clk_drive <= '0';
            WAIT FOR PS2_HALF_PERIOD;
            tb_mouse_clk_drive <= '1';
            WAIT FOR PS2_HALF_PERIOD;
        END PROCEDURE drive_mouse_serial_bit;

        PROCEDURE send_mouse_byte(
            CONSTANT data_byte : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            CONSTANT phase_value : IN INTEGER
        ) IS
        BEGIN
            tb_phase <= phase_value;
            tb_bytes_sent <= tb_bytes_sent + 1;

            tb_mouse_clk_drive <= '1';
            tb_mouse_data_drive <= '1';
            WAIT FOR PS2_HALF_PERIOD;

            drive_mouse_serial_bit('0', 0);
            FOR bit_index IN 0 TO 7 LOOP
                drive_mouse_serial_bit(data_byte(bit_index), bit_index + 1);
            END LOOP;
            drive_mouse_serial_bit(odd_parity(data_byte), 9);
            drive_mouse_serial_bit('1', 10);

            tb_mouse_bit <= -1;
            tb_mouse_data_drive <= '1';
            WAIT FOR PS2_HALF_PERIOD;
        END PROCEDURE send_mouse_byte;

        PROCEDURE send_mouse_packet(
            CONSTANT byte1 : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            CONSTANT byte2 : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            CONSTANT byte3 : IN STD_LOGIC_VECTOR(7 DOWNTO 0)
        ) IS
        BEGIN
            send_mouse_byte(byte1, 4);
            send_mouse_byte(byte2, 4);
            send_mouse_byte(byte3, 4);
            tb_packets_sent <= tb_packets_sent + 1;
            wait_25mhz_cycles(32);
        END PROCEDURE send_mouse_packet;

        PROCEDURE expect_position(
            CONSTANT expected_x : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            CONSTANT expected_y : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            CONSTANT x_code : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            CONSTANT y_code : IN STD_LOGIC_VECTOR(7 DOWNTO 0)
        ) IS
        BEGIN
            wait_25mhz_cycles(8);
            IF out_mouse_x /= expected_x THEN
                fail(x_code);
            ELSIF out_mouse_y /= expected_y THEN
                fail(y_code);
            END IF;
        END PROCEDURE expect_position;

        PROCEDURE expect_buttons(
            CONSTANT expected_left : IN STD_LOGIC;
            CONSTANT expected_right : IN STD_LOGIC;
            CONSTANT code : IN STD_LOGIC_VECTOR(7 DOWNTO 0)
        ) IS
        BEGIN
            wait_25mhz_cycles(8);
            IF (left_button /= expected_left) OR (right_button /= expected_right) THEN
                fail(code);
            END IF;
        END PROCEDURE expect_buttons;
    BEGIN
        finished_i <= '0';
        error_code_i <= x"00";
        tb_phase <= 0;
        tb_host_bit <= -1;
        tb_mouse_bit <= -1;
        tb_bytes_sent <= 0;
        tb_packets_sent <= 0;

        tb_mouse_clk_drive <= 'Z';
        tb_mouse_data_drive <= 'Z';
        reset <= '1';
        wait_25mhz_cycles(16);

        -- Let the DUT inhibit the clock, then take over the mouse side when
        -- the DUT reaches its command-load phase.
        reset <= '0';
        tb_phase <= 1;
        wait_for_line(mouse_clk, '1', 6000, x"01");
        tb_mouse_clk_drive <= '1';
        wait_for_line(mouse_data, '0', 256, x"02");

        -- The DUT should request PS/2 streaming mode by sending F4.
        clock_dut_command(x"F4");

        -- Reply with ACK and check the cursor starts in the visible-screen centre.
        tb_mouse_clk_drive <= '1';
        tb_mouse_data_drive <= '1';
        wait_25mhz_cycles(64);
        send_mouse_byte(x"FA", 3);
        expect_position(
            CONV_STD_LOGIC_VECTOR(320, 10),
            CONV_STD_LOGIC_VECTOR(240, 10),
            x"21",
            x"22"
        );
        expect_buttons('0', '0', x"23");

        -- Packet 1: left pressed, dx=+12, dy=+7.
        -- PS/2 reports positive Y as up, so screen Y should decrease.
        send_mouse_packet(x"09", x"0C", x"07");
        expect_position(
            CONV_STD_LOGIC_VECTOR(332, 10),
            CONV_STD_LOGIC_VECTOR(233, 10),
            x"31",
            x"32"
        );
        expect_buttons('1', '0', x"33");

        -- Packet 2: right pressed, dx=-8, dy=-4.
        send_mouse_packet(x"3A", x"F8", x"FC");
        expect_position(
            CONV_STD_LOGIC_VECTOR(324, 10),
            CONV_STD_LOGIC_VECTOR(237, 10),
            x"31",
            x"32"
        );
        expect_buttons('0', '1', x"33");

        -- Right edge clamp: 324 + 127 + 127 + 127 should clamp at x=639.
        send_mouse_packet(x"08", x"7F", x"00");
        send_mouse_packet(x"08", x"7F", x"00");
        send_mouse_packet(x"08", x"7F", x"00");
        expect_position(
            CONV_STD_LOGIC_VECTOR(639, 10),
            CONV_STD_LOGIC_VECTOR(237, 10),
            x"41",
            x"32"
        );

        -- Bottom edge clamp: dy=-128 twice should clamp at y=479.
        send_mouse_packet(x"28", x"00", x"80");
        send_mouse_packet(x"28", x"00", x"80");
        expect_position(
            CONV_STD_LOGIC_VECTOR(639, 10),
            CONV_STD_LOGIC_VECTOR(479, 10),
            x"41",
            x"42"
        );

        error_code_i <= x"00";
        finished_i <= '1';
        WAIT;
    END PROCESS stim_proc;

    -- Trace PS/2 lines, DUT outputs, and TB-visible state into a CSV file
    -- (and optionally the transcript).
    -- CSV columns:
    -- cycle,time_ns,phase,host_bit,mouse_bit,bytes_sent,packets_sent,reset,
    -- mouse_clk,mouse_data,tb_clk_drive,tb_data_drive,left,right,x,y,error_code
    trace_proc: PROCESS
        VARIABLE L : LINE;
        VARIABLE sample : INTEGER := 0;
        VARIABLE time_ns : INTEGER;
    BEGIN
        IF TRACE_TO_FILE THEN
            WRITE(L, STRING'("cycle,time_ns,phase,host_bit,mouse_bit,bytes_sent,packets_sent,reset,mouse_clk,mouse_data,tb_clk_drive,tb_data_drive,left,right,x,y,error_code"));
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
                    WRITE(L, INTEGER'IMAGE(tb_phase));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(tb_host_bit));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(tb_mouse_bit));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(tb_bytes_sent));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(tb_packets_sent));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(reset));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(mouse_clk));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(mouse_data));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(tb_mouse_clk_drive));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(tb_mouse_data_drive));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(left_button));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, STD_LOGIC'IMAGE(right_button));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(slv_to_integer(out_mouse_x)));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(slv_to_integer(out_mouse_y)));
                    WRITE(L, CHARACTER'(','));
                    WRITE(L, INTEGER'IMAGE(slv_to_integer(error_code_i)));
                    WRITELINE(trace_f, L);
                END IF;

                IF TRACE_TO_TRANSCRIPT AND ((sample MOD TRANSCRIPT_EVERY_N) = 0) THEN
                    REPORT "mouse_tb trace: t=" & INTEGER'IMAGE(time_ns) & "ns"
                        & " phase=" & INTEGER'IMAGE(tb_phase)
                        & " clk=" & STD_LOGIC'IMAGE(mouse_clk)
                        & " data=" & STD_LOGIC'IMAGE(mouse_data)
                        & " buttons=" & STD_LOGIC'IMAGE(left_button) & STD_LOGIC'IMAGE(right_button)
                        & " xy=(" & INTEGER'IMAGE(slv_to_integer(out_mouse_x))
                        & "," & INTEGER'IMAGE(slv_to_integer(out_mouse_y)) & ")";
                END IF;
            END IF;
        END LOOP;

        IF TRACE_TO_FILE THEN
            FILE_CLOSE(trace_f);
        END IF;
        WAIT;
    END PROCESS trace_proc;
END ARCHITECTURE behaviour;
