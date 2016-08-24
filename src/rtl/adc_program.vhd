-------------------------------------------------------------------------------
-- ADS5403 ADC, serial programming
--
-- TODO: Readback
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc_program is
    port (
        -- application interface
        clk_main: in std_logic;
        start: in std_logic;
        busy: out std_logic;
        addr: in std_logic_vector(6 downto 0);
        din: in std_logic_vector(15 downto 0);
        -- adc interface
        adc_sdenb: out std_logic;
        adc_sdio: out std_logic;
        adc_sclk: out std_logic
    );
end adc_program;

architecture adc_program_arch of adc_program is
    -- state machine
    type output_state_t is (s_output, s_deselect, s_done);
    constant nbits: integer := 24;
    type state_t is record
        output_state: output_state_t;
        clk_count: unsigned(3 downto 0);
        bit_count: integer range 0 to nbits-1;
        shift_reg: std_logic_vector(nbits-1 downto 0);
    end record;
    constant default_state: state_t := (
        output_state => s_done,
        clk_count => (others => '0'),
        bit_count => 0,
        shift_reg => (others => '0')
    );
    signal state: state_t := default_state;
    signal next_state: state_t;
    signal shift_bit: std_logic;

    -- registered iob outputs
    signal iob_adc_sdenb: std_logic := '1';
    signal iob_adc_sdio: std_logic := '0';
    signal iob_adc_sclk: std_logic := '0';
    signal next_iob_adc_sdenb: std_logic;
    signal next_iob_adc_sdio: std_logic;
    signal next_iob_adc_sclk: std_logic;
    attribute IOB: string;
    attribute IOB of iob_adc_sdenb: signal is "true";
    attribute IOB of iob_adc_sdio: signal is "true";
    attribute IOB of iob_adc_sclk: signal is "true";
begin

adc_sdenb <= iob_adc_sdenb;
adc_sdio <= iob_adc_sdio;
adc_sclk <= iob_adc_sclk;
busy <= '0' when state.output_state = s_done else '1';

-- register in and outputs
sync_proc: process(clk_main)
begin
    if rising_edge(clk_main) then
        if (start = '1') then
            state <= default_state;
            state.output_state <= s_output;
            state.shift_reg <= "0" & addr & din; -- 0 for write only
            iob_adc_sdenb <= '1';
            iob_adc_sdio <= '0';
            iob_adc_sclk <= '0';
        else
            state <= next_state;
            iob_adc_sdenb <= next_iob_adc_sdenb;
            iob_adc_sdio <= next_iob_adc_sdio;
            iob_adc_sclk <= next_iob_adc_sclk;
        end if;
    end if;
end process;

-- combinatorial logic / state transitions
comb_proc: process(state)
    variable cycle: boolean;
begin
    -- default: keep state, deselect DAC
    next_state <= state;
    next_iob_adc_sdenb <= '1';
    next_iob_adc_sdio <= '0';
    next_iob_adc_sclk <= '0';

    -- increment clock divide counter
    if state.output_state /= s_done then
        next_state.clk_count <= state.clk_count + 1;
    end if;
    cycle := (state.clk_count = (state.clk_count'high downto 0 => '1'));

    case state.output_state is
        when s_output =>
            -- generate clock signal from counter and output MSB of shift reg
            next_iob_adc_sdenb <= '0';
            next_iob_adc_sclk <= state.clk_count(state.clk_count'high);
            next_iob_adc_sdio <= state.shift_reg(state.shift_reg'high);
            
            -- bit shift on clock count overflow, next state after 16th bit
            if cycle then
                next_state.shift_reg <= state.shift_reg(state.shift_reg'high-1 downto 0) & '0';
                next_state.bit_count <= state.bit_count + 1;
                if state.bit_count = (nbits-1) then
                    next_state.output_state <= s_deselect;
                end if;
            end if;
        when s_deselect =>
            -- wait one cycle in deselect
            next_iob_adc_sdenb <= '1';
            if cycle then
                next_state.output_state <= s_done;
            end if;
        when others =>
            null;
    end case;
end process;

end adc_program_arch;
