LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.STD_LOGIC_ARITH.all;
USE IEEE.STD_LOGIC_UNSIGNED.all;

ENTITY mouse IS
	PORT (
		clock_25Mhz, reset	 		: IN STD_LOGIC;
		mouse_data					: INOUT STD_LOGIC;
		mouse_clk 					: INOUT STD_LOGIC;
		left_button, right_button	: OUT STD_LOGIC;
		out_mouse_x 				: OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
		out_mouse_y 				: OUT STD_LOGIC_VECTOR(9 DOWNTO 0)
	);
END mouse;

ARCHITECTURE behavior OF mouse IS

	TYPE STATE_TYPE IS (
		INHIBIT,
		LOAD_CMD,
		LOAD_CMD2,
		WAIT_output_ready,
		WAIT_CMD_ACK,
		INPUT_PACKETS
	);

	-- Signals for Mouse
	SIGNAL state											: STATE_TYPE;
	SIGNAL inhibit_wait_count								: STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL in_char, out_char								: STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL new_mouse_x, new_mouse_y 						: STD_LOGIC_VECTOR(9 DOWNTO 0);
	SIGNAL mouse_x, mouse_y 								: STD_LOGIC_VECTOR(9 DOWNTO 0);
	SIGNAL in_cnt, out_cnt, out_msb 						: STD_LOGIC_VECTOR(3 DOWNTO 0);
	SIGNAL packet_count 									: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL in_shift 										: STD_LOGIC_VECTOR(8 DOWNTO 0);
	SIGNAL out_shift 										: STD_LOGIC_VECTOR(10 DOWNTO 0);
	SIGNAL packet_char1, packet_char2, packet_char3			: STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL data_ready, read_char							: STD_LOGIC;
	SIGNAL cursor, iready_set, break, toggle_next,
		output_ready, send_char, send_data					: STD_LOGIC;
	SIGNAL mouse_data_dir, mouse_data_out, mouse_data_buf	: STD_LOGIC;
	SIGNAL mouse_clk_dir, mouse_clk_buf, mouse_clk_filter   : STD_LOGIC;
	SIGNAL filter 											: STD_LOGIC_VECTOR(7 DOWNTO 0);

	CONSTANT SCREEN_CENTER_X : INTEGER := 320;
	CONSTANT SCREEN_CENTER_Y : INTEGER := 240;
	CONSTANT SCREEN_MAX_X    : INTEGER := 639;
	CONSTANT SCREEN_MAX_Y    : INTEGER := 479;

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

	FUNCTION motion_to_integer(data_byte : STD_LOGIC_VECTOR(7 DOWNTO 0))
		RETURN INTEGER IS
		VARIABLE value : INTEGER;
	BEGIN
		value := CONV_INTEGER(data_byte);
		IF data_byte(7) = '1' THEN
			RETURN value - 256;
		ELSE
			RETURN value;
		END IF;
	END FUNCTION motion_to_integer;

	FUNCTION clamp_integer(
		value     : INTEGER;
		min_value : INTEGER;
		max_value : INTEGER
	) RETURN INTEGER IS
	BEGIN
		IF value < min_value THEN
			RETURN min_value;
		ELSIF value > max_value THEN
			RETURN max_value;
		ELSE
			RETURN value;
		END IF;
	END FUNCTION clamp_integer;

