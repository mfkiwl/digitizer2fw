-------------------------------------------------------------------------------
-- ADS5403 ADC, serial programming
--
-- TODO: Read operation currently shifts in bits at falling edges
--
-- Author: Peter Würtz, TU Kaiserslautern (2016)
-- Distributed under the terms of the GNU General Public License Version 3.
-- The full license is in the file COPYING.txt, distributed with this software.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

Library UNISIM;
use UNISIM.vcomponents.all;

entity adc_program is
    port (
        -- application interface
        clk_main: in std_logic;
        start: in std_logic;
        rd: in std_logic;
        busy: out std_logic;
        addr: in std_logic_vector(6 downto 0);
        din: in std_logic_vector(15 downto 0);
        dout: out std_logic_vector(15 downto 0);
        -- adc interface
        adc_sdenb: out std_logic;
        adc_sdio: inout std_logic;
        adc_sclk: out std_logic
    );
end adc_program;

architecture adc_program_arch of adc_program is
    -- state machine
    type output_state_t is (s_output, s_deselect, s_done);
    constant nbits: integer := 24;
    constant nbits_addr: integer := 8;
    type state_t is record
        output_state: output_state_t;
        rd: boolean;
        clk_count: unsigned(3 downto 0);
        bit_count: integer range 0 to nbits-1;
        shift_reg: std_logic_vector(nbits-1 downto 0);
    end record;
    constant default_state: state_t := (
        output_state => s_done,
        rd => false,
        clk_count => (others => '0'),
        bit_count => 0,
        shift_reg => (others => '0')
    );
    signal state: state_t := default_state;
    signal next_state: state_t;
    signal shift_bit: std_logic;

    -- registered iob outputs
    signal iob_adc_sdenb: std_logic := '1';
    signal iob_adc_sdout: std_logic := '0';
    signal iob_adc_sdin, iob_adc_sdin_from_iobuf: std_logic := '0';
    signal iob_adc_sdhz: std_logic := '1';
    signal iob_adc_sclk: std_logic := '0';
    signal next_iob_adc_sdenb: std_logic;
    signal next_iob_adc_sdout: std_logic;
    signal next_iob_adc_sdhz: std_logic;
    signal next_iob_adc_sclk: std_logic;
    attribute IOB: string;
    attribute IOB of iob_adc_sdenb: signal is "true";
    attribute IOB of iob_adc_sdout: signal is "true";
    attribute IOB of iob_adc_sdin: signal is "true";
    attribute IOB of iob_adc_sdhz: signal is "true";
    attribute IOB of iob_adc_sclk: signal is "true";
begin

busy <= '0' when state.output_state = s_done else '1';
dout <= state.shift_reg(15 downto 0);

adc_sdenb <= iob_adc_sdenb;
adc_sclk <= iob_adc_sclk;
adc_sdio_inst: IOBUF
generic map (DRIVE => 12, IOSTANDARD => "DEFAULT", SLEW => "SLOW")
port map (
    I => iob_adc_sdout,
    IO => adc_sdio,
    O => iob_adc_sdin_from_iobuf,
    T => iob_adc_sdhz 
);

-- register in and outputs
sync_proc: process(clk_main)
begin
    if rising_edge(clk_main) then
        if (start = '1') then
            state <= default_state;
            state.output_state <= s_output;
            state.rd <= (rd = '1');
            state.shift_reg <= rd & addr & din;
        else
            state <= next_state;
            iob_adc_sclk <= next_iob_adc_sclk;
            iob_adc_sdenb <= next_iob_adc_sdenb;
            iob_adc_sdout <= next_iob_adc_sdout;
            iob_adc_sdin <= iob_adc_sdin_from_iobuf;
            iob_adc_sdhz <= next_iob_adc_sdhz;
        end if;
    end if;
end process;

-- combinatorial logic / state transitions
comb_proc: process(state, iob_adc_sdin)
    variable sclk_falling, sclk_rising: boolean;
    type phase_t is (READ_PHASE, WRITE_PHASE);
    variable phase: phase_t;
begin
    -- default: keep state, deselect DAC
    next_state <= state;
    next_iob_adc_sdenb <= '1';
    next_iob_adc_sdout <= '0';
    next_iob_adc_sdhz <= '0';
    next_iob_adc_sclk <= '0';

    -- increment clock divide counter
    if state.output_state /= s_done then
        next_state.clk_count <= state.clk_count + 1;
    end if;
    sclk_rising := (state.clk_count = "0111");
    sclk_falling := (state.clk_count = "1111");

    -- determine if data is read or written
    if state.rd and state.bit_count > (8-1) then
        phase := READ_PHASE;
    else
        phase := WRITE_PHASE;
    end if;

    -- state machine
    case state.output_state is
        when s_output =>
            -- control tristate iob
        case phase is
        when READ_PHASE => next_iob_adc_sdhz <= '1';
        when WRITE_PHASE => next_iob_adc_sdhz <= '0';
        end case;

            -- generate clock signal from counter and output MSB of shift reg
            next_iob_adc_sdenb <= '0';
            next_iob_adc_sclk <= state.clk_count(state.clk_count'high);
            next_iob_adc_sdout <= state.shift_reg(state.shift_reg'high);

            -- for writing, shift bit out on falling edge
            -- for reading, shift bit in on rising edge
            if ((phase = WRITE_PHASE) and sclk_falling) or ((phase = READ_PHASE) and sclk_rising) then
                next_state.shift_reg <= state.shift_reg(state.shift_reg'high-1 downto 0) & iob_adc_sdin;
                next_state.bit_count <= state.bit_count + 1;
                -- go to deselect state when all bits are written/read
                if state.bit_count = (nbits-1) then
                    next_state.output_state <= s_deselect;
                end if;
            end if;
        when s_deselect =>
            -- wait one cycle in deselect
            next_iob_adc_sdenb <= '1';
            if sclk_falling then
                next_state.output_state <= s_done;
            end if;
        when others =>
            null;
    end case;
end process;

end adc_program_arch;
