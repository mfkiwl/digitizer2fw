library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

use work.sampling_pkg.all;
use work.tdc_sample_prep_pkg.all;

entity tdc_sample_prep_tb is
end tdc_sample_prep_tb;

architecture tdc_sample_prep_tb_arch of tdc_sample_prep_tb is

    constant CNT_BITS: natural := 8;
    signal samples_d_in: din_samples_t( 0 to 3 ) := (others => (others => '0'));
    signal samples_a_in: adc_samples_t( 0 to 1 ) := (others => (ovfl => '0', data => (others => '0')));
    signal a_threshold: a_sample_t := (others => '0');
    signal a_invert: std_logic := '0';
    signal a_average: std_logic_vector( 1 downto 0 ) := (others => '0');
    signal samples_d_out: din_samples_t( 0 to 3 );
    signal samples_a_out: a_samples_t( 0 to 1 );
    signal sample_cnt: unsigned(CNT_BITS-1 downto 0);
    signal tdc_events: tdc_events_t;
    
    constant clk_period : time := 4 ns;
    signal clk: std_logic := '0';

begin

uut: tdc_sample_prep
generic map (CNT_BITS => CNT_BITS)
port map(
    clk           => clk,
    samples_d_in  => samples_d_in,
    samples_a_in  => samples_a_in,
    a_threshold   => a_threshold,
    a_invert      => a_invert,
    a_average     => a_average,
    samples_d_out => samples_d_out,
    samples_a_out => samples_a_out,
    cnt           => sample_cnt,
    tdc_events    => tdc_events
);

clk_process: process
begin
    clk <= '0';
    wait for clk_period/2;
    clk <= '1';
    wait for clk_period/2;
end process;

stimulus: process
begin
    a_invert <= '1';
	wait for 10*clk_period;
	samples_d_in <= (others => (others => '1'));
	wait for 5*clk_period;
	samples_d_in <= (others => (others => '0'));
	wait for 10*clk_period;
	samples_a_in(0).data <= to_signed(-1000, ADC_SAMPLE_BITS);
	samples_a_in(1).data <= to_signed(0, ADC_SAMPLE_BITS);
	wait for clk_period;
	samples_a_in <= (others => (ovfl => '0', data => (others => '0')));
    
	wait;
end process;

end tdc_sample_prep_tb_arch;
