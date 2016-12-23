library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

use work.sampling_pkg.all;
use work.tdc_sample_prep_pkg.all;

entity acquisition_tb is
end acquisition_tb;

architecture acquisition_tb_arch of acquisition_tb is

    constant clk_samples_period : time := 4 ns;
    signal clk_samples: std_logic := '0';

    signal samples_d_in: din_samples_t( 0 to 3 ) := (others => (others => '0'));
    signal samples_a_in: adc_samples_t( 0 to 1 ) := (others => (ovfl => '0', data => (others => '0')));
    signal a_threshold: a_sample_t := (others => '0');
    signal a_invert: std_logic := '0';
    signal a_average: std_logic_vector( 1 downto 0 ) := (others => '0');
    signal acq_mode: std_logic_vector( 1 downto 0 ) := (others => '0');
    signal acq_start_src: std_logic_vector( 2 downto 0 ) := (others => '0');
    signal acq_stop_src: std_logic_vector( 2 downto 0 ) := (others => '0');
    signal acq_reset: std_logic := '0';
    signal acq_stop: std_logic := '0';
    signal acq_state: std_logic_vector( 2 downto 0 );

    constant clk_rd_period : time := 10 ns;
    signal clk_rd: std_logic := '0';
    
    signal rd_en: std_logic := '0';
    signal rd_empty: std_logic;
    signal rd_data: std_logic_vector(15 downto 0);
    signal rd_2xcnt: std_logic_vector(15 downto 0);

begin

process begin
    clk_samples <= '0';
    wait for clk_samples_period/2;
    clk_samples <= '1';
    wait for clk_samples_period/2;
end process;

process begin
    clk_rd <= '0';
    wait for clk_rd_period/2;
    clk_rd <= '1';
    wait for clk_rd_period/2;
end process;

acquisition_inst: entity work.acquisition
port map(
    clk_samples => clk_samples,
    samples_d_in => samples_d_in,
    samples_a_in => samples_a_in,
    a_threshold => a_threshold,
    a_invert => a_invert,
    a_average => a_average,
    acq_mode => acq_mode,
    acq_start_src => acq_start_src,
    acq_stop_src => acq_stop_src,
    acq_reset => acq_reset,
    acq_stop => acq_stop,
    acq_state => acq_state,
    clk_rd => clk_rd,
    rd_en => rd_en,
    rd_empty => rd_empty,
    rd_data => rd_data,
    rd_2xcnt => rd_2xcnt
);

stimulus: process
begin
    a_invert <= '1';
    acq_mode <= "10";
    acq_start_src <= std_logic_vector(to_unsigned(1, 3));
    acq_stop_src  <= std_logic_vector(to_unsigned(2, 3));
    
    wait for 8*clk_samples_period;
    acq_reset <= '1';
    wait for 2*clk_samples_period;
    acq_reset <= '0';
    
	wait for 10*clk_samples_period;
	samples_d_in <= ("00", "01", "01", "00");
	wait for 8*clk_samples_period;
	samples_d_in <= (others => (others => '0'));
	wait for 10*clk_samples_period;
	samples_a_in(0).data <= to_signed(-1000, ADC_SAMPLE_BITS);
	samples_a_in(1).data <= to_signed(0, ADC_SAMPLE_BITS);
	wait for clk_samples_period;
	samples_a_in <= (others => (ovfl => '0', data => (others => '0')));
	wait;
end process;

end acquisition_tb_arch;
