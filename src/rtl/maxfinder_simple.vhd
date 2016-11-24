-------------------------------------------------------------------------------
-- Simple interface to the maxfinder module
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.maxfinder_pkg.all;
use work.sampling_pkg.all;

entity maxfinder_simple is
    generic (
        N_FRAC_BITS: natural := 8;
        N_ADIFF_CLIP: natural := 0
    );
    port (
        clk: in std_logic;
        samples_in: in a_samples_t(0 to 1);
        threshold: in a_sample_t;
        max_found: out std_logic;
        max_pos: out unsigned(1+N_FRAC_BITS-1 downto 0);
        max_height: out a_sample_t
    );
end maxfinder_simple;

architecture maxfinder_simple_arch of maxfinder_simple is

    component division_lut
        generic (ROUND_FLOAT: boolean);
        port (
            clk: in std_logic;
            clk_en: in std_logic;
            divisor: in unsigned;
            result: out unsigned
        );
    end component;

    signal smax_samples_in: std_logic_vector(2*ADC_SAMPLE_BITS-1 downto 0);
    signal smax_found: std_logic_vector(0 downto 0);
    signal smax_pos: std_logic_vector(0 downto 0);
    signal smax_adiff0: std_logic_vector(ADC_SAMPLE_BITS-1 downto 0);
    signal smax_adiff1: std_logic_vector(ADC_SAMPLE_BITS-1 downto 0);
    signal smax_sample0: std_logic_vector(ADC_SAMPLE_BITS-1 downto 0);
    signal smax_sample1: std_logic_vector(ADC_SAMPLE_BITS-1 downto 0);

    -- stage 0, prepare nominator and denominator for interpolation, average max samples
    signal s0_nominator: unsigned(ADC_SAMPLE_BITS-N_ADIFF_CLIP-1 downto 0);
    signal s0_denominator: unsigned(ADC_SAMPLE_BITS-N_ADIFF_CLIP downto 0);
    signal s0_sample_avg: signed(ADC_SAMPLE_BITS-1 downto 0);
    signal s0_valid: std_logic := '0';
    signal s0_pos: unsigned(0 downto 0);
    
    -- stage 1, calculate division and queue signals required at output
    signal s1_nominator: unsigned(s0_nominator'range);
    signal s1_division_result: unsigned(s0_denominator'high+1 downto 0);
    signal s1_valid: std_logic;
    signal s1_pos: unsigned(0 downto 0);
    signal s1_sample_avg: signed(s0_sample_avg'range);
    
    -- stage 2, multiply with d0 and register result
begin


stage0: process(clk)
    variable denom: unsigned(s0_denominator'range);
    variable sample0, sample1: signed(s0_sample_avg'high+1 downto 0);
begin
    if rising_edge(clk) then
        s0_nominator <= unsigned(smax_adiff0(s0_nominator'range));
        denom := resize(unsigned(smax_adiff0(s0_nominator'range)), denom'length) + resize(unsigned(smax_adiff1(s0_nominator'range)), denom'length);
        s0_denominator <= denom;
        --
        sample0 := resize(signed(smax_sample0), sample0'length);
        sample1 := resize(signed(smax_sample1), sample0'length);
        s0_sample_avg <= resize(shift_right(sample0 + sample1, 1), s0_sample_avg'length);
        --
        s0_valid <= smax_found(0);
        s0_pos <= unsigned(smax_pos);
    end if;
end process;


stage1_lut: division_lut 
generic map (ROUND_FLOAT => FALSE) -- always convert to smaller result so the interpolation never exceeds 1.0 later
port map (
    clk => clk,
    clk_en => s0_valid,
    divisor => s0_denominator,
    result => s1_division_result
);
stage1: process(clk)
begin
    if rising_edge(clk) then
        s1_nominator <= s0_nominator;
        s1_valid <= s0_valid;
        s1_pos <= s0_pos;
        s1_sample_avg <= s0_sample_avg;
    end if;
end process;


stage2: process(clk)
    variable x: unsigned(s1_nominator'length+s1_division_result'length-1 downto 0);
    variable fraction: unsigned(N_FRAC_BITS-1 downto 0);
begin
    if rising_edge(clk) then
        x := s1_nominator * s1_division_result;
        -- TODO: assert x(high downto s1_division_result'high) is zero
        fraction := x(s1_division_result'high-1 downto s1_division_result'high-1 - (fraction'length-1));
        max_found <= s1_valid;
        if s1_valid = '1' then
            max_pos <= s1_pos & fraction;
            max_height <= s1_sample_avg;
        else
            max_pos <= (others => '-');
            max_height <= (others => '-');
        end if;
    end if;
end process;


-------------------------------------------------------------------------------

smax_samples_in <= std_logic_vector(samples_in(1)) & std_logic_vector(samples_in(0));

maxfinder_inst: maxfinder_base
generic map (
    N_WINDOW_LENGTH => 2,
    N_OUTPUTS => 1,
    N_SAMPLE_BITS => ADC_SAMPLE_BITS,
    SYNC_STAGE1 => FALSE,
    SYNC_STAGE2 => TRUE,
    SYNC_STAGE3 => TRUE
)
port map (
    clk => clk,
    samples => smax_samples_in,
    threshold => std_logic_vector(threshold),
    max_found => smax_found,
    max_pos => smax_pos,
    max_adiff0 => smax_adiff0,
    max_adiff1 => smax_adiff1,
    max_sample0 => smax_sample0,
    max_sample1 => smax_sample1
);

end maxfinder_simple_arch;
