library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mouseTop is
    port (
        CLOCK_50 : in std_logic;

        KEY  : in std_logic_vector(3 downto 0);
        SW   : in std_logic_vector(9 downto 0);
        LEDR : out std_logic_vector(9 downto 0);

        HEX0 : out std_logic_vector(6 downto 0);
        HEX1 : out std_logic_vector(6 downto 0);
        HEX2 : out std_logic_vector(6 downto 0);
        HEX3 : out std_logic_vector(6 downto 0);
        HEX4 : out std_logic_vector(6 downto 0);
        HEX5 : out std_logic_vector(6 downto 0);

        PS2_CLK : inout std_logic;
        PS2_DAT : inout std_logic;

        VGA_R  : out std_logic_vector(3 downto 0);
        VGA_G  : out std_logic_vector(3 downto 0);
        VGA_B  : out std_logic_vector(3 downto 0);
        VGA_HS : out std_logic;
        VGA_VS : out std_logic
    );
end mouseTop;

architecture rtl of mouseTop is

    signal clk25 : std_logic := '0';
    signal reset : std_logic;

    signal pixel_row    : std_logic_vector(9 downto 0);
    signal pixel_column : std_logic_vector(9 downto 0);

    signal mouse_row : std_logic_vector(9 downto 0);
    signal mouse_col : std_logic_vector(9 downto 0);

    signal left_btn  : std_logic;
    signal right_btn : std_logic;

    signal red_sig   : std_logic;
    signal green_sig : std_logic;
    signal blue_sig  : std_logic;

    signal vga_red_1   : std_logic;
    signal vga_green_1 : std_logic;
    signal vga_blue_1  : std_logic;

    signal player_on : std_logic;

    constant PLAYER_SIZE : integer := 10;

    function hex7seg(x : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case x is
            when "0000" => return "1000000"; -- 0
            when "0001" => return "1111001"; -- 1
            when "0010" => return "0100100"; -- 2
            when "0011" => return "0110000"; -- 3
            when "0100" => return "0011001"; -- 4
            when "0101" => return "0010010"; -- 5
            when "0110" => return "0000010"; -- 6
            when "0111" => return "1111000"; -- 7
            when "1000" => return "0000000"; -- 8
            when "1001" => return "0010000"; -- 9
            when "1010" => return "0001000"; -- A
            when "1011" => return "0000011"; -- b
            when "1100" => return "1000110"; -- C
            when "1101" => return "0100001"; -- d
            when "1110" => return "0000110"; -- E
            when others => return "0001110"; -- F
        end case;
    end function;

begin

    reset <= not KEY(0);

    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            clk25 <= not clk25;
        end if;
    end process;

    mouse_inst : entity work.MOUSE
        port map (
            clock_25Mhz         => clk25,
            reset               => reset,
            mouse_data          => PS2_DAT,
            mouse_clk           => PS2_CLK,
            left_button         => left_btn,
            right_button        => right_btn,
            mouse_cursor_row    => mouse_row,
            mouse_cursor_column => mouse_col
        );

    player_on <= '1' when
        (to_integer(unsigned(pixel_column)) >= to_integer(unsigned(mouse_col)) - PLAYER_SIZE) and
        (to_integer(unsigned(pixel_column)) <= to_integer(unsigned(mouse_col)) + PLAYER_SIZE) and
        (to_integer(unsigned(pixel_row))    >= to_integer(unsigned(mouse_row)) - PLAYER_SIZE) and
        (to_integer(unsigned(pixel_row))    <= to_integer(unsigned(mouse_row)) + PLAYER_SIZE)
        else '0';

    red_sig   <= player_on;
    green_sig <= left_btn;
    blue_sig  <= right_btn;

    vga_inst : entity work.VGA_SYNC
        port map (
            clock_25Mhz    => clk25,
            red            => red_sig,
            green          => green_sig,
            blue           => blue_sig,
            red_out        => vga_red_1,
            green_out      => vga_green_1,
            blue_out       => vga_blue_1,
            horiz_sync_out => VGA_HS,
            vert_sync_out  => VGA_VS,
            pixel_row      => pixel_row,
            pixel_column   => pixel_column
        );

    VGA_R <= (others => vga_red_1);
    VGA_G <= (others => vga_green_1);
    VGA_B <= (others => vga_blue_1);

    HEX0 <= hex7seg(mouse_col(3 downto 0));
    HEX1 <= hex7seg(mouse_col(7 downto 4));
    HEX2 <= hex7seg(mouse_row(3 downto 0));
    HEX3 <= hex7seg(mouse_row(7 downto 4));
    HEX4 <= hex7seg("00" & right_btn & left_btn);
    HEX5 <= hex7seg(SW(3 downto 0));

    LEDR <= SW;

end rtl;