BEGIN

	out_mouse_x <= mouse_x;
	out_mouse_y <= mouse_y;

	-- tri_state control logic for mouse data and clock lines
	mouse_data <= 'Z' WHEN mouse_data_dir = '0' ELSE mouse_data_buf;
	mouse_clk <=  'Z' WHEN mouse_clk_dir = '0' ELSE mouse_clk_buf;

	-- state machine to send init command and start recv process.
	PROCESS (reset, clock_25Mhz) BEGIN
		IF reset = '1' THEN
			state <= INHIBIT;
			inhibit_wait_count <= (OTHERS => '0');
			send_data <= '0';
		ELSIF RISING_EDGE(clock_25Mhz) THEN
			CASE state IS
				-- Mouse powers up and sends self test codes, AA and 00 out before board is downloaded
				-- Pull clock line low to inhibit any transmissions from mouse
				-- Need at least 60usec to stop a transmission in progress
				-- Note: This is perhaps optional since mouse should not be tranmitting
				WHEN INHIBIT =>
					inhibit_wait_count <= inhibit_wait_count + 1;
					IF inhibit_wait_count(11 DOWNTO 10) = "11" THEN
						state <= LOAD_CMD;
					END IF;
					-- Enable Streaming Mode Command, F4
					out_char <= "11110100";
				-- Pull data low to signal data available to mouse
				WHEN LOAD_CMD =>
					send_data <= '1';
					state <= LOAD_CMD2;
				WHEN LOAD_CMD2 =>
					send_data <= '1';
					state <= WAIT_output_ready;
				-- Wait for Mouse to Clock out all bits in command.
				-- Command sent is F4, Enable Streaming Mode
				-- This tells the mouse to start sending 3-byte packets with movement data
				WHEN WAIT_output_ready =>
					send_data <= '0';
					-- Output Ready signals that all data is clocked out of shift register
					IF output_ready='1' THEN
						state <= WAIT_CMD_ACK;
					ELSE
						state <= WAIT_output_ready;
					END IF;
				-- Wait for Mouse to send back Command Acknowledge, FA
				WHEN WAIT_CMD_ACK =>
					send_data <= '0';
					IF iready_set='1' THEN
						state <= INPUT_PACKETS;
					END IF;
				-- Release clock_25Mhz and data lines and go into mouse input mode
				-- Stay in this state and recieve 3-byte mouse data packets forever
				-- Default rate is 100 packets per second
				WHEN INPUT_PACKETS =>
					state <= INPUT_PACKETS;
			END CASE;
		END IF;
	END PROCESS;

	WITH state SELECT
		-- Mouse Data Tri-state control line: '1' DE0 drives, '0'=Mouse Drives
		mouse_data_dir	<=	'0'	WHEN INHIBIT,
							'0'	WHEN LOAD_CMD,
							'0'	WHEN LOAD_CMD2,
							'1'	WHEN WAIT_output_ready,
							'0'	WHEN WAIT_CMD_ACK,
							'0'	WHEN INPUT_PACKETS;
	WITH state SELECT
		-- Mouse Clock Tri-state control line: '1' DE0 drives, '0'=Mouse Drives
		mouse_clk_dir 	<=	'1'	WHEN INHIBIT,
							'1'	WHEN LOAD_CMD,
							'1'	WHEN LOAD_CMD2,
							'0'	WHEN WAIT_output_ready,
							'0'	WHEN WAIT_CMD_ACK,
							'0'	WHEN INPUT_PACKETS;
	WITH state SELECT
		-- Input to DE0 tri-state buffer mouse clock_25Mhz line
		mouse_clk_buf 	<=	'0'	WHEN INHIBIT,
							'1'	WHEN LOAD_CMD,
							'1'	WHEN LOAD_CMD2,
							'1'	WHEN WAIT_output_ready,
							'1'	WHEN WAIT_CMD_ACK,
							'1'	WHEN INPUT_PACKETS;

	-- filter for mouse clock
	PROCESS BEGIN
		WAIT UNTIL RISING_EDGE(clock_25Mhz);
		filter(7 DOWNTO 1) <= filter(6 DOWNTO 0);
		filter(0) <= mouse_clk;
		IF filter = "11111111" THEN
			mouse_clk_filter <= '1';
		ELSIF filter = "00000000" THEN
			mouse_clk_filter <= '0';
		END IF;
	END PROCESS;

	--This process sends serial data going to the mouse
	SEND_UART: PROCESS (send_data, mouse_clk_filter) BEGIN
		IF send_data = '1' THEN
			out_cnt <= "0000";
			send_char <= '1';
			output_ready <= '0';
			-- Send out Start Bit(0) + Command(F4) + Parity  Bit(0) + Stop Bit(1)
			out_shift(8 DOWNTO 1) <= out_char;
			-- START BIT
			out_shift(0) <= '0';
			-- COMPUTE ODD PARITY BIT
			out_shift(9) <= not (
				out_char(7) xor
				out_char(6) xor
				out_char(5) xor
				out_char(4) xor
				out_char(3) xor
				out_char(2) xor
				out_char(1) xor
				out_char(0)
			);
			-- STOP BIT
			out_shift(10) <= '1';
			-- Data Available Flag to Mouse
			-- Tells mouse to clock out command data (is also start bit)
			mouse_data_buf <= '0';

		ELSIF FALLING_EDGE(mouse_clk_filter) THEN
			IF mouse_data_dir='1' THEN
				-- SHIFT OUT NEXT SERIAL BIT
				IF send_char = '1' THEN
					-- Loop through all bits in shift register
					IF out_cnt <= "1001" THEN
						out_cnt <= out_cnt + 1;
						-- Shift out next bit to mouse
						out_shift(9 DOWNTO 0) <= out_shift(10 DOWNTO 1);
						out_shift(10) <= '1';
						mouse_data_buf <= out_shift(1);
						output_ready <= '0';
					-- END OF CHARACTER
					ELSE
						send_char <= '0';
						-- Signal the character has been output
						output_ready <= '1';
						out_cnt <= "0000";
					END IF;
				END IF;
			END IF;
		END IF;
	END PROCESS SEND_UART;

	RECV_UART: PROCESS(reset, mouse_clk_filter)
		VARIABLE rx_char : STD_LOGIC_VECTOR(7 DOWNTO 0);
		VARIABLE next_x  : INTEGER;
		VARIABLE next_y  : INTEGER;
	BEGIN
		IF reset='1' THEN
			in_cnt <= "0000";
			read_char <= '0';
			packet_count <= "00";
			left_button <= '0';
			right_button <= '0';
			in_char <= "00000000";
			iready_set <= '0';
			mouse_x <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_X,10);
			mouse_y <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_Y,10);
			new_mouse_x <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_X,10);
			new_mouse_y <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_Y,10);
		ELSIF FALLING_EDGE(mouse_clk_filter) THEN
			IF mouse_data_dir = '0' THEN
				IF mouse_data = '0' AND read_char = '0' THEN
					read_char <= '1';
					iready_set <= '0';
				ELSE
					-- SHIFT IN NEXT SERIAL BIT
					IF read_char = '1' THEN
						IF in_cnt < "1001" THEN
							in_cnt <= in_cnt + 1;
							in_shift(7 DOWNTO 0) <= in_shift(8 DOWNTO 1);
							in_shift(8) <= mouse_data;
							iready_set <= '0';
							-- END OF CHARACTER
						ELSE
							rx_char := in_shift(7 DOWNTO 0);
							in_char <= rx_char;
							read_char <= '0';
							iready_set <= '0';
							in_cnt <= conv_std_logic_vector(0,4);

							IF (mouse_data = '1') AND (in_shift(8) = odd_parity(rx_char)) THEN
								-- PACKET_COUNT = "00" IS ACK COMMAND
								IF packet_count = "00" THEN
									IF rx_char = x"FA" THEN
										-- Set cursor to middle of 640x480 screen after ACK.
										mouse_x <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_X,10);
										mouse_y <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_Y,10);
										new_mouse_x <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_X,10);
										new_mouse_y <= CONV_STD_LOGIC_VECTOR(SCREEN_CENTER_Y,10);
										packet_count <= "01";
										iready_set <= '1';
									ELSE
										packet_count <= "00";
									END IF;
								ELSIF packet_count = "01" THEN
									packet_char1 <= rx_char;
									packet_count <= "10";
								ELSIF packet_count = "10" THEN
									packet_char2 <= rx_char;
									packet_count <= "11";
								ELSIF packet_count = "11" THEN
									packet_char3 <= rx_char;

									-- PS/2 byte 2 is signed X motion. PS/2 positive Y is up,
									-- so it subtracts from the VGA row coordinate.
									next_x := clamp_integer(
										CONV_INTEGER(mouse_x) + motion_to_integer(packet_char2),
										0,
										SCREEN_MAX_X
									);
									next_y := clamp_integer(
										CONV_INTEGER(mouse_y) - motion_to_integer(rx_char),
										0,
										SCREEN_MAX_Y
									);

									mouse_x <= CONV_STD_LOGIC_VECTOR(next_x,10);
									mouse_y <= CONV_STD_LOGIC_VECTOR(next_y,10);
									new_mouse_x <= CONV_STD_LOGIC_VECTOR(next_x,10);
									new_mouse_y <= CONV_STD_LOGIC_VECTOR(next_y,10);
									left_button <= packet_char1(0);
									right_button <= packet_char1(1);
									packet_count <= "01";
								END IF;
							ELSE
								-- Bad parity or stop bit: drop the partial byte and resync.
								IF packet_count = "00" THEN
									packet_count <= "00";
								ELSE
									packet_count <= "01";
								END IF;
							END IF;
						END IF;
					END IF;
				END IF;
			END IF;
		END IF;
	END PROCESS RECV_UART;

END behavior;
