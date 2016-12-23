-------------------------------------------------------------------------------
-- Moving average filter
--
-- n=0 "00" no averaging
-- n=1 "01" 2 samples
-- n=2 "10" 4 samples
-- n=3 "11" undefined
--
-- TODO: adapt to incoming signal length
-- TODO: carry correct overflow bits to result
--
-- Author: Peter Würtz, TU Kaiserslautern (2016)
-- Distributed under the terms of the GNU General Public License Version 3.
-- The full license is in the file COPYING.txt, distributed with this software.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sampling_pkg.all;

entity sample_average is
    port (
        clk: in std_logic;
        n: in std_logic_vector(1 downto 0);
        samples_a_in: in adc_samples_t(0 to 1);
        samples_a_out: out adc_samples_t(0 to 1)
    );
end sample_average;

architecture sample_average_arch of sample_average is

    type samples_t is array (integer range <>) of signed(ADC_SAMPLE_BITS-1 downto 0);

    signal s0_samples: samples_t(0 to 4);
    signal s1_samples: samples_t(0 to 3);
    signal s2_samples: samples_t(0 to 1);
begin

stage0: process(clk)
begin
    if rising_edge(clk) then
        -- shift buffer
        s0_samples(0 to 2) <= s0_samples(2 to 4);
        -- add new samples
        s0_samples(3) <= signed(samples_a_in(0).data);
        s0_samples(4) <= signed(samples_a_in(1).data);
    end if;
end process;

stage1: process(clk)
    variable a2, a3: signed(ADC_SAMPLE_BITS downto 0);
begin
    if rising_edge(clk) then
        -- shift buffer
        s1_samples(0 to 1) <= s1_samples(2 to 3);
        -- calculate new averages
        a2 := resize(s0_samples(2), ADC_SAMPLE_BITS+1) + resize(s0_samples(3), ADC_SAMPLE_BITS+1);
        a3 := resize(s0_samples(3), ADC_SAMPLE_BITS+1) + resize(s0_samples(4), ADC_SAMPLE_BITS+1);
        s1_samples(2) <= a2(ADC_SAMPLE_BITS downto 1);
        s1_samples(3) <= a3(ADC_SAMPLE_BITS downto 1);
    end if;
end process;

stage2: process(clk)
    variable a0, a1: signed(ADC_SAMPLE_BITS downto 0);
begin
    if rising_edge(clk) then
        -- calculate new averages
        a0 := resize(s1_samples(0), ADC_SAMPLE_BITS+1) + resize(s1_samples(2), ADC_SAMPLE_BITS+1);
        a1 := resize(s1_samples(1), ADC_SAMPLE_BITS+1) + resize(s1_samples(3), ADC_SAMPLE_BITS+1);
        s2_samples(0) <= a0(ADC_SAMPLE_BITS downto 1);
        s2_samples(1) <= a1(ADC_SAMPLE_BITS downto 1);
    end if;
end process;

output_selection: process(n, samples_a_in, s1_samples, s2_samples)
begin
    samples_a_out(0).ovfl <= samples_a_in(0).ovfl;
    samples_a_out(1).ovfl <= samples_a_in(1).ovfl;
    
    case n is
        when "00" =>
            samples_a_out(0).data <= samples_a_in(0).data;
            samples_a_out(1).data <= samples_a_in(1).data;
        when "01" =>
            samples_a_out(0).data <= signed(s1_samples(2));
            samples_a_out(1).data <= signed(s1_samples(3));
        when "10" =>
            samples_a_out(0).data <= signed(s2_samples(0));
            samples_a_out(1).data <= signed(s2_samples(1));
        when others =>
            samples_a_out(0).data <= (others => '-');
            samples_a_out(1).data <= (others => '-');
    end case;
end process;

end sample_average_arch;